# PocketCHIP Trixie Release Checklist

Use this before tagging or uploading public artifacts.

## Source Hygiene

- Worktree is clean, or only intentional release edits are staged.
- `make publish-check` passes.
- `git ls-files` does not include `configs/local.env`, `.local/`, `build/`,
  generated images, generated DTBs, caches, or logs.
- `git check-ignore configs/local.env .local/chip-assets/splash.png` confirms
  local credentials and personal splash artwork remain ignored.
- No build logs, screenshots, UART captures, or docs contain private Wi-Fi
  credentials, local passwords, tokens, or private paths.
- `LICENSE` is present and the release notes identify the project as
  GPL-2.0-only.

## Default Image

- Build once with no `configs/local.env`.
- Confirm `scripts/build-rootfs.sh --no-local-env --print-defaults` reports:
  locked root, user `chip`, no root/user password set, no Wi-Fi SSID/PSK set,
  dark mode enabled, network time enabled, boot splash disabled, and no local
  wallpaper or splash image required.
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

- Confirm NetworkManager Wi-Fi, SSH, i3, touch calibration, battery status,
  brightness, volume, and power menu still work.
- Confirm display and GPU claims match the tested image:

  ```sh
  ls -la /dev/dri
  lsmod | grep -Ei 'lima|sun4i_drm|drm'
  grep -Ei 'glamor|Mali400|DRI|sun4i-drm' /var/log/Xorg.0.log
  ```

  The release may claim Mali/Lima X/glamor acceleration only if Xorg reports
  `glamor X acceleration enabled on Mali400`. Do not claim strong 3D, WebGL,
  game, or media acceleration without separate tests.
- Confirm Bluetooth helper commands do not prompt for systemd authorization.
  Confirm `/proc/device-tree/soc/serial@1c28c00/uart-has-rtscts` exists on the
  tested image, `/sys/class/bluetooth/hci0` exists, `btmgmt info` reports one
  controller, and a short `bluetoothctl` scan can discover nearby devices.
  If `/sys/class/bluetooth` is empty or `btmgmt info` reports zero controllers,
  document Bluetooth HCI/controller bring-up as unresolved for that release.
- Confirm audio and media notes are honest: ALSA driver/module presence is not
  the same as playback/recording support, and `sunxi_cedrus` module presence is
  not the same as validated accelerated video decode.

## Optional Splash Asset

- Default release image keeps `POCKETCHIP_BOOT_SPLASH=0` and does not require a
  splash asset.
- Personal splash artwork stays under ignored `.local/chip-assets/`; the repo
  commits only the documented options and scripts.
- If testing a splash image, confirm:
  - `POCKETCHIP_SPLASH_IMAGE=splash.png`
  - `POCKETCHIP_SPLASH_TOP_MARGIN=14`
  - `POCKETCHIP_BOOT_SPLASH=0`
  - `POCKETCHIP_BOOT_SPLASH_HOLD=0`
  - `POCKETCHIP_LOGIN_SPLASH=1` or `auto`
  - `POCKETCHIP_LOGIN_SPLASH_HOLD=0`
  - `/usr/share/pocketchip/splash.png` exists
  - `/usr/share/pocketchip/splash.fb` exists and is `522240` bytes
  - `systemctl is-enabled pocketchip-framebuffer-splash.service` reports
    `disabled` when testing the default no-pre-login-splash path
  - `sudo pocketchip-framebuffer-splash status` reports the expected paths and
    framebuffer mode
  - `pocketchip-splash status` reports the expected desktop background path.
