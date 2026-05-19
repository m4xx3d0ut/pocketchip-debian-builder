#!/usr/bin/env bash
set -euo pipefail

config="${1:-}"
image="${2:-}"

if [[ -z "$config" || ! -f "$config" ]]; then
  printf 'usage: %s /path/to/.config [/path/to/u-boot-sunxi-with-spl.bin]\n' "$0" >&2
  exit 2
fi

missing=0

has() {
  local key="$1"
  grep -Eq "^${key}=y$" "$config"
}

require() {
  local key="$1"
  local why="$2"
  if has "$key"; then
    printf 'ok      %-28s %s\n' "$key" "$why"
  else
    printf 'missing %-28s %s\n' "$key" "$why"
    missing=1
  fi
}

require CONFIG_ARCH_SUNXI "Allwinner sunxi platform"
require CONFIG_MACH_SUN5I "A13/R8 sun5i target"
require CONFIG_USB_EHCI_HCD "USB host controller"
require CONFIG_USB_OHCI_HCD "USB companion host controller"
require CONFIG_CMD_USB "U-Boot usb command"
require CONFIG_USB_STORAGE "USB mass-storage support"
require CONFIG_CMD_EXT4 "ext4 filesystem loading"
require CONFIG_CMD_BOOTZ "ARM zImage boot command"

if has CONFIG_CMD_SYSBOOT || has CONFIG_BOOTSTD; then
  printf 'ok      %-28s extlinux/sysboot or bootstd path\n' 'CONFIG_CMD_SYSBOOT|CONFIG_BOOTSTD'
else
  printf 'missing %-28s extlinux/sysboot or bootstd path\n' 'CONFIG_CMD_SYSBOOT|CONFIG_BOOTSTD'
  missing=1
fi

if grep -Eq '^CONFIG_DEFAULT_DEVICE_TREE="(allwinner/)?sun5i-r8-chip"$' "$config"; then
  printf 'ok      %-28s sun5i-r8-chip\n' CONFIG_DEFAULT_DEVICE_TREE
else
  printf 'missing %-28s expected sun5i-r8-chip\n' CONFIG_DEFAULT_DEVICE_TREE
  missing=1
fi

if [[ -n "$image" ]]; then
  if [[ -s "$image" ]]; then
    printf 'ok      %-28s %s\n' u-boot-sunxi-with-spl.bin "$image"
  else
    printf 'missing %-28s %s\n' u-boot-sunxi-with-spl.bin "$image"
    missing=1
  fi
fi

if (( missing != 0 )); then
  exit 1
fi

printf '\nU-Boot config looks suitable for the FEL USB-rootfs milestone.\n'

