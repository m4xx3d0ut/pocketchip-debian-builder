SHELL := /usr/bin/env bash

.PHONY: check publish-check upstreams dtbo rootfs image uboot verify-uboot fel-boot fel-verify
.PHONY: sunxi-tools-misc chip-mtd-utils nand-preflight uboot-legacy uboot-legacy-mlc-pc uboot-legacy-mlc-pc-slc uboot-nand nand-image nand-image-mlc-pc nand-image-mlc-pc-slc nand-rescue-initramfs-slc nand-rescue-initramfs-usb-slc nand-rescue-usb-payload-slc
.PHONY: nand-probe-legacy nand-probe-legacy-serial nand-probe-legacy-mlc-pc nand-probe-mainline nand-flash-legacy nand-flash-legacy-slc nand-flash-bootloader-slc nand-rescue-install-slc nand-rescue-install-usb-slc nand-verify

check:
	./scripts/check-host.sh

publish-check:
	./scripts/publish-check.sh

upstreams:
	./scripts/fetch-upstreams.sh

dtbo:
	./scripts/build-pocketchip-dtbo.sh

rootfs:
	sudo ./scripts/build-rootfs.sh

image:
	sudo ./scripts/build-usb-image.sh

uboot:
	./scripts/build-mainline-uboot.sh

verify-uboot:
	./scripts/verify-uboot-config.sh build/u-boot-mainline/.config build/u-boot-mainline/u-boot-sunxi-with-spl.bin

fel-boot:
	sudo ./scripts/fel-boot.sh

fel-verify:
	sudo ./scripts/fel-usb-boot-verify.py

sunxi-tools-misc:
	./scripts/build-sunxi-tools-misc.sh

chip-mtd-utils:
	./scripts/build-chip-mtd-utils.sh

nand-preflight:
	./scripts/nand-preflight.sh

uboot-legacy:
	./scripts/build-legacy-uboot.sh

uboot-legacy-mlc-pc:
	LEGACY_UBOOT_REF=origin/production-mlc-pc LEGACY_UBOOT_BUILD_DIR=build/u-boot-legacy-mlc-pc ./scripts/build-legacy-uboot.sh

uboot-legacy-mlc-pc-slc:
	LEGACY_UBOOT_REF=origin/production-mlc-pc \
	LEGACY_UBOOT_BUILD_DIR=build/u-boot-legacy-mlc-pc-slc \
	LEGACY_UBOOT_WORKTREE_DIR=build/u-boot-legacy-mlc-pc-slc-src \
	LEGACY_UBOOT_PATCHES="patches/chip-u-boot/pocketchip-cortex-a8-spectre-v2.patch patches/chip-u-boot/pocketchip-slc-mode.patch patches/chip-u-boot/pocketchip-spl-toshiba-mlc.patch patches/chip-u-boot/pocketchip-spl-toshiba-slc-uboot.patch patches/chip-u-boot/pocketchip-spl-nand-trace.patch" \
	./scripts/build-legacy-uboot.sh

uboot-nand:
	./scripts/build-mainline-nand-uboot.sh

nand-image:
	sudo ./scripts/build-nand-image.sh

nand-image-mlc-pc:
	sudo env NAND_UBOOT_DIR=$(CURDIR)/build/u-boot-legacy-mlc-pc NAND_FORMATS=toshiba-4g-mlc ./scripts/build-nand-image.sh

nand-image-mlc-pc-slc:
	sudo env NAND_UBOOT_DIR=$(CURDIR)/build/u-boot-legacy-mlc-pc-slc \
	  NAND_FORMATS=toshiba-4g-mlc \
	  NAND_SLC_MODE=1 \
	  NAND_BUILD_DIR=$(CURDIR)/build/nand-slc \
	  NAND_IMAGE_DIR=$(CURDIR)/build/nand-slc/images \
	  ./scripts/build-nand-image.sh

nand-rescue-initramfs-slc:
	sudo env NAND_BUILD_DIR=$(CURDIR)/build/nand-slc \
	  NAND_IMAGE_DIR=$(CURDIR)/build/nand-slc/images \
	  ./scripts/build-nand-rescue-initramfs.sh

nand-rescue-initramfs-usb-slc:
	sudo env NAND_BUILD_DIR=$(CURDIR)/build/nand-slc \
	  NAND_IMAGE_DIR=$(CURDIR)/build/nand-slc/images \
	  NAND_RESCUE_SOURCE=usb \
	  ./scripts/build-nand-rescue-initramfs.sh

nand-rescue-usb-payload-slc:
	@test -n "$$USB_MOUNT" || { \
	  printf 'Set USB_MOUNT=/path/to/mounted/usb.\\n' >&2; \
	  exit 2; \
	}
	./scripts/prepare-nand-rescue-usb.sh "$$USB_MOUNT"

nand-probe-legacy:
	sudo ./scripts/fel-nand.py probe-legacy

nand-probe-legacy-serial:
	sudo ./scripts/fel-nand.py probe-legacy-serial

nand-probe-legacy-mlc-pc:
	sudo ./scripts/fel-nand.py probe-legacy-serial --uboot-dir build/u-boot-legacy-mlc-pc

nand-probe-mainline:
	sudo ./scripts/fel-nand.py probe-mainline

nand-flash-legacy:
	@test "$$CONFIRM_NAND_WRITE" = YES || { \
	  printf 'Refusing NAND write. Re-run with CONFIRM_NAND_WRITE=YES.\\n' >&2; \
	  exit 2; \
	}
	sudo ./scripts/fel-nand.py flash-legacy --i-understand-this-erases-nand

nand-flash-legacy-slc:
	@test "$$CONFIRM_NAND_WRITE" = YES || { \
	  printf 'Refusing NAND write. Re-run with CONFIRM_NAND_WRITE=YES.\\n' >&2; \
	  exit 2; \
	}
	sudo ./scripts/fel-nand.py \
	  --nand-dir build/nand-slc \
	  --images-dir build/nand-slc/images \
	  --timeout 240 \
	  flash-legacy \
	  --format toshiba-4g-mlc \
	  --require-slc-mode \
	  --source-over-serial \
	  --i-understand-this-erases-nand

nand-flash-bootloader-slc:
	@test "$$CONFIRM_NAND_WRITE" = YES || { \
	  printf 'Refusing NAND bootloader write. Re-run with CONFIRM_NAND_WRITE=YES.\\n' >&2; \
	  exit 2; \
	}
	sudo ./scripts/fel-nand.py \
	  --nand-dir build/nand-slc \
	  --images-dir build/nand-slc/images \
	  --timeout 120 \
	  flash-bootloader \
	  --format toshiba-4g-mlc \
	  --require-slc-mode \
	  --source-over-serial \
	  --i-understand-this-erases-bootloader

nand-rescue-install-slc:
	@test "$$CONFIRM_NAND_WRITE" = YES || { \
	  printf 'Refusing Linux-side UBI rewrite. Re-run with CONFIRM_NAND_WRITE=YES.\\n' >&2; \
	  exit 2; \
	}
	sudo ./scripts/fel-nand.py \
	  --nand-dir build/nand-slc \
	  --images-dir build/nand-slc/images \
	  --timeout 300 \
	  rescue-install \
	  --format toshiba-4g-mlc \
	  --require-slc-mode \
	  --source-over-serial \
	  --i-understand-this-erases-ubi

nand-rescue-install-usb-slc:
	@test "$$CONFIRM_NAND_WRITE" = YES || { \
	  printf 'Refusing Linux-side UBI rewrite. Re-run with CONFIRM_NAND_WRITE=YES.\\n' >&2; \
	  exit 2; \
	}
	sudo ./scripts/fel-nand.py \
	  --nand-dir build/nand-slc \
	  --images-dir build/nand-slc/images \
	  --timeout 600 \
	  rescue-install \
	  --format toshiba-4g-mlc \
	  --require-slc-mode \
	  --source usb \
	  --source-over-serial \
	  --i-understand-this-erases-ubi

nand-verify:
	@test -n "$$POCKETCHIP_ROOT_PASSWORD" || { \
	  printf 'Set POCKETCHIP_ROOT_PASSWORD or run scripts/fel-nand.py verify --root-password ...\\n' >&2; \
	  exit 2; \
	}
	sudo ./scripts/fel-nand.py verify
