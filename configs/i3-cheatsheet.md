# PocketCHIP i3 Cheat Sheet

Mod is Alt on the PocketCHIP keyboard.

## i3

- Mod+Enter: terminal
- Mod+w: Firefox ESR
- Mod+Shift+w: lightweight browser if installed
- Mod+Left / Mod+Right: browser back/forward, otherwise workspace prev/next
- Mod+Up / Mod+Down: browser page up/down
- Mod+u: focus browser URL bar, including from browser fullscreen
- Mod+r: browser reload
- Mod+f: fullscreen; sends browser F11 when a browser is focused
- Mod+Shift+f: browser fullscreen alias
- Mod+m: PocketCHIP menu
- Mod+i: system about/support card
- Mod+d: PocketCHIP app launcher
- Mod+x: power menu
- Mod+Esc: screen off + password lock
- Mod+Shift+x: low-power lock
- Mod+h/j/k/l: focus left/down/up/right
- Mod+Shift+h/j/k/l: move window left/down/up/right
- Mod+1..4: switch workspace
- Mod+Shift+1..4: move window to workspace
- Mod+Space: switch tiling/floating focus
- Mod+Shift+Space: toggle floating
- Mod+Shift+q: close window
- Mod+n: Wi-Fi TUI
- Mod+b: Bluetooth TUI
- Mod+Shift+n: PocketCHIP connect menu
- Mod+Shift+p: CPU performance mode
- Mod+c: controls menu
- Mod+v: ALSA volume mixer
- Mod+Shift+v: brightness TUI
- Mod+- / Mod+=: brightness down/up
- Mod+, / Mod+.: volume down/up
- Mod+/: toggle audio output
- Mod+Shift+t: touchscreen calibration presets
- Mod+Shift+/: this cheat sheet
- Mod+Shift+r: reload i3 config
- Mod+Shift+e: exit i3

About card:

- Mod+i: open system about/support card
- j/k: scroll line down/up
- Space/b: scroll page down/up
- q: close

i3 bar colors:

- green: healthy/connected
- yellow: warning/medium
- red: low/off/high load
- cyan: charging/time

## Touch Gestures

- Swipe from left edge to right: previous workspace
- Swipe from right edge to left: next workspace
- In browser, horizontal swipes map to back/forward
- In browser, vertical swipes map to page up/down
- Outside browser, bottom/top gestures remain menu/navigation oriented

Touch presets:

- pocketchip-touch-calibrate menu
- pocketchip-touch-calibrate edge-fit
- pocketchip-touch-calibrate invert-xy
- pocketchip-touch-calibrate edge-fit-y
- pocketchip-touch-calibrate edge-fit-strong
- pocketchip-touch-calibrate learn-edges
- pocketchip-touch-calibrate status

## CLI

- starti3: launch i3 from the login shell
- tm: attach/create tmux session named pocketchip
- wifi: open nmtui
- bt: open bluetoothctl
- connect: PocketCHIP Wi-Fi/Bluetooth helper
- web: Firefox ESR
- web-light: lightweight browser if installed
- pocketchip-about: system about/support card
- pocketchip-power menu: lock/logout/reboot/poweroff menu
- pocketchip-control menu: brightness/audio controls
- pocketchip-control brightness: brightness TUI
- pocketchip-control volume: ALSA mixer TUI
- cheat: read this file
- tmux-mouse: toggle tmux mouse mode

## Brightness and Audio

- pocketchip-control status
- pocketchip-control brightness-up
- pocketchip-control brightness-down
- pocketchip-control brightness-set LEVEL
- pocketchip-control volume-up
- pocketchip-control volume-down
- pocketchip-control volume-mute
- pocketchip-control volume-on
- pocketchip-control volume-off

## Power

- pocketchip-power lock: password lock, screen off, wake by power button or charger
- pocketchip-power low-lock: lock plus Wi-Fi/Bluetooth down and low CPU cap
- pocketchip-power performance: switch CPU governor to performance
- pocketchip-power normal: restore CPU cap/governor and turn radios back on
- pocketchip-power screen-off: turn display off now
- pocketchip-power screen-on: turn display on now

## Wi-Fi and Bluetooth

- pocketchip-connect menu
- pocketchip-connect wifi-list
- pocketchip-connect wifi-connect SSID
- pocketchip-connect wifi-connect --hidden SSID
- pocketchip-connect wifi-hidden PROFILE yes
- pocketchip-connect bt-info
- pocketchip-connect bt-reset
- pocketchip-connect bt-scan 15
- pocketchip-connect bt-devices
- pocketchip-connect bt-pair MAC
