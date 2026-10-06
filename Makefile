# x-os -- the Linux kernel, x and its languages, as a container and as a
# bootable image.
#
#   make fetch            acquire the sources pins.xon names
#   make container        build the container image for ARCH
#   make boot             build the kernel and the initramfs for ARCH
#   make iso              build the bootable ISO image for ARCH
#   make test             both, and both tests
#
# ARCH is amd64 or arm64 and defaults to the host's.
# CONTAINER is the container command, docker unless it is set: podman runs
# the same builds and tests.

ARCH ?= $(if $(filter arm64 aarch64,$(shell uname -m)),arm64,amd64)
CONTAINER ?= docker
export CONTAINER
IMAGE ?= x-os
PLATFORM = linux/$(ARCH)
BOOT_DIR = build/boot-$(ARCH)
ISO_DIR = build/iso-$(ARCH)
ISO = $(ISO_DIR)/x-os-$(ARCH).iso

.PHONY: fetch
fetch: ## Acquire the pinned sources into build/src
	sh tools/fetch.sh

.PHONY: container
container: fetch ## Build the container image
	$(CONTAINER) build --platform $(PLATFORM) --target root -t $(IMAGE):$(ARCH) .

.PHONY: boot
boot: fetch ## Build the kernel and the initramfs into build/boot-ARCH
	$(CONTAINER) build --platform $(PLATFORM) --target boot --output $(BOOT_DIR) .

.PHONY: iso
iso: fetch ## Build the bootable ISO image into build/iso-ARCH
	$(CONTAINER) build --platform $(PLATFORM) --target iso --output $(ISO_DIR) .

.PHONY: test-container
test-container: container ## Run the shell in the container
	sh tools/container-test.sh $(IMAGE):$(ARCH) $(PLATFORM)
	expect tools/terminal-test.exp $(IMAGE):$(ARCH) $(PLATFORM)

.PHONY: test-boot
test-boot: boot ## Boot the image under QEMU
	sh tools/boot-test.sh $(BOOT_DIR) $(ARCH)

# A PC starts the image from firmware of either kind, so it is tested by both.
.PHONY: test-iso
test-iso: iso ## Boot the ISO image under QEMU
	sh tools/boot-test.sh $(ISO) $(ARCH) uefi
ifeq ($(ARCH),amd64)
	sh tools/boot-test.sh $(ISO) $(ARCH) bios
endif

.PHONY: test
test: test-container test-boot test-iso ## Every test

.PHONY: clean
clean: ## Remove what was fetched and built
	rm -rf build

.PHONY: help
help: ## Show targets
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z0-9_-]+:.*?## / {printf "  %-16s %s\n", $$1, $$2}' $(MAKEFILE_LIST)
