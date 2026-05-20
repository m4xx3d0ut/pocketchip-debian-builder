#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
wt_dir="$(cd "$repo_root/.." && pwd)"
upstreams_dir="${UPSTREAMS_DIR:-$wt_dir/upstreams}"
src="${CHIP_MTD_UTILS_SRC:-$upstreams_dir/chip-mtd-utils}"
url="${CHIP_MTD_UTILS_URL:-https://github.com/Project-chip-crumbs/chip-mtd-utils.git}"
ref="${CHIP_MTD_UTILS_REF:-origin/nextthing/1.5.2/next-mlc}"
build_dir="${CHIP_MTD_UTILS_BUILD_DIR:-$repo_root/build/chip-mtd-utils}"
tools_dir="${NAND_TOOLS_DIR:-$repo_root/build/host-tools/bin}"
jobs="${JOBS:-$(nproc 2>/dev/null || echo 2)}"

need() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'error: %s is required.\n' "$1" >&2
    exit 1
  fi
}

need git
need make
need gcc

mkdir -p "$upstreams_dir" "$tools_dir"

if [[ ! -d "$src/.git" ]]; then
  git clone --filter=blob:none "$url" "$src"
fi

git -C "$src" fetch --all --prune --tags
git -C "$src" checkout --force "$ref"

# Older mtd-utils used local variables named major/minor in the same expression
# as glibc device-number helpers. Rename the locals in this checkout so it
# builds on current Debian hosts.
if rg -q 'int i, fd, major, minor|int i, major, minor|int major, minor' "$src/ubi-utils/libubi.c"; then
  perl -0pi -e '
    s/int i, fd, major, minor;/int i, fd, dev_major, dev_minor;/g;
    s/int i, major, minor;/int i, dev_major, dev_minor;/g;
    s/int major, minor;/int dev_major, dev_minor;/g;
    s/\bmajor = major\(st\.st_rdev\);/dev_major = major(st.st_rdev);/g;
    s/\bminor = minor\(st\.st_rdev\);/dev_minor = minor(st.st_rdev);/g;
    s/\bmajor = major\(sb\.st_rdev\);/dev_major = major(sb.st_rdev);/g;
    s/\bminor = minor\(sb\.st_rdev\);/dev_minor = minor(sb.st_rdev);/g;
    s/\bminor == 0\b/dev_minor == 0/g;
    s/\bminor != 0\b/dev_minor != 0/g;
    s/\bmajor1 == major\b/major1 == dev_major/g;
    s/\bmajor != MTD_CHAR_MAJOR\b/dev_major != MTD_CHAR_MAJOR/g;
    s/\bminor \/ 2\b/dev_minor \/ 2/g;
    s/minor - 1/dev_minor - 1/g;
    s/\*vol_id = minor/\*vol_id = dev_minor/g;
    s/node, major, minor/node, dev_major, dev_minor/g;
  ' "$src/ubi-utils/libubi.c"
fi

rm -rf "$build_dir"
make -C "$src" WITHOUT_XATTR=1 BUILDDIR="$build_dir" -j"$jobs" "$build_dir/ubi-utils/ubinize"
install -m 0755 "$build_dir/ubi-utils/ubinize" "$tools_dir/ubinize"

if ! "$tools_dir/ubinize" -M dist3 -h >/dev/null 2>&1; then
  printf 'error: built ubinize does not accept -M dist3.\n' >&2
  exit 1
fi

printf 'built patched MLC ubinize:\n'
printf '  %s\n' "$tools_dir/ubinize"
