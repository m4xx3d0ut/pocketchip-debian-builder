# PocketCHIP Serial UART Wiring

This is the wiring procedure for using a USB serial/debug adapter with a
PocketCHIP/CHIP serial console.

## Critical Safety Check

Do not use a true RS-232 level adapter directly on PocketCHIP.

PocketCHIP/CHIP wants 3.3 V TTL UART logic on the UART pins. A real RS-232
adapter can drive negative and higher positive voltages and can damage the CHIP.
Many cheap adapters are marketed loosely as "USB RS232" while actually being
USB-to-TTL UART. Check the adapter label, jumper, or datasheet before connecting.

Safe adapter markings usually say one of:

- `USB TTL`
- `USB UART`
- `3.3V TTL`
- `CP2102`, `CH340`, `FT232`, or `PL2303` with 3.3 V logic selected

Do not connect if the adapter output is:

- DB9/de9 RS-232 only
- `RS232 +/-12V`
- 5 V-only UART logic

## Required Wires

Use only three wires, even if the adapter has four, five, or six pins:

- GND
- Adapter RXD
- Adapter TXD

Do not connect the adapter VCC wire for serial console. The PocketCHIP should be
powered through its normal battery/USB power path.

For a common 6-pin adapter labeled `GND`, `RX`, `TX`, `5V`, `3V`, `DT`:

| Adapter pin | Use? | PocketCHIP / CHIP connection |
| --- | --- | --- |
| `GND` | Yes | `GND` |
| `RX` | Yes | `UART1-TX` |
| `TX` | Yes | `UART1-RX` |
| `5V` | No | Leave disconnected |
| `3V` / `3V3` | No | Leave disconnected |
| `DT` / `DTR` | No | Leave disconnected |

`DT` is commonly `DTR`. It is used by some boards for reset/bootloader control,
but it is not needed for PocketCHIP serial console access.

## Pin Mapping

With the CHIP oriented as in the original NTC docs, USB connectors at the top,
the UART console is on header `U14`:

| CHIP/PocketCHIP signal | U14 pin | Connects to adapter |
| --- | ---: | --- |
| `GND` | 1 | `GND` |
| `UART1-TX` | 3 | `RXD` |
| `UART1-RX` | 5 | `TXD` |
| `VCC-5V` / `VCC-3V3` | nearby pins | Do not connect |

TX and RX cross over:

- CHIP `TX` goes to adapter `RXD`
- CHIP `RX` goes to adapter `TXD`

If your adapter has the common NTC tutorial colors:

| Adapter wire | Meaning | Connect to |
| --- | --- | --- |
| Black | GND | U14 pin 1 `GND` |
| Green | Adapter RX | U14 pin 3 `UART1-TX` |
| White | Adapter TX | U14 pin 5 `UART1-RX` |
| Red | VCC, often +5 V | Leave disconnected |

If your adapter uses different colors, ignore colors and follow the printed pin
labels or datasheet.

If your adapter exposes both `5V` and `3V` pins, those are usually power output
pins. They do not automatically prove that the UART `TX` logic is 3.3 V. When in
doubt, measure adapter `TX` to adapter `GND`; idle should be about 3.3 V before
connecting it to PocketCHIP.

## Before Connecting

1. Unplug PocketCHIP power.
2. Unplug the USB serial adapter from the host.
3. Confirm the adapter is set to 3.3 V logic if it has a `3V3/5V` jumper.
4. If you have a multimeter, verify adapter `TXD` idles around 3.3 V relative
   to adapter `GND`, not 5 V and not RS-232 voltage.
5. Confirm which PocketCHIP header pins are `GND`, `TX`, and `RX`.

## Physical Connection Steps

1. Connect adapter `GND` to CHIP/PocketCHIP `GND`.
2. Connect adapter `RXD` to CHIP/PocketCHIP `UART1-TX`.
3. Connect adapter `TXD` to CHIP/PocketCHIP `UART1-RX`.
4. Leave adapter `VCC`, `5V`, or `3V3` unconnected.
5. Plug the USB serial adapter into the host computer.
6. Open the serial terminal on the host.
7. Power on PocketCHIP.

## Host Serial Settings

Use:

- Baud: `115200`
- Data bits: `8`
- Parity: `none`
- Stop bits: `1`
- Flow control: `none`

Linux examples:

```sh
dmesg --follow
```

Plug in the adapter and note the new device, usually `/dev/ttyUSB0` or
`/dev/ttyACM0`.

Then connect:

```sh
screen /dev/ttyUSB0 115200
```

or:

```sh
picocom -b 115200 /dev/ttyUSB0
```

To exit `screen`, press `Ctrl-A`, then `K`, then `Y`.

## Interrupting U-Boot

For boot testing:

1. Start the serial terminal before applying power.
2. Power on PocketCHIP.
3. Watch for U-Boot output.
4. Press a key during the boot countdown to stop autoboot.
5. Run USB boot commands from the U-Boot prompt.

For the USB rootfs image created by this repo, the first command to try is:

```text
usb start
sysboot usb 0:1 any ${scriptaddr} /boot/extlinux/extlinux.conf
```

## Troubleshooting

No output:

- Check that GND is connected.
- Swap only TX/RX; do not move VCC.
- Confirm the serial device path is correct.
- Confirm 115200 8N1 with no flow control.
- Start the terminal before powering PocketCHIP.

Readable output, but typing does nothing:

- Adapter RX is correct, but adapter TX may not be connected to CHIP RX.
- Check TX/RX crossover.
- Make sure hardware flow control is disabled.

Gibberish output:

- Wrong baud rate or terminal settings.
- Use 115200 8N1.

Adapter gets hot or PocketCHIP behaves strangely:

- Disconnect immediately.
- Re-check that VCC is not connected.
- Re-check that the adapter is TTL 3.3 V, not true RS-232.
