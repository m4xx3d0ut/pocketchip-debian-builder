# PocketCHIP - Debian 13 Trixie

*(Unofficial a.k.a. ***"PocketTRIX"***)*

PocketCHIP Trixie is an unofficial Debian 13/Trixie image and builder for
PocketCHIP. It provides a reproducible Debian rootfs build, mainline U-Boot/FEL
bring-up tools, PocketCHIP hardware defaults, an i3 handheld environment, and an
experimental NAND/SLC rescue install path using patched legacy CHIP U-Boot.

This is an unofficial community project. It is not affiliated with, endorsed by,
or supported by Next Thing Co., PocketCHIP.co, or the Debian Project.
“PocketCHIP” and “C.H.I.P.” are used only to identify compatible hardware.

The stable development milestone is a Debian 13/trixie USB root filesystem
booted through FEL and mainline U-Boot. The NAND/SLC path has also been
validated on one Toshiba 4G MLC PocketCHIP, but remains experimental until more
hardware variants are tested. USB/FEL remains the safest development loop for
kernel, display, keyboard, and userland work.

## Terminology

This project is best described as an unofficial Debian 13/Trixie-based
PocketCHIP image and builder.

- Debian: the root filesystem is built from Debian 13/Trixie `armhf` packages.
  It is a Debian-based device image, with PocketCHIP-specific integration.
- Kernel: the image uses Debian's packaged `linux-image-armmp` kernel, which is
  mainline-based but carries Debian configuration and packaging.
- U-Boot for FEL/USB: the USB development path uses mainline U-Boot.
- U-Boot for NAND: the tested NAND/SLC path uses patched legacy CHIP U-Boot,
  because NAND boot support still depends on CHIP-specific legacy code.

## Quick Start

From this repo:

```sh
./scripts/check-host.sh
./scripts/fetch-upstreams.sh
./scripts/build-mainline-uboot.sh
./scripts/build-pocketchip-dtbo.sh
sudo ./scripts/build-rootfs.sh
sudo ./scripts/build-usb-image.sh
sudo ./scripts/fel-usb-boot-verify.py
```

Experimental NAND commands are documented in `docs/nand.md`. The currently
tested Toshiba 4G MLC SLC-mode rescue flow is:

```sh
./scripts/nand-preflight.sh
make nand-image-mlc-pc-slc
make nand-rescue-initramfs-usb-slc
USB_MOUNT=/mnt/pocketchip-rescue-usb make nand-rescue-usb-payload-slc
CONFIRM_NAND_WRITE=YES make nand-flash-bootloader-slc
CONFIRM_NAND_WRITE=YES make nand-rescue-install-usb-slc
```

The flash/install commands erase internal NAND and intentionally require an
explicit confirmation variable plus script-level destructive-write guards.

Optional per-image settings live in `configs/local.env`, which is gitignored
because it may contain passwords or Wi-Fi credentials. Start from:

```sh
cp configs/local.env.example configs/local.env
$EDITOR configs/local.env
```

Default builds do not require `configs/local.env`, local assets, Wi-Fi
credentials, or a root password. The default root account is locked, the default
user is `chip`, and first-boot direct i3 setup prompts for a user password before
disabling tty1 autologin.

Personal wallpaper and splash files belong under `.local/chip-assets/`, which is
also gitignored. The repo documents the build options, but does not ship private
or project-specific artwork.

The build supports image profile, account, Wi-Fi, display/touch, browser, power,
time, and optional asset knobs documented in `configs/local.env.example` and
`docs/bringup.md`. Use `POCKETCHIP_ROOT_AUTH=password` plus
`POCKETCHIP_ROOT_PASSWORD=...` only for intentional lab/recovery images.
The optional splash path uses static images; video boot animation support is
intentionally not included because it was unreliable on this hardware.

On Debian/Ubuntu hosts, the expected dependencies are:

```sh
sudo apt install \
  binfmt-support curl device-tree-compiler e2fsprogs fastboot git gnupg mmdebstrap \
  python3-pil qemu-user-static rsync sunxi-tools u-boot-tools util-linux
sudo apt install \
  bc bison flex gcc-arm-linux-gnueabihf libssl-dev make openssl python3 swig
```

The generated USB image lands in `build/images/`. Write it to a USB drive only
after checking the target device path:

```sh
sudo dd if=build/images/pocketchip-debian-trixie-armhf.img of=/dev/sdX bs=4M conv=fsync status=progress
```

Before publishing or tagging a release, run:

```sh
make publish-check
```

## Project Layout

- `scripts/`: host checks, upstream checkout, rootfs build, DT overlay build,
  USB image assembly, U-Boot builds, FEL boot verification, and experimental
  NAND image/probe/flash helpers.
- `dts/`: PocketCHIP mainline device-tree overlay source.
- `configs/`: package list, initramfs module list, and default user/desktop
  configuration files.
- `docs/`: bring-up notes, acceptance checks, release checklist, Bluetooth HCI
  notes, NAND notes, and legacy flashing review.
- `../upstreams/`: local clones of Project CHIP Crumbs repositories.

## Current Target

- OS: Debian 13/trixie `armhf`
- Kernel: Debian `linux-image-armmp`, a Debian-packaged mainline-based ARM
  kernel.
- Boot: mainline U-Boot for FEL/USB bring-up with USB rootfs by label
  `pocketroot`; patched legacy CHIP U-Boot for the experimental NAND/SLC rescue
  installer path.
- UI: Xorg plus `i3`
- Terminal: Sakura/VTE by default through `pocketchip-terminal`, with optional
  xterm fallback when xterm is manually installed. `xterm` is intentionally not
  part of the default image because Sakura gives better Unicode/TUI behavior on
  the PocketCHIP display.
- Userland: `zsh`, Oh My Zsh, `tmux`, `neovim`, Powerline/Font Awesome/Unifont
  terminal glyph coverage, and basic CLI/admin tools
- Network: NetworkManager, OpenSSH server/client, autossh, mosh, bluez, and
  RTL8723BS Wi-Fi/Bluetooth firmware support. The PocketCHIP Wi-Fi module is
  2.4 GHz only. Bluetooth HCI exposure and validation are documented in
  `docs/bluetooth.md`.
- Power: DPMS idle lock, i3 power menu, and a conservative low-power lock mode
  that blanks/locks the display and can turn radios down.
- Keyboard: original TCA8418 matrix plus PocketCHIP X/console Fn layers for
  brackets, braces, function keys, Home/End, and Page Up/Down.

## Hardware Support Status

This status reflects the live NAND/SLC validation run on May 21, 2026, using
Debian `6.12.86+deb13-armmp` on a Toshiba 4G MLC PocketCHIP.

| Area | Status | Notes |
| --- | --- | --- |
| Boot and storage | Supported on tested unit | NAND boot reaches Debian 13 from a writable UBIFS rootfs. The autoresized rootfs volume mounted `rw` with about 1.1 GiB free after the balanced image install. |
| USB/FEL recovery | Supported | FEL boot, USB rootfs bring-up, and USB-sourced NAND rescue install are the safest recovery/development paths. |
| LCD/display | Supported | The 480x272 PocketCHIP LCD runs through `sun4i-drm`; `/dev/fb0` reports `sun4i-drmdrmfb` and DRM devices are present. |
| Mali GPU | Accelerated for X/glamor | The `lima` kernel driver is loaded, Mesa DRI/EGL/GLX libraries are installed, `/dev/dri/renderD128` exists, and Xorg reports `glamor X acceleration enabled on Mali400`. This is useful desktop/X acceleration, not a claim of strong 3D, WebGL, or game performance. |
| Keyboard | Supported | The TCA8418 matrix keyboard works with PocketCHIP-specific console/X keymap layers and i3 bindings. |
| Touch input | Usable with caveats | The resistive touch panel works as pointer/stylus input, but edge accuracy remains imperfect and should not be treated like a modern multitouch panel. |
| Wi-Fi | Supported | RTL8723BS SDIO Wi-Fi works through NetworkManager. The radio is 2.4 GHz only. |
| Bluetooth | Supported | RTL8723BS Bluetooth works through UART3/H5 after enabling `uart-has-rtscts`; `hci0` appears, powers on, and scans nearby devices. |
| SSH and remote tools | Supported | OpenSSH server, mosh, autossh, serial tools, and field diagnostics are included in the balanced profile. |
| Audio | Present, needs user-facing test | The `sun4i_codec` ALSA path loads. Playback/recording should be tested before claiming full audio support in a release note. |
| Battery and power | Basic support | Battery/charger reporting, backlight control, lock/screen-off behavior, zram swap, and i3 power menus are present. There is no proven suspend-to-RAM/S0-style sleep path. |
| Video decode | Driver present, unvalidated | The `sunxi_cedrus` V4L2 driver loads, but accelerated media decode has not been validated and is not part of the supported user experience yet. |

## Hardware Notes

Use a 3.3 V UART adapter during bring-up. The UART is the primary source of
truth until the LCD and keyboard are confirmed. Keep a known-good legacy CHIP OS
flash procedure available as recovery before experimental NAND writes.

## License

This repository is licensed under GPL-2.0-only. See `LICENSE`.
