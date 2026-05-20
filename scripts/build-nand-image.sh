#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
wt_dir="$(cd "$repo_root/.." && pwd)"
upstreams_dir="${UPSTREAMS_DIR:-$wt_dir/upstreams}"

suite="${SUITE:-trixie}"
arch="${ARCH:-armhf}"
build_dir="${BUILD_DIR:-$repo_root/build}"
rootfs="${ROOTFS:-$build_dir/rootfs-$suite-$arch}"
nand_dir="${NAND_BUILD_DIR:-$build_dir/nand}"
image_dir="${NAND_IMAGE_DIR:-$nand_dir/images}"
work_dir="${NAND_WORK_DIR:-$nand_dir/work}"
tools_dir="${NAND_TOOLS_DIR:-$repo_root/build/host-tools/bin}"
uboot_dir="${NAND_UBOOT_DIR:-$build_dir/u-boot-legacy}"
dtbo_source="${POCKETCHIP_DTSO:-$repo_root/dts/pocketchip-v73-mainline.dtso}"
uboot_src="${UBOOT_SRC:-$upstreams_dir/u-boot-mainline}"
formats="${NAND_FORMATS:-toshiba-4g-mlc hynix-8g-mlc toshiba-512m-slc}"
keep_raw_ubi="${KEEP_RAW_UBI:-0}"
nand_slc_mode="${NAND_SLC_MODE:-0}"
ubifs_compressor="${NAND_UBIFS_COMPRESSOR:-lzo}"

# Raw NAND boot payload layout. Old CHIP U-Boot can boot from normal raw NAND,
# but it cannot reliably attach the Linux slc-mode UBI image. Keep /boot assets
# outside UBI and let Linux own UBI after the kernel starts.
nand_boot_reserved_mib=80
raw_boot_start_bytes=$((16 * 1024 * 1024))
raw_boot_size_bytes=$((64 * 1024 * 1024))
raw_kernel_slot_bytes=$((8 * 1024 * 1024))
raw_dtb_slot_bytes=$((4 * 1024 * 1024))
raw_initrd_slot_bytes=$((16 * 1024 * 1024))

case "$nand_slc_mode" in
  0|1) ;;
  *) printf 'error: NAND_SLC_MODE must be 0 or 1.\n' >&2; exit 2 ;;
esac

case "$ubifs_compressor" in
  none|lzo|zlib|zstd) ;;
  *) printf 'error: NAND_UBIFS_COMPRESSOR must be none, lzo, zlib, or zstd.\n' >&2; exit 2 ;;
esac

PATH="$tools_dir:$PATH"

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  printf 'error: build-nand-image.sh must run as root for chroot/update-initramfs.\n' >&2
  exit 1
fi

need() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'error: %s is required. Run ./scripts/nand-preflight.sh first.\n' "$1" >&2
    exit 1
  fi
}

for cmd in mkfs.ubifs ubinize img2simg simg2img sunxi-nand-image-builder mkimage dtc fdtoverlay rsync; do
  need "$cmd"
done

if [[ ! -d "$rootfs" ]]; then
  printf 'error: rootfs not found at %s. Run sudo ./scripts/build-rootfs.sh first.\n' "$rootfs" >&2
  exit 1
fi

if [[ ! -d "$uboot_dir" ]]; then
  printf 'error: U-Boot dir not found at %s.\n' "$uboot_dir" >&2
  printf '       Run ./scripts/build-legacy-uboot.sh or set NAND_UBOOT_DIR.\n' >&2
  exit 1
fi

spl="$uboot_dir/spl/sunxi-spl.bin"
runtime_uboot="$uboot_dir/u-boot-dtb.bin"
if [[ ! -f "$runtime_uboot" ]]; then
  runtime_uboot="$uboot_dir/u-boot-dtb-nand.bin"
fi

nand_uboot=""
for candidate in \
  "$uboot_dir/u-boot-dtb-nand.img" \
  "$uboot_dir/u-boot-dtb.img" \
  "$uboot_dir/u-boot.img" \
  "$uboot_dir/u-boot-dtb-nand.bin" \
  "$uboot_dir/u-boot-dtb.bin"; do
  if [[ -f "$candidate" ]]; then
    nand_uboot="$candidate"
    break
  fi
done

if [[ ! -f "$spl" || ! -f "$runtime_uboot" || -z "$nand_uboot" ]]; then
  printf 'error: missing U-Boot SPL or U-Boot image in %s.\n' "$uboot_dir" >&2
  printf '       Expected %s, u-boot-dtb.bin, and preferably u-boot-dtb.img.\n' "$spl" >&2
  exit 1
fi

kernel="$(find "$rootfs/boot" -maxdepth 1 -type f -name 'vmlinuz-*armmp*' -printf '%f\n' 2>/dev/null | sort -V | tail -1 || true)"
if [[ -z "$kernel" ]]; then
  printf 'error: rootfs is missing an armmp kernel in /boot.\n' >&2
  exit 1
fi
version="${kernel#vmlinuz-}"

required_modules=(ofpart sunxi_nand ubi ubifs)
for module in "${required_modules[@]}"; do
  if ! find "$rootfs/lib/modules/$version" -type f -name "$module.ko*" -print -quit | grep -q .; then
    printf 'error: rootfs kernel %s is missing module %s.\n' "$version" "$module" >&2
    exit 1
  fi
done

base_dts="$uboot_src/dts/upstream/src/arm/allwinner/sun5i-r8-chip.dts"
if [[ ! -f "$base_dts" ]]; then
  printf 'error: missing mainline base DTS at %s.\n' "$base_dts" >&2
  exit 1
fi

mkdir -p "$image_dir" "$work_dir"

hex_no_prefix() {
  printf '%x' "$1"
}

write_u64_cells() {
  local value="$1"
  printf '0x%x 0x%08x' "$((value >> 32))" "$((value & 0xffffffff))"
}

format_info() {
  case "$1" in
    hynix-8g-mlc)
      nandtype=mlc
      maxlebcount=4096
      erasesize=4194304
      writesize=16384
      subpagesize=16384
      oobsize=1664
      volume_mib=7168
      total_mib=8192
      ;;
    toshiba-4g-mlc)
      nandtype=mlc
      maxlebcount=4096
      erasesize=4194304
      writesize=16384
      subpagesize=16384
      oobsize=1280
      volume_mib=3584
      total_mib=4096
      ;;
    toshiba-512m-slc)
      nandtype=slc
      maxlebcount=2048
      erasesize=262144
      writesize=4096
      subpagesize=1024
      oobsize=256
      volume_mib=496
      total_mib=512
      ;;
    *)
      printf 'error: unknown NAND format: %s\n' "$1" >&2
      exit 2
      ;;
  esac
}

build_dtb() {
  local out_dir="$1"
  local ubi_part_offset="$2"
  local ubi_part_bytes="$3"
  local slc_mode="$4"
  local overlay="$out_dir/pocketchip-nand.dtso"
  local overlay_pp="$out_dir/pocketchip-nand.dtso.pp"
  local overlay_dtbo="$out_dir/pocketchip-nand.dtbo"
  local pocket_pp="$out_dir/pocketchip-v73-mainline.dtso.pp"
  local pocket_dtbo="$out_dir/pocketchip-v73-mainline.dtbo"
  local base_pp="$out_dir/sun5i-r8-chip.dts.pp"
  local base_dtb="$out_dir/sun5i-r8-chip-symbols.dtb"
  local pocket_dtb="$out_dir/sun5i-r8-pocketchip-base.dtb"
  local out_dtb="$out_dir/sun5i-r8-chip-nand.dtb"
  local boot_offset_cells boot_size_cells ubi_offset_cells ubi_size_cells ubi_slc_mode_prop

  boot_offset_cells="$(write_u64_cells "$raw_boot_start_bytes")"
  boot_size_cells="$(write_u64_cells "$raw_boot_size_bytes")"
  ubi_offset_cells="$(write_u64_cells "$ubi_part_offset")"
  ubi_size_cells="$(write_u64_cells "$ubi_part_bytes")"
  ubi_slc_mode_prop=""
  if [[ "$slc_mode" == 1 ]]; then
    ubi_slc_mode_prop=$'\t\t\t\t\t\tslc-mode;'
  fi

  cpp -nostdinc -undef -x assembler-with-cpp \
    -I "$repo_root/dts" \
    -I "$upstreams_dir/CHIP-linux/include" \
    -I "$upstreams_dir/CHIP-dt-overlays/include" \
    -I "$upstreams_dir/CHIP-dt-overlays" \
    "$dtbo_source" "$pocket_pp"
  dtc -@ -I dts -O dtb -o "$pocket_dtbo" "$pocket_pp"

  cpp -nostdinc -undef -x assembler-with-cpp \
    -I "$uboot_src/dts/upstream/src/arm/allwinner" \
    -I "$uboot_src/dts/upstream/src/arm" \
    -I "$uboot_src/dts/upstream/include" \
    "$base_dts" "$base_pp"
  dtc -@ -I dts -O dtb -o "$base_dtb" "$base_pp"
  fdtoverlay -i "$base_dtb" -o "$pocket_dtb" "$pocket_dtbo"

  cat > "$overlay" <<EOF
/dts-v1/;
/plugin/;

/ {
	compatible = "nextthing,pocketchip", "nextthing,chip", "allwinner,sun5i-r8";

	fragment@0 {
		target = <&nfc>;
		__overlay__ {
			#address-cells = <1>;
			#size-cells = <0>;
			pinctrl-names = "default";
			pinctrl-0 = <&nand_pins &nand_cs0_pin &nand_rb0_pin>;
			status = "okay";

			nand@0 {
				reg = <0>;
				allwinner,rb = <0>;
				nand-ecc-mode = "hw";

				partitions {
					compatible = "fixed-partitions";
					#address-cells = <2>;
					#size-cells = <2>;

					partition@0 {
						label = "spl";
						reg = <0x0 0x00000000 0x0 0x00400000>;
						read-only;
					};

					partition@400000 {
						label = "spl-backup";
						reg = <0x0 0x00400000 0x0 0x00400000>;
						read-only;
					};

					partition@800000 {
						label = "uboot";
						reg = <0x0 0x00800000 0x0 0x00400000>;
						read-only;
					};

					partition@c00000 {
						label = "env";
						reg = <0x0 0x00c00000 0x0 0x00400000>;
					};

					partition@1000000 {
						label = "boot";
						reg = <$boot_offset_cells $boot_size_cells>;
						read-only;
					};

					partition@5000000 {
						label = "UBI";
						reg = <$ubi_offset_cells $ubi_size_cells>;
$ubi_slc_mode_prop
					};
				};
			};
		};
	};
};
EOF

  cpp -nostdinc -undef -x assembler-with-cpp \
    -I "$uboot_src/dts/upstream/src/arm/allwinner" \
    -I "$uboot_src/dts/upstream/src/arm" \
    -I "$uboot_src/dts/upstream/include" \
    "$overlay" "$overlay_pp"
  dtc -@ -I dts -O dtb -o "$overlay_dtbo" "$overlay_pp"
  fdtoverlay -i "$pocket_dtb" -o "$out_dtb" "$overlay_dtbo"
  printf '%s\n' "$out_dtb"
}

pad_asset() {
  local src="$1"
  local dst="$2"
  local align="$3"
  local size padded

  install -m 0644 "$src" "$dst"
  size="$(stat --printf='%s' "$dst")"
  padded=$((((size + align - 1) / align) * align))
  if (( padded > size )); then
    truncate -s "$padded" "$dst"
  fi
}

check_slot_size() {
  local name="$1"
  local path="$2"
  local max_bytes="$3"
  local size

  size="$(stat --printf='%s' "$path")"
  if (( size > max_bytes )); then
    printf 'error: %s is %s bytes, exceeds raw NAND boot slot of %s bytes.\n' \
      "$name" "$size" "$max_bytes" >&2
    exit 1
  fi
}

stage_rootfs() {
  local format="$1"
  local stage="$work_dir/rootfs-$format"
  local dtb="$2"

  rm -rf "$stage"
  mkdir -p "$stage"
  rsync -aHAX --numeric-ids "$rootfs"/ "$stage"/

  install -m 0644 "$dtb" "$stage/boot/sun5i-r8-chip.dtb"
  install -m 0644 "$dtb" "$stage/boot/sun5i-r8-pocketchip.dtb"
  install -m 0644 "$stage/boot/$kernel" "$stage/boot/zImage"
  touch "$stage/etc/initramfs-tools/modules"

  initramfs_modules=(ofpart sunxi_nand ubi ubifs)
  if find "$stage/lib/modules/$version" -type f -name 'zstd.ko*' -print -quit | grep -q .; then
    initramfs_modules=(zstd "${initramfs_modules[@]}")
  fi

  for module in "${initramfs_modules[@]}"; do
    if ! grep -qx "$module" "$stage/etc/initramfs-tools/modules"; then
      printf '%s\n' "$module" >> "$stage/etc/initramfs-tools/modules"
    fi
  done

  chroot "$stage" update-initramfs -u -k "$version" >&2
  mkimage -A arm -O linux -T ramdisk -C none \
    -n "Debian $suite PocketCHIP NAND initramfs" \
    -d "$stage/boot/initrd.img-$version" "$stage/boot/initrd.uimage" >/dev/null

  printf '%s\n' "$stage"
}

prepare_boot_assets() {
  local outputdir="$1"
  local stage="$2"
  local eraseblocksize="$3"
  local pagesize="$4"
  local oob="$5"
  local ebhex phex ohex kernel_out dtb_out initrd_out meta_out kernel_size dtb_size initrd_size

  ebhex="$(hex_no_prefix "$eraseblocksize")"
  phex="$(hex_no_prefix "$pagesize")"
  ohex="$(hex_no_prefix "$oob")"
  kernel_out="$outputdir/boot-zImage-$ebhex-$phex-$ohex.bin"
  dtb_out="$outputdir/boot-sun5i-r8-chip-$ebhex-$phex-$ohex.dtb"
  initrd_out="$outputdir/boot-initrd-$ebhex-$phex-$ohex.uimage"
  meta_out="$outputdir/boot-layout-$ebhex-$phex-$ohex.env"

  pad_asset "$stage/boot/zImage" "$kernel_out" "$pagesize"
  pad_asset "$stage/boot/sun5i-r8-chip.dtb" "$dtb_out" "$pagesize"
  pad_asset "$stage/boot/initrd.uimage" "$initrd_out" "$pagesize"

  check_slot_size "zImage" "$kernel_out" "$raw_kernel_slot_bytes"
  check_slot_size "DTB" "$dtb_out" "$raw_dtb_slot_bytes"
  check_slot_size "initrd.uimage" "$initrd_out" "$raw_initrd_slot_bytes"

  kernel_size="$(stat --printf='%s' "$kernel_out")"
  dtb_size="$(stat --printf='%s' "$dtb_out")"
  initrd_size="$(stat --printf='%s' "$initrd_out")"

  {
    printf 'boot_start=0x%08x\n' "$raw_boot_start_bytes"
    printf 'boot_size=0x%08x\n' "$raw_boot_size_bytes"
    printf 'kernel_offset=0x01000000\n'
    printf 'kernel_size=0x%08x\n' "$kernel_size"
    printf 'dtb_offset=0x02000000\n'
    printf 'dtb_size=0x%08x\n' "$dtb_size"
    printf 'initrd_offset=0x02400000\n'
    printf 'initrd_size=0x%08x\n' "$initrd_size"
    printf 'ubi_offset=0x05000000\n'
  } > "$meta_out"
}

prepare_spl() {
  local outputdir="$1"
  local spl_image="$2"
  local eraseblocksize="$3"
  local pagesize="$4"
  local oob="$5"
  local tmpdir
  tmpdir="$(mktemp -d -p "$work_dir" chip-spl-XXXXXX)"

  local repeat=$((eraseblocksize / pagesize / 64))
  local nandspl="$tmpdir/nand-spl.bin"
  local nandpaddedspl="$tmpdir/nand-padded-spl.bin"
  local padding="$tmpdir/padding"
  local splpadding="$tmpdir/nand-spl-padding"
  local ebhex phex ohex out splsize paddingsize
  ebhex="$(hex_no_prefix "$eraseblocksize")"
  phex="$(hex_no_prefix "$pagesize")"
  ohex="$(hex_no_prefix "$oob")"
  out="$outputdir/spl-$ebhex-$phex-$ohex.bin"

  sunxi-nand-image-builder -c 64/1024 -p "$pagesize" -o "$oob" -u 1024 -e "$eraseblocksize" -b -s "$spl_image" "$nandspl"
  splsize="$(stat --printf='%s' "$nandspl")"
  paddingsize=$((64 - (splsize / (pagesize + oob))))

  : > "$out"
  for ((i = 0; i < repeat; i++)); do
    dd if=/dev/urandom of="$padding" bs=1024 count="$paddingsize" status=none
    sunxi-nand-image-builder -c 64/1024 -p "$pagesize" -o "$oob" -u 1024 -e "$eraseblocksize" -b -s "$padding" "$splpadding"
    cat "$nandspl" "$splpadding" > "$nandpaddedspl"
    cat "$nandpaddedspl" >> "$out"
  done

  rm -rf "$tmpdir"
}

prepare_uboot() {
  local outputdir="$1"
  local uboot_image="$2"
  local eraseblocksize="$3"
  local ebhex out
  ebhex="$(hex_no_prefix "$eraseblocksize")"
  out="$outputdir/uboot-$ebhex.bin"
  install -m 0644 "$uboot_image" "$out"
}

prepare_ubi() {
  local outputdir="$1"
  local stage="$2"
  local format="$3"
  local nandtype="$4"
  local maxleb="$5"
  local eraseblocksize="$6"
  local pagesize="$7"
  local subpage="$8"
  local oob="$9"
  local volume_mib="${10}"
  local ubi_part_bytes="${11}"
  local ebhex phex ohex lebsize mlcopts raw sparse ubifs cfg volspec
  local ubi_erasesize ubi_maxleb sparse_blocksize

  ebhex="$(hex_no_prefix "$eraseblocksize")"
  phex="$(hex_no_prefix "$pagesize")"
  ohex="$(hex_no_prefix "$oob")"
  ubifs="$work_dir/rootfs-$format.ubifs"
  cfg="$work_dir/ubi-$format.cfg"
  raw="$outputdir/chip-$ebhex-$phex-$ohex.ubi"
  sparse="$raw.sparse"
  mlcopts=""
  ubi_erasesize="$eraseblocksize"
  ubi_maxleb="$maxleb"
  sparse_blocksize="$eraseblocksize"

  if [[ "$nandtype" == mlc ]]; then
    if [[ "$nand_slc_mode" == 1 ]]; then
      # Mainline Linux exposes an slc-mode MLC partition as one logical
      # eraseblock per physical paired-page eraseblock, with half erasesize.
      # Leave rootfs autoresize enabled so UBI can reserve wear-leveling and
      # bad-block handling PEBs before expanding the persistent volume.
      ubi_erasesize=$((eraseblocksize / 2))
      ubi_maxleb=$((ubi_part_bytes / eraseblocksize))
      sparse_blocksize="$ubi_erasesize"
      lebsize=$((ubi_erasesize - pagesize * 2))
      volspec="vol_flags=autoresize"
    else
      lebsize=$((eraseblocksize / 2 - pagesize * 2))
      mlcopts="-M dist3"
      volspec="vol_size=${volume_mib}MiB"
    fi
  elif (( subpage < pagesize )); then
    lebsize=$((eraseblocksize - pagesize))
    volspec="vol_flags=autoresize"
  else
    lebsize=$((eraseblocksize - pagesize * 2))
    volspec="vol_flags=autoresize"
  fi

  mkfs.ubifs -x "$ubifs_compressor" -d "$stage" -m "$pagesize" -e "$lebsize" -c "$ubi_maxleb" -o "$ubifs"
  cat > "$cfg" <<EOF
[rootfs]
mode=ubi
vol_id=0
$volspec
vol_type=dynamic
vol_name=rootfs
vol_alignment=1
image=$ubifs
EOF
  # shellcheck disable=SC2086
  ubinize -o "$raw" -p "$ubi_erasesize" -m "$pagesize" -s "$subpage" $mlcopts "$cfg"
  img2simg "$raw" "$sparse" "$sparse_blocksize"
  simg2img "$sparse" "$work_dir/verify-$format.ubi"
  cmp -s "$raw" "$work_dir/verify-$format.ubi"
  rm -f "$work_dir/verify-$format.ubi"
  if [[ "$keep_raw_ubi" != 1 ]]; then
    rm -f "$raw"
  fi
}

install -m 0644 "$spl" "$image_dir/sunxi-spl.bin"
install -m 0644 "$runtime_uboot" "$image_dir/u-boot-dtb.bin"
install -m 0644 "$nand_uboot" "$image_dir/u-boot-nand.img"
printf '%s\n' "$nand_slc_mode" > "$image_dir/nand_slc_mode"

for format in $formats; do
  format_info "$format"
  rootfs_mib="$(du -sm "$rootfs" | awk '{print $1}')"
  rootfs_budget_mib="$volume_mib"
  if [[ "$nandtype" == mlc && "$nand_slc_mode" == 1 ]]; then
    rootfs_budget_mib=$(((total_mib - nand_boot_reserved_mib) / 2))
  fi
  if (( rootfs_mib > rootfs_budget_mib - 64 )); then
    printf 'skip    %-18s rootfs %sMiB exceeds NAND volume budget %sMiB\n' "$format" "$rootfs_mib" "$rootfs_budget_mib"
    continue
  fi

  printf 'build   %s\n' "$format"
  if [[ "$nandtype" == mlc ]]; then
    if [[ "$nand_slc_mode" == 1 ]]; then
      printf 'info    %-18s enabling Linux MTD slc-mode on the UBI partition\n' "$format" >&2
    else
      printf 'warn    %-18s mainline Linux UBI refuses MLC NAND without slc-mode or a kernel-side override\n' "$format" >&2
    fi
  fi
  fmt_dir="$work_dir/$format"
  mkdir -p "$fmt_dir"
  ubi_part_offset=$((nand_boot_reserved_mib * 1024 * 1024))
  ubi_part_bytes=$(((total_mib - nand_boot_reserved_mib) * 1024 * 1024))
  format_slc_mode=0
  if [[ "$nandtype" == mlc && "$nand_slc_mode" == 1 ]]; then
    format_slc_mode=1
  fi
  dtb="$(build_dtb "$fmt_dir" "$ubi_part_offset" "$ubi_part_bytes" "$format_slc_mode")"
  stage="$(stage_rootfs "$format" "$dtb")"
  prepare_boot_assets "$image_dir" "$stage" "$erasesize" "$writesize" "$oobsize"
  prepare_spl "$image_dir" "$spl" "$erasesize" "$writesize" "$oobsize"
  prepare_uboot "$image_dir" "$nand_uboot" "$erasesize"
  prepare_ubi "$image_dir" "$stage" "$format" "$nandtype" "$maxlebcount" "$erasesize" "$writesize" "$subpagesize" "$oobsize" "$volume_mib" "$ubi_part_bytes"
done

printf '\nNAND artifacts written to %s\n' "$image_dir"
find "$image_dir" -maxdepth 1 -type f -printf '  %f %s bytes\n' | sort
