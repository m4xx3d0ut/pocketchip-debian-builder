#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
wt_dir="$(cd "$repo_root/.." && pwd)"
upstreams_dir="${UPSTREAMS_DIR:-$wt_dir/upstreams}"
sunxi_fel="${SUNXI_FEL:-sunxi-fel}"

if ! command -v "$sunxi_fel" >/dev/null 2>&1; then
  printf 'error: %s is required. Install sunxi-tools.\n' "$sunxi_fel" >&2
  exit 1
fi

uboot_image="${UBOOT_IMAGE:-}"
if [[ -z "$uboot_image" ]]; then
  for candidate in \
    "$repo_root/build/u-boot-mainline/u-boot-sunxi-with-spl.bin" \
    "$repo_root/build/u-boot/u-boot-sunxi-with-spl.bin" \
    /usr/lib/u-boot/CHIP/u-boot-sunxi-with-spl.bin \
    "$upstreams_dir/CHIP-u-boot/u-boot-sunxi-with-spl.bin"; do
    if [[ -f "$candidate" ]]; then
      uboot_image="$candidate"
      break
    fi
  done
fi

if [[ -z "$uboot_image" || ! -f "$uboot_image" ]]; then
  cat >&2 <<'MSG'
error: no U-Boot SPL image found.

Install Debian's u-boot-sunxi package for armhf or build U-Boot, then set:

  ./scripts/build-mainline-uboot.sh

or:

  UBOOT_IMAGE=/path/to/u-boot-sunxi-with-spl.bin sudo ./scripts/fel-boot.sh

MSG
  exit 1
fi

printf 'Booting %s via FEL...\n' "$uboot_image"
exec "$sunxi_fel" uboot "$uboot_image"
