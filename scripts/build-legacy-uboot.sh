#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
local_env="${LOCAL_ENV:-$repo_root/configs/local.env}"
if [[ -r "$local_env" ]]; then
  set -a
  # shellcheck source=/dev/null
  . "$local_env"
  set +a
fi
wt_dir="$(cd "$repo_root/.." && pwd)"
upstreams_dir="${UPSTREAMS_DIR:-$wt_dir/upstreams}"
uboot_src="${LEGACY_UBOOT_SRC:-$upstreams_dir/CHIP-u-boot}"
build_dir="${LEGACY_UBOOT_BUILD_DIR:-$repo_root/build/u-boot-legacy}"
uboot_ref="${LEGACY_UBOOT_REF:-}"
uboot_patches="${LEGACY_UBOOT_PATCHES:-}"
uboot_worktree="${LEGACY_UBOOT_WORKTREE_DIR:-}"
isolated_src="${LEGACY_UBOOT_ISOLATED_SRC:-auto}"
cross_compile="${CROSS_COMPILE:-arm-linux-gnueabi-}"
jobs="${JOBS:-$(nproc 2>/dev/null || echo 2)}"
pocketchip_spectre_v2_mitigation="${POCKETCHIP_SPECTRE_V2_MITIGATION:-1}"

case "$pocketchip_spectre_v2_mitigation" in
  0|1) ;;
  *) printf 'error: POCKETCHIP_SPECTRE_V2_MITIGATION must be 0 or 1.\n' >&2; exit 2 ;;
esac

need() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'error: %s is required.\n' "$1" >&2
    exit 1
  fi
}

if [[ ! -d "$uboot_src" ]]; then
  printf 'error: missing legacy U-Boot source at %s; run ./scripts/fetch-upstreams.sh first.\n' "$uboot_src" >&2
  exit 1
fi

need make
need "${cross_compile}gcc"

mkdir -p "$build_dir"
build_dir="$(cd "$build_dir" && pwd)"

if [[ "$isolated_src" == auto ]]; then
  if [[ -n "$uboot_patches" ]]; then
    isolated_src=1
  else
    isolated_src=0
  fi
fi

case "$isolated_src" in
  0|1) ;;
  *) printf 'error: LEGACY_UBOOT_ISOLATED_SRC must be auto, 0, or 1.\n' >&2; exit 2 ;;
esac

if [[ "$isolated_src" == 1 ]]; then
  need git
  src_ref="${uboot_ref:-HEAD}"
  worktree_dir="${uboot_worktree:-$build_dir-src}"
  if [[ "$worktree_dir" != /* ]]; then
    worktree_dir="$repo_root/$worktree_dir"
  fi

  git -C "$uboot_src" fetch --all --prune --tags
  git -C "$uboot_src" worktree remove --force "$worktree_dir" >/dev/null 2>&1 || rm -rf "$worktree_dir"
  git -C "$uboot_src" worktree prune
  git -C "$uboot_src" worktree add --force --detach "$worktree_dir" "$src_ref"
  uboot_src="$worktree_dir"

  for patch in $uboot_patches; do
    if [[ "$patch" != /* ]]; then
      patch="$repo_root/$patch"
    fi
    if [[ ! -f "$patch" ]]; then
      printf 'error: U-Boot patch not found: %s\n' "$patch" >&2
      exit 2
    fi
    printf 'apply   %s\n' "$patch"
    git -C "$uboot_src" apply --3way "$patch"
  done
elif [[ -n "$uboot_ref" ]]; then
  need git
  git -C "$uboot_src" fetch --all --prune --tags
  git -C "$uboot_src" checkout --force "$uboot_ref"
fi

mkdir -p "$build_dir/include/linux"

make -C "$uboot_src" O="$build_dir" CROSS_COMPILE="$cross_compile" CHIP_defconfig
if [[ "$pocketchip_spectre_v2_mitigation" == 1 ]]; then
  extra_options="$(sed -n 's/^CONFIG_SYS_EXTRA_OPTIONS="\([^"]*\)"/\1/p' "$build_dir/.config")"
  if [[ -n "$extra_options" && "$extra_options" != *POCKETCHIP_CORTEX_A8_SPECTRE_V2* ]]; then
    extra_options="$extra_options,POCKETCHIP_CORTEX_A8_SPECTRE_V2"
    sed -i "s/^CONFIG_SYS_EXTRA_OPTIONS=.*/CONFIG_SYS_EXTRA_OPTIONS=\"$extra_options\"/" "$build_dir/.config"
  elif [[ -z "$extra_options" ]]; then
    printf 'CONFIG_SYS_EXTRA_OPTIONS="POCKETCHIP_CORTEX_A8_SPECTRE_V2"\n' >> "$build_dir/.config"
  fi
fi
make -C "$uboot_src" O="$build_dir" CROSS_COMPILE="$cross_compile" silentoldconfig

# This U-Boot vintage has a broken out-of-tree host-tool include path: some
# host compile commands include the source tree's linux/kconfig.h, which then
# expects source-tree include/generated/autoconf.h. Mirror the generated file
# only for the duration of this build.
src_generated="$uboot_src/include/generated"
src_autoconf="$src_generated/autoconf.h"
build_autoconf="$build_dir/include/generated/autoconf.h"
backup_autoconf=""

cleanup_autoconf() {
  if [[ -n "$backup_autoconf" && -f "$backup_autoconf" ]]; then
    mv "$backup_autoconf" "$src_autoconf"
  else
    rm -f "$src_autoconf"
    rmdir "$src_generated" 2>/dev/null || true
  fi
}
trap cleanup_autoconf EXIT

mkdir -p "$src_generated"
if [[ -e "$src_autoconf" ]]; then
  backup_autoconf="$(mktemp -p "$build_dir" legacy-autoconf.XXXXXX)"
  cp -a "$src_autoconf" "$backup_autoconf"
fi
cp "$build_autoconf" "$src_autoconf"

# CHIP-u-boot predates modern GCC version header names. Keep the compatibility
# shim in the out-of-tree build dir instead of patching the upstream checkout.
gcc_major="$("${cross_compile}gcc" -dumpversion | cut -d. -f1)"
if [[ ! -f "$uboot_src/include/linux/compiler-gcc${gcc_major}.h" ]]; then
  cp "$uboot_src/include/linux/compiler-gcc5.h" "$build_dir/include/linux/compiler-gcc${gcc_major}.h"
fi

# Force the normal build path to regenerate include/config.h and autoconf.mk.
# Some CHIP branches leave include/config/auto.conf in place after defconfig,
# which prevents that compatibility header from being created.
rm -f \
  "$build_dir/include/config/auto.conf" \
  "$build_dir/include/config/auto.conf.cmd" \
  "$build_dir/include/autoconf.mk" \
  "$build_dir/include/autoconf.mk.dep" \
  "$build_dir/include/config.h"

# The production MLC PocketCHIP branch advertises u-boot-sunxi-with-spl.bin as
# its default target but only defines that rule behind a stale CONFIG_SUNXI
# Makefile guard. Build the two NAND-flow artifacts explicitly.
make -C "$uboot_src" O="$build_dir" CROSS_COMPILE="$cross_compile" -j"$jobs" \
  spl/sunxi-spl.bin u-boot-dtb.bin u-boot-dtb.img

printf 'built legacy U-Boot:\n'
printf '  %s\n' "$build_dir/spl/sunxi-spl.bin"
printf '  %s\n' "$build_dir/u-boot-dtb.bin"
printf '  %s\n' "$build_dir/u-boot-dtb.img"
