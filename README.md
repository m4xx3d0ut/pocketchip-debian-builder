# PocketCHIP Trixie

PocketCHIP Trixie is an unofficial Debian 13/Trixie image and builder for
PocketCHIP. It provides a reproducible rootfs build, mainline U-Boot/FEL bring-up
tools, PocketCHIP hardware defaults, an i3 handheld environment, and an
experimental NAND/SLC rescue install path.

This is an unofficial community project. It is not affiliated with, endorsed by,
or supported by Next Thing Co., PocketCHIP.co, or the Debian Project.
“PocketCHIP” and “C.H.I.P.” are used only to identify compatible hardware.

The stable milestone is a Debian 13/trixie USB root filesystem booted through
FEL and mainline U-Boot. An experimental NAND path now exists, but USB/FEL
remains the safest development loop for kernel, display, keyboard, and userland
work.

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

Experimental NAND commands are documented in `docs/nand.md`. The short form is:

```sh
./scripts/nand-preflight.sh
./scripts/build-legacy-uboot.sh
sudo ./scripts/build-nand-image.sh
sudo ./scripts/fel-nand.py probe-legacy
CONFIRM_NAND_WRITE=YES make nand-flash-legacy
```

The final command erases internal NAND and intentionally requires an explicit
confirmation variable plus the script-level destructive-write guard.

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
intentionally not included.

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
- `docs/`: bring-up notes, acceptance checks, release checklist, NAND notes,
  and legacy flashing review.
- `../upstreams/`: local clones of Project CHIP Crumbs repositories.

## Current Target

- OS: Debian 13/trixie `armhf`
- Kernel: Debian `linux-image-armmp`
- Boot: FEL-loaded U-Boot, merged PocketCHIP DTB, USB rootfs by label `pocketroot`
- UI: Xorg plus `i3`
- Userland: `zsh`, Oh My Zsh, `tmux`, `neovim`, and basic CLI/admin tools
- Network: NetworkManager, OpenSSH server/client, autossh, mosh, bluez, and
  RTL8723BS firmware support. The PocketCHIP Wi-Fi module is 2.4 GHz only.
- Power: DPMS idle lock, i3 power menu, and a conservative low-power lock mode
  that blanks/locks the display and can turn radios down.
- Keyboard: original TCA8418 matrix plus PocketCHIP X/console Fn layers for
  brackets, braces, function keys, Home/End, and Page Up/Down.

## Hardware Notes

Use a 3.3 V UART adapter during bring-up. The UART is the primary source of
truth until the LCD and keyboard are confirmed. Keep a known-good legacy CHIP OS
flash procedure available as recovery before experimental NAND writes.

## License

This repository is licensed under GPL-2.0-only. See `LICENSE`.
