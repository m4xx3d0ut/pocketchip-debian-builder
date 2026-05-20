#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
nand_dir="${NAND_BUILD_DIR:-$repo_root/build/nand-slc}"
work_dir="${NAND_WORK_DIR:-$nand_dir/work}"
format="${NAND_RESCUE_FORMAT:-toshiba-4g-mlc}"
payload="${NAND_RESCUE_UBIFS:-$work_dir/rootfs-$format.ubifs}"
mountpoint="${1:-${NAND_RESCUE_USB_MOUNT:-}}"
dest_rel="${NAND_RESCUE_USB_PAYLOAD:-pocketchip/rootfs.ubifs}"

if [[ -z "$mountpoint" ]]; then
  printf 'usage: %s /path/to/mounted/usb\n' "$0" >&2
  printf 'or set NAND_RESCUE_USB_MOUNT=/path/to/mounted/usb\n' >&2
  exit 2
fi

if [[ ! -f "$payload" ]]; then
  printf 'error: UBIFS payload not found: %s\n' "$payload" >&2
  exit 1
fi

if [[ ! -d "$mountpoint" ]]; then
  printf 'error: mountpoint does not exist: %s\n' "$mountpoint" >&2
  exit 1
fi

if ! findmnt -T "$mountpoint" >/dev/null 2>&1; then
  printf 'error: %s does not appear to be on a mounted filesystem\n' "$mountpoint" >&2
  exit 1
fi

dest="$mountpoint/$dest_rel"
mkdir -p "$(dirname "$dest")"
install -m 0644 "$payload" "$dest"
sha256sum "$dest" > "$dest.sha256"
sync "$mountpoint"

printf 'payload %s\n' "$dest"
printf 'size    %s bytes\n' "$(stat --printf='%s' "$dest")"
printf 'sha256  %s\n' "$(awk '{print $1}' "$dest.sha256")"
