#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
wt_dir="$(cd "$repo_root/.." && pwd)"
upstreams_dir="${UPSTREAMS_DIR:-$wt_dir/upstreams}"
uboot_url="${UBOOT_URL:-https://source.denx.de/u-boot/u-boot.git}"
uboot_ref="${UBOOT_REF:-v2026.04}"
uboot_src="${UBOOT_SRC:-$upstreams_dir/u-boot-mainline}"
build_dir="${UBOOT_BUILD_DIR:-$repo_root/build/u-boot-mainline}"
cross_compile="${CROSS_COMPILE:-arm-linux-gnueabihf-}"
jobs="${JOBS:-$(nproc 2>/dev/null || echo 2)}"

need() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'error: %s is required.\n' "$1" >&2
    exit 1
  fi
}

need git
need make
need "${cross_compile}gcc"

mkdir -p "$upstreams_dir" "$build_dir"

if [[ ! -d "$uboot_src/.git" ]]; then
  git clone --filter=blob:none "$uboot_url" "$uboot_src"
fi

git -C "$uboot_src" fetch --tags --prune origin
git -C "$uboot_src" checkout --force "$uboot_ref"

make -C "$uboot_src" O="$build_dir" CROSS_COMPILE="$cross_compile" CHIP_defconfig

config_tool="$uboot_src/scripts/config"
if [[ "${UBOOT_SKIP_CONFIG_TWEAKS:-0}" != 1 && -x "$config_tool" ]]; then
  "$config_tool" --file "$build_dir/.config" \
    -e CONFIG_USB_EHCI_HCD \
    -e CONFIG_USB_OHCI_HCD \
    -e CONFIG_CMD_USB \
    -e CONFIG_USB_STORAGE \
    -e CONFIG_CMD_EXT4 \
    -e CONFIG_CMD_BOOTZ \
    -e CONFIG_CMD_SYSBOOT || true
  make -C "$uboot_src" O="$build_dir" CROSS_COMPILE="$cross_compile" olddefconfig
fi

"$repo_root/scripts/verify-uboot-config.sh" "$build_dir/.config"

make -C "$uboot_src" O="$build_dir" CROSS_COMPILE="$cross_compile" -j"$jobs"

"$repo_root/scripts/verify-uboot-config.sh" "$build_dir/.config" "$build_dir/u-boot-sunxi-with-spl.bin"

printf '\nBuilt mainline U-Boot:\n  %s\n' "$build_dir/u-boot-sunxi-with-spl.bin"
printf 'Use it with:\n  UBOOT_IMAGE=%q sudo ./scripts/fel-boot.sh\n' "$build_dir/u-boot-sunxi-with-spl.bin"
