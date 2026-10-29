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
		"printf 'a\\n--batch\\n' | grep -e --batch" \
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
		'mkdir /tmp/made' \
		"printf 'all: out.txt\\n\\t@cat out.txt\\nout.txt: in.txt\\n\\t@sed -e s/in/out/ in.txt > out.txt\\n' > /tmp/made/Makefile" \
		'echo in-by-make > /tmp/made/in.txt' \
		'cd /tmp/made && make' \
		"printf 'one\\r\\ntwo\\033[1;2HX' > /tmp/screen.txt" \
		'tmux vt dump /tmp/screen.txt | head -2 | sed -e s/^/tmux-row-/ -e "s/  *|$/|/"' \
		"printf '# Hi\\n\\nA [link](b.md).\\n' > /tmp/page.md" \
		'browse -dump /tmp/page.md | head -3 | sed -e s/^/browse-/' \
		"printf '<h1>Html</h1><p>An <a href=b.html>anchor</a>.</p>\\n' > /tmp/page.html" \
		'browse -dump /tmp/page.html | head -3 | sed -e s/^/browse-/' \
		"printf 'open mailbox\\nread leaflet\\n' | infocom /usr/share/infocom/zork1.z3" \
		'export HOME=/root' \
		'mkdir -p /etc/ssh && ssh-keygen -A > /dev/null' \
		"ssh-keygen -q -t ed25519 -N '' -f /tmp/userkey" \
		'mkdir -p /root/.ssh' \
		'cp /tmp/userkey.pub /root/.ssh/authorized_keys' \
		'sshd -f /dev/null -o ListenAddress=127.0.0.1 -p 2222 -o PidFile=/tmp/sshd.pid -o "Subsystem=sftp internal-sftp"' \
		"ssh -o StrictHostKeyChecking=accept-new -i /tmp/userkey -p 2222 root@127.0.0.1 'echo ssh-says-\$((6*7))' < /dev/null" \
		'eval "$(ssh-agent -s)" > /dev/null && ssh-add -q /tmp/userkey' \
		"ssh -o IdentityFile=none -p 2222 root@127.0.0.1 'echo agent-says-\$((6*6))' < /dev/null" \
		'ssh-agent -k > /dev/null' \
		"printf 'alice:x:1000:1000:alice:/home/alice:/bin/sh\\n' >> /etc/passwd" \
		'mkdir -p /home/alice/.ssh && cp /tmp/userkey.pub /home/alice/.ssh/authorized_keys' \
		"ssh -i /tmp/userkey -p 2222 alice@127.0.0.1 'echo \$(id -un)-uid-\$(id -u)-in-\$(pwd)' < /dev/null" \
		'echo scp-carried > /tmp/sent' \
		'scp -P 2222 -i /tmp/userkey /tmp/sent root@127.0.0.1:/tmp/received' \
		'cat /tmp/received' \
		'git init -b main /tmp/repo > /dev/null' \
		"printf '[user]\\n\\tname = X\\n\\temail = x@x-os\\n' >> /tmp/repo/.git/config" \
		'cd /tmp/repo && echo git-carried > f && git add f && git commit -q -m one' \
		'cd /tmp && git clone file:///tmp/repo local 2> /dev/null && cat /tmp/local/f' \
		"export GIT_SSH_COMMAND='ssh -i /tmp/userkey'" \
		'cd /tmp && git clone ssh://root@127.0.0.1:2222/tmp/repo remote 2> /dev/null && echo git-over-ssh-$(cat /tmp/remote/f)' \
		"printf '[user]\\n\\tname = X\\n\\temail = x@x-os\\n' >> /tmp/remote/.git/config" \
		'cd /tmp/remote && echo more >> f && git add f && git commit -q -m pushed-over-ssh && git branch landed' \
		'cd /tmp/remote && git push origin landed 2> /dev/null && git -C /tmp/repo log --oneline landed | head -1'
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
^--batch$
^x-says-123$
^xe-says-1/2$
^x-piped-42$
^x-awk-42$
^1007$
^\(>>> \)\{0,1\}python-says-1267650600228229401496703205376$
^sh-says-42$
^out-by-make$
WELCOME TO ZORK
^tmux-row-oXe|$
^tmux-row-two|$
^browse-Hi$
^browse-A \[1\]link\.$
^browse-Html$
^browse-An \[1\]anchor\.$
^ssh-says-42$
^agent-says-36$
^alice-uid-1000-in-/home/alice$
^scp-carried$
^git-carried$
^git-over-ssh-git-carried$
 pushed-over-ssh$'

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
echo "container-test: $platform ran the shell, the applets, a pipeline, grep, sed, awk, cc, x, logo, python, make, infocom, ssh, its agent, a second user, git, tmux and browse"
