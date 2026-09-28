#!/bin/sh
# boot-test.sh -- boot the kernel and the initramfs under QEMU and hold a
# conversation with the shell over the serial console.
#
#   sh tools/boot-test.sh DIR ARCH
#
# DIR holds vmlinuz and initramfs.cpio.gz; ARCH is amd64 or arm64.  Each step
# waits for what the step before it should have printed, so the test keeps
# time with the guest, whatever the host's speed.  It ends with poweroff: a
# guest that powers down ends QEMU, and one that does not is a failure.
set -e

dir="$1"
arch="$2"
if [ ! -f "$dir/vmlinuz" ] || [ ! -f "$dir/initramfs.cpio.gz" ] || [ -z "$arch" ]; then
	echo "usage: boot-test.sh DIR ARCH" >&2
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

work=$(mktemp -d "${TMPDIR:-/tmp}/x-os-boot.XXXXXX")
log="$work/console.log"
mkfifo "$work/in"
trap 'kill $pid 2>/dev/null || true; rm -rf "$work"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# shellcheck disable=SC2086
$qemu $machine $accel $cpu -m "$MEM" -nographic -no-reboot \
	-kernel "$dir/vmlinuz" -initrd "$dir/initramfs.cpio.gz" \
	-append "console=$console panic=-1 quiet" \
	< "$work/in" > "$log" 2>&1 &
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
echo "boot-test: $arch booted, ran a shell twice and powered down"
