#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
suite="${SUITE:-trixie}"
arch="${ARCH:-armhf}"
build_dir="${BUILD_DIR:-$repo_root/build}"
rootfs="${ROOTFS:-$build_dir/rootfs-$suite-$arch}"
nand_dir="${NAND_BUILD_DIR:-$build_dir/nand-slc}"
image_dir="${NAND_IMAGE_DIR:-$nand_dir/images}"
work_dir="${NAND_WORK_DIR:-$nand_dir/work}"
format="${NAND_RESCUE_FORMAT:-toshiba-4g-mlc}"
apt_install="${NAND_RESCUE_APT_INSTALL:-1}"
device_ip="${NAND_RESCUE_DEVICE_IP:-172.16.42.2}"
host_ip="${NAND_RESCUE_HOST_IP:-172.16.42.1}"
port="${NAND_RESCUE_PORT:-4242}"
source_mode="${NAND_RESCUE_SOURCE:-net}"
usb_payload_path="${NAND_RESCUE_USB_PAYLOAD:-pocketchip/rootfs.ubifs}"

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  printf 'error: build-nand-rescue-initramfs.sh must run as root.\n' >&2
  exit 1
fi

need() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'error: %s is required.\n' "$1" >&2
    exit 1
  fi
}

for cmd in cpio gzip mkimage arm-linux-gnueabihf-readelf chroot install; do
  need "$cmd"
done

if [[ ! -d "$rootfs" ]]; then
  printf 'error: rootfs not found at %s\n' "$rootfs" >&2
  exit 1
fi

kernel="$(find "$rootfs/boot" -maxdepth 1 -type f -name 'vmlinuz-*armmp*' -printf '%f\n' 2>/dev/null | sort -V | tail -1 || true)"
if [[ -z "$kernel" ]]; then
  printf 'error: rootfs is missing an armmp kernel in /boot.\n' >&2
  exit 1
fi
version="${kernel#vmlinuz-}"

suffix="400000-4000-500"
case "$format" in
  toshiba-4g-mlc) suffix="400000-4000-500" ;;
  *) printf 'error: unsupported rescue format %s\n' "$format" >&2; exit 2 ;;
esac

ubifs="$work_dir/rootfs-$format.ubifs"
kernel_image="$image_dir/boot-zImage-$suffix.bin"
dtb_image="$image_dir/boot-sun5i-r8-chip-$suffix.dtb"
if [[ ! -f "$ubifs" || ! -f "$kernel_image" || ! -f "$dtb_image" ]]; then
  printf 'error: missing NAND artifacts. Run make nand-image-mlc-pc-slc first.\n' >&2
  printf '  expected %s\n' "$ubifs" >&2
  printf '  expected %s\n' "$kernel_image" >&2
  printf '  expected %s\n' "$dtb_image" >&2
  exit 1
fi

if [[ ! -x "$rootfs/usr/sbin/ubiformat" || ! -x "$rootfs/usr/sbin/ubiupdatevol" || ! -x "$rootfs/bin/busybox" ]]; then
  if [[ "$apt_install" != 1 ]]; then
    printf 'error: rootfs lacks mtd-utils or busybox-static. Re-run with NAND_RESCUE_APT_INSTALL=1.\n' >&2
    exit 1
  fi
  printf 'install %-18s mtd-utils busybox-static into %s\n' rescue "$rootfs"
  chroot "$rootfs" apt-get update
  DEBIAN_FRONTEND=noninteractive chroot "$rootfs" \
    apt-get install -y --no-install-recommends mtd-utils busybox-static
  chroot "$rootfs" apt-get clean
fi

install -d -m 0755 \
  "$rootfs/etc/pocketchip" \
  "$rootfs/etc/initramfs-tools/hooks" \
  "$rootfs/etc/initramfs-tools/scripts/local-top"

ubifs_size="$(stat --printf='%s' "$ubifs")"
ubifs_sha256="$(sha256sum "$ubifs" | awk '{print $1}')"
cat > "$rootfs/etc/pocketchip/nand-rescue.env" <<EOF
ROOTFS_UBIFS_SIZE=$ubifs_size
ROOTFS_UBIFS_SHA256=$ubifs_sha256
DEVICE_IP=$device_ip
HOST_IP=$host_ip
PORT=$port
SOURCE=$source_mode
USB_PAYLOAD_PATH=$usb_payload_path
EOF

modules_file="$rootfs/etc/initramfs-tools/modules"
modules_backup="$work_dir/initramfs-tools-modules.rescue.bak"
cp -a "$modules_file" "$modules_backup"
cleanup_rescue_initramfs_tools() {
  if [[ -f "$modules_backup" ]]; then
    cp -a "$modules_backup" "$modules_file"
  fi
  rm -f \
    "$rootfs/etc/initramfs-tools/hooks/pocketchip-nand-rescue" \
    "$rootfs/etc/initramfs-tools/scripts/local-top/pocketchip-nand-rescue" \
    "$rootfs/etc/pocketchip/nand-rescue.env"
}
trap cleanup_rescue_initramfs_tools EXIT

for module in ofpart sunxi_nand ubi phy_sun4i_usb phy_generic musb_hdrc sunxi ehci-platform ohci-platform usb-storage uas scsi_common scsi_mod sd_mod ext4 vfat fat nls_ascii nls_cp437; do
  if ! grep -Eq "^[[:space:]]*$module([[:space:]]|\$)" "$modules_file"; then
    printf '%s\n' "$module" >> "$modules_file"
  fi
done

cat > "$rootfs/etc/initramfs-tools/hooks/pocketchip-nand-rescue" <<'EOF'
#!/bin/sh
set -e

PREREQ=""
prereqs() { echo "$PREREQ"; }
case "${1:-}" in
  prereqs) prereqs; exit 0 ;;
esac

. /usr/share/initramfs-tools/hook-functions

copy_exec /bin/busybox /bin/busybox
copy_exec /usr/sbin/ip /usr/sbin/ip
copy_exec /usr/sbin/ubiformat /usr/sbin/ubiformat
copy_exec /usr/sbin/ubiattach /usr/sbin/ubiattach
copy_exec /usr/sbin/ubidetach /usr/sbin/ubidetach
copy_exec /usr/sbin/ubimkvol /usr/sbin/ubimkvol
copy_exec /usr/sbin/ubiupdatevol /usr/sbin/ubiupdatevol
copy_exec /usr/sbin/ubinfo /usr/sbin/ubinfo
copy_file config /etc/pocketchip/nand-rescue.env /etc/pocketchip/nand-rescue.env
manual_add_modules g_ether usb_f_rndis u_ether libcomposite
EOF
chmod 0755 "$rootfs/etc/initramfs-tools/hooks/pocketchip-nand-rescue"

cat > "$rootfs/etc/initramfs-tools/scripts/local-top/pocketchip-nand-rescue" <<'EOF'
#!/bin/sh
set -eu

PREREQ=""
prereqs() { echo "$PREREQ"; }
case "${1:-}" in
  prereqs) prereqs; exit 0 ;;
esac

case " $(cat /proc/cmdline) " in
  *" pocketchip_nand_rescue=1 "*) ;;
  *) exit 0 ;;
esac

PATH=/sbin:/usr/sbin:/bin:/usr/bin
export PATH

. /scripts/functions
. /etc/pocketchip/nand-rescue.env

log_rescue() {
  echo "[rescue] $*"
  echo "[rescue] $*" >/dev/console 2>/dev/null || true
}

die_rescue() {
  log_rescue "ERROR: $*"
  log_rescue "Dropping to initramfs shell."
  exec sh
}

dmesg -n 4 2>/dev/null || true
log_rescue "PocketCHIP NAND rescue installer booted"
log_rescue "rootfs UBIFS payload size: $ROOTFS_UBIFS_SIZE bytes"
log_rescue "payload source mode: $SOURCE"

for module in ofpart sunxi_nand ubi; do
  modprobe "$module" 2>/dev/null || log_rescue "module $module not loaded explicitly"
done
sleep 2

cat /proc/mtd >/dev/console 2>/dev/null || true
mtd_num="$(awk -F: '$2 ~ /"UBI"/ { sub(/^mtd/, "", $1); print $1; exit }' /proc/mtd)"
[ -n "$mtd_num" ] || die_rescue "could not find MTD partition named UBI"
mtd_dev="/dev/mtd$mtd_num"
[ -c "$mtd_dev" ] || die_rescue "$mtd_dev is missing"

log_rescue "formatting $mtd_dev with Linux mtd-utils"
ubidetach -m "$mtd_num" 2>/dev/null || true
ubiformat "$mtd_dev" -y || die_rescue "ubiformat failed"

log_rescue "attaching UBI on mtd$mtd_num"
ubiattach /dev/ubi_ctrl -m "$mtd_num" || die_rescue "ubiattach failed"

if [ ! -e /dev/ubi0_0 ]; then
  log_rescue "creating autoresized rootfs volume"
  ubimkvol /dev/ubi0 -N rootfs -m || die_rescue "ubimkvol failed"
fi

verify_payload() {
  payload="$1"
  size="$(wc -c < "$payload" | busybox awk '{print $1}')"
  [ "$size" = "$ROOTFS_UBIFS_SIZE" ] ||
    die_rescue "payload size mismatch: got $size expected $ROOTFS_UBIFS_SIZE"
  sha="$(busybox sha256sum "$payload" | busybox awk '{print $1}')"
  [ "$sha" = "$ROOTFS_UBIFS_SHA256" ] ||
    die_rescue "payload sha256 mismatch: got $sha expected $ROOTFS_UBIFS_SHA256"
}

install_from_usb() {
  log_rescue "waiting for USB storage payload: $USB_PAYLOAD_PATH"
  for module in phy_sun4i_usb ehci-platform ohci-platform usb-storage uas scsi_common scsi_mod sd_mod ext4 vfat fat nls_ascii nls_cp437; do
    modprobe "$module" 2>/dev/null || log_rescue "module $module not loaded explicitly"
  done

  mount_dir="/run/pocketchip-rescue-usb"
  mkdir -p "$mount_dir"
  payload=""
  for _ in $(seq 1 240); do
    for dev in /dev/sd*[0-9] /dev/sd*; do
      [ -b "$dev" ] || continue
      umount "$mount_dir" 2>/dev/null || true
      if mount -o ro "$dev" "$mount_dir" 2>/dev/null; then
        if [ -f "$mount_dir/$USB_PAYLOAD_PATH" ]; then
          payload="$mount_dir/$USB_PAYLOAD_PATH"
          break
        fi
        for candidate in "$mount_dir"/rootfs*.ubifs "$mount_dir"/pocketchip/*.ubifs; do
          [ -f "$candidate" ] || continue
          payload="$candidate"
          break
        done
        [ -n "$payload" ] && break
        umount "$mount_dir" 2>/dev/null || true
      fi
    done
    [ -n "$payload" ] && break
    sleep 1
  done
  [ -n "$payload" ] || die_rescue "USB payload not found"

  log_rescue "found payload $payload"
  verify_payload "$payload"
  log_rescue "writing USB payload to /dev/ubi0_0"
  ubiupdatevol /dev/ubi0_0 "$payload" ||
    die_rescue "USB ubiupdatevol failed"
  umount "$mount_dir" 2>/dev/null || true
}

install_from_net() {
  log_rescue "starting USB gadget Ethernet"
  for module in phy_sun4i_usb phy_generic musb_hdrc sunxi; do
    modprobe "$module" 2>/dev/null || log_rescue "module $module not loaded explicitly"
  done
  for _ in $(seq 1 80); do
    ls /sys/class/udc/* >/dev/null 2>&1 && break
    sleep 0.25
  done
  ls /sys/class/udc/* >/dev/null 2>&1 ||
    die_rescue "no USB device controller visible before g_ether"
  modprobe -r g_ether usb_f_rndis u_ether 2>/dev/null || true
  modprobe g_ether host_addr=02:00:de:ad:42:01 dev_addr=02:00:de:ad:42:02 2>/dev/null ||
    die_rescue "could not load g_ether"

  iface=""
  for _ in $(seq 1 80); do
    for net in /sys/class/net/*; do
      name="$(basename "$net")"
      [ "$name" = lo ] && continue
      [ "$name" = usb0 ] || [ "$name" = eth0 ] || [ -e "$net/device" ] || continue
      iface="$name"
      break
    done
    [ -n "$iface" ] && break
    sleep 0.25
  done
  [ -n "$iface" ] || die_rescue "no USB gadget network interface appeared"

  ip link set "$iface" up || die_rescue "could not bring $iface up"
  ip addr add "$DEVICE_IP/24" dev "$iface" 2>/dev/null || true
  log_rescue "waiting for host stream on $DEVICE_IP:$PORT via $iface"
  busybox nc -l -p "$PORT" | ubiupdatevol /dev/ubi0_0 -s "$ROOTFS_UBIFS_SIZE" - ||
    die_rescue "network ubiupdatevol failed"
}

case "$SOURCE" in
  usb) install_from_usb ;;
  net) install_from_net ;;
  *) die_rescue "unsupported SOURCE=$SOURCE" ;;
esac

sync
log_rescue "install complete; rebooting"
sleep 2
ubinfo /dev/ubi0 >/dev/console 2>/dev/null || true
reboot -f
sleep 30
exec sh
EOF
chmod 0755 "$rootfs/etc/initramfs-tools/scripts/local-top/pocketchip-nand-rescue"

rescue_out_rel="/tmp/pocketchip-rescue-initramfs"
rescue_out="$rootfs$rescue_out_rel"
rm -rf "$rescue_out"
install -d -m 0755 "$rescue_out"
chroot "$rootfs" update-initramfs -c -k "$version" -b "$rescue_out_rel" >&2

stock_initrd="$rescue_out/initrd.img-$version"
out_uimage="$image_dir/nand-rescue-initrd-$suffix.uimage"
install -m 0644 "$stock_initrd" "$image_dir/nand-rescue-initramfs-$suffix.cpio.gz"
mkimage -A arm -T ramdisk -C none -n "PocketCHIP NAND rescue installer" -d "$stock_initrd" "$out_uimage"
rm -rf "$rescue_out"

cleanup_rescue_initramfs_tools
trap - EXIT

printf 'rescue %-18s %s\n' initramfs "$image_dir/nand-rescue-initramfs-$suffix.cpio.gz"
printf 'rescue %-18s %s\n' uimage "$out_uimage"
printf 'rescue %-18s %s (%s bytes)\n' rootfs "$ubifs" "$ubifs_size"
exit 0
