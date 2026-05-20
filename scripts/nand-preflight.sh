#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tools_dir="${NAND_TOOLS_DIR:-$repo_root/build/host-tools/bin}"

PATH="$tools_dir:$PATH"

missing=0

need() {
  if command -v "$1" >/dev/null 2>&1; then
    printf 'ok      %-28s %s\n' "$1" "$(command -v "$1")"
  else
    printf 'missing %-28s\n' "$1"
    missing=1
  fi
}

optional() {
  if command -v "$1" >/dev/null 2>&1; then
    printf 'ok      %-28s %s\n' "$1" "$(command -v "$1")"
  else
    printf 'optional %-28s\n' "$1"
  fi
}

printf 'NAND host tool preflight\n'
printf 'tools dir: %s\n\n' "$tools_dir"

need mkfs.ubifs
need ubinize
if command -v ubinize >/dev/null 2>&1 && ubinize -M dist3 -h >/dev/null 2>&1; then
  printf 'ok      %-28s MLC -M dist3 supported\n' ubinize-mlc
else
  printf 'missing %-28s MLC -M dist3 support\n' ubinize-mlc
  missing=1
fi
need img2simg
need simg2img
need sunxi-nand-image-builder
need sunxi-fel
need fastboot
need mkimage
need dtc
need fdtoverlay
need rsync
need qemu-arm-static
optional arm-linux-gnueabi-gcc
optional arm-linux-gnueabihf-gcc

if [[ -r /proc/sys/fs/binfmt_misc/qemu-arm ]] &&
   grep -q 'enabled' /proc/sys/fs/binfmt_misc/qemu-arm 2>/dev/null; then
  printf 'ok      %-28s enabled\n' qemu-arm-binfmt
else
  printf 'missing %-28s\n' qemu-arm-binfmt
  missing=1
fi

if (( missing != 0 )); then
  cat <<EOF

Install packaged NAND dependencies with:

  sudo apt install mtd-utils android-sdk-libsparse-utils fastboot u-boot-tools

If sunxi-nand-image-builder is still missing, build the local misc sunxi tools:

  ./scripts/build-sunxi-tools-misc.sh

If ubinize lacks MLC -M dist3 support, build the local patched CHIP mtd-utils:

  ./scripts/build-chip-mtd-utils.sh

The legacy CHIP U-Boot build may require a soft-float ARM compiler:

  sudo apt install gcc-arm-linux-gnueabi

EOF
  exit 1
fi

printf '\nNAND host tools look ready.\n'
