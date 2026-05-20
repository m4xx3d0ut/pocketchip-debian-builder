# PocketCHIP NAND Path

This is the experimental direct-NAND path for the Debian 13 PocketCHIP image.
Keep UART connected and keep FEL recovery working before using it. The flash
step erases the internal NAND.

## Current Strategy

Use the legacy CHIP-tools NAND layout for boot assets:

- SPL at `0x00000000`
- backup SPL at `0x00400000`
- U-Boot at `0x00800000`
- environment at `0x00c00000`
- raw boot payload area at `0x01000000` through `0x04ffffff`
- UBI root filesystem from `0x05000000`

The Debian kernel has `sunxi_nand`, `ubi`, `ubifs`, and `ofpart` as modules, so
the NAND image installs a NAND-enabled DTB and rebuilds the initramfs with those
modules forced in. The fixed DT partitions mirror the legacy CHIP layout because
the Debian kernel does not currently have `CONFIG_MTD_CMDLINE_PARTS` enabled.

Mainline NAND U-Boot remains a probe/compare path until it proves it can detect
the PocketCHIP NAND reliably and boot back from NAND. The first destructive path
should use the production MLC PocketCHIP legacy branch in
`build/u-boot-legacy-mlc-pc`; the older `chip/stable` build has been observed to
report `NAND: 0 MiB` on this device.

Important current result: the PocketCHIP tested here has 4 GiB Toshiba MLC NAND
(`400000-4000-500`). The basic flash flow succeeds, and legacy U-Boot can attach
the UBI image and read `/boot` from UBIFS. Debian 13's mainline-style kernel
then refuses to attach plain UBI on MLC NAND:

```text
ubi: refuse attaching mtd4 - MLC NAND is not supported
```

The preferred persistent NAND path is now SLC-on-MLC emulation, not a patched
Debian `ubi.ko` that blindly bypasses this guard. Linux accepts UBI on an MLC
partition when the MTD partition is exposed with the `slc-mode` fixed-partition
flag. The SLC path therefore:

- builds a patched legacy PocketCHIP U-Boot in an isolated worktree;
- restores the old CHIP SLC-mode NAND write/read helpers and fastboot `UBI`
  SLC write behavior;
- generates a NAND DTB with `slc-mode;` on the `UBI` partition;
- writes U-Boot, `zImage`, the NAND DTB, and `initrd.uimage` with U-Boot's
  `.slc-mode` NAND helpers. SPL applies the matching Toshiba lower-page mapping
  when loading the U-Boot slot, and old U-Boot never needs to mount the
  slc-mode UBI volume;
- builds the rootfs UBIFS image as 2 MiB logical SLC eraseblocks with
  an autoresizing rootfs volume using LZO UBIFS compression. The preferred
  rootfs write path is now the Linux rescue installer, which formats UBI and
  writes the UBIFS volume through the same `sunxi_nand`/UBI stack that will
  mount it at runtime.
  Autoresize is intentional: Linux UBI needs to reserve wear-leveling and
  bad-block handling PEBs before expanding the persistent volume.

This trades capacity for reliability. The 4 GiB physical MLC NAND is treated as
roughly 2 GiB of logical SLC-mode NAND for Linux. Clean shutdowns still matter;
this is raw NAND, not eMMC.

## Host Preflight

```sh
./scripts/nand-preflight.sh
```

If tools are missing:

```sh
sudo apt install mtd-utils android-sdk-libsparse-utils fastboot u-boot-tools
sudo apt install gcc-arm-linux-gnueabi
./scripts/build-sunxi-tools-misc.sh
./scripts/build-chip-mtd-utils.sh
```

`gcc-arm-linux-gnueabi` is needed for the legacy CHIP U-Boot build. The normal
USB/FEL mainline U-Boot build uses `gcc-arm-linux-gnueabihf`.

The MLC NAND images require the old CHIP `ubinize -M dist3` page-pairing
extension. Debian's packaged `ubinize` does not include that option, so
`build-chip-mtd-utils.sh` installs the patched binary into
`build/host-tools/bin`.

## Build Artifacts

```sh
./scripts/fetch-upstreams.sh
make uboot-legacy-mlc-pc-slc
make nand-image-mlc-pc-slc
```

Expected output directory:

```text
build/nand/images/
  sunxi-spl.bin
  u-boot-dtb.bin
  u-boot-nand.img
  spl-<erase>-<page>-<oob>.bin
  uboot-<erase>.bin
  boot-zImage-<erase>-<page>-<oob>.bin
  boot-sun5i-r8-chip-<erase>-<page>-<oob>.dtb
  boot-initrd-<erase>-<page>-<oob>.uimage
  boot-layout-<erase>-<page>-<oob>.env
  chip-<erase>-<page>-<oob>.ubi.sparse
```

The SLC-mode build uses a separate output directory so it is not confused with
the older plain-MLC proof image:

```text
build/nand-slc/images/
  nand_slc_mode
  sunxi-spl.bin
  u-boot-dtb.bin
  u-boot-nand.img
  spl-400000-4000-500.bin
  uboot-400000.bin
  boot-zImage-400000-4000-500.bin
  boot-sun5i-r8-chip-400000-4000-500.dtb
  boot-initrd-400000-4000-500.uimage
  boot-layout-400000-4000-500.env
  chip-400000-4000-500.ubi.sparse
```

`u-boot-dtb.bin` is kept for FEL execution from DRAM. `uboot-<erase>.bin` is
the NAND second-stage image; prefer the mkimage-wrapped `u-boot-dtb.img` source
so SPL reads the actual U-Boot length instead of a fixed raw 768 KiB window.

The builder knows these NAND geometries:

```text
hynix-8g-mlc       400000-4000-680
toshiba-4g-mlc     400000-4000-500
toshiba-512m-slc   40000-1000-100
```

The `uboot-legacy-mlc-pc-slc` build applies a Toshiba-specific SPL patch for
the current PocketCHIP target. That SPL uses the known Toshiba 4G MLC boot
geometry directly: 16 KiB pages, 1 KiB ECC steps, ECC40, 5 address cycles, and
NAND randomization. It also applies Toshiba SLC lower-page mapping when reading
the U-Boot slot, matching the `.slc-mode` write path and avoiding fragile normal
MLC reads for second-stage U-Boot. Full U-Boot remains generic; only the tiny
NAND SPL skips the fragile geometry auto-detection path. Add a separate SPL
geometry/page-mapping patch before using the same boot image flow on Hynix MLC
units.

The legacy SLC build also enables the default PocketCHIP Cortex-A8 Spectre v2
mitigation path. `POCKETCHIP_SPECTRE_V2_MITIGATION=1` adds an early U-Boot
ACTLR IBE-bit write so Linux branch predictor hardening is active instead of
printing the boot-time firmware warning. Set it to `0` only for controlled
benchmark comparisons.

By default `build-nand-image.sh` creates UBIFS with `NAND_UBIFS_COMPRESSOR=lzo`.
The builder also forces the kernel's `zstd` crypto module into the initramfs
when the module is present, because an older flashed UBIFS volume or compressor
metadata can otherwise stop boot at initramfs with `cannot initialize compressor
zstd`.

The current Debian rootfs is too large for the 512 MiB SLC target, so that
format should be skipped unless the image is reduced substantially.

## Probe NAND Geometry

Put the PocketCHIP in FEL mode with UART attached, then run the serial probe
using the production MLC PocketCHIP U-Boot:

```sh
sudo ./scripts/fel-nand.py probe-legacy-serial --uboot-dir build/u-boot-legacy-mlc-pc
```

This is read-only. It loads NAND-capable U-Boot through FEL, runs `nand info`,
and writes the detected geometry from UART output. The non-serial probe also
exports the geometry to SRAM and resets back into FEL, but this board can land
in a stale FEL state where `lsusb` shows `1f3a:efe8` while `sunxi-fel ver` times
out. If that happens, clear the host-side USB device with `sudo usbreset
1f3a:efe8` and physically re-enter FEL.

Successful probes write:

```text
build/nand/legacy-serial-probe.env
build/nand/images/ubi_type
```

The older SRAM-export probe is still available as a fallback:

```sh
sudo ./scripts/fel-nand.py probe-legacy
```

Optional mainline comparison:

```sh
./scripts/build-mainline-nand-uboot.sh
sudo ./scripts/fel-nand.py probe-mainline
```

Only use the mainline NAND U-Boot for flashing after it detects NAND correctly
and has been tested through a full boot cycle.

## Flash NAND

After the probe and image build both match the detected `ubi_type`:

```sh
CONFIRM_NAND_WRITE=YES make nand-flash-legacy-slc
```

Equivalent direct command:

```sh
sudo ./scripts/fel-nand.py \
  --nand-dir build/nand-slc \
  --images-dir build/nand-slc/images \
  --timeout 240 \
  flash-legacy \
  --format toshiba-4g-mlc \
  --require-slc-mode \
  --source-over-serial \
  --i-understand-this-erases-nand
```

The older plain-MLC proof image can still be flashed with `make
nand-flash-legacy`, but it is expected to hit the Debian `MLC NAND is not
supported` UBI guard unless a custom kernel/module override is added.

To force a specific detected geometry on the non-SLC flow:

```sh
sudo ./scripts/fel-nand.py flash-legacy \
  --format hynix-8g-mlc \
  --i-understand-this-erases-nand
```

The flash flow:

1. FEL-loads SPL, U-Boot, and a generated U-Boot script.
   `--source-over-serial` interrupts U-Boot over UART and runs the loaded
   script explicitly, which avoids stale NAND environment skipping the FEL
   boot target.
2. Erases NAND with `nand erase.chip` by default.
3. Writes primary SPL, backup SPL, and U-Boot.
4. Writes raw NAND boot assets with `.slc-mode`:
   `zImage` at `0x01000000`, DTB at `0x02000000`, and `initrd.uimage` at
   `0x02400000`.
5. Saves a raw-NAND boot environment with `ubi.mtd=UBI`, not a numeric MTD
   index. U-Boot loads the boot assets with `nand read.slc-mode`; Linux mounts
   UBIFS after the kernel starts.
6. Enters U-Boot fastboot.
7. Flashes the sparse UBI image to the `UBI` partition. On the SLC target,
   `fel-nand.py` refuses to proceed unless the image directory is marked with
   `nand_slc_mode=1`.

If a freshly rewritten UBIFS rootfs repeatedly reports an uncorrectable UBI
read from the same PEB, mark that single eraseblock bad before reflashing. For
example, UBI `PEB 423` maps to absolute NAND offset `0x6ec00000` with this
layout (`0x05000000 + 423 * 0x400000`):

```sh
sudo ./scripts/fel-nand.py \
  --nand-dir build/nand-slc \
  --images-dir build/nand-slc/images \
  --timeout 240 \
  flash-legacy \
  --format toshiba-4g-mlc \
  --require-slc-mode \
  --source-over-serial \
  --markbad-offset 0x6ec00000 \
  --i-understand-this-erases-nand
```

Use `--erase-mode scrub` only if targeted bad-block marking plus normal erase is
not enough; scrub is more aggressive around bad-block metadata.

## Linux-Side UBI Rescue Install

If U-Boot fastboot writes a rootfs that Linux later mounts read-only with UBI
ECC errors, use the rescue installer. It FEL-boots the Debian kernel with a
small initramfs, formats the `UBI` MTD partition with Linux `ubiformat`, creates
the `rootfs` UBI volume, and writes the UBIFS payload with Linux
`ubiupdatevol`. This avoids using U-Boot's NAND writer for the persistent
rootfs.

Build the rescue initramfs after `nand-image-mlc-pc-slc`:

```sh
make nand-rescue-initramfs-slc
```

Then boot the PocketCHIP into FEL and run:

```sh
CONFIRM_NAND_WRITE=YES make nand-rescue-install-slc
```

Default host/device rescue addresses are `172.16.42.1` and `172.16.42.2`,
with the device listening on TCP port `4242`. Override with
`NAND_RESCUE_NET_IFACE`, `NAND_RESCUE_HOST_IP`, `NAND_RESCUE_DEVICE_IP`, or
`NAND_RESCUE_PORT` if needed.

On this PocketCHIP, Debian's MUSB gadget path exposes
`/sys/class/udc/musb-hdrc.1.auto`, but `g_ether` fails to start the controller.
Use the USB-stick payload fallback instead:

```sh
make nand-rescue-initramfs-usb-slc
sudo mount /dev/sdX1 /mnt/pocketchip-rescue-usb
sudo ./scripts/prepare-nand-rescue-usb.sh /mnt/pocketchip-rescue-usb
sudo umount /mnt/pocketchip-rescue-usb
```

The helper writes `pocketchip/rootfs.ubifs` plus a `.sha256` file to the mounted
stick. Plug that stick into the PocketCHIP USB host port, boot the board into
FEL, then run:

```sh
CONFIRM_NAND_WRITE=YES make nand-rescue-install-usb-slc
```

The rescue initramfs waits for the USB storage device, mounts it read-only,
verifies the payload size and SHA256 against the build artifact, writes
`/dev/ubi0_0`, syncs, and reboots.

If the rootfs UBI partition was already written and only the boot area needs a
refresh, use the bootloader target from FEL mode:

```sh
CONFIRM_NAND_WRITE=YES make nand-flash-bootloader-slc
```

That path erases and rewrites only the first 80 MiB NAND boot area:
`spl`, `spl-backup`, `uboot`, `env`, and the raw `boot` payloads. It
intentionally leaves the `UBI` partition at `0x05000000` untouched.

## Verify NAND Boot

After flashing, power-cycle without the USB rootfs drive. Keep UART connected:

```sh
sudo ./scripts/fel-nand.py verify --root-password '<lab-root-password>'
```

The verifier checks the serial shell for Debian, `/proc/cmdline`, `/proc/mtd`,
UBIFS mounts, NAND/UBI modules, and i3 process state.
New default images lock root, so use the serial login for the configured user
or build a temporary lab image with `POCKETCHIP_ROOT_AUTH=password` only when
this root verifier path is needed.

For a persistence smoke test:

```sh
echo nand-persist-test-$(date +%s) >/home/m4xx3d0ut/nand-persist-test.txt
sync
reboot
cat /home/m4xx3d0ut/nand-persist-test.txt
```

## Recovery Notes

- FEL mode remains the recovery path if NAND boot fails.
- USB/FEL boot remains the safest way to test rootfs, display, keyboard, Wi-Fi,
  Bluetooth, and i3 changes.
- Direct Linux-side NAND writes are not the preferred first path. The current
  USB boot does not expose `/proc/mtd` until a NAND-enabled DTB and initramfs are
  used, and raw NAND writes from Linux add more risk than the U-Boot fastboot
  flow.
