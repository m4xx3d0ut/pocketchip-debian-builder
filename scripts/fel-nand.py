#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import argparse
import os
import re
import select
import socket
import subprocess
import sys
import tempfile
import termios
import time
from pathlib import Path


# RAM layout for the destructive flash script. Keep these temporary payloads
# separate from the default sunxi script address at 0x43100000 and from the
# runtime U-Boot entry at 0x4a000000.
SPL_MEM = "0x48000000"
UBOOT_NAND_MEM = "0x49000000"
UBOOT_MEM = "0x4a000000"
SCRIPT_MEM = "0x43100000"
BOOT_KERNEL_MEM = "0x42000000"
BOOT_DTB_MEM = "0x42f00000"
BOOT_INITRD_MEM = "0x44000000"
NAND_INFO_MEM = "0x7c00"
NAND_INFO_SIZE = "0x100"

BOOT_KERNEL_OFF = 0x01000000
BOOT_DTB_OFF = 0x02000000
BOOT_INITRD_OFF = 0x02400000
UBI_OFF = 0x05000000

GEOMETRIES = {
    "hynix-8g-mlc": {
        "ubi_type": "400000-4000-680",
        "erase": 0x400000,
        "write": 0x4000,
        "oob": 0x680,
    },
    "toshiba-4g-mlc": {
        "ubi_type": "400000-4000-500",
        "erase": 0x400000,
        "write": 0x4000,
        "oob": 0x500,
    },
    "toshiba-512m-slc": {
        "ubi_type": "40000-1000-100",
        "erase": 0x40000,
        "write": 0x1000,
        "oob": 0x100,
    },
}

FORMAT_BY_UBI_TYPE = {v["ubi_type"]: k for k, v in GEOMETRIES.items()}
SHELL_MARKER = "__PC_NAND_VERIFY_DONE__"
BOOTLOADER_MARKER = "__PC_NAND_BOOTLOADER_FLASH_DONE__"


def run(cmd: list[str], check: bool = True, capture: bool = False) -> subprocess.CompletedProcess[str]:
    print("+ " + " ".join(cmd))
    result = subprocess.run(
        cmd,
        check=False,
        text=True,
        stdout=subprocess.PIPE if capture else None,
        stderr=subprocess.STDOUT if capture else None,
    )
    if capture and result.stdout:
        print(result.stdout.rstrip())
    if check and result.returncode != 0:
        raise SystemExit(result.returncode)
    return result


def wait_for_command_output(cmd: list[str], timeout: int, label: str) -> str:
    deadline = time.time() + timeout
    while time.time() < deadline:
        result = subprocess.run(cmd, check=False, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        if result.returncode == 0 and result.stdout.strip():
            return result.stdout.strip()
        time.sleep(1)
    raise RuntimeError(f"timed out waiting for {label}")


def wait_for_fel(args: argparse.Namespace) -> str:
    return wait_for_command_output([args.fel, "ver"], args.timeout, "FEL")


def wait_for_fastboot(args: argparse.Namespace) -> str:
    return wait_for_command_output([args.fastboot, "devices"], args.timeout, "fastboot")


def fastboot_visible(args: argparse.Namespace) -> bool:
    result = subprocess.run(
        [args.fastboot, "devices"],
        check=False,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    return result.returncode == 0 and bool(result.stdout.strip())


def mk_uboot_script(args: argparse.Namespace, lines: list[str], name: str, out_dir: Path) -> Path:
    script_txt = out_dir / f"{name}.cmd"
    script_img = out_dir / f"{name}.scr"
    script_txt.write_text("\n".join(lines) + "\n", encoding="utf-8")
    run([args.mkimage, "-A", "arm", "-T", "script", "-C", "none", "-n", name, "-d", str(script_txt), str(script_img)])
    return script_img


def resolve_uboot_pair(uboot_dir: Path) -> tuple[Path, Path]:
    spl = uboot_dir / "spl/sunxi-spl.bin"
    candidates = [
        uboot_dir / "u-boot-dtb-nand.bin",
        uboot_dir / "u-boot-dtb.bin",
        uboot_dir / "u-boot.bin",
    ]
    uboot = next((path for path in candidates if path.is_file()), candidates[0])
    missing = [path for path in (spl, uboot) if not path.is_file()]
    if missing:
        for path in missing:
            print(f"missing {path}", file=sys.stderr)
        raise SystemExit(2)
    return spl, uboot


def fel_load_script(args: argparse.Namespace, spl: Path, uboot: Path, script: Path) -> None:
    print(f"[fel] waiting for FEL device with {args.fel} ver")
    print(wait_for_fel(args))
    run([args.fel, "spl", str(spl)])
    time.sleep(1)
    run([args.fel, "write", UBOOT_MEM, str(uboot)])
    run([args.fel, "write", SCRIPT_MEM, str(script)])
    run([args.fel, "exe", UBOOT_MEM])


def fel_load_flash_script(
    args: argparse.Namespace,
    dram_spl: Path,
    runtime_uboot: Path,
    nand_spl: Path,
    nand_uboot: Path,
    script: Path,
    boot_kernel: Path | None = None,
    boot_dtb: Path | None = None,
    boot_initrd: Path | None = None,
) -> None:
    print(f"[fel] waiting for FEL device with {args.fel} ver")
    print(wait_for_fel(args))
    run([args.fel, "spl", str(dram_spl)])
    time.sleep(1)
    run([args.fel, "write", SPL_MEM, str(nand_spl)])
    run([args.fel, "write", UBOOT_NAND_MEM, str(nand_uboot)])
    if boot_kernel:
        run([args.fel, "write", BOOT_KERNEL_MEM, str(boot_kernel)])
    if boot_dtb:
        run([args.fel, "write", BOOT_DTB_MEM, str(boot_dtb)])
    if boot_initrd:
        run([args.fel, "write", BOOT_INITRD_MEM, str(boot_initrd)])
    run([args.fel, "write", UBOOT_MEM, str(runtime_uboot)])
    run([args.fel, "write", SCRIPT_MEM, str(script)])
    run([args.fel, "exe", UBOOT_MEM])


def fel_load_uboot(args: argparse.Namespace, spl: Path, uboot: Path) -> None:
    print(f"[fel] waiting for FEL device with {args.fel} ver")
    print(wait_for_fel(args))
    run([args.fel, "spl", str(spl)])
    time.sleep(1)
    run([args.fel, "write", UBOOT_MEM, str(uboot)])
    run([args.fel, "exe", UBOOT_MEM])


def fel_load_rescue_boot(
    args: argparse.Namespace,
    spl: Path,
    runtime_uboot: Path,
    kernel: Path,
    dtb: Path,
    initrd: Path,
    script: Path,
) -> None:
    print(f"[fel] waiting for FEL device with {args.fel} ver")
    print(wait_for_fel(args))
    run([args.fel, "spl", str(spl)])
    time.sleep(1)
    run([args.fel, "write", BOOT_KERNEL_MEM, str(kernel)])
    run([args.fel, "write", BOOT_DTB_MEM, str(dtb)])
    run([args.fel, "write", BOOT_INITRD_MEM, str(initrd)])
    run([args.fel, "write", UBOOT_MEM, str(runtime_uboot)])
    run([args.fel, "write", SCRIPT_MEM, str(script)])
    run([args.fel, "exe", UBOOT_MEM])


def parse_env_blob(path: Path) -> dict[str, str]:
    raw = path.read_bytes().replace(b"\x00", b"\n").decode("utf-8", "replace")
    env: dict[str, str] = {}
    for line in raw.splitlines():
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip()
        if key:
            env[key] = value
    return env


def normalize_hex(value: str) -> str:
    value = value.strip().lower()
    if value.startswith("0x"):
        return f"{int(value, 16):x}"
    if re.fullmatch(r"[0-9a-f]+", value):
        return value.lstrip("0") or "0"
    return f"{int(value, 0):x}"


def parse_int(value: str) -> int:
    return int(value, 0)


def geometry_from_env(env: dict[str, str]) -> tuple[str, str]:
    required = ["nand_erasesize", "nand_writesize", "nand_oobsize"]
    missing = [key for key in required if key not in env]
    if missing:
        raise RuntimeError(f"NAND probe did not export {', '.join(missing)}")
    ubi_type = "-".join(normalize_hex(env[key]) for key in required)
    if ubi_type not in FORMAT_BY_UBI_TYPE:
        raise RuntimeError(f"unsupported NAND geometry {ubi_type}")
    return FORMAT_BY_UBI_TYPE[ubi_type], ubi_type


def geometry_from_numbers(erase: int, write: int, oob: int) -> tuple[str, str]:
    ubi_type = f"{erase:x}-{write:x}-{oob:x}"
    if ubi_type not in FORMAT_BY_UBI_TYPE:
        raise RuntimeError(f"unsupported NAND geometry {ubi_type}")
    return FORMAT_BY_UBI_TYPE[ubi_type], ubi_type


def parse_nand_info(nand_info: str, printenv: str) -> tuple[str, str]:
    env: dict[str, str] = {}
    for line in printenv.splitlines():
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        if key.strip() in {"nand_erasesize", "nand_writesize", "nand_oobsize"}:
            env[key.strip()] = value.strip()
    if {"nand_erasesize", "nand_writesize", "nand_oobsize"} <= set(env):
        return geometry_from_env(env)

    patterns = {
        "erase": r"(?:Erase|erase)\s+size[^0-9]*(\d+)",
        "write": r"(?:Page|page|Write|write)\s+size[^0-9]*(\d+)",
        "oob": r"(?:OOB|oob)\s+size[^0-9]*(\d+)",
    }
    values: dict[str, int] = {}
    for key, pattern in patterns.items():
        match = re.search(pattern, nand_info)
        if match:
            values[key] = int(match.group(1), 10)
    if {"erase", "write", "oob"} <= set(values):
        return geometry_from_numbers(values["erase"], values["write"], values["oob"])

    raise RuntimeError("could not parse NAND geometry from U-Boot output")


def probe(args: argparse.Namespace, label: str, uboot_dir: Path) -> int:
    spl, uboot = resolve_uboot_pair(uboot_dir)
    args.images_dir.mkdir(parents=True, exist_ok=True)
    args.nand_dir.mkdir(parents=True, exist_ok=True)

    with tempfile.TemporaryDirectory(prefix=f"pocketchip-{label}-", dir=args.nand_dir) as temp_name:
        temp = Path(temp_name)
        script = mk_uboot_script(
            args,
            [
                "nand info",
                f"env export -t -s {NAND_INFO_SIZE} {NAND_INFO_MEM} nand_erasesize nand_writesize nand_oobsize",
                "reset",
            ],
            f"probe-{label}",
            temp,
        )
        fel_load_script(args, spl, uboot, script)

        print("[fel] waiting for reset back into FEL")
        print(wait_for_fel(args))
        info = temp / "nand-info.env"
        run([args.fel, "read", NAND_INFO_MEM, NAND_INFO_SIZE, str(info)])

        env = parse_env_blob(info)
        out = args.nand_dir / f"{label}-probe.env"
        out.write_text("".join(f"{key}={value}\n" for key, value in sorted(env.items())), encoding="utf-8")

        fmt, ubi_type = geometry_from_env(env)
        (args.images_dir / "ubi_type").write_text(ubi_type + "\n", encoding="utf-8")
        print(f"[probe] format={fmt}")
        print(f"[probe] ubi_type={ubi_type}")
        print(f"[probe] wrote {out}")
        print(f"[probe] wrote {args.images_dir / 'ubi_type'}")
    return 0


def probe_serial(args: argparse.Namespace, label: str, uboot_dir: Path) -> int:
    spl, uboot = resolve_uboot_pair(uboot_dir)
    args.images_dir.mkdir(parents=True, exist_ok=True)
    args.nand_dir.mkdir(parents=True, exist_ok=True)

    log_path = args.log if args.log else args.nand_dir / f"{label}-serial-probe.log"
    serial = SerialSession(args.serial, args.baud, log_path)
    try:
        fel_load_uboot(args, spl, uboot)
        if not serial.wait_for_uboot_prompt(30, interrupt=True):
            raise RuntimeError("U-Boot prompt was not detected over serial")

        print("\n[probe] nand info")
        nand_info = serial.uboot_command("nand info", timeout=20)
        print("\n[probe] printenv nand_erasesize nand_writesize nand_oobsize")
        printenv = serial.uboot_command("printenv nand_erasesize nand_writesize nand_oobsize", timeout=10)

        fmt, ubi_type = parse_nand_info(nand_info, printenv)
        out = args.nand_dir / f"{label}-serial-probe.env"
        out.write_text(
            f"format={fmt}\nubi_type={ubi_type}\nsource=serial\n",
            encoding="utf-8",
        )
        (args.images_dir / "ubi_type").write_text(ubi_type + "\n", encoding="utf-8")
        print(f"[probe] format={fmt}")
        print(f"[probe] ubi_type={ubi_type}")
        print(f"[probe] wrote {out}")
        print(f"[probe] wrote {args.images_dir / 'ubi_type'}")
        return 0
    finally:
        serial.close()


def resolve_flash_geometry(args: argparse.Namespace) -> tuple[str, dict[str, int | str]]:
    requested = args.format
    if requested == "auto":
        ubi_type_file = args.images_dir / "ubi_type"
        if not ubi_type_file.is_file():
            raise RuntimeError(
                f"missing {ubi_type_file}; run probe-legacy first or pass --format "
                + "|".join(GEOMETRIES)
            )
        requested = ubi_type_file.read_text(encoding="utf-8").strip()

    if requested in FORMAT_BY_UBI_TYPE:
        requested = FORMAT_BY_UBI_TYPE[requested]

    if requested not in GEOMETRIES:
        raise RuntimeError(f"unknown NAND format {requested}")

    return requested, GEOMETRIES[requested]


def require_artifact(path: Path) -> Path:
    if not path.is_file():
        raise RuntimeError(f"missing artifact: {path}")
    return path


def boot_artifacts(args: argparse.Namespace, geom: dict[str, int | str]) -> tuple[Path, Path, Path]:
    erase_hex, write_hex, oob_hex = str(geom["ubi_type"]).split("-")
    suffix = f"{erase_hex}-{write_hex}-{oob_hex}"
    return (
        require_artifact(args.images_dir / f"boot-zImage-{suffix}.bin"),
        require_artifact(args.images_dir / f"boot-sun5i-r8-chip-{suffix}.dtb"),
        require_artifact(args.images_dir / f"boot-initrd-{suffix}.uimage"),
    )


def rescue_artifacts(args: argparse.Namespace, geom: dict[str, int | str]) -> tuple[Path, Path, Path, Path]:
    erase_hex, write_hex, oob_hex = str(geom["ubi_type"]).split("-")
    suffix = f"{erase_hex}-{write_hex}-{oob_hex}"
    fmt_name = getattr(args, "resolved_format", args.format)
    ubifs = args.ubifs if args.ubifs else args.nand_dir / "work" / f"rootfs-{fmt_name}.ubifs"
    return (
        require_artifact(args.images_dir / f"boot-zImage-{suffix}.bin"),
        require_artifact(args.images_dir / f"boot-sun5i-r8-chip-{suffix}.dtb"),
        require_artifact(args.images_dir / f"nand-rescue-initrd-{suffix}.uimage"),
        require_artifact(ubifs),
    )


def nand_boot_env_lines(kernel_size: int, dtb_size: int, initrd_size: int, slc_boot: bool) -> list[str]:
    kernel_size_hex = f"0x{kernel_size:08x}"
    dtb_size_hex = f"0x{dtb_size:08x}"
    initrd_size_hex = f"0x{initrd_size:08x}"
    nand_read = "nand read.slc-mode" if slc_boot else "nand read"
    return [
        "setenv mtdids nand0=sunxi-nand.0",
        "setenv mtdparts 'mtdparts=sunxi-nand.0:4m(spl),4m(spl-backup),4m(uboot),4m(env),64m(boot),-(UBI)'",
        "setenv bootargs 'console=tty0 console=ttyS0,115200 root=ubi0:rootfs rootfstype=ubifs rw rootwait ubi.mtd=UBI loglevel=4'",
        "setenv kernel_addr_r 0x42000000",
        "setenv fdt_addr_r 0x43000000",
        "setenv ramdisk_addr_r 0x44000000",
        "setenv bootpaths 'initrd noinitrd'",
        f"setenv boot_initrd 'mtdparts; {nand_read} ${{fdt_addr_r}} 0x{BOOT_DTB_OFF:08x} {dtb_size_hex}; {nand_read} ${{ramdisk_addr_r}} 0x{BOOT_INITRD_OFF:08x} {initrd_size_hex}; {nand_read} ${{kernel_addr_r}} 0x{BOOT_KERNEL_OFF:08x} {kernel_size_hex}; bootz ${{kernel_addr_r}} ${{ramdisk_addr_r}} ${{fdt_addr_r}}'",
        f"setenv boot_noinitrd 'mtdparts; {nand_read} ${{fdt_addr_r}} 0x{BOOT_DTB_OFF:08x} {dtb_size_hex}; {nand_read} ${{kernel_addr_r}} 0x{BOOT_KERNEL_OFF:08x} {kernel_size_hex}; bootz ${{kernel_addr_r}} - ${{fdt_addr_r}}'",
        "setenv clear_fastboot 'i2c mw 0x34 0x4 0x00 4;'",
        "setenv write_fastboot 'i2c mw 0x34 0x4 66 1; i2c mw 0x34 0x5 62 1; i2c mw 0x34 0x6 30 1; i2c mw 0x34 0x7 00 1'",
        "setenv test_fastboot 'i2c read 0x34 0x4 4 0x80200000; if itest.s *0x80200000 -eq fb0; then echo (Fastboot); i2c mw 0x34 0x4 0x00 4; fastboot 0; fi'",
        "setenv bootcmd 'run test_fastboot; for path in ${bootpaths}; do run boot_${path}; done'",
        "setenv video-mode",
        "setenv stdout serial,vidconsole",
        "setenv stderr serial,vidconsole",
        "setenv bootdelay 1",
    ]


def nand_write_payload(mem_addr: int, nand_offset: int, size: int, erase_size: int, slc_boot: bool) -> list[str]:
    if slc_boot:
        return [f"nand write.slc-mode 0x{mem_addr:08x} 0x{nand_offset:08x} 0x{size:08x}"]

    lines: list[str] = []
    remaining = size
    current_mem = mem_addr
    current_nand = nand_offset
    max_chunk = max(erase_size // 2, 0x10000)
    while remaining:
        block_remaining = erase_size - (current_nand % erase_size)
        chunk = min(remaining, block_remaining, max_chunk)
        lines.append(f"nand write 0x{current_mem:08x} 0x{current_nand:08x} 0x{chunk:08x}")
        current_mem += chunk
        current_nand += chunk
        remaining -= chunk
    return lines


def build_flash_script(
    args: argparse.Namespace,
    geom: dict[str, int | str],
    uboot_size: int,
    kernel_size: int,
    dtb_size: int,
    initrd_size: int,
    slc_boot: bool,
    out_dir: Path,
) -> Path:
    erase = int(geom["erase"])
    write = int(geom["write"])
    pages_per_eb = erase // write
    uboot_size_hex = f"0x{uboot_size:08x}"
    uboot_write = "nand write.slc-mode" if slc_boot else "nand write"
    erase_cmd = "nand scrub.chip -y" if args.erase_mode == "scrub" else "nand erase.chip"
    markbad_lines = []
    for offset in args.markbad_offset:
        markbad_lines.extend(
            [
                f"echo marking weak NAND block bad at 0x{offset:08x}",
                f"nand markbad 0x{offset:08x}",
            ]
        )

    lines = [
        "echo PocketCHIP NAND flash: destructive erase starting",
        *markbad_lines,
        erase_cmd,
        f"nand write.raw.noverify {SPL_MEM} 0x0 {pages_per_eb:x}",
        f"nand write.raw.noverify {SPL_MEM} 0x400000 {pages_per_eb:x}",
        f"{uboot_write} {UBOOT_NAND_MEM} 0x800000 {uboot_size_hex}",
        *nand_write_payload(int(BOOT_KERNEL_MEM, 16), BOOT_KERNEL_OFF, kernel_size, erase, slc_boot),
        *nand_write_payload(int(BOOT_DTB_MEM, 16), BOOT_DTB_OFF, dtb_size, erase, slc_boot),
        *nand_write_payload(int(BOOT_INITRD_MEM, 16), BOOT_INITRD_OFF, initrd_size, erase, slc_boot),
        *nand_boot_env_lines(kernel_size, dtb_size, initrd_size, slc_boot),
        "saveenv",
        "mtdparts",
        "echo going to fastboot mode for UBI flash",
        "fastboot 0",
        "while true; do sleep 10; done",
    ]
    return mk_uboot_script(args, lines, "flash-pocketchip-nand", out_dir)


def build_bootloader_script(
    args: argparse.Namespace,
    geom: dict[str, int | str],
    uboot_size: int,
    kernel_size: int,
    dtb_size: int,
    initrd_size: int,
    slc_boot: bool,
    out_dir: Path,
) -> Path:
    erase = int(geom["erase"])
    write = int(geom["write"])
    pages_per_eb = erase // write
    uboot_size_hex = f"0x{uboot_size:08x}"
    uboot_write = "nand write.slc-mode" if slc_boot else "nand write"

    lines = [
        "echo PocketCHIP NAND boot-area refresh: erasing first 80MiB only",
        "nand erase 0x0 0x5000000",
        *nand_write_payload(int(BOOT_KERNEL_MEM, 16), BOOT_KERNEL_OFF, kernel_size, erase, slc_boot),
        *nand_write_payload(int(BOOT_DTB_MEM, 16), BOOT_DTB_OFF, dtb_size, erase, slc_boot),
        *nand_write_payload(int(BOOT_INITRD_MEM, 16), BOOT_INITRD_OFF, initrd_size, erase, slc_boot),
        f"nand write.raw.noverify {SPL_MEM} 0x0 {pages_per_eb:x}",
        f"nand write.raw.noverify {SPL_MEM} 0x400000 {pages_per_eb:x}",
        f"{uboot_write} {UBOOT_NAND_MEM} 0x800000 {uboot_size_hex}",
        *nand_boot_env_lines(kernel_size, dtb_size, initrd_size, slc_boot),
        "saveenv",
        f"echo {BOOTLOADER_MARKER}",
    ]
    return mk_uboot_script(args, lines, "refresh-pocketchip-bootloader", out_dir)


def build_rescue_boot_script(args: argparse.Namespace, out_dir: Path) -> Path:
    lines = [
        "echo Booting PocketCHIP NAND rescue installer",
        "setenv bootargs 'console=tty0 console=ttyS0,115200 rdinit=/init loglevel=7 ignore_loglevel panic=-1 pocketchip_nand_rescue=1'",
        f"fdt addr {BOOT_DTB_MEM}",
        "fdt resize 0x1000",
        "fdt set /soc/usb@1c13000 dr_mode peripheral",
        f"bootz {BOOT_KERNEL_MEM} {BOOT_INITRD_MEM} {BOOT_DTB_MEM}",
    ]
    return mk_uboot_script(args, lines, "boot-pocketchip-nand-rescue", out_dir)


def net_ifaces() -> set[str]:
    try:
        return {path.name for path in Path("/sys/class/net").iterdir()}
    except FileNotFoundError:
        return set()


def iface_address(iface: str) -> str:
    try:
        return Path("/sys/class/net", iface, "address").read_text(encoding="utf-8").strip().lower()
    except OSError:
        return ""


def pick_rescue_iface(preferred: str, before: set[str], timeout: int) -> str:
    if preferred != "auto":
        return preferred

    deadline = time.time() + timeout
    macs = {"02:00:de:ad:42:01", "02:00:de:ad:42:02"}
    while time.time() < deadline:
        current = net_ifaces()
        for iface in sorted(current - before):
            if iface != "lo":
                return iface
        for iface in sorted(current):
            if iface != "lo" and iface_address(iface) in macs:
                return iface
        time.sleep(1)
    raise RuntimeError("timed out waiting for USB gadget network interface")


def configure_rescue_iface(args: argparse.Namespace, iface: str) -> None:
    run(["ip", "link", "set", iface, "up"], check=False)
    result = run(["ip", "addr", "add", f"{args.host_ip}/24", "dev", iface], check=False, capture=True)
    if result.returncode != 0 and "File exists" not in (result.stdout or ""):
        raise RuntimeError(f"could not assign {args.host_ip}/24 to {iface}")


def send_file_to_rescue(args: argparse.Namespace, payload: Path) -> None:
    total = payload.stat().st_size
    deadline = time.time() + args.timeout
    sock = None
    while time.time() < deadline:
        try:
            sock = socket.create_connection((args.device_ip, args.port), timeout=5)
            break
        except OSError:
            time.sleep(1)
    if sock is None:
        raise RuntimeError(f"timed out connecting to rescue listener at {args.device_ip}:{args.port}")

    sent = 0
    last_report = 0
    print(f"[rescue] streaming {payload} ({total} bytes)")
    with sock:
        with payload.open("rb") as fh:
            while True:
                chunk = fh.read(1024 * 1024)
                if not chunk:
                    break
                sock.sendall(chunk)
                sent += len(chunk)
                if sent - last_report >= 32 * 1024 * 1024 or sent == total:
                    print(f"[rescue] sent {sent}/{total} bytes ({sent * 100 // total}%)")
                    last_report = sent
    print("[rescue] payload stream complete")


def rescue_install(args: argparse.Namespace) -> int:
    if not args.i_understand_this_erases_ubi:
        print("error: refusing rescue NAND install without --i-understand-this-erases-ubi", file=sys.stderr)
        return 2
    if not args.source_over_serial:
        raise RuntimeError("rescue-install currently requires --source-over-serial")

    fmt, geom = resolve_flash_geometry(args)
    args.resolved_format = fmt
    spl = require_artifact(args.images_dir / "sunxi-spl.bin")
    runtime_uboot = require_artifact(args.images_dir / "u-boot-dtb.bin")
    kernel, dtb, rescue_initrd, ubifs = rescue_artifacts(args, geom)
    if args.require_slc_mode:
        slc_mode_file = args.images_dir / "nand_slc_mode"
        slc_mode = slc_mode_file.read_text(encoding="utf-8").strip() if slc_mode_file.is_file() else ""
        if slc_mode != "1":
            raise RuntimeError(
                f"{args.images_dir} is not marked as an SLC-mode NAND image; "
                "rebuild with NAND_SLC_MODE=1"
            )

    print(f"[rescue] format={fmt}")
    print(f"[rescue] ubi_type={geom['ubi_type']}")
    print(f"[rescue] source={args.source}")
    print("[rescue] this will reformat only the UBI partition from Linux")

    before_ifaces = net_ifaces()
    with tempfile.TemporaryDirectory(prefix="pocketchip-rescue-", dir=args.nand_dir) as temp_name:
        temp = Path(temp_name)
        script = build_rescue_boot_script(args, temp)
        log_path = args.log if args.log else args.nand_dir / "rescue-install-serial.log"
        serial = SerialSession(args.serial, args.baud, log_path)
        try:
            fel_load_rescue_boot(args, spl, runtime_uboot, kernel, dtb, rescue_initrd, script)
            if not serial.wait_for_uboot_prompt(20, interrupt=True):
                raise RuntimeError("U-Boot prompt was not detected over serial")

            print(f"[serial] running source {SCRIPT_MEM}")
            serial.write(f"source {SCRIPT_MEM}\r")

            if args.source == "net":
                if not serial.wait_for(r"\[rescue\].*waiting for host stream", args.timeout):
                    raise RuntimeError("rescue initramfs did not reach the network receive step")

                iface = pick_rescue_iface(args.net_iface, before_ifaces, args.timeout)
                print(f"[rescue] host USB network interface: {iface}")
                configure_rescue_iface(args, iface)
                send_file_to_rescue(args, ubifs)
            else:
                if not serial.wait_for(r"\[rescue\].*writing USB payload", args.timeout):
                    raise RuntimeError("rescue initramfs did not start the USB payload write step")

            deadline = time.time() + args.timeout
            while time.time() < deadline:
                serial.pump(0.5)
                if (
                    "[rescue] install complete" in serial.buffer
                    or "reboot: Restarting system" in serial.buffer
                    or "Reboot failed -- System halted" in serial.buffer
                ):
                    print("[rescue] Linux-side UBI install complete")
                    return 0
            raise RuntimeError("timed out waiting for rescue install completion")
        finally:
            serial.close()


def flash_legacy(args: argparse.Namespace) -> int:
    if not args.i_understand_this_erases_nand:
        print("error: refusing to write NAND without --i-understand-this-erases-nand", file=sys.stderr)
        return 2

    fmt, geom = resolve_flash_geometry(args)
    erase_hex, write_hex, oob_hex = str(geom["ubi_type"]).split("-")
    spl = require_artifact(args.images_dir / "sunxi-spl.bin")
    runtime_uboot = require_artifact(args.images_dir / "u-boot-dtb.bin")
    nand_uboot = require_artifact(args.images_dir / f"uboot-{erase_hex}.bin")
    nand_spl = require_artifact(args.images_dir / f"spl-{erase_hex}-{write_hex}-{oob_hex}.bin")
    sparse_ubi = require_artifact(args.images_dir / f"chip-{erase_hex}-{write_hex}-{oob_hex}.ubi.sparse")
    boot_kernel, boot_dtb, boot_initrd = boot_artifacts(args, geom)
    if args.require_slc_mode:
        slc_mode_file = args.images_dir / "nand_slc_mode"
        slc_mode = slc_mode_file.read_text(encoding="utf-8").strip() if slc_mode_file.is_file() else ""
        if slc_mode != "1":
            raise RuntimeError(
                f"{args.images_dir} is not marked as an SLC-mode NAND image; "
                "rebuild with NAND_SLC_MODE=1"
            )

    print(f"[flash] format={fmt}")
    print(f"[flash] ubi_type={geom['ubi_type']}")
    if args.require_slc_mode:
        print("[flash] requiring SLC-mode NAND image metadata")
    print("[flash] this will erase the internal NAND")

    with tempfile.TemporaryDirectory(prefix="pocketchip-flash-", dir=args.nand_dir) as temp_name:
        temp = Path(temp_name)
        script = build_flash_script(
            args,
            geom,
            nand_uboot.stat().st_size,
            boot_kernel.stat().st_size,
            boot_dtb.stat().st_size,
            boot_initrd.stat().st_size,
            args.require_slc_mode,
            temp,
        )
        serial = None
        if args.source_over_serial:
            log_path = args.log if args.log else args.nand_dir / "flash-source-serial.log"
            serial = SerialSession(args.serial, args.baud, log_path)
        fel_load_flash_script(args, spl, runtime_uboot, nand_spl, nand_uboot, script, boot_kernel, boot_dtb, boot_initrd)

        if serial:
            try:
                if serial.wait_for_uboot_prompt(15, interrupt=True):
                    print(f"[serial] running source {SCRIPT_MEM}")
                    serial.write(f"source {SCRIPT_MEM}\r")
                    deadline = time.time() + args.timeout
                    while time.time() < deadline and not fastboot_visible(args):
                        serial.pump(0.5)
                else:
                    print("[serial] U-Boot prompt not detected; continuing to fastboot wait")
            finally:
                serial.close()

        print("[fastboot] waiting for U-Boot fastboot")
        print(wait_for_fastboot(args))
        run([args.fastboot, "flash", "UBI", str(sparse_ubi)])
        if not args.no_fastboot_continue:
            run([args.fastboot, "continue"], check=False)

    print("[flash] NAND flash command sequence complete")
    return 0


def flash_bootloader(args: argparse.Namespace) -> int:
    if not args.i_understand_this_erases_bootloader:
        print("error: refusing to write NAND bootloader without --i-understand-this-erases-bootloader", file=sys.stderr)
        return 2
    if not args.source_over_serial:
        raise RuntimeError("flash-bootloader currently requires --source-over-serial")

    fmt, geom = resolve_flash_geometry(args)
    erase_hex, write_hex, oob_hex = str(geom["ubi_type"]).split("-")
    spl = require_artifact(args.images_dir / "sunxi-spl.bin")
    runtime_uboot = require_artifact(args.images_dir / "u-boot-dtb.bin")
    nand_uboot = require_artifact(args.images_dir / f"uboot-{erase_hex}.bin")
    nand_spl = require_artifact(args.images_dir / f"spl-{erase_hex}-{write_hex}-{oob_hex}.bin")
    boot_kernel, boot_dtb, boot_initrd = boot_artifacts(args, geom)
    if args.require_slc_mode:
        slc_mode_file = args.images_dir / "nand_slc_mode"
        slc_mode = slc_mode_file.read_text(encoding="utf-8").strip() if slc_mode_file.is_file() else ""
        if slc_mode != "1":
            raise RuntimeError(
                f"{args.images_dir} is not marked as an SLC-mode NAND image; "
                "rebuild with NAND_SLC_MODE=1"
            )

    print(f"[bootloader] format={fmt}")
    print(f"[bootloader] ubi_type={geom['ubi_type']}")
    print("[bootloader] this will erase/rewrite only the first 80MiB boot area")

    with tempfile.TemporaryDirectory(prefix="pocketchip-bootloader-", dir=args.nand_dir) as temp_name:
        temp = Path(temp_name)
        script = build_bootloader_script(
            args,
            geom,
            nand_uboot.stat().st_size,
            boot_kernel.stat().st_size,
            boot_dtb.stat().st_size,
            boot_initrd.stat().st_size,
            args.require_slc_mode,
            temp,
        )
        log_path = args.log if args.log else args.nand_dir / "bootloader-source-serial.log"
        serial = SerialSession(args.serial, args.baud, log_path)
        try:
            fel_load_flash_script(args, spl, runtime_uboot, nand_spl, nand_uboot, script, boot_kernel, boot_dtb, boot_initrd)
            if not serial.wait_for_uboot_prompt(15, interrupt=True):
                raise RuntimeError("U-Boot prompt was not detected over serial")

            print(f"[serial] running source {SCRIPT_MEM}")
            serial.write(f"source {SCRIPT_MEM}\r")
            deadline = time.time() + args.timeout
            while time.time() < deadline:
                serial.pump(0.5)
                if BOOTLOADER_MARKER in serial.buffer:
                    print("[bootloader] NAND bootloader refresh complete")
                    return 0
            raise RuntimeError("timed out waiting for bootloader refresh to complete")
        finally:
            serial.close()


def baud_to_termios(baud: int) -> int:
    mapping = {
        9600: termios.B9600,
        19200: termios.B19200,
        38400: termios.B38400,
        57600: termios.B57600,
        115200: termios.B115200,
    }
    if baud not in mapping:
        raise RuntimeError(f"unsupported baud rate {baud}")
    return mapping[baud]


class SerialSession:
    def __init__(self, port: str, baud: int, log_path: Path | None):
        self.fd = os.open(port, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
        attrs = termios.tcgetattr(self.fd)
        attrs[0] = 0
        attrs[1] = 0
        attrs[2] = termios.CS8 | termios.CREAD | termios.CLOCAL
        attrs[3] = 0
        attrs[4] = baud_to_termios(baud)
        attrs[5] = baud_to_termios(baud)
        attrs[6][termios.VMIN] = 0
        attrs[6][termios.VTIME] = 0
        if hasattr(termios, "CRTSCTS"):
            attrs[2] &= ~termios.CRTSCTS
        termios.tcsetattr(self.fd, termios.TCSANOW, attrs)
        termios.tcflush(self.fd, termios.TCIOFLUSH)
        self.buffer = ""
        self.log = None
        if log_path:
            log_path.parent.mkdir(parents=True, exist_ok=True)
            self.log = log_path.open("w", encoding="utf-8", errors="replace")

    def close(self) -> None:
        if self.log:
            self.log.close()
        os.close(self.fd)

    def write(self, data: str) -> None:
        os.write(self.fd, data.encode())

    def pump(self, seconds: float) -> str:
        end = time.time() + seconds
        start = len(self.buffer)
        while time.time() < end:
            r, _, _ = select.select([self.fd], [], [], 0.05)
            if self.fd in r:
                data = os.read(self.fd, 4096)
                if data:
                    text = data.decode("utf-8", "replace")
                    sys.stdout.write(text)
                    sys.stdout.flush()
                    if self.log:
                        self.log.write(text)
                        self.log.flush()
                    self.buffer = (self.buffer + text)[-60000:]
        return self.buffer[start:]

    def wait_for(self, pattern: str, timeout: float) -> bool:
        deadline = time.time() + timeout
        while time.time() < deadline:
            self.pump(0.2)
            if re.search(pattern, self.buffer, re.IGNORECASE):
                return True
        return False

    def command(self, command: str, timeout: float = 10.0) -> str:
        marker = f"{SHELL_MARKER}_{int(time.time() * 1000)}"
        start = len(self.buffer)
        self.write(f"{command}; echo {marker} $?\r")
        deadline = time.time() + timeout
        while time.time() < deadline:
            self.pump(0.2)
            if marker in self.buffer[start:]:
                break
        return self.buffer[start:]

    def wait_for_uboot_prompt(self, timeout: float, interrupt: bool = False) -> bool:
        prompt = re.compile(r"(^|\r|\n)=>\s*$")
        deadline = time.time() + timeout
        last_interrupt = 0.0
        while time.time() < deadline:
            now = time.time()
            if interrupt and now - last_interrupt > 0.05:
                self.write(" \r")
                last_interrupt = now
            self.pump(0.2)
            if prompt.search(self.buffer):
                return True
        return False

    def uboot_command(self, command: str, timeout: float = 10.0) -> str:
        prompt = re.compile(r"(^|\r|\n)=>\s*$")
        start = len(self.buffer)
        self.write(command + "\r")
        deadline = time.time() + timeout
        while time.time() < deadline:
            self.pump(0.2)
            if prompt.search(self.buffer[start:]):
                break
        return self.buffer[start:]


def login_root(serial: SerialSession, password: str) -> None:
    serial.write("\r")
    serial.pump(2)
    if re.search(r"login:\s*$", serial.buffer, re.IGNORECASE):
        serial.write("root\r")
        serial.wait_for(r"password:\s*$", 10)
        serial.write(password + "\r")
        serial.pump(2)
    elif re.search(r"password:\s*$", serial.buffer, re.IGNORECASE):
        serial.write(password + "\r")
        serial.pump(2)

    out = serial.command("printf READY", timeout=6)
    if "READY" not in out:
        raise RuntimeError("could not establish a shell over serial")


def verify(args: argparse.Namespace) -> int:
    log_path = args.log if args.log else args.nand_dir / "nand-verify-serial.log"
    serial = SerialSession(args.serial, args.baud, log_path)
    try:
        login_root(serial, args.root_password)
        commands = [
            "uname -a",
            "cat /etc/os-release | sed -n '1,6p'",
            "cat /proc/cmdline",
            "findmnt /",
            "cat /proc/mtd",
            "mount | grep -E 'ubi|ubifs' || true",
            "lsmod | grep -E 'sunxi_nand|ubi|ubifs|ofpart' || true",
            "systemctl is-active graphical.target multi-user.target || true",
            "pgrep -a i3 || true",
        ]
        combined = ""
        for command in commands:
            print(f"\n[verify] {command}")
            combined += serial.command(command, timeout=12)
        ok = "root=ubi0:rootfs" in combined and "ubifs" in combined and "UBI" in combined
        print(f"\n[verify] NAND rootfs check: {'PASS' if ok else 'CHECK OUTPUT'}")
        return 0 if ok else 1
    finally:
        serial.close()


def main() -> int:
    repo_root = Path(__file__).resolve().parents[1]
    nand_dir = repo_root / "build/nand"
    parser = argparse.ArgumentParser(description="PocketCHIP FEL/NAND probe and flash helper.")
    parser.add_argument("--repo-root", type=Path, default=repo_root)
    parser.add_argument("--nand-dir", type=Path, default=nand_dir)
    parser.add_argument("--images-dir", type=Path, default=nand_dir / "images")
    parser.add_argument("--fel", default=os.environ.get("SUNXI_FEL", "sunxi-fel"))
    parser.add_argument("--fastboot", default=os.environ.get("FASTBOOT", "fastboot"))
    parser.add_argument("--mkimage", default=os.environ.get("MKIMAGE", "mkimage"))
    parser.add_argument("--serial", default=os.environ.get("SERIAL_PORT", "/dev/ttyUSB0"))
    parser.add_argument("--baud", type=int, default=int(os.environ.get("SERIAL_BAUD", "115200")))
    parser.add_argument("--timeout", type=int, default=int(os.environ.get("FEL_TIMEOUT", "60")))
    parser.add_argument("--log", type=Path, default=None)

    sub = parser.add_subparsers(dest="command", required=True)
    legacy_probe = sub.add_parser("probe-legacy", help="read NAND geometry with legacy CHIP U-Boot")
    legacy_probe.add_argument("--uboot-dir", type=Path, default=repo_root / "build/u-boot-legacy")

    mainline_probe = sub.add_parser("probe-mainline", help="read NAND geometry with mainline NAND U-Boot")
    mainline_probe.add_argument("--uboot-dir", type=Path, default=repo_root / "build/u-boot-mainline-nand")

    legacy_serial_probe = sub.add_parser(
        "probe-legacy-serial",
        help="read NAND geometry from legacy CHIP U-Boot over serial",
    )
    legacy_serial_probe.add_argument("--uboot-dir", type=Path, default=repo_root / "build/u-boot-legacy")

    mainline_serial_probe = sub.add_parser(
        "probe-mainline-serial",
        help="read NAND geometry from mainline NAND U-Boot over serial",
    )
    mainline_serial_probe.add_argument("--uboot-dir", type=Path, default=repo_root / "build/u-boot-mainline-nand")

    flash = sub.add_parser("flash-legacy", help="destructively flash generated NAND images")
    flash.add_argument("--format", default="auto", help="auto, ubi_type, or one of: " + ", ".join(GEOMETRIES))
    flash.add_argument("--erase-mode", choices=["erase", "scrub"], default="erase")
    flash.add_argument(
        "--markbad-offset",
        action="append",
        type=parse_int,
        default=[],
        help="absolute NAND offset to mark bad before erase/write; may be passed more than once",
    )
    flash.add_argument("--i-understand-this-erases-nand", action="store_true")
    flash.add_argument("--no-fastboot-continue", action="store_true")
    flash.add_argument("--require-slc-mode", action="store_true")
    flash.add_argument(
        "--source-over-serial",
        action="store_true",
        help="interrupt U-Boot over UART and run the FEL-loaded flash script explicitly",
    )

    bootloader = sub.add_parser("flash-bootloader", help="refresh only SPL/U-Boot/env NAND boot area")
    bootloader.add_argument("--format", default="auto", help="auto, ubi_type, or one of: " + ", ".join(GEOMETRIES))
    bootloader.add_argument("--i-understand-this-erases-bootloader", action="store_true")
    bootloader.add_argument("--require-slc-mode", action="store_true")
    bootloader.add_argument(
        "--source-over-serial",
        action="store_true",
        help="interrupt U-Boot over UART and run the FEL-loaded bootloader script explicitly",
    )

    rescue = sub.add_parser(
        "rescue-install",
        help="FEL-boot Linux rescue initramfs and stream UBIFS into UBI from Linux",
    )
    rescue.add_argument("--format", default="auto", help="auto, ubi_type, or one of: " + ", ".join(GEOMETRIES))
    rescue.add_argument("--ubifs", type=Path, default=None, help="UBIFS payload to stream; defaults to build work dir")
    rescue.add_argument("--source", choices=["net", "usb"], default=os.environ.get("NAND_RESCUE_SOURCE", "net"))
    rescue.add_argument("--i-understand-this-erases-ubi", action="store_true")
    rescue.add_argument("--require-slc-mode", action="store_true")
    rescue.add_argument(
        "--source-over-serial",
        action="store_true",
        help="interrupt U-Boot over UART and run the FEL-loaded rescue boot script explicitly",
    )
    rescue.add_argument("--net-iface", default=os.environ.get("NAND_RESCUE_NET_IFACE", "auto"))
    rescue.add_argument("--host-ip", default=os.environ.get("NAND_RESCUE_HOST_IP", "172.16.42.1"))
    rescue.add_argument("--device-ip", default=os.environ.get("NAND_RESCUE_DEVICE_IP", "172.16.42.2"))
    rescue.add_argument("--port", type=int, default=int(os.environ.get("NAND_RESCUE_PORT", "4242")))

    verify_parser = sub.add_parser("verify", help="verify a NAND boot through the serial console")
    verify_parser.add_argument("--root-password", default=os.environ.get("POCKETCHIP_ROOT_PASSWORD"))

    args = parser.parse_args()
    if args.command == "verify" and not args.root_password:
        parser.error("verify requires --root-password or POCKETCHIP_ROOT_PASSWORD")
    args.nand_dir.mkdir(parents=True, exist_ok=True)

    try:
        if args.command == "probe-legacy":
            return probe(args, "legacy", args.uboot_dir)
        if args.command == "probe-mainline":
            return probe(args, "mainline", args.uboot_dir)
        if args.command == "probe-legacy-serial":
            return probe_serial(args, "legacy", args.uboot_dir)
        if args.command == "probe-mainline-serial":
            return probe_serial(args, "mainline", args.uboot_dir)
        if args.command == "flash-legacy":
            return flash_legacy(args)
        if args.command == "flash-bootloader":
            return flash_bootloader(args)
        if args.command == "rescue-install":
            return rescue_install(args)
        if args.command == "verify":
            return verify(args)
    except RuntimeError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
