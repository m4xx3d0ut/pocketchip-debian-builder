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

## Image Personalization

The rootfs and U-Boot build scripts read `configs/local.env` when it exists.
That file is gitignored and is the intended place for throwaway prototype
credentials, local Wi-Fi credentials, local artwork names, and local build
toggles. Keep personal assets under `.local/chip-assets/`; `.local/` is
gitignored, so release source only carries the documented options.

Useful knobs:

```sh
POCKETCHIP_IMAGE_PROFILE=balanced
POCKETCHIP_ROOT_AUTH=locked
POCKETCHIP_USER=chip
POCKETCHIP_USER_PASSWORD=
POCKETCHIP_AUTOLOGIN_TTY1=auto
POCKETCHIP_BOOT_TO_I3=1
POCKETCHIP_FIRST_LOGIN_PASSWORD_SETUP=1
POCKETCHIP_WIFI_SSID='your-2g-ssid'
POCKETCHIP_WIFI_PSK='your-password'
POCKETCHIP_WIFI_HIDDEN=0
POCKETCHIP_WIFI_COUNTRY=US
POCKETCHIP_SPECTRE_V2_MITIGATION=1
POCKETCHIP_TOUCH_MATRIX='-1 0 1 0 -1.18 1.09 0 0 1'
POCKETCHIP_TOUCH_OUTPUT=
POCKETCHIP_ASSET_DIR='.local/chip-assets'
# POCKETCHIP_BG_IMAGE=bg.png
POCKETCHIP_BG_TOP_MARGIN=14
# POCKETCHIP_SPLASH_IMAGE=splash.png
POCKETCHIP_SPLASH_TOP_MARGIN=14
POCKETCHIP_BOOT_SPLASH=0
POCKETCHIP_BOOT_SPLASH_HOLD=0
POCKETCHIP_LOGIN_SPLASH=auto
POCKETCHIP_LOGIN_SPLASH_HOLD=0
POCKETCHIP_BROWSER=firefox-esr
POCKETCHIP_GESTURES=1
POCKETCHIP_DARK_MODE=1
POCKETCHIP_TIMEZONE=America/Los_Angeles
POCKETCHIP_NETWORK_TIME=1
POCKETCHIP_FIREFOX_SCALE=1.15
POCKETCHIP_FIREFOX_DEFAULT_ZOOM=1.0
POCKETCHIP_BROWSER_FULLSCREEN=1
POCKETCHIP_BROWSER_TOUCH_MODE=gestures
```

The default root account is locked. Leave `POCKETCHIP_USER_PASSWORD` empty for
first-boot direct i3 setup. With `POCKETCHIP_FIRST_LOGIN_PASSWORD_SETUP=1`, the
image prompts for the user password in i3, disables tty1 autologin after the
password is set, and adds the user to password-required sudo. Set a real
`POCKETCHIP_USER_PASSWORD` and use `POCKETCHIP_AUTOLOGIN_TTY1=auto` or `0` when
the image should require an interactive login immediately. Use
`POCKETCHIP_ROOT_AUTH=password` plus `POCKETCHIP_ROOT_PASSWORD=...` only for
temporary lab/recovery images.

The PocketCHIP RTL8723BS radio is a 2.4 GHz Wi-Fi part. Use a 2.4 GHz SSID or a
dual-band SSID that still accepts 2.4 GHz clients. Set
`POCKETCHIP_WIFI_HIDDEN=1` for a hidden build-time SSID.

The optional splash is a static image loaded from `POCKETCHIP_ASSET_DIR`, usually
`.local/chip-assets/splash.png`. The source image is local artwork and should
not be committed. The default image does not paint a splash before login, so the
tty login prompt appears as soon as the system is ready. It is intentionally not
an MP4 animation because video playback adds a large package stack and proved
unreliable on this device. To check the configured splash from a shell:

```sh
sudo pocketchip-framebuffer-splash status
sudo pocketchip-framebuffer-splash paint
pocketchip-splash status
cat /run/pocketchip-framebuffer-splash.log
```

Set `POCKETCHIP_SPLASH_IMAGE=splash.png` to copy the local asset into the image
and generate `/usr/share/pocketchip/splash.fb`. Set
`POCKETCHIP_SPLASH_TOP_MARGIN=14` to inset the splash slightly from the top edge
so PocketCHIP LCD edge clipping does not cut off the artwork. The build
stretches the splash to the full 480px width, matching the desktop wallpaper
preparation. Keep `POCKETCHIP_BOOT_SPLASH=0` for a fast login prompt. With
`POCKETCHIP_LOGIN_SPLASH=auto`, the build enables the login splash only when a
splash image is configured. `pocketchip-splash login` paints the image on the X
root window after a successful tty1 login and keeps it visible until i3 applies
the desktop background. Leave
`POCKETCHIP_LOGIN_SPLASH_HOLD=0` unless you intentionally want to delay X/i3
startup after login.

Set `POCKETCHIP_NETWORK_TIME=1` to install and enable `systemd-timesyncd` so the
device corrects date/time after NetworkManager brings Wi-Fi online. Set it to
`0` for fully offline images that should not adjust time from the network.

Wi-Fi and Bluetooth can be configured from a serial shell, local tty, or i3
terminal with:

```sh
pocketchip-connect menu
pocketchip-connect wifi-list
pocketchip-connect wifi-connect 'SSID'
pocketchip-connect wifi-connect --hidden 'SSID'
pocketchip-connect wifi-hidden 'PROFILE' yes
pocketchip-connect bt-info
pocketchip-connect bt-reset
pocketchip-connect bt-scan 15
pocketchip-connect bt-devices
pocketchip-connect bt-pair 'AA:BB:CC:DD:EE:FF'
```

The image installs `polkitd` plus a PocketCHIP policy rule so the configured
user can manage NetworkManager from the i3/tty TUIs as a member of `netdev`.
The user is also added to `bluetooth` when that group exists. If `nmtui` reports
authorization errors, check:

```sh
systemctl is-active polkit.service
id
nmcli general permissions
```

Power helpers:

```sh
pocketchip-power menu
pocketchip-power lock
pocketchip-power low-lock
pocketchip-power performance
pocketchip-power normal
```

`lock` starts a black `i3lock`, forces the display off, disables the local
keyboard and touch devices while the display is off, then waits for the AXP
power button or charger/power-supply event before turning the display and local
input back on for password entry. `low-lock` additionally turns Wi-Fi and
Bluetooth off and caps CPU frequency to the lowest available value while locked;
`performance` switches the CPU governor to `performance`; `normal` restores the
saved CPU cap/governor and turns radios back on.

## LCD and Keyboard Verification

The mainline PocketCHIP DTB should route the local framebuffer to the 480x272
LCD panel, not to the stock CHIP composite output. If the serial shell works but
the PocketCHIP screen is dark, check the backlight and DRM connector state from
the serial console:

```sh
cat /sys/class/backlight/backlight/{brightness,actual_brightness,max_brightness,bl_power}
for connector in /sys/class/drm/card0-*; do
  echo "$connector"
  cat "$connector/status" "$connector/enabled" "$connector/modes" 2>/dev/null
done
fbset -i
```

Expected LCD state:

- `/sys/class/backlight/backlight/bl_power` is `0`.
- The LCD connector exposes `480x272` and is enabled.
- The composite connector is disabled or no longer owns `/dev/fb0`.
- `fbset -i` reports a 480x272 framebuffer.

If the backlight is powered down, this live test should turn it on without
changing the image:

```sh
echo 10 > /sys/class/backlight/backlight/brightness
echo 0 > /sys/class/backlight/backlight/bl_power
```

The keyboard driver should bind as `tca8418`. Confirm physical keys with:

```sh
grep -A8 -B2 tca8418 /proc/bus/input/devices
evtest /dev/input/event2
```

During the `evtest` capture, press letters, Enter, arrows, Esc, Backspace, and
modifiers. A working matrix emits key press and release events; wrong key names
mean the keymap needs correction, while no events means the interrupt, I2C, or
matrix wiring still needs investigation.

The image loads two PocketCHIP usability layers above the raw matrix:

- `/usr/local/share/keymaps/pocketchip.kmap` is loaded on boot for Linux tty
  use.
- `$HOME/.Xmodmap` is loaded from `$HOME/.xinitrc` for X11/i3 use.

Right Alt is treated as the PocketCHIP Fn/AltGr layer. Expected terminal-use
combos include:

```text
Fn+1..0       F1..F10
Fn+-          F11
Fn+=/+        F12
Fn+y/u        { }
Fn+i/o        [ ]
Fn+p          |
Fn+h/j        < >
Fn+k/l        ' "
Fn+b/n        ` ~
Fn+m          :
Fn+arrows     Home/End/PageUp/PageDown
```

## Xorg/i3 Verification

Run `startx` as the configured user after the LCD and keyboard work:

```sh
su - "$(sed -n 's/^POCKETCHIP_USER=//p' /etc/default/pocketchip-user)"
startx
```

If `startx` fails before i3 starts, check the Xorg log:

```sh
tail -160 ~/.local/share/xorg/Xorg.0.log
```

The error below means Xorg could see DRM/KMS but did not have permission to open
the virtual console:

```text
systemd-logind: failed to get session
xf86OpenConsole: Cannot open virtual console 1 (Permission denied)
```

That is expected when `startx` is run from the serial shell as an unprivileged
user. Either run `startx` from a local LCD VT login, or start the desktop from
the serial root shell with:

```sh
pocketchip-startx
```

`pocketchip-startx` starts Xorg as root on `vt1` and runs `i3` as the configured
user, which avoids depending on a local logind session during serial bring-up.
The configured user can also run `starti3`; the image installs a narrow sudoers
entry for that helper.

PocketCHIP i3 bindings:

```text
Mod+Enter        terminal
Mod+w            Firefox ESR
Mod+d            PocketCHIP app launcher
Mod+x            power menu
Mod+Esc          screen off + password lock
Mod+Shift+x      low-power lock
Mod+Shift+c      caffeine stay-awake toggle
Mod+h/j/k/l      focus left/down/up/right
Mod+Shift+h/j/k/l move window left/down/up/right
Mod+1..4         switch workspace
Mod+Shift+1..4   move window to workspace
Mod+f            fullscreen; sends browser F11 when browser is focused
Mod+Shift+Space  floating toggle
Mod+n            Wi-Fi TUI
Mod+b            Bluetooth TUI
Mod+Shift+n      PocketCHIP connect menu
Mod+Shift+t      touchscreen calibration presets
Mod+Left/Right   browser back/forward, workspace prev/next outside browser
Mod+Up/Down      browser page up/down
Mod+u            browser URL bar, including from browser fullscreen
Mod+r            browser reload
Mod+Shift+f      browser fullscreen alias
Mod+Shift+slash  on-device cheat sheet
```

X idle locking is enabled by `xss-lock` from `.xinitrc`. The default X
screensaver and DPMS timeouts are 600 seconds. The kernel exposes `s2idle`, but
daily power saving should use `pocketchip-power low-lock` until suspend/resume
has been tested on the target device. Use `pocketchip-power caffeine` or
`Mod+Shift+c` to temporarily keep the screen on and disable X idle blanking;
toggle it again to restore the 600 second policy.

## Touch and Battery

Xorg should use `/dev/input/event*` for `1c25000.rtp` as an absolute touchscreen
and ignore the duplicate `/dev/input/mouse*` compatibility node. That preserves
stylus-like point/click behavior while avoiding two drivers fighting over the
same resistive panel.

Confirm the live X input state with:

```sh
xinput list
xinput list-props '1c25000.rtp'
grep -E '1c25000.rtp|Ignoring' ~/.local/share/xorg/Xorg.0.log
```

If pointer movement is inverted or rotated, use the device hotkey
`Mod+Shift+t`, or run one of these from an X terminal:

```sh
pocketchip-touch-calibrate identity
pocketchip-touch-calibrate invert-x
pocketchip-touch-calibrate invert-y
pocketchip-touch-calibrate invert-xy
pocketchip-touch-calibrate swap-xy
pocketchip-touch-calibrate learn-edges
pocketchip-touch-calibrate status
```

The current default is `invert-xy`, which corrects the observed 180-degree
inversion on the PocketCHIP panel. If a future build behaves differently, use
the calibration menu or `learn-edges` to find the correct matrix, then persist it in
`configs/local.env` with `POCKETCHIP_TOUCH_MATRIX='...'` and rebuild the image.

Browser use is optimized for keyboard plus gestures. Horizontal gestures map to
back/forward in Firefox, vertical gestures map to page up/down, and precise edge
taps are not required for normal browser navigation.

Battery state comes from the AXP20x power-supply driver:

```sh
cat /sys/class/power_supply/axp20x-battery/uevent
upower -d
```

The i3 bar uses `/usr/local/bin/pocketchip-status` instead of stock `i3status`
so it can display the `axp20x-battery` capacity and charge state directly.

## Milestone 2: NAND

NAND work is now scoped in `docs/nand.md`. The first write path should use the
legacy CHIP-tools NAND layout with repo-generated Debian UBIFS/UBI artifacts.
Mainline NAND U-Boot remains a probe/compare path until it reliably detects the
device NAND and survives a full NAND boot cycle.
