#!/usr/bin/env python3
import argparse
import os
import re
import select
import subprocess
import sys
import termios
import time
from pathlib import Path


PROMPT_RE = re.compile(r"(^|\r|\n)=>\s*$")


def configure_serial(fd: int, baud: int = termios.B115200) -> None:
    attrs = termios.tcgetattr(fd)
    attrs[0] = 0
    attrs[1] = 0
    attrs[2] = termios.CS8 | termios.CREAD | termios.CLOCAL
    attrs[3] = 0
    attrs[4] = baud
    attrs[5] = baud
    attrs[6][termios.VMIN] = 0
    attrs[6][termios.VTIME] = 0
    if hasattr(termios, "CRTSCTS"):
        attrs[2] &= ~termios.CRTSCTS
    termios.tcsetattr(fd, termios.TCSANOW, attrs)
    termios.tcflush(fd, termios.TCIOFLUSH)


class SerialSession:
    def __init__(self, port: str, log_path: Path | None):
        self.port = port
        self.fd = os.open(port, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
        configure_serial(self.fd)
        self.buffer = ""
        self.log = None
        if log_path:
            log_path.parent.mkdir(parents=True, exist_ok=True)
            self.log = log_path.open("w", encoding="utf-8", errors="replace")

    def close(self) -> None:
        if self.log:
            self.log.close()
        os.close(self.fd)

    def write(self, data: str | bytes) -> None:
        raw = data.encode() if isinstance(data, str) else data
        os.write(self.fd, raw)

    def _emit(self, data: bytes) -> None:
        text = data.decode("utf-8", "replace")
        sys.stdout.write(text)
        sys.stdout.flush()
        if self.log:
            self.log.write(text)
            self.log.flush()
        self.buffer = (self.buffer + text)[-30000:]

    def pump(self, seconds: float, interrupt: bool = False) -> str:
        end = time.time() + seconds
        last_interrupt = 0.0
        start_len = len(self.buffer)
        while time.time() < end:
            now = time.time()
            if interrupt and now - last_interrupt > 0.03:
                self.write(b" \r")
                last_interrupt = now
            r, _, _ = select.select([self.fd], [], [], 0.05)
            if self.fd in r:
                try:
                    data = os.read(self.fd, 4096)
                except BlockingIOError:
                    data = b""
                if data:
                    self._emit(data)
        return self.buffer[start_len:]

    def wait_for_prompt(self, timeout: float, interrupt: bool = False) -> bool:
        end = time.time() + timeout
        while time.time() < end:
            self.pump(0.2, interrupt=interrupt)
            if PROMPT_RE.search(self.buffer):
                return True
        return False

    def command(self, command: str, timeout: float = 8.0) -> str:
        marker = f"__CMD_{int(time.time() * 1000)}__"
        start_len = len(self.buffer)
        self.write(command + "\r")
        end = time.time() + timeout
        while time.time() < end:
            self.pump(0.2)
            if PROMPT_RE.search(self.buffer[start_len:]):
                break
        output = self.buffer[start_len:]
        if self.log:
            self.log.write(f"\n[{marker}] {command}\n")
            self.log.flush()
        return output


def run_checked(cmd: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(cmd, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)


def wait_for_fel(sunxi_fel: str, timeout: int) -> bool:
    deadline = time.time() + timeout
    while time.time() < deadline:
        result = run_checked([sunxi_fel, "ver"])
        if result.returncode == 0:
            print(result.stdout.strip())
            return True
        time.sleep(1)
    return False


def parse_boot_names(ext4ls_output: str) -> tuple[str | None, str | None, str | None]:
    kernels = sorted(set(re.findall(r"\bvmlinuz-[^\s]+", ext4ls_output)))
    initrds = sorted(set(re.findall(r"\binitrd\.img-[^\s]+", ext4ls_output)))
    kernel = kernels[-1] if kernels else None
    initrd = initrds[-1] if initrds else None
    version = kernel.removeprefix("vmlinuz-") if kernel else None
    return kernel, initrd, version


def main() -> int:
    repo_root = Path(__file__).resolve().parents[1]
    default_uboot = repo_root / "build/u-boot-mainline/u-boot-sunxi-with-spl.bin"
    default_log = repo_root / "build/logs/fel-usb-boot-verify.log"

    parser = argparse.ArgumentParser(description="FEL-load mainline U-Boot and verify USB rootfs boot.")
    parser.add_argument("--serial", default=os.environ.get("SERIAL_PORT", "/dev/ttyUSB0"))
    parser.add_argument("--sunxi-fel", default=os.environ.get("SUNXI_FEL", "sunxi-fel"))
    parser.add_argument("--uboot", default=os.environ.get("UBOOT_IMAGE", str(default_uboot)))
    parser.add_argument("--log", default=os.environ.get("FEL_VERIFY_LOG", str(default_log)))
    parser.add_argument("--fel-timeout", type=int, default=int(os.environ.get("FEL_TIMEOUT", "60")))
    parser.add_argument("--no-sysboot", action="store_true", help="skip sysboot and force manual ext4load fallback")
    args = parser.parse_args()

    uboot = Path(args.uboot)
    if not uboot.is_file():
        print(f"error: U-Boot image not found: {uboot}", file=sys.stderr)
        return 2

    print(f"[fel] waiting for FEL device with {args.sunxi_fel} ver")
    if not wait_for_fel(args.sunxi_fel, args.fel_timeout):
        print("error: FEL device not found. Hold FEL to GND during reset/power-on and retry.", file=sys.stderr)
        return 1

    log_path = Path(args.log) if args.log else None
    serial = SerialSession(args.serial, log_path)
    try:
        print(f"[serial] opened {args.serial} at 115200 8N1")
        print(f"[fel] loading {uboot}")
        result = subprocess.run([args.sunxi_fel, "uboot", str(uboot)])
        if result.returncode != 0:
            return result.returncode

        if not serial.wait_for_prompt(30, interrupt=True):
            print("error: U-Boot prompt was not detected after FEL load.", file=sys.stderr)
            return 1

        print("\n[verify] U-Boot prompt detected")
        checks = [
            "version",
            "printenv boot_targets bootcmd bootdelay fdtfile",
            "usb reset",
            "usb tree",
            "usb storage",
            "usb part 0",
            "ext4ls usb 0:1 /",
            "ext4ls usb 0:1 /boot",
            "ext4ls usb 0:1 /boot/extlinux",
        ]

        outputs: dict[str, str] = {}
        for command in checks:
            print(f"\n[verify] {command}")
            outputs[command] = serial.command(command, timeout=10)

        if "No controllers found" in outputs.get("usb reset", ""):
            print("error: FEL-loaded U-Boot still reports no USB controllers.", file=sys.stderr)
            return 1
        if "** Bad device usb 0 **" in "".join(outputs.values()):
            print("error: U-Boot did not enumerate USB storage as usb 0.", file=sys.stderr)
            return 1

        if not args.no_sysboot:
            print("\n[boot] trying extlinux sysboot")
            sysboot_out = serial.command(
                "sysboot usb 0:1 any ${scriptaddr} /boot/extlinux/extlinux.conf",
                timeout=20,
            )
            if "Starting kernel" in sysboot_out or "Loading Linux" in sysboot_out:
                serial.pump(90)
                return 0
            if not PROMPT_RE.search(sysboot_out):
                serial.pump(90)
                return 0
            print("\n[boot] sysboot returned to prompt; trying manual ext4load fallback")

        boot_listing = outputs.get("ext4ls usb 0:1 /boot", "")
        kernel, initrd, version = parse_boot_names(boot_listing)
        if not kernel or not initrd or not version:
            print("error: could not infer vmlinuz/initrd names from /boot listing.", file=sys.stderr)
            return 1

        fdt_path = (
            "/boot/sun5i-r8-pocketchip.dtb"
            if "sun5i-r8-pocketchip.dtb" in boot_listing
            else f"/usr/lib/linux-image-{version}/sun5i-r8-chip.dtb"
        )
        manual = [
            "setenv bootargs console=ttyS0,115200 root=LABEL=pocketroot rootwait rw loglevel=4",
            f"ext4load usb 0:1 ${{kernel_addr_r}} /boot/{kernel}",
            f"ext4load usb 0:1 ${{ramdisk_addr_r}} /boot/{initrd}",
            "setenv ramdisk_size ${filesize}",
            f"ext4load usb 0:1 ${{fdt_addr_r}} {fdt_path}",
            "bootz ${kernel_addr_r} ${ramdisk_addr_r}:${ramdisk_size} ${fdt_addr_r}",
        ]
        for command in manual:
            print(f"\n[boot] {command}")
            serial.command(command, timeout=15)
            if command.startswith("bootz"):
                serial.pump(90)
                break
    finally:
        serial.close()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
