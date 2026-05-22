# PocketCHIP Quick Reference

Mod is Alt on the PocketCHIP keyboard.

## Start Here

| Key | Action |
| --- | --- |
| Mod+Enter | terminal |
| Mod+m or Mod+d | PocketCHIP app menu |
| Mod+Shift+/ | this cheat sheet |
| Mod+i | system about/support card |
| Mod+w | Firefox ESR |
| Mod+n / Mod+b | Wi-Fi / Bluetooth TUI |
| Mod+c | controls menu |
| Mod+x | power menu |
| Mod+Esc | screen off + password lock |
| Mod+Shift+c | caffeine stay-awake toggle |

Menu entries are grouped for dmenu filtering: `app:`, `net:`, `ctl:`, `sys:`,
and `power:`.

## Daily Keys

| Key | Action |
| --- | --- |
| Mod+h/j/k/l | focus left/down/up/right |
| Mod+Shift+h/j/k/l | move window left/down/up/right |
| Mod+1..4 | switch workspace |
| Mod+Shift+1..4 | move window to workspace |
| Mod+f | move focused window to/from 5:focus workspace |
| Mod+Shift+f | browser F11 fullscreen |
| Mod+Space | switch tiling/floating focus |
| Mod+Shift+Space | toggle floating |
| Mod+Shift+q | close window |
| Mod+Shift+r | reload i3 config |
| Mod+Shift+e | exit i3 |
| Mod+Shift+Esc | force exit app/i3 fullscreen |

## Terminal And SSH

| Key | Action |
| --- | --- |
| Ctrl++ | Sakura terminal zoom in |
| Ctrl+- | Sakura terminal zoom out |
| Mod+Shift+= | send terminal zoom in to focused app |
| Mod+Shift+- | send terminal zoom out to focused app |
| Ctrl+Shift+c / Ctrl+Shift+v | copy / paste in Sakura |
| Enter then `~.` | OpenSSH escape to disconnect a stuck SSH session |
| Mod+Backspace | send OpenSSH disconnect escape to focused terminal |
| Mod+Shift+Backspace | hard close focused window |

Use `Mod+Backspace` only with a terminal/SSH session focused. It sends
`Enter` followed by `~.`, which OpenSSH treats as a local disconnect escape at
the start of a line. If the terminal itself is wedged, use
`Mod+Shift+Backspace`.

## Browser And Gestures

| Key or Gesture | Action |
| --- | --- |
| Mod+w | Firefox ESR |
| Mod+Shift+w | lightweight browser if installed |
| Mod+Left / Mod+Right | browser back/forward, otherwise workspace prev/next |
| Mod+Up / Mod+Down | browser page up/down |
| Mod+u | focus browser URL bar, including from browser fullscreen |
| Mod+r | browser reload |
| Mod+f | move focused window to/from 5:focus workspace |
| Mod+Shift+f | browser F11 fullscreen |
| Left/right edge swipe | browser back/forward |
| Vertical browser swipe | page up/down |

Touch outside the browser is best treated as coarse navigation; normal i3 use is
keyboard-first.

`Mod+f` moves the focused window to a dedicated `5:focus` workspace and follows
it. Press `Mod+f` again from `5:focus` to send it back to its original
workspace. If the focused app exits while on `5:focus`, i3 returns to the
original workspace. This avoids true fullscreen and tabbed-layout input edge
cases.

## Controls

| Key | Action |
| --- | --- |
| Mod+c | controls menu |
| Mod+v | ALSA volume mixer |
| Mod+Shift+v | brightness TUI |
| Mod+- / Mod+= | brightness down/up |
| Mod+, / Mod+. | volume down/up |
| Mod+/ | toggle audio output |
| Mod+Shift+t | touchscreen calibration presets |

Brightness and volume hotkeys show a short `br ...` or `vol ...` alert in the
i3 bar.

## Power

| Command | Action |
| --- | --- |
| pocketchip-power menu | lock/logout/reboot/poweroff menu |
| pocketchip-power lock | password lock; screen off; wake by power or charger |
| pocketchip-power low-lock | lock plus Wi-Fi/Bluetooth down and low CPU cap |
| pocketchip-power caffeine | toggle stay-awake mode |
| pocketchip-power caffeine-status | show stay-awake state and X idle policy |
| pocketchip-power performance | switch CPU governor to performance |
| pocketchip-power normal | restore CPU cap/governor and radios |
| pocketchip-power screen-off | turn display off now |
| pocketchip-power screen-on | turn display on now |

## Network And Bluetooth

| Command | Action |
| --- | --- |
| pocketchip-connect menu | combined connection menu |
| pocketchip-connect wifi-list | scan Wi-Fi |
| pocketchip-connect wifi-connect SSID | connect to visible Wi-Fi |
| pocketchip-connect wifi-connect --hidden SSID | connect to hidden Wi-Fi |
| pocketchip-connect wifi-hidden PROFILE yes | mark profile as hidden |
| pocketchip-connect bt-info | Bluetooth state |
| pocketchip-connect bt-reset | reset Bluetooth service/radio |
| pocketchip-connect bt-scan 15 | scan for 15 seconds |
| pocketchip-connect bt-devices | known Bluetooth devices |
| pocketchip-connect bt-pair MAC | pair device |

## Touch Calibration

| Command | Action |
| --- | --- |
| pocketchip-touch-calibrate menu | choose preset |
| pocketchip-touch-calibrate edge-fit | default stylus-style edge fit |
| pocketchip-touch-calibrate edge-fit-y | adjust vertical reach |
| pocketchip-touch-calibrate edge-fit-strong | stronger edge compensation |
| pocketchip-touch-calibrate invert-xy | invert both axes |
| pocketchip-touch-calibrate learn-edges | interactive edge sampling |
| pocketchip-touch-calibrate status | show active config |

## CLI Aliases

| Alias | Action |
| --- | --- |
| starti3 | launch i3 from login shell |
| tm | attach/create tmux session named pocketchip |
| wifi | open nmtui |
| bt | open bluetoothctl |
| connect | PocketCHIP Wi-Fi/Bluetooth helper |
| web | Firefox ESR |
| web-light | lightweight browser if installed |
| cheat | read this file |
| tmux-mouse | toggle tmux mouse mode |

## About Card And Bar

About card: `Mod+i`, `j/k` scroll line, `Space/b` scroll page, `q` close.

Bar colors: green healthy/connected, yellow warning/medium/caffeine, red
low/off/high load, cyan charging/time.
