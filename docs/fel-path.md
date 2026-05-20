# FEL Path

The stable boot path is FEL-loaded mainline U-Boot plus the existing USB rootfs.
This keeps stock NAND intact while we test USB storage, the Debian kernel, and
the root filesystem.

## NAND Status

The repo now has an experimental NAND path, but direct NAND writing remains a
destructive full-flash operation. It writes a CHIP-specific SPL/ECC layout and a
UBIFS/UBI root filesystem. Use the USB/FEL path for normal development and read
`docs/nand.md` before any NAND write.

## Build Mainline U-Boot

```sh
./scripts/check-host.sh
./scripts/prepare-debian-keyring.sh
./scripts/build-mainline-uboot.sh
./scripts/build-pocketchip-dtbo.sh
```

The build script uses:

- Source: `https://source.denx.de/u-boot/u-boot.git`
- Ref: `v2026.04`
- Defconfig: `CHIP_defconfig`
- Output: `build/u-boot-mainline/u-boot-sunxi-with-spl.bin`

It verifies the resulting `.config` has sunxi/CHIP support, USB host/storage,
ext4 loading, `bootz`, and an extlinux/sysboot-compatible path.

`build-pocketchip-dtbo.sh` also builds `build/dtbo/sun5i-r8-pocketchip.dtb`,
a host-merged DTB that combines the mainline CHIP base DTS with the PocketCHIP
LCD, backlight, touchscreen, and TCA8418 keyboard overlay. The USB image uses
that merged DTB directly because Debian's packaged `sun5i-r8-chip.dtb` does not
include the `__symbols__` section needed for reliable U-Boot overlay fixups.

## Enter FEL Mode

See `docs/fel-mode.md` for the full physical procedure.

1. Keep the UART adapter attached.
2. Ground the CHIP FEL pin.
3. Reset or power-cycle the PocketCHIP.
4. Confirm the host sees FEL:

   ```sh
   sunxi-fel ver
   ```

FEL mode should appear as USB VID/PID `1f3a:efe8`.

## Verify USB Boot

With the Debian USB drive installed in PocketCHIP:

```sh
sudo ./scripts/fel-usb-boot-verify.py
```

Observed on May 18, 2026: FEL-loaded mainline U-Boot `2026.04` initializes
DRAM, reaches the UART prompt, enumerates the PocketCHIP USB host controller,
finds USB mass storage as `usb 0`, reads the DOS partition table, and can list
the ext4 root filesystem. If `/boot/extlinux/extlinux.conf` is missing or
`/boot` contains no `vmlinuz-*` and `initrd.img-*`, rebuild and rewrite the USB
image; the failure is then the image contents, not FEL, UART, U-Boot, or USB
host enumeration.

The verifier:

1. Waits for the FEL device.
2. Loads `build/u-boot-mainline/u-boot-sunxi-with-spl.bin` into RAM.
3. Watches UART for the U-Boot prompt.
4. Runs:

   ```text
   usb reset
   usb tree
   usb storage
   usb part 0
   ext4ls usb 0:1 /
   ext4ls usb 0:1 /boot
   ext4ls usb 0:1 /boot/extlinux
   sysboot usb 0:1 any ${scriptaddr} /boot/extlinux/extlinux.conf
   ```

5. Falls back to manual `ext4load` and `bootz` if `sysboot` returns to the
   prompt.

Logs are written to `build/logs/fel-usb-boot-verify.log`.

## Success Criteria

- UART reports mainline U-Boot, not stock `2016.01`.
- `usb reset` enumerates storage instead of `No controllers found`.
- `/boot/extlinux/extlinux.conf` is readable from `usb 0:1`.
- `/boot/sun5i-r8-pocketchip.dtb` is readable from `usb 0:1`.
- Debian boots with `root=LABEL=pocketroot rootwait`.
- Serial login reaches the Debian USB rootfs.
