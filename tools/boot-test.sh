#!/bin/sh
# boot-test.sh -- boot the image under QEMU and hold a conversation with the
# shell over the serial console.
#
#   sh tools/boot-test.sh DIR ARCH              the kernel and the initramfs
#   sh tools/boot-test.sh FILE.iso ARCH [bios|uefi]   the ISO image
#
# DIR holds vmlinuz and initramfs.cpio.gz; ARCH is amd64 or arm64.  An ISO
# image is started by firmware of the kind named, UEFI when none is: set
# BOOT_FIRMWARE to the firmware's file when it is not where this looks.  Each
# step waits for what the step before it should have printed, so the test
# keeps time with the guest, whatever the host's speed.  It ends with
# poweroff: a guest that powers down ends QEMU, and one that does not is a
# failure.
set -e

from="$1"
arch="$2"
firmware="${3:-uefi}"
if [ -z "$from" ] || [ -z "$arch" ]; then
	echo "usage: boot-test.sh DIR|FILE.iso ARCH [bios|uefi]" >&2
	exit 2
fi
if [ -d "$from" ]; then
	iso=
	if [ ! -f "$from/vmlinuz" ] || [ ! -f "$from/initramfs.cpio.gz" ]; then
		echo "boot-test: no vmlinuz and initramfs.cpio.gz in $from" >&2
		exit 2
	fi
elif [ -f "$from" ]; then
	iso="$from"
else
	echo "boot-test: no $from" >&2
	exit 2
fi

MEM="${BOOT_MEM:-4096}"
WAIT="${BOOT_WAIT:-300}"
host=$(uname -m)

case "$arch" in
	amd64)
		qemu=qemu-system-x86_64
		machine=""
		console=ttyS0
		firmware_names="edk2-x86_64-code.fd OVMF.fd OVMF_CODE_4M.fd OVMF_CODE.fd"
		cpu=""
		case "$host" in
			x86_64 | amd64)
				native=1
				;;
			*)
				native=
				;;
		esac
		;;
	arm64)
		qemu=qemu-system-aarch64
		machine="-machine virt"
		console=ttyAMA0
		firmware_names="edk2-aarch64-code.fd QEMU_EFI.fd AAVMF_CODE.fd"
		cpu="-cpu cortex-a72"
		case "$host" in
			arm64 | aarch64)
				native=1
				;;
			*)
				native=
				;;
		esac
		;;
	*)
		echo "boot-test: unknown arch $arch" >&2
		exit 2
		;;
esac

# The host's own virtualization when the guest is the host's architecture and
# the host offers it; emulation otherwise.
accel="-accel tcg"
if [ -n "$native" ]; then
	if [ "$(uname -s)" = Darwin ]; then
		accel="-accel hvf"
		cpu="-cpu host"
	elif [ -w /dev/kvm ]; then
		accel="-accel kvm"
		cpu="-cpu host"
	fi
fi

# The firmware's file, by the names it goes by, where QEMU's packages put it.
find_firmware() {
	if [ -n "${BOOT_FIRMWARE:-}" ]; then
		printf '%s\n' "$BOOT_FIRMWARE"
		return
	fi
	for name in $firmware_names; do
		for place in /opt/homebrew/share/qemu /usr/local/share/qemu \
			/usr/share/qemu /usr/share/ovmf /usr/share/OVMF \
			/usr/share/qemu-efi-aarch64 /usr/share/AAVMF; do
			if [ -f "$place/$name" ]; then
				printf '%s\n' "$place/$name"
				return
			fi
		done
	done
}

# What QEMU starts from.  An ISO image is a disc on a SCSI bus, which the
# firmware of both kinds and both machines can read.
if [ -n "$iso" ]; then
	start="-drive file=$iso,format=raw,if=none,id=disc,media=cdrom,readonly=on"
	start="$start -device virtio-scsi-pci -device scsi-cd,drive=disc,bootindex=0"
	case "$firmware" in
		uefi)
			file=$(find_firmware)
			if [ -z "$file" ]; then
				echo "boot-test: no UEFI firmware for $arch; set BOOT_FIRMWARE" >&2
				exit 2
			fi
			start="$start -bios $file"
			;;
		bios)
			if [ "$arch" != amd64 ]; then
				echo "boot-test: $arch has no BIOS" >&2
				exit 2
			fi
			;;
		*)
			echo "boot-test: unknown firmware $firmware" >&2
			exit 2
			;;
	esac
	what="$arch from the ISO image by $firmware"
else
	what="$arch"
fi

work=$(mktemp -d "${TMPDIR:-/tmp}/x-os-boot.XXXXXX")
log="$work/console.log"
mkfifo "$work/in"
trap 'kill $pid 2>/dev/null || true; rm -rf "$work"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

if [ -n "$iso" ]; then
	# shellcheck disable=SC2086
	$qemu $machine $accel $cpu -m "$MEM" -nographic -no-reboot $start \
		< "$work/in" > "$log" 2>&1 &
else
	# shellcheck disable=SC2086
	$qemu $machine $accel $cpu -m "$MEM" -nographic -no-reboot \
		-kernel "$from/vmlinuz" -initrd "$from/initramfs.cpio.gz" \
		-append "console=$console panic=-1 quiet" \
		< "$work/in" > "$log" 2>&1 &
fi
pid=$!
exec 3> "$work/in"

# The console so far, without terminal escapes or carriage returns.
console_text() {
	sed 's/\x1b\[[0-9;?]*[A-Za-z]//g' "$log" | tr -d '\r'
}

# Report a failure, with the end of the console, and exit.
fail() {
	echo "boot-test: $*" >&2
	echo "--- console" >&2
	console_text | grep -v '^[[:space:]]*$' | tail -40 >&2
	exit 1
}

# Wait for a line matching a pattern to appear, a number of times:
# await_console PATTERN [COUNT]
await_console() {
	waited=0
	while [ "$(console_text | grep -c -e "$1" || true)" -lt "${2:-1}" ]; do
		if ! kill -0 "$pid" 2>/dev/null; then
			fail "QEMU ended while waiting for: $1"
		fi
		waited=$((waited + 1))
		if [ "$waited" -gt "$WAIT" ]; then
			fail "no '$1' after ${WAIT}s"
		fi
		sleep 1
	done
}

# Type a line at the guest's console.
type_line() {
	printf '%s\n' "$1" >&3
}

# The menu's second entry puts the shell on the serial line: down, then enter.
if [ -n "$iso" ]; then
	await_console 'on the serial console'
	printf '\016\r' >&3
fi

await_console 'exit or ctrl-d to leave'
type_line 'echo pid-is-$$'
await_console '^pid-is-[0-9]'
type_line 'uname -m'
await_console '^\(x86_64\|aarch64\)$'
type_line 'cat /proc/version'
await_console '^Linux version'
type_line 'exit'
await_console 'exit or ctrl-d to leave' 2
type_line 'echo second-shell'
await_console '^second-shell$'
type_line 'poweroff'
await_console 'reboot: Power down'

waited=0
while kill -0 "$pid" 2>/dev/null; do
	waited=$((waited + 1))
	if [ "$waited" -gt 30 ]; then
		fail "the guest powered down and QEMU did not end"
	fi
	sleep 1
done

if console_text | grep -q 'Kernel panic'; then
	fail "the kernel panicked"
fi
echo "boot-test: $what booted, ran a shell twice and powered down"
