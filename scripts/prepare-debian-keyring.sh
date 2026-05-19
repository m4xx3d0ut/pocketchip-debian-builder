#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
keyring_dir="${KEYRING_DIR:-$repo_root/build/keyrings}"
keyring="${KEYRING:-$keyring_dir/debian-trixie-archive-keyring.gpg}"
base_url="${DEBIAN_KEY_BASE_URL:-https://ftp-master.debian.org/keys}"

need() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'error: %s is required.\n' "$1" >&2
    exit 1
  fi
}

need curl
need gpg

mkdir -p "$keyring_dir"
tmpdir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmpdir"
}
trap cleanup EXIT

keys=(
  archive-key-12.asc
  archive-key-12-security.asc
  release-12.asc
  archive-key-13.asc
  archive-key-13-security.asc
  release-13.asc
)

for key in "${keys[@]}"; do
  curl -fsSL "$base_url/$key" -o "$tmpdir/$key"
done

cat "$tmpdir"/*.asc | gpg --batch --dearmor > "$keyring.tmp"
mv -f "$keyring.tmp" "$keyring"
chmod 0644 "$keyring"

printf '%s\n' "$keyring"

