# Entering FEL Mode

FEL is the Allwinner BootROM USB recovery mode. For PocketCHIP/CHIP, use the
micro-USB OTG/data port connected to the host running `sunxi-fel`.

## What To Connect

- UART adapter stays connected for logs.
- PocketCHIP USB rootfs drive can stay plugged into the PocketCHIP USB host
  port.
- Host computer connects to PocketCHIP/CHIP through the micro-USB data/power
  port.
- A temporary jumper connects `FEL` to `GND` only while powering on or resetting.

## Procedure

1. Start a host-side watcher:

   ```sh
   watch -n 0.5 'lsusb | grep -Ei "1f3a|efe8|Allwinner|Onda" || true'
   ```

   Or repeatedly run:

   ```sh
   sunxi-fel ver
   ```

2. Power the PocketCHIP fully off. If the battery keeps it alive, use reset or
   disconnect/reconnect power so the SoC really restarts.
3. Connect the `FEL` pin to any `GND` pin with a jumper.
4. While `FEL` is grounded, power on or reset the PocketCHIP.
5. Confirm the host sees FEL. Expected USB VID/PID is:

   ```text
   1f3a:efe8
   ```

6. Once `sunxi-fel ver` works, remove the `FEL` to `GND` jumper.
7. Run:

   ```sh
   sudo ./scripts/fel-usb-boot-verify.py
   ```

## Notes

- Do not connect `FEL` to voltage. It is only pulled to `GND`.
- Keep UART attached; FEL itself is silent on UART until U-Boot is loaded.
- If stock Linux boots instead, the `FEL` pin was not grounded during reset or
  the board did not fully restart.
- If nothing appears on USB, try a known data-capable micro-USB cable and check
  that the host sees the CP2104 UART separately from the CHIP micro-USB cable.

