#!/bin/sh
# container-test.sh -- run a script through the container's shell and check
# what it printed.
#
#   sh tools/container-test.sh IMAGE PLATFORM
#
# The container runs under a memory and a process limit: the shell is the
# image's own, and nothing else bounds what it starts.
set -e

image="$1"; platform="$2"
[ -n "$image" ] && [ -n "$platform" ] || { echo "usage: container-test.sh IMAGE PLATFORM" >&2; exit 2; }

out=$(printf '%s\n' \
	'echo shell-ok' \
	'uname -m' \
	'echo one two three | wc -w' \
	'cat /etc/passwd' \
	'ls -l /usr/libexec/x' \
	| docker run --rm -i --platform "$platform" \
		--memory "${TEST_MEM:-3g}" --pids-limit 256 "$image" 2>&1) || {
	echo "container-test: the container failed" >&2
	printf '%s\n' "$out" >&2
	exit 1
}

fail=0
for want in '^shell-ok$' '^\(x86_64\|aarch64\)$' '^3$' '^root:x:0:0:' \
	'^-rwxr-xr-x .* x-bin$'; do
	printf '%s\n' "$out" | grep -q -e "$want" || {
		echo "container-test: nothing matching $want" >&2
		fail=1
	}
done
[ "$fail" -eq 0 ] || { printf '%s\n' "--- output" "$out" >&2; exit 1; }
echo "container-test: $platform ran the shell, an applet, a pipeline, cat and ls -l"
