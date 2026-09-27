# x-os -- the Linux kernel, x and its languages, as a container and as a
# bootable image.
#
#   make fetch            acquire the sources pins.xon names
#   make container        build the container image for ARCH
#   make boot             build the kernel and the initramfs for ARCH
#   make test             both, and both tests
#
# ARCH is amd64 or arm64 and defaults to the host's.

ARCH ?= $(shell case "$$(uname -m)" in arm64|aarch64) echo arm64 ;; *) echo amd64 ;; esac)
IMAGE ?= x-os
PLATFORM = linux/$(ARCH)
BOOT_DIR = build/boot-$(ARCH)

.PHONY: fetch
fetch: ## Acquire the pinned sources into build/src
	sh tools/fetch.sh

.PHONY: container
container: fetch ## Build the container image
	docker build --platform $(PLATFORM) --target root -t $(IMAGE):$(ARCH) .

.PHONY: boot
boot: fetch ## Build the kernel and the initramfs into build/boot-ARCH
	docker build --platform $(PLATFORM) --target boot --output $(BOOT_DIR) .

.PHONY: test-container
test-container: container ## Run the shell in the container
	sh tools/container-test.sh $(IMAGE):$(ARCH) $(PLATFORM)

.PHONY: test-boot
test-boot: boot ## Boot the image under QEMU
	sh tools/boot-test.sh $(BOOT_DIR) $(ARCH)

.PHONY: test
test: test-container test-boot ## Both tests

.PHONY: clean
clean: ## Remove what was fetched and built
	rm -rf build

.PHONY: help
help: ## Show targets
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z0-9_-]+:.*?## / {printf "  %-16s %s\n", $$1, $$2}' $(MAKEFILE_LIST)
