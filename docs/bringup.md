# PocketCHIP Bring-Up Notes

## Milestone 1: USB Rootfs

Stock PocketCHIP firmware does not automatically boot a USB root filesystem
just because the drive is present. The NTC U-Boot environment normally boots
the kernel and rootfs from NAND/UBI. For the USB-rootfs milestone, plan to use a
3.3 V serial console and either interrupt U-Boot manually or boot a test U-Boot
through FEL.

Observed on stock PocketCHIP NAND U-Boot `2016.01-00115-g5f814bb`: UART
interrupt works, but `usb reset` returns `No controllers found`. The USB drive
is visible from stock Linux as `/dev/sda1` with label `pocketroot`, so the drive
and Linux host-side image are plausible; stock U-Boot is not currently a usable
USB-storage bootloader on this device. Prefer FEL-loading a newer/mainline
U-Boot for the USB-rootfs milestone.

See `docs/fel-path.md` for the concrete mainline U-Boot/FEL procedure.

1. Attach a 3.3 V UART adapter and confirm serial output at `115200n8`.
   See `docs/serial-uart-wiring.md` for the PocketCHIP/CHIP pin mapping.
2. Put the PocketCHIP into FEL mode.
3. Build mainline U-Boot with `./scripts/build-mainline-uboot.sh`.
4. Build the PocketCHIP DT overlay and merged DTB with
   `./scripts/build-pocketchip-dtbo.sh`.
5. Insert the generated Debian USB drive if it is not already attached.
6. Boot and verify with `sudo ./scripts/fel-usb-boot-verify.py`.
7. From U-Boot, use the extlinux path when available:

   ```text
   usb start
   sysboot usb 0:1 any ${scriptaddr} /boot/extlinux/extlinux.conf
   ```

8. Confirm Linux reaches a serial login prompt.

If `sysboot` or `extlinux` is unavailable in the U-Boot build, boot the same
artifacts manually from the USB partition:

```text
usb start
ext4load usb 0:1 ${kernel_addr_r} /boot/vmlinuz-...
ext4load usb 0:1 ${ramdisk_addr_r} /boot/initrd.img-...
setenv ramdisk_size ${filesize}
ext4load usb 0:1 ${fdt_addr_r} /boot/sun5i-r8-pocketchip.dtb
setenv bootargs console=ttyS0,115200 root=LABEL=pocketroot rootwait rw
bootz ${kernel_addr_r} ${ramdisk_addr_r}:${ramdisk_size} ${fdt_addr_r}
```

## Stock OS USB Gadget Console

When stock CHIP OS is already booted, the host may see a USB CDC serial gadget
such as `/dev/ttyACM0` with a `chip login:` prompt. That console is useful for
read-only sanity checks, for example:

```sh
lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,MOUNTPOINT
blkid /dev/sda /dev/sda1
cat /proc/cmdline
```

This does not replace the UART console for bootloader work. The USB gadget
appears after Linux has booted, so it cannot interrupt U-Boot.

## Hardware Acceptance Checks

Run these on the PocketCHIP after boot:

```sh
uname -a
cat /proc/device-tree/model
ls /dev/input
sudo evtest
find /sys/class/backlight -maxdepth 2 -type f
nmcli radio wifi
aplay -l
upower -d || true
```

Expected first-pass outcomes:

- Model reports a CHIP/PocketCHIP-compatible device tree.
- The TCA8418 keyboard appears under `/dev/input`.
- The LCD lights and exposes a framebuffer or DRM device.
- Backlight brightness can be adjusted through sysfs.
- Wi-Fi enumerates; firmware may still need iteration.
- `zsh`, `tmux`, `nvim`, and `startx` all run.

## Milestone 2: NAND

Do not start NAND work until the USB milestone is stable. NAND work should use
the legacy NTC/CHIP-tools path only as a controlled experiment and should keep a
known-good recovery image available.

Open questions for NAND:

- Whether current mainline U-Boot can read enough from CHIP NAND for boot on
  the specific device revision.
- Whether NTC U-Boot should remain the NAND bootloader while Debian provides
  the kernel and root filesystem.
- Whether the final community artifact should be a NAND image, a USB-rootfs
  kit, or both.
