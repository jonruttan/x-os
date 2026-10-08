#!/bin/sh
# container-test.sh -- run a script through the container's shell and check
# what it printed.
#
#   sh tools/container-test.sh IMAGE PLATFORM
#
# CONTAINER names the container command, docker when it is not set.
#
# The container runs under a memory and a process limit: the shell is the
# image's own, and nothing else bounds what it starts.
set -e

image="$1"
platform="$2"
if [ -z "$image" ] || [ -z "$platform" ]; then
	echo "usage: container-test.sh IMAGE PLATFORM" >&2
	exit 2
fi

# What the shell is given, a command a line.
script() {
	printf '%s\n' \
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
		"echo 'print 19*53' > /tmp/seven.logo" \
		'x -q -l logo -f /tmp/seven.logo' \
		"echo 'print(\"python-says-\" + str(2 ** 100))' | python" \
		"sh -c 'echo sh-says-\$((6*7))'" \
		'wget -q -O /tmp/https.html https://github.com/ && echo https-verified' \
		'mkdir /tmp/made' \
		"printf 'all: out.txt\\n\\t@cat out.txt\\nout.txt: in.txt\\n\\t@sed -e s/in/out/ in.txt > out.txt\\n' > /tmp/made/Makefile" \
		'echo in-by-make > /tmp/made/in.txt' \
		'cd /tmp/made && make' \
		"printf 'open mailbox\\nread leaflet\\n' | infocom /usr/share/infocom/zork1.z3"
}

# A line of the output each must match, in any order.
expected='^shell-ok$
^\(x86_64\|aarch64\)$
^3$
^root:x:0:0:
^-rwxr-xr-x .* x-bin$
^2:daemon:x:1:$
^ROOT:x:0:$
^awk-daemon$
^hello from C, 42$
^2$
^PIPED:x:1:$
^x-says-123$
^xe-says-1/2$
^x-piped-42$
^x-awk-42$
^1007$
^\(>>> \)\{0,1\}python-says-1267650600228229401496703205376$
^sh-says-42$
^https-verified$
^out-by-make$
WELCOME TO ZORK'

if ! out=$(script | "${CONTAINER:-docker}" run --rm -i --platform "$platform" \
	--memory "${TEST_MEM:-3g}" --memory-swap "${TEST_MEM:-3g}" \
	--pids-limit 256 "$image" 2>&1); then
	echo "container-test: the container failed" >&2
	printf '%s\n' "$out" >&2
	exit 1
fi

failed=0
while read -r want; do
	if ! printf '%s\n' "$out" | grep -q -e "$want"; then
		echo "container-test: nothing matching $want" >&2
		failed=1
	fi
done <<EOF
$expected
EOF

# What no command may print: a lang that cannot find part of its library.
if printf '%s\n' "$out" | grep -q -e 'unreadable'; then
	echo "container-test: a lang could not read part of its library" >&2
	failed=1
fi

if [ "$failed" -ne 0 ]; then
	printf '%s\n' "--- output" "$out" >&2
	exit 1
fi
echo "container-test: $platform ran the shell, the applets, a pipeline, grep, sed, awk, cc, x, logo, python, make, infocom and wget over https"
