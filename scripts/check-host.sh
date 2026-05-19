#!/usr/bin/env bash
set -euo pipefail

missing=0

need() {
  if command -v "$1" >/dev/null 2>&1; then
    printf 'ok      %s\n' "$1"
  else
    printf 'missing %s\n' "$1"
    missing=1
  fi
}

optional() {
  if command -v "$1" >/dev/null 2>&1; then
    printf 'ok      %s\n' "$1"
  else
    printf 'optional %s\n' "$1"
  fi
}

need git
need curl
need gpg
need make
need gcc
need arm-linux-gnueabihf-gcc
need python3
need bison
need flex
need swig
need openssl
need bc
need cpp
need dtc
need lsinitramfs
need mmdebstrap
need mke2fs
need losetup
need sfdisk
need rsync
need qemu-arm-static
need sunxi-fel
optional fastboot
optional mkimage

if [[ -r /usr/include/openssl/ssl.h ]]; then
  printf 'ok      libssl-dev headers\n'
else
  printf 'missing libssl-dev headers\n'
  missing=1
fi

if [[ -r /proc/sys/fs/binfmt_misc/qemu-arm ]]; then
  if grep -q 'enabled' /proc/sys/fs/binfmt_misc/qemu-arm 2>/dev/null; then
    printf 'ok      qemu-arm binfmt\n'
  else
    printf 'missing qemu-arm binfmt is not enabled\n'
    missing=1
  fi
else
  printf 'missing qemu-arm binfmt registration\n'
  missing=1
fi

if (( missing != 0 )); then
  cat <<'MSG'

Install the expected Debian/Ubuntu host dependencies with:

  sudo apt install \
    bc binfmt-support bison build-essential device-tree-compiler e2fsprogs \
    curl fastboot flex gcc-arm-linux-gnueabihf git gnupg libssl-dev mmdebstrap openssl swig \
    qemu-user-static ripgrep rsync sunxi-tools u-boot-tools util-linux

MSG
  exit 1
fi

printf '\nHost looks ready.\n'
