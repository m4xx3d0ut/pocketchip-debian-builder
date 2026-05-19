#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
wt_dir="$(cd "$repo_root/.." && pwd)"
upstreams_dir="${UPSTREAMS_DIR:-$wt_dir/upstreams}"

mkdir -p "$upstreams_dir"

clone_or_update() {
  local name="$1"
  local url="$2"
  local branch="$3"
  local depth="${4:-}"
  local dest="$upstreams_dir/$name"

  if [[ -d "$dest/.git" ]]; then
    git -C "$dest" fetch --all --prune --tags
    git -C "$dest" checkout "$branch"
    git -C "$dest" pull --ff-only origin "$branch"
  else
    if [[ -n "$depth" ]]; then
      git clone --depth="$depth" --single-branch --branch "$branch" --filter=blob:none "$url" "$dest"
    else
      git clone --branch "$branch" --filter=blob:none "$url" "$dest"
    fi
  fi

  printf '%-18s %s %s\n' "$name" "$(git -C "$dest" rev-parse --abbrev-ref HEAD)" "$(git -C "$dest" rev-parse --short HEAD)"
}

clone_or_update CHIP-tools https://github.com/Project-chip-crumbs/CHIP-tools.git chip/stable
clone_or_update CHIP-dt-overlays https://github.com/Project-chip-crumbs/CHIP-dt-overlays.git master
clone_or_update CHIP-u-boot https://github.com/Project-chip-crumbs/CHIP-u-boot.git chip/stable
clone_or_update CHIP-linux https://github.com/Project-chip-crumbs/CHIP-linux.git ntc-stable-4.4.y 1

printf '\nUpstreams are in %s\n' "$upstreams_dir"

