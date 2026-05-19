SHELL := /usr/bin/env bash

.PHONY: check upstreams dtbo rootfs image uboot verify-uboot fel-boot fel-verify

check:
	./scripts/check-host.sh

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
