#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
suite="${SUITE:-trixie}"
arch="${ARCH:-armhf}"
mirror="${MIRROR:-http://deb.debian.org/debian}"
security_mirror="${SECURITY_MIRROR:-http://security.debian.org/debian-security}"
build_dir="${BUILD_DIR:-$repo_root/build}"
rootfs="${ROOTFS:-$build_dir/rootfs-$suite-$arch}"
packages_file="${PACKAGES_FILE:-$repo_root/configs/debian-trixie-armhf.packages}"
default_password="${DEFAULT_PASSWORD:-chip}"
install_oh_my_zsh="${INSTALL_OH_MY_ZSH:-1}"
debian_keyring="${DEBIAN_KEYRING:-$build_dir/keyrings/debian-trixie-archive-keyring.gpg}"
initramfs_modules_file="${INITRAMFS_MODULES_FILE:-$repo_root/configs/initramfs-modules}"

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  printf 'error: build-rootfs.sh must run as root because it creates device nodes and chroots.\n' >&2
  exit 1
fi

for cmd in mmdebstrap chroot install lsinitramfs rsync; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    printf 'error: %s is required.\n' "$cmd" >&2
    exit 1
  fi
done

host_arch="$(dpkg --print-architecture 2>/dev/null || uname -m)"
if [[ "$host_arch" != "$arch" && "$host_arch" != armhf && "$host_arch" != armv7l ]]; then
  if [[ ! -r /proc/sys/fs/binfmt_misc/qemu-arm ]] || ! grep -q enabled /proc/sys/fs/binfmt_misc/qemu-arm; then
    printf 'error: qemu-arm binfmt is required for foreign armhf chroot configuration.\n' >&2
    printf '       Install qemu-user-static and binfmt-support, then retry.\n' >&2
    exit 1
  fi
fi

if [[ -e "$rootfs" && "${FORCE:-0}" != 1 ]]; then
  printf 'error: %s already exists. Set FORCE=1 to replace it.\n' "$rootfs" >&2
  exit 1
fi

if [[ -e "$rootfs" ]]; then
  rm -rf "$rootfs"
fi

cleanup_failed_rootfs() {
  local rc=$?
  if (( rc != 0 )); then
    printf 'error: rootfs build failed; removing incomplete %s\n' "$rootfs" >&2
    rm -rf "$rootfs"
  fi
  exit "$rc"
}
trap cleanup_failed_rootfs EXIT

package_csv="$(awk 'NF && $1 !~ /^#/ { print $1 }' "$packages_file" | paste -sd, -)"

mkdir -p "$build_dir"

if [[ ! -f "$debian_keyring" ]]; then
  debian_keyring="$("$repo_root/scripts/prepare-debian-keyring.sh")"
fi

mmdebstrap \
  --architectures="$arch" \
  --components='main,contrib,non-free-firmware' \
  --variant=minbase \
  --keyring="$debian_keyring" \
  --include="$package_csv" \
  "$suite" "$rootfs" \
  "$mirror"

cat > "$rootfs/etc/apt/sources.list" <<EOF
deb $mirror $suite main contrib non-free-firmware
deb $mirror $suite-updates main contrib non-free-firmware
deb $security_mirror $suite-security main contrib non-free-firmware
EOF

printf 'pocketchip\n' > "$rootfs/etc/hostname"
cat > "$rootfs/etc/hosts" <<'EOF'
127.0.0.1 localhost
127.0.1.1 pocketchip

::1 localhost ip6-localhost ip6-loopback
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
EOF

chip_groups="sudo,adm,dialout,video,input,audio"
if chroot "$rootfs" getent group netdev >/dev/null 2>&1; then
  chip_groups="$chip_groups,netdev"
fi

chroot "$rootfs" useradd -m -s /usr/bin/zsh -G "$chip_groups" chip
printf 'root:%s\nchip:%s\n' "$default_password" "$default_password" | chroot "$rootfs" chpasswd
install -m 0644 "$initramfs_modules_file" "$rootfs/etc/initramfs-tools/modules"
ln -sfn ../lib/systemd/systemd "$rootfs/usr/sbin/init"
chroot "$rootfs" update-initramfs -u -k all
chroot "$rootfs" apt-get clean

install -m 0644 "$repo_root/configs/zshrc" "$rootfs/home/chip/.zshrc"
install -m 0644 "$repo_root/configs/xinitrc" "$rootfs/home/chip/.xinitrc"
install -d -m 0755 "$rootfs/home/chip/.config/i3"
install -m 0644 "$repo_root/configs/i3-config" "$rootfs/home/chip/.config/i3/config"

if [[ "$install_oh_my_zsh" == 1 ]]; then
  if command -v git >/dev/null 2>&1; then
    git clone --depth=1 https://github.com/ohmyzsh/ohmyzsh.git "$rootfs/home/chip/.oh-my-zsh"
  else
    printf 'warning: git missing on host; skipping Oh My Zsh clone.\n' >&2
  fi
fi

chip_uid="$(chroot "$rootfs" id -u chip)"
chip_gid="$(chroot "$rootfs" id -g chip)"
chown -R "$chip_uid:$chip_gid" "$rootfs/home/chip"

kernel="$(find "$rootfs/boot" -maxdepth 1 -type f -name 'vmlinuz-*armmp*' -printf '%f\n' | sort -V | tail -1)"
if [[ -z "$kernel" ]]; then
  printf 'error: rootfs is missing an armmp kernel in /boot.\n' >&2
  exit 1
fi

version="${kernel#vmlinuz-}"
if [[ ! -x "$rootfs/sbin/init" ]]; then
  printf 'error: rootfs is missing executable /sbin/init.\n' >&2
  exit 1
fi

if [[ ! -f "$rootfs/boot/initrd.img-$version" ]]; then
  printf 'error: rootfs is missing initrd.img-%s.\n' "$version" >&2
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
    printf 'error: initrd.img-%s is missing %s for USB-root boot.\n' "$version" "$module" >&2
    exit 1
  fi
done

if ! find "$rootfs/usr/lib/linux-image-$version" -type f -name 'sun5i-r8-chip.dtb' -print -quit | grep -q .; then
  printf 'error: rootfs is missing sun5i-r8-chip.dtb for %s.\n' "$version" >&2
  exit 1
fi

trap - EXIT

printf '\nBuilt rootfs at %s\n' "$rootfs"
printf 'Default prototype credentials: root/%s and chip/%s\n' "$default_password" "$default_password"
