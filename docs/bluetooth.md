# PocketCHIP Bluetooth HCI Bring-Up

The PocketCHIP radio is an RTL8723BS combo part. Wi-Fi is exposed over SDIO;
Bluetooth is exposed over UART3 using the Realtek H5 protocol.

## Current Status

BlueZ, Bluetooth CLI tools, firmware, and kernel modules are present in the
balanced image. Bluetooth HCI was verified on a NAND boot after adding UART3
RTS/CTS flow control to the PocketCHIP overlay.

```sh
test -e /proc/device-tree/soc/serial@1c28c00/uart-has-rtscts && echo ok
ls -la /sys/class/bluetooth
btmgmt info
```

Expected success state:

```text
/proc/device-tree/soc/serial@1c28c00/uart-has-rtscts exists
/sys/class/bluetooth/hci0 exists
btmgmt info lists at least one controller
```

## Known Good Pieces

On the Debian 13 NAND bring-up image, the following pieces were confirmed:

- `bluetooth.service` starts.
- `bluetoothctl` and `btmgmt` are installed.
- Realtek firmware exists under `/lib/firmware/rtl_bt/`.
- `hci_uart`, `btrtl`, and `bluetooth` modules load.
- The live device tree contains a `bluetooth` child under UART3
  (`/proc/device-tree/soc/serial@1c28c00/bluetooth`).
- The serial-bus child binds to the kernel `hci_uart_h5` driver.

That means a missing controller is below BlueZ. The failing layer is the UART/H5
controller handshake.

## Device Tree Fix

The mainline Realtek Bluetooth binding example declares RTS/CTS on the parent
UART, and comparable Allwinner Bluetooth UART nodes do the same. The PocketCHIP
base DT already assigns UART3 TX/RX and CTS/RTS pins, but the live DTB did not
contain `uart-has-rtscts`.

The PocketCHIP overlay now adds:

```dts
&uart3 {
	uart-has-rtscts;
};
```

Rebuild and boot a fresh DTB before retesting Bluetooth:

```sh
./scripts/build-pocketchip-dtbo.sh
make nand-image-mlc-pc-slc
```

On the device, confirm the DT property landed:

```sh
test -e /proc/device-tree/soc/serial@1c28c00/uart-has-rtscts && echo ok
```

Then retest:

```sh
systemctl is-active bluetooth.service
ls -la /sys/class/bluetooth
btmgmt info
bluetoothctl show
bluetoothctl --timeout 10 scan on
dmesg | grep -Ei 'Bluetooth|hci|H5|rtl|btrtl|serdev|8723|firmware'
```

## If `hci0` Is Still Missing

Capture the low-level state before changing userspace:

```sh
rfkill list
lsmod | grep -Ei 'bluetooth|hci|rtl|8723'
find /sys/bus/serial/devices -maxdepth 2 -type l -o -type f
gpioinfo
```

The next suspects are:

- `device-wake-gpios` polarity or role on AXP GPIO3.
- Whether AXP GPIO3 should be modeled as `enable-gpios` instead of, or in
  addition to, `device-wake-gpios`.
- UART3 flow-control behavior if `uart-has-rtscts` is still not sufficient.
- A userspace attach fallback that disables the DT Bluetooth child, exposes
  UART3 as a tty, and runs a Realtek H5 attach helper.

Do not ship release notes claiming Bluetooth support until `hci0` appears and a
basic scan succeeds.
