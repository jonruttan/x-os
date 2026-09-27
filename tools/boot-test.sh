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

dir="$1"; arch="$2"
[ -f "$dir/vmlinuz" ] && [ -f "$dir/initramfs.cpio.gz" ] && [ -n "$arch" ] || {
	echo "usage: boot-test.sh DIR ARCH" >&2; exit 2; }

MEM="${BOOT_MEM:-4096}"
WAIT="${BOOT_WAIT:-300}"
host=$(uname -m)

case "$arch" in
	amd64)
		qemu=qemu-system-x86_64
		machine=""
		console=ttyS0
		case "$host" in x86_64|amd64) native=1 ;; *) native= ;; esac
		;;
	arm64)
		qemu=qemu-system-aarch64
		machine="-machine virt"
		console=ttyAMA0
		case "$host" in arm64|aarch64) native=1 ;; *) native= ;; esac
		;;
	*) echo "boot-test: unknown arch $arch" >&2; exit 2 ;;
esac

# The host's own virtualization when the guest is the host's architecture and
# the host offers it; emulation otherwise.
accel="-accel tcg"
cpu=""
[ "$arch" = arm64 ] && cpu="-cpu cortex-a72"
if [ -n "$native" ]; then
	if [ "$(uname -s)" = Darwin ]; then
		accel="-accel hvf"; cpu="-cpu host"
	elif [ -w /dev/kvm ]; then
		accel="-accel kvm"; cpu="-cpu host"
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

clean() { sed 's/\x1b\[[0-9;?]*[A-Za-z]//g' "$log" | tr -d '\r'; }

fail() {
	echo "boot-test: $*" >&2
	echo "--- console" >&2
	clean | grep -v '^[[:space:]]*$' | tail -40 >&2
	exit 1
}

# Wait for a line matching $1 to appear at least $2 times.
await() {
	n=0
	while [ "$(clean | grep -c -e "$1" || true)" -lt "${2:-1}" ]; do
		kill -0 $pid 2>/dev/null || fail "QEMU ended while waiting for: $1"
		n=$((n + 1))
		[ "$n" -le "$WAIT" ] || fail "no '$1' after ${WAIT}s"
		sleep 1
	done
}

say() { printf '%s\n' "$1" >&3; }

await 'exit or ctrl-d to leave'
say 'echo pid-is-$$'
await '^pid-is-[0-9]'
say 'uname -m'
await '^\(x86_64\|aarch64\)$'
say 'cat /proc/version'
await '^Linux version'
say 'exit'
await 'exit or ctrl-d to leave' 2
say 'echo second-shell'
await '^second-shell$'
say 'poweroff'
await 'reboot: Power down'

n=0
while kill -0 $pid 2>/dev/null; do
	n=$((n + 1))
	[ "$n" -le 30 ] || fail "the guest powered down and QEMU did not end"
	sleep 1
done

clean | grep -q 'Kernel panic' && fail "the kernel panicked"
echo "boot-test: $arch booted, ran a shell twice and powered down"
