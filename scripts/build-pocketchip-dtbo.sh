#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
wt_dir="$(cd "$repo_root/.." && pwd)"
upstreams_dir="${UPSTREAMS_DIR:-$wt_dir/upstreams}"
source_dtso="${SOURCE_DTSO:-$repo_root/dts/pocketchip-v73-mainline.dtso}"
build_dir="${BUILD_DIR:-$repo_root/build/dtbo}"
out_dtbo="${OUT_DTBO:-$build_dir/pocketchip-v73-mainline.dtbo}"
out_dtb="${OUT_DTB:-$build_dir/sun5i-r8-pocketchip.dtb}"
uboot_src="${UBOOT_SRC:-$upstreams_dir/u-boot-mainline}"

for cmd in cpp dtc fdtoverlay; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    printf 'error: %s is required. Install device-tree-compiler and build-essential/cpp.\n' "$cmd" >&2
    exit 1
  fi
done

if [[ ! -d "$upstreams_dir/CHIP-linux/include/dt-bindings" ]]; then
  printf 'error: missing CHIP-linux include files; run ./scripts/fetch-upstreams.sh first.\n' >&2
  exit 1
fi

base_dts="$uboot_src/dts/upstream/src/arm/allwinner/sun5i-r8-chip.dts"
if [[ ! -f "$base_dts" ]]; then
  printf 'error: missing mainline U-Boot DTS source at %s.\n' "$base_dts" >&2
  printf '       Run ./scripts/build-mainline-uboot.sh first.\n' >&2
  exit 1
fi

mkdir -p "$build_dir"
preprocessed="$build_dir/$(basename "$source_dtso").pp"
base_preprocessed="$build_dir/sun5i-r8-chip.dts.pp"
base_dtb="$build_dir/sun5i-r8-chip-symbols.dtb"

cpp -nostdinc -undef -x assembler-with-cpp \
  -I "$repo_root/dts" \
  -I "$upstreams_dir/CHIP-linux/include" \
  -I "$upstreams_dir/CHIP-dt-overlays/include" \
  -I "$upstreams_dir/CHIP-dt-overlays" \
  "$source_dtso" "$preprocessed"

dtc -@ -I dts -O dtb -o "$out_dtbo" "$preprocessed"

cpp -nostdinc -undef -x assembler-with-cpp \
  -I "$uboot_src/dts/upstream/src/arm/allwinner" \
  -I "$uboot_src/dts/upstream/src/arm" \
  -I "$uboot_src/dts/upstream/include" \
  "$base_dts" "$base_preprocessed"

dtc -@ -I dts -O dtb -o "$base_dtb" "$base_preprocessed"
fdtoverlay -i "$base_dtb" -o "$out_dtb" "$out_dtbo"

printf 'built %s\n' "$out_dtbo"
printf 'built %s\n' "$out_dtb"
