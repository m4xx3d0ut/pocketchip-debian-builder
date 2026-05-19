# Review: CHIP_FLASH_METHOD_2025.md

`CHIP_FLASH_METHOD_2025.md` is useful as a recovery note for archived CHIP OS
images. It should not be treated as the mainline Debian build path.

Useful parts:

- It documents a working host-side dependency set for `CHIP-tools`.
- It captures the FEL-to-fastboot flow and VirtualBox USB handoff issues.
- It preserves a practical path back to a known-good legacy image.

Issues to keep in mind:

- The flow is tied to archived NTC/CHIP OS image layouts.
- It starts from the old `setup_ubuntu1404.sh` SDK script.
- It edits legacy `CHIP-tools` scripts by hand to account for newer host tools.
- It contains small typos in package names and VID/PID references.
- It does not build a mainline kernel, a modern rootfs, or a reproducible image.

Recommended use:

- Keep it as `legacy recovery`.
- Use `../upstreams/CHIP-tools` for controlled NAND/recovery experiments.
- Keep mainline Debian development in this repo's scripts and docs.

