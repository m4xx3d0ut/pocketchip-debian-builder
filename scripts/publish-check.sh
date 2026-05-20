#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

fail() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

section() {
  printf '\n== %s ==\n' "$*"
}

section "tracked artifact guard"
forbidden="$(git ls-files | grep -E '(^build/|^\.local/|^configs/local\.env$|\.img$|\.dtb$|\.dtbo$|\.py[co]$)' || true)"
if [[ -n "$forbidden" ]]; then
  printf '%s\n' "$forbidden" >&2
  fail "publish-blocking generated/local files are tracked"
fi
printf 'ok\n'

section "high-signal secret scan"
raw_secret_matches="$(git grep -n -I -E 'AKIA[0-9A-Z]{16}|BEGIN (RSA |OPENSSH |EC |DSA )?PRIVATE KEY|POCKETCHIP_ROOT_PASSWORD=[^#[:space:]].+|POCKETCHIP_WIFI_PSK=[^#[:space:]].+' || true)"
secret_matches="$(printf '%s\n' "$raw_secret_matches" | grep -Ev 'temporary-lab-password|your-password|POCKETCHIP_ROOT_PASSWORD=[.][.][.]|scripts/publish-check.sh' || true)"
if [[ -n "$secret_matches" ]]; then
  printf '%s\n' "$secret_matches" >&2
  fail "possible tracked secret found"
fi
printf 'ok\n'

section "whitespace"
git diff --check

section "shell syntax"
while IFS= read -r file; do
  bash -n "$file"
done < <(git grep -Il '^#!.*sh' -- scripts configs)
printf 'ok\n'

section "python syntax"
if compgen -G 'scripts/*.py' >/dev/null; then
  python3 -m py_compile scripts/*.py
fi
printf 'ok\n'

section "sudoers syntax"
if command -v visudo >/dev/null 2>&1; then
  for file in configs/sudoers-*; do
    [[ -e "$file" ]] || continue
    visudo -cf "$file" >/dev/null
  done
  printf 'ok\n'
else
  printf 'skipped: visudo not installed\n'
fi

section "default image config without local.env"
defaults="$(env -i PATH="$PATH" HOME="${HOME:-}" ./scripts/build-rootfs.sh --no-local-env --print-defaults)"
printf '%s\n' "$defaults"
grep -qx 'POCKETCHIP_IMAGE_PROFILE=balanced' <<<"$defaults" || fail "unexpected default image profile"
grep -qx 'POCKETCHIP_ROOT_AUTH=locked' <<<"$defaults" || fail "root is not locked by default"
grep -qx 'POCKETCHIP_ROOT_PASSWORD_SET=no' <<<"$defaults" || fail "root password is set by default"
grep -qx 'POCKETCHIP_USER=chip' <<<"$defaults" || fail "unexpected default user"
grep -qx 'POCKETCHIP_USER_PASSWORD_SET=no' <<<"$defaults" || fail "user password is set by default"
grep -qx 'POCKETCHIP_WIFI_SSID_SET=no' <<<"$defaults" || fail "Wi-Fi SSID is set by default"
grep -qx 'POCKETCHIP_WIFI_PSK_SET=no' <<<"$defaults" || fail "Wi-Fi PSK is set by default"
grep -qx 'POCKETCHIP_BG_IMAGE=' <<<"$defaults" || fail "wallpaper asset is required by default"
grep -qx 'POCKETCHIP_BOOT_VIDEO=' <<<"$defaults" || fail "boot video asset is required by default"
grep -qx 'POCKETCHIP_BOOT_ANIMATION=0' <<<"$defaults" || fail "boot animation is enabled by default"
grep -qx 'POCKETCHIP_DARK_MODE=1' <<<"$defaults" || fail "dark mode is not enabled by default"
grep -qx 'POCKETCHIP_NETWORK_TIME=1' <<<"$defaults" || fail "network time is not enabled by default"

if [[ "${REQUIRE_CLEAN:-0}" == 1 ]]; then
  section "clean worktree"
  [[ -z "$(git status --short)" ]] || fail "worktree is not clean"
  printf 'ok\n'
fi

printf '\npublish checks passed\n'
