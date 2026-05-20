# PocketCHIP Trixie Release Checklist

Use this before tagging or uploading public artifacts.

## Source Hygiene

- Worktree is clean, or only intentional release edits are staged.
- `make publish-check` passes.
- `git ls-files` does not include `configs/local.env`, `.local/`, `build/`,
  generated images, generated DTBs, caches, or logs.
- No build logs, screenshots, UART captures, or docs contain private Wi-Fi
  credentials, local passwords, tokens, or private paths.
- `LICENSE` is present and the release notes identify the project as
  GPL-2.0-only.

## Default Image

- Build once with no `configs/local.env`.
- Confirm `scripts/build-rootfs.sh --no-local-env --print-defaults` reports:
  locked root, user `chip`, no root/user password set, no Wi-Fi SSID/PSK set,
  dark mode enabled, network time enabled, boot animation disabled, and no local
  wallpaper or boot video required.
- Confirm rootfs build output redacts passwords and prints only whether
  passwords are set.

## Device Acceptance

- Boot USB/FEL image and confirm Debian 13/Trixie reaches serial login or i3.
- Boot NAND/SLC image only on the known tested target and keep release notes
  marked experimental unless more hardware variants are validated.
- Capture rootfs version, kernel version, U-Boot version, and NAND geometry.
- Confirm Spectre v2 reports branch predictor hardening:

  ```sh
  cat /sys/devices/system/cpu/vulnerabilities/spectre_v2
  ```

- Confirm NetworkManager Wi-Fi, Bluetooth tools, SSH, i3, touch calibration,
  battery status, brightness, volume, and power menu still work.

## Optional Boot Animation

- Default release image keeps `POCKETCHIP_BOOT_ANIMATION=0`.
- If testing an animation image, confirm:
  - `POCKETCHIP_BOOT_VIDEO=boot.mp4`
  - `POCKETCHIP_BOOT_ANIMATION=1`
  - `/usr/share/pocketchip/boot.mp4` exists
  - `mpv` is installed
  - `pocketchip-boot-animation-test` succeeds over UART.
