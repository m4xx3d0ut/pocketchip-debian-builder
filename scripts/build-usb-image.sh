#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
suite="${SUITE:-trixie}"
arch="${ARCH:-armhf}"
build_dir="${BUILD_DIR:-$repo_root/build}"
rootfs="${ROOTFS:-$build_dir/rootfs-$suite-$arch}"
image_dir="${IMAGE_DIR:-$build_dir/images}"
image="${IMAGE:-$image_dir/pocketchip-debian-$suite-$arch.img}"
size_mb="${SIZE_MB:-4096}"
label="${ROOT_LABEL:-pocketroot}"
dtbo="${DTBO:-$build_dir/dtbo/pocketchip-v73-mainline.dtbo}"
merged_dtb="${MERGED_DTB:-$build_dir/dtbo/sun5i-r8-pocketchip.dtb}"

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  printf 'error: build-usb-image.sh must run as root for loop devices and mounts.\n' >&2
  exit 1
fi

for cmd in losetup lsinitramfs mkfs.ext4 mount rsync sfdisk sync umount; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    printf 'error: %s is required.\n' "$cmd" >&2
    exit 1
  fi
done

if [[ ! -d "$rootfs" ]]; then
  printf 'error: rootfs not found at %s. Run sudo ./scripts/build-rootfs.sh first.\n' "$rootfs" >&2
  exit 1
fi

kernel="$(find "$rootfs/boot" -maxdepth 1 -type f -name 'vmlinuz-*armmp*' -printf '%f\n' 2>/dev/null | sort -V | tail -1 || true)"
if [[ -z "$kernel" ]]; then
  printf 'error: rootfs is incomplete: no armmp kernel found in %s/boot.\n' "$rootfs" >&2
  printf '       Rebuild it with: FORCE=1 sudo ./scripts/build-rootfs.sh\n' >&2
  exit 1
fi

version="${kernel#vmlinuz-}"
if [[ ! -x "$rootfs/sbin/init" ]]; then
  printf 'error: rootfs is incomplete: missing executable %s/sbin/init.\n' "$rootfs" >&2
  exit 1
fi

if [[ ! -f "$rootfs/boot/initrd.img-$version" ]]; then
  printf 'error: rootfs is incomplete: missing %s/boot/initrd.img-%s.\n' "$rootfs" "$version" >&2
  exit 1
fi

required_initrd_modules=(
  i2c-mv64xxx.ko
  axp20x-regulator.ko
  axp20x_usb_power.ko
  axp20x_ac_power.ko
  axp20x_battery.ko
  axp20x_adc.ko
  pinctrl-axp209.ko
  phy-sun4i-usb.ko
  ehci-platform.ko
  ohci-platform.ko
  usb-storage.ko
  uas.ko
  scsi_common.ko
  scsi_mod.ko
  sd_mod.ko
  ext4.ko
)
initrd_listing="$(lsinitramfs "$rootfs/boot/initrd.img-$version")"
for module in "${required_initrd_modules[@]}"; do
  if ! grep -Fq "/$module" <<<"$initrd_listing"; then
    printf 'error: rootfs initrd is missing %s for USB-root boot.\n' "$module" >&2
    printf '       Reinstall %s into /etc/initramfs-tools/modules and run update-initramfs.\n' "$module" >&2
    exit 1
  fi
done

if ! find "$rootfs/usr/lib/linux-image-$version" -type f -name 'sun5i-r8-chip.dtb' -print -quit | grep -q .; then
  printf 'error: rootfs is incomplete: missing sun5i-r8-chip.dtb for %s.\n' "$version" >&2
  exit 1
fi

if [[ -e "$image" && "${FORCE:-0}" != 1 ]]; then
  printf 'error: %s already exists. Set FORCE=1 to replace it.\n' "$image" >&2
  exit 1
fi

mkdir -p "$image_dir"
tmp_image="$(mktemp "$image_dir/.tmp-$(basename "$image").XXXXXX")"
rm -f "$tmp_image"
cleanup_image() {
  local rc=$?
  if (( rc != 0 )); then
    rm -f "$tmp_image"
  fi
  exit "$rc"
}
trap cleanup_image EXIT

truncate -s "${size_mb}M" "$tmp_image"

sfdisk "$tmp_image" >/dev/null <<'EOF'
label: dos
unit: sectors

start=2048, type=83, bootable
EOF

loopdev="$(losetup --find --partscan --show "$tmp_image")"
mount_dir="$(mktemp -d)"

cleanup() {
  set +e
  mountpoint -q "$mount_dir" && umount "$mount_dir"
  losetup -d "$loopdev" >/dev/null 2>&1 || true
  rmdir "$mount_dir" >/dev/null 2>&1 || true
  if [[ "${BUILD_USB_IMAGE_SUCCESS:-0}" != 1 ]]; then
    rm -f "$tmp_image"
  fi
}
trap cleanup EXIT

part="${loopdev}p1"
for _ in {1..20}; do
  [[ -b "$part" ]] && break
  sleep 0.25
done

if [[ ! -b "$part" ]]; then
  printf 'error: partition device %s did not appear.\n' "$part" >&2
  exit 1
fi

mkfs.ext4 -F -L "$label" "$part" >/dev/null
mount "$part" "$mount_dir"
rsync -aHAX --numeric-ids "$rootfs"/ "$mount_dir"/

mkdir -p "$mount_dir/boot/extlinux" "$mount_dir/boot/overlays"
if [[ -f "$dtbo" ]]; then
  install -m 0644 "$dtbo" "$mount_dir/boot/overlays/pocketchip-v73-mainline.dtbo"
else
  printf 'warning: DTBO not found at %s; PocketCHIP overlay artifact will not be copied.\n' "$dtbo" >&2
fi

kernel="$(find "$mount_dir/boot" -maxdepth 1 -type f -name 'vmlinuz-*armmp*' -printf '%f\n' | sort -V | tail -1)"
if [[ -z "$kernel" ]]; then
  printf 'error: no armmp kernel found in rootfs /boot.\n' >&2
  exit 1
fi

version="${kernel#vmlinuz-}"
initrd="initrd.img-$version"
if [[ ! -f "$mount_dir/boot/$initrd" ]]; then
  printf 'error: missing /boot/%s in rootfs.\n' "$initrd" >&2
  exit 1
fi

if [[ -f "$merged_dtb" ]]; then
  install -m 0644 "$merged_dtb" "$mount_dir/boot/sun5i-r8-pocketchip.dtb"
  dtb_path="/boot/sun5i-r8-pocketchip.dtb"
else
  printf 'warning: merged PocketCHIP DTB not found at %s; falling back to base CHIP DTB.\n' "$merged_dtb" >&2
  printf '         Run ./scripts/build-pocketchip-dtbo.sh before building the image for LCD/keyboard DT support.\n' >&2
  dtb="$(find "$mount_dir/usr/lib/linux-image-$version" -type f -name 'sun5i-r8-chip.dtb' -print -quit 2>/dev/null || true)"
  if [[ -z "$dtb" ]]; then
    printf 'error: could not find sun5i-r8-chip.dtb for %s.\n' "$version" >&2
    exit 1
  fi
  dtb_path="/${dtb#"$mount_dir"/}"
fi

cat > "$mount_dir/boot/extlinux/extlinux.conf" <<EOF
DEFAULT debian
TIMEOUT 30
PROMPT 1

LABEL debian
  MENU LABEL Debian $suite PocketCHIP USB rootfs
  LINUX /boot/$kernel
  INITRD /boot/$initrd
  FDT $dtb_path
  APPEND console=ttyS0,115200 root=LABEL=$label rootwait rw loglevel=4
EOF

sync
BUILD_USB_IMAGE_SUCCESS=1
umount "$mount_dir"
losetup -d "$loopdev"
rmdir "$mount_dir"
mv -f "$tmp_image" "$image"
trap - EXIT
printf 'built %s\n' "$image"
