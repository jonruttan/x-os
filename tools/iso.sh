#!/bin/sh
# iso.sh -- write the bootable ISO image from a kernel and an initramfs.
#
#   sh iso.sh BOOT OUT
#
# BOOT holds vmlinuz and initramfs.cpio.gz; OUT receives x-os-ARCH.iso, ARCH
# being the machine's.  It runs in the builder, where GRUB's tools are.
#
# The menu has two entries.  The shell is on the last console the kernel is
# given, so the first entry ends with the screen and the second with the
# serial line.
set -e

boot="$1"
out="$2"

# Report an error and exit with a status: fail STATUS MESSAGE
fail() {
	status="$1"
	shift
	echo "iso: $*" >&2
	exit "$status"
}

if [ -z "$boot" ] || [ -z "$out" ]; then
	fail 2 "usage: iso.sh BOOT OUT"
fi
if [ ! -f "$boot/vmlinuz" ] || [ ! -f "$boot/initramfs.cpio.gz" ]; then
	fail 1 "no vmlinuz and initramfs.cpio.gz in $boot"
fi

# The architecture's name in an image's, and its serial console.  GRUB
# reaches the serial line itself only where the firmware does not lend it
# one: a PC's BIOS.
case "$(uname -m)" in
	x86_64)
		arch=amd64
		serial=ttyS0
		grub_serial=1
		;;
	aarch64)
		arch=arm64
		serial=ttyAMA0
		grub_serial=
		;;
	*)
		fail 1 "no ISO image for $(uname -m)"
		;;
esac

# The menu: write_menu FILE
write_menu() {
	{
		if [ -n "$grub_serial" ]; then
			printf '%s\n' \
				'serial --unit=0 --speed=115200' \
				'terminal_input console serial' \
				'terminal_output console serial'
		fi
		printf '%s\n' \
			'set timeout=5' \
			'set default=0' \
			'' \
			'menuentry "x-os" {' \
			"	linux /boot/vmlinuz console=$serial console=tty0 quiet" \
			'	initrd /boot/initramfs.cpio.gz' \
			'}' \
			'' \
			'menuentry "x-os, on the serial console" {' \
			"	linux /boot/vmlinuz console=tty0 console=$serial panic=-1 quiet" \
			'	initrd /boot/initramfs.cpio.gz' \
			'}'
	} > "$1"
}

tree=$(mktemp -d)
mkdir -p "$tree/boot/grub" "$out"
cp "$boot/vmlinuz" "$boot/initramfs.cpio.gz" "$tree/boot/"
write_menu "$tree/boot/grub/grub.cfg"

grub-mkrescue -o "$out/x-os-$arch.iso" "$tree"
rm -rf "$tree"
if [ ! -s "$out/x-os-$arch.iso" ]; then
	fail 1 "no image written"
fi
echo "iso: $out/x-os-$arch.iso"
