#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
wt_dir="$(cd "$repo_root/.." && pwd)"
upstreams_dir="${UPSTREAMS_DIR:-$wt_dir/upstreams}"
sunxi_url="${SUNXI_TOOLS_URL:-https://github.com/linux-sunxi/sunxi-tools.git}"
sunxi_ref="${SUNXI_TOOLS_REF:-master}"
sunxi_src="${SUNXI_TOOLS_SRC:-$upstreams_dir/sunxi-tools}"
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

if [[ ! -d "$sunxi_src/.git" ]]; then
  git clone --filter=blob:none "$sunxi_url" "$sunxi_src"
fi

git -C "$sunxi_src" fetch --tags --prune origin
git -C "$sunxi_src" checkout --force "$sunxi_ref"

make -C "$sunxi_src" misc -j"$jobs"
install -m 0755 "$sunxi_src/sunxi-nand-image-builder" "$tools_dir/sunxi-nand-image-builder"

printf 'built %s\n' "$tools_dir/sunxi-nand-image-builder"
