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
	'grep -n daemon /etc/group' \
	'sed -e s/root/ROOT/ /etc/group' \
	'cat /etc/group | grep -c x' \
	'cat /etc/group | sed -e s/daemon/PIPED/' \
	"awk -F: '{ print \"awk-\" \$1 }' /etc/group" \
	'cat /etc/hello.c' \
	'cc run /etc/hello.c' \
	"x -q -c '(display \"x-says-\") (write (+ 100 23)) (newline)'" \
	"x -q -l xe -c '(display \"xe-says-\") (write (+ 1/3 1/6)) (newline)'" \
	"echo '(display \"x-piped-\") (write 42) (newline)' | x -q" \
	"x -q -l awk -- 'BEGIN { print \"x-awk-\" 6*7 }'" \
	| docker run --rm -i --platform "$platform" \
		--memory "${TEST_MEM:-3g}" --pids-limit 256 "$image" 2>&1) || {
	echo "container-test: the container failed" >&2
	printf '%s\n' "$out" >&2
	exit 1
}

fail=0
for want in '^shell-ok$' '^\(x86_64\|aarch64\)$' '^3$' '^root:x:0:0:' \
	'^-rwxr-xr-x .* x-bin$' '^2:daemon:x:1:$' '^ROOT:x:0:$' '^awk-daemon$' \
	'^hello from C, 42$' '^2$' '^PIPED:x:1:$' '^x-says-123$' '^xe-says-1/2$' \
	'^x-piped-42$' '^x-awk-42$'; do
	printf '%s\n' "$out" | grep -q -e "$want" || {
		echo "container-test: nothing matching $want" >&2
		fail=1
	}
done
[ "$fail" -eq 0 ] || { printf '%s\n' "--- output" "$out" >&2; exit 1; }
echo "container-test: $platform ran the shell, the applets, a pipeline, grep, sed, awk, cc and x"
