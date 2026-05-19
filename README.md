# PocketCHIP Mainline Debian Bring-Up

This repo is a reproducible bring-up workspace for a best-effort, open source
PocketCHIP distribution based on mainline Debian armhf.

The first milestone is a Debian 13/trixie USB root filesystem booted through
FEL and mainline U-Boot. NAND flashing is intentionally a later milestone: the
legacy NTC tooling is still useful for recovery and NAND experiments, but it is
not the safest first path for kernel, display, keyboard, and userland work.

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

On Debian/Ubuntu hosts, the expected dependencies are:

```sh
sudo apt install \
  binfmt-support curl device-tree-compiler e2fsprogs fastboot git gnupg mmdebstrap \
  qemu-user-static rsync sunxi-tools u-boot-tools util-linux
sudo apt install \
  bc bison flex gcc-arm-linux-gnueabihf libssl-dev make openssl python3 swig
```

The generated USB image lands in `build/images/`. Write it to a USB drive only
after checking the target device path:

```sh
sudo dd if=build/images/pocketchip-debian-trixie-armhf.img of=/dev/sdX bs=4M conv=fsync status=progress
```

## Project Layout

- `scripts/`: host checks, upstream checkout, rootfs build, DT overlay build,
  USB image assembly, mainline U-Boot build, and FEL boot verification.
- `dts/`: PocketCHIP mainline device-tree overlay source.
- `configs/`: package list, initramfs module list, and default user/desktop
  configuration files.
- `docs/`: bring-up notes, acceptance checks, and legacy flashing review.
- `../upstreams/`: local clones of Project CHIP Crumbs repositories.

## Current Target

- OS: Debian 13/trixie `armhf`
- Kernel: Debian `linux-image-armmp`
- Boot: FEL-loaded U-Boot, merged PocketCHIP DTB, USB rootfs by label `pocketroot`
- UI: Xorg plus `i3`
- Userland: `zsh`, Oh My Zsh, `tmux`, `neovim`, and basic CLI/admin tools

## Hardware Notes

Use a 3.3 V UART adapter during bring-up. The UART is the primary source of
truth until the LCD and keyboard are confirmed. Keep a known-good legacy CHIP OS
flash procedure available as recovery, but avoid NAND writes during the first
mainline Debian milestone.
