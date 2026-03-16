OS_NAME := thymos
ARCH ?= x86_64

# Directories
INCLUDE_DIR := include
LIMINE_DIR := $(INCLUDE_DIR)/limine
BUILD_DIR := zig-out
ISO_DIR := $(BUILD_DIR)/$(ARCH)/isodir

# Files
KERNEL := $(BUILD_DIR)/$(ARCH)/$(OS_NAME)
ISO := $(BUILD_DIR)/$(ARCH)/$(OS_NAME).iso

# Toolchain
ZIG_FLAGS := -Darch=$(ARCH) -Doptimize=Debug --prefix-exe-dir $(ARCH)
QEMU_FLAGS := --enable-kvm -cdrom $(ISO)

# Default target
all: kernel

# Fetch all required libraries/dependencies
.PHONY: fetchDeps
fetchDeps:
	mkdir -p $(INCLUDE_DIR)

	@echo "[DEPS] Fetching Limine"
	rm -rf $(LIMINE_DIR)
	git clone https://codeberg.org/Limine/Limine.git --branch=v10.x-binary --depth=1 $(LIMINE_DIR)
	rm -rf $(LIMINE_DIR)/.git
	@echo "[DEPS] Building Limine binaries"
	make -C $(LIMINE_DIR)
	@echo "[DEPS] Fetching Limine protocol header"
	curl https://codeberg.org/Limine/limine-protocol/raw/branch/trunk/include/limine.h -o $(LIMINE_DIR)/limine.h

	@echo "[DEPS] Fetching SSFN (Text renderer)"
	curl https://gitlab.com/bztsrc/scalable-font2/-/raw/master/ssfn.h?ref_type=heads -o $(INCLUDE_DIR)/ssfn.h

	@echo "[DEPS] Fetching Tiny Printf implementation"
	mkdir -p $(INCLUDE_DIR)/printf
	curl https://raw.githubusercontent.com/eyalroz/printf/refs/heads/master/src/printf/printf.h -o $(INCLUDE_DIR)/printf/printf.h
	curl https://raw.githubusercontent.com/eyalroz/printf/refs/heads/master/src/printf/printf.c -o $(INCLUDE_DIR)/printf/printf.c

# Run/Emulate the OS in QEMU
.PHONY: run
run: iso
	qemu-system-$(ARCH) $(QEMU_FLAGS)

# Build the kernel
.PHONY: kernel
kernel:
	zig build $(ZIG_FLAGS)

# Create a bootable ISO
.PHONY: iso
iso: limine.conf kernel
	mkdir -p $(ISO_DIR)/boot/limine $(ISO_DIR)/EFI/BOOT
	cp $(KERNEL) $(ISO_DIR)/boot/
	cp limine.conf $(ISO_DIR)/boot/limine/

ifeq ($(ARCH),x86_64)
	cp $(addprefix $(LIMINE_DIR)/limine-, bios.sys bios-cd.bin uefi-cd.bin) $(ISO_DIR)/boot/limine/
	cp $(addprefix $(LIMINE_DIR)/BOOT, IA32.EFI X64.EFI) $(ISO_DIR)/EFI/BOOT/
	xorriso -as mkisofs -R -r -J -b boot/limine/limine-bios-cd.bin \
		-no-emul-boot -boot-load-size 4 -boot-info-table -hfsplus \
		-apm-block-size 2048 --efi-boot boot/limine/limine-uefi-cd.bin \
		-efi-boot-part --efi-boot-image --protective-msdos-label \
		$(ISO_DIR) -o $(ISO)
	./$(LIMINE_DIR)/limine bios-install $(ISO)
endif
ifeq ($(ARCH),riscv64)
	@cp -v $(LIMINE_DIR)/limine-uefi-cd.bin $(ISO_DIR)/boot/limine/
	@cp -v $(LIMINE_DIR)/BOOTRISCV64.EFI $(ISO_DIR)/EFI/BOOT/
	@xorriso -as mkisofs -R -r -J \
		-hfsplus -apm-block-size 2048 \
		--efi-boot boot/limine/limine-uefi-cd.bin \
		-efi-boot-part --efi-boot-image --protective-msdos-label \
		$(ISO_DIR) -o $(ISO)
endif
ifeq ($(ARCH),aarch64)
	@cp -v $(LIMINE_DIR)/limine-uefi-cd.bin $(ISO_DIR)/boot/limine/
	@cp -v $(LIMINE_DIR)/BOOTAA64.EFI $(ISO_DIR)/EFI/BOOT/
	@xorriso -as mkisofs -R -r -J \
		-hfsplus -apm-block-size 2048 \
		--efi-boot boot/limine/limine-uefi-cd.bin \
		-efi-boot-part --efi-boot-image --protective-msdos-label \
		$(ISO_DIR) -o $(ISO)
endif

# Clean everything
.PHONY: cleanDeps cleanCache clean
cleanDeps:
	# Delete every single dependency/library EXCEPT `printf/printf_config.h` since that file is created by us
	# `printf.c` imports `printf_config.h` from the current directory so that's why we can't really move it
	rm -rf $(LIMINE_DIR) $(INCLUDE_DIR)/ssfn.h $(INCLUDE_DIR)/printf/printf.h $(INCLUDE_DIR)/printf/printf.c
cleanCache:
	rm -rf .zig-cache
clean:
	rm -rf $(BUILD_DIR)
