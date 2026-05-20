#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
local_env="${LOCAL_ENV:-$repo_root/configs/local.env}"
if [[ -r "$local_env" ]]; then
  set -a
  # shellcheck source=/dev/null
  . "$local_env"
  set +a
fi
wt_dir="$(cd "$repo_root/.." && pwd)"
upstreams_dir="${UPSTREAMS_DIR:-$wt_dir/upstreams}"
uboot_url="${UBOOT_URL:-https://source.denx.de/u-boot/u-boot.git}"
uboot_ref="${UBOOT_REF:-v2026.04}"
uboot_src="${UBOOT_SRC:-$upstreams_dir/u-boot-mainline}"
build_dir="${UBOOT_NAND_BUILD_DIR:-$repo_root/build/u-boot-mainline-nand}"
cross_compile="${CROSS_COMPILE:-arm-linux-gnueabihf-}"
jobs="${JOBS:-$(nproc 2>/dev/null || echo 2)}"
pocketchip_spectre_v2_mitigation="${POCKETCHIP_SPECTRE_V2_MITIGATION:-1}"

nand_erasesize="${NAND_ERASESIZE:-0x400000}"
nand_writesize="${NAND_WRITESIZE:-0x4000}"
nand_oobsize="${NAND_OOBSIZE:-0x680}"
nand_max_eccpos="${NAND_MAX_ECCPOS:-1664}"

case "$pocketchip_spectre_v2_mitigation" in
  0|1) ;;
  *) printf 'error: POCKETCHIP_SPECTRE_V2_MITIGATION must be 0 or 1.\n' >&2; exit 2 ;;
esac

need() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'error: %s is required.\n' "$1" >&2
    exit 1
  fi
}

need git
need make
need "${cross_compile}gcc"
need fdtoverlay

mkdir -p "$upstreams_dir" "$build_dir"

if [[ ! -d "$uboot_src/.git" ]]; then
  git clone --filter=blob:none "$uboot_url" "$uboot_src"
fi

git -C "$uboot_src" fetch --tags --prune origin
git -C "$uboot_src" checkout --force "$uboot_ref"

if [[ "$pocketchip_spectre_v2_mitigation" == 1 ]] &&
   ! grep -q 'select ARM_CORTEX_A8_CVE_2017_5715' "$uboot_src/arch/arm/mach-sunxi/Kconfig"; then
  git -C "$uboot_src" apply "$repo_root/patches/u-boot-mainline/sun5i-cortex-a8-spectre-v2.patch"
fi

make -C "$uboot_src" O="$build_dir" CROSS_COMPILE="$cross_compile" CHIP_defconfig

config_tool="$uboot_src/scripts/config"
if [[ ! -x "$config_tool" ]]; then
  printf 'error: missing U-Boot config helper at %s\n' "$config_tool" >&2
  exit 1
fi

config_args=(
  --file "$build_dir/.config"
  -e CONFIG_USB_EHCI_HCD
  -e CONFIG_USB_OHCI_HCD
  -e CONFIG_CMD_USB
  -e CONFIG_USB_STORAGE
  -e CONFIG_CMD_EXT4
  -e CONFIG_CMD_BOOTZ
  -e CONFIG_CMD_SYSBOOT
  -e CONFIG_CMD_MTDPARTS
  -e CONFIG_CMD_NAND
  -e CONFIG_CMD_NAND_TRIMFFS
  -e CONFIG_CMD_UBI
  -e CONFIG_CMD_UBIFS
  -e CONFIG_MTD
  -e CONFIG_MTD_PARTITIONS
  -e CONFIG_MTD_RAW_NAND
  -e CONFIG_NAND_SUNXI
  -e CONFIG_SYS_NAND_ONFI_DETECTION
  --set-str CONFIG_MTDIDS_DEFAULT 'nand0=sunxi-nand.0' \
  --set-str CONFIG_MTDPARTS_DEFAULT 'mtdparts=sunxi-nand.0:4m(spl),4m(spl-backup),4m(uboot),4m(env),-(UBI)' \
  --set-val CONFIG_SYS_MAX_NAND_DEVICE 8 \
  --set-val CONFIG_SYS_NAND_BLOCK_SIZE "$nand_erasesize" \
  --set-val CONFIG_SYS_NAND_PAGE_SIZE "$nand_writesize" \
  --set-val CONFIG_SYS_NAND_OOBSIZE "$nand_oobsize" \
  --set-val CONFIG_SYS_NAND_MAX_ECCPOS "$nand_max_eccpos" \
  --set-val CONFIG_NAND_SUNXI_SPL_ECC_STRENGTH 64 \
  --set-val CONFIG_NAND_SUNXI_SPL_ECC_SIZE 1024 \
  --set-val CONFIG_NAND_SUNXI_SPL_USABLE_PAGE_SIZE 1024
)
if [[ "$pocketchip_spectre_v2_mitigation" == 1 ]]; then
  config_args+=(-e CONFIG_ARM_CORTEX_A8_CVE_2017_5715)
else
  config_args+=(-d CONFIG_ARM_CORTEX_A8_CVE_2017_5715)
fi
"$config_tool" "${config_args[@]}"

make -C "$uboot_src" O="$build_dir" CROSS_COMPILE="$cross_compile" olddefconfig
make -C "$uboot_src" O="$build_dir" CROSS_COMPILE="$cross_compile" -j"$jobs"

overlay_dir="$build_dir/nand-dtb"
mkdir -p "$overlay_dir"
cat > "$overlay_dir/nand-enable.dtso" <<'EOF'
/dts-v1/;
/plugin/;

/ {
	compatible = "nextthing,chip", "allwinner,sun5i-r8";

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
			};
		};
	};
};
EOF

dtc -@ -I dts -O dtb -o "$overlay_dir/nand-enable.dtbo" "$overlay_dir/nand-enable.dtso"
fdtoverlay -i "$build_dir/u-boot.dtb" -o "$overlay_dir/u-boot-nand.dtb" "$overlay_dir/nand-enable.dtbo"
cat "$build_dir/u-boot-nodtb.bin" "$overlay_dir/u-boot-nand.dtb" > "$build_dir/u-boot-dtb-nand.bin"

printf 'built mainline NAND U-Boot probe:\n'
printf '  %s\n' "$build_dir/spl/sunxi-spl.bin"
printf '  %s\n' "$build_dir/u-boot-dtb-nand.bin"
