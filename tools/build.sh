#!/bin/sh
# build.sh -- the steps of the image build that run in the builder, one a
# subcommand, so that each is a layer of its own.
#
#   sh build.sh install-langs SOURCES     install every lang among SOURCES
#   sh build.sh image-langs SOURCES       write every installed lang's image
#   sh build.sh image-dialects DIALECT... write each dialect's image
#   sh build.sh streams COMMANDS INIT     write the boot streams
#   sh build.sh root ROOT COMMANDS ETC    assemble the image's root
#
# SOURCES is a directory holding one fetched source a directory, as
# tools/fetch.sh leaves them; COMMANDS is commands.xon; INIT holds init.x and
# power.x; ETC holds the files the root's /etc is given.
set -e

share=/usr/share/x
launcher=/usr/libexec/x/launch
here=$(cd "$(dirname "$0")" && pwd)

# Report an error and exit with a status: fail STATUS MESSAGE
fail() {
	status="$1"
	shift
	echo "build: $*" >&2
	exit "$status"
}

# The name a lang declares in its lang.xon: lang_name DIR
lang_name() {
	sed -n 's/^(lang "\(.*\)").*/\1/p' "$1/lang.xon"
}

# The commands commands.xon names, as NAME LANG lines: command_rows FILE
command_rows() {
	rows=$(sed -n 's/^(command[[:space:]]\{1,\}\([a-z0-9-]*\)[[:space:]]\{1,\}\([a-z0-9-]*\)).*/\1 \2/p' "$1")
	if [ "$(grep -c '^(command' "$1")" != "$(printf '%s\n' "$rows" | grep -c .)" ]; then
		fail 2 "$1 has a (command ...) row this reader cannot parse"
	fi
	printf '%s\n' "$rows"
}

# An image written while another's compiled code is cached lacks what the
# cache answered for, and a boot from it, with no cache, compiles that again.
# So each image is written from an empty cache.
clear_code_cache() {
	rm -f /tmp/x-asm-*
}

# Every source but the platform is a lang.  All are installed before any is
# imaged, since a lang may require another.
install_langs() {
	for dir in "$1"/*/; do
		if [ ! -f "$dir/lang.xon" ]; then
			continue
		fi
		clear_code_cache
		make -C "$dir" install PREFIX=/usr LANG_VERSION="$(cut -c1-12 "$dir/.commit")"
	done
}

# A lang that writes no image would boot from source, which the image has no
# wrapper to do, so that is an error.
image_langs() {
	for dir in "$1"/*/; do
		if [ ! -f "$dir/lang.xon" ]; then
			continue
		fi
		name=$(lang_name "$dir")
		clear_code_cache
		x --image -l "$name"
		if [ ! -f "$share/langs/$name/.images/$name.boot.x.ximg" ]; then
			fail 1 "no state image for $name"
		fi
	done
}

# The wrapper writes a dialect's image to its cache, in a directory named for
# the tree; the x command looks for it among the images.
image_dialects() {
	cache=$(mktemp -d)
	mkdir -p "$share/images"
	for dialect in "$@"; do
		clear_code_cache
		XDG_CACHE_HOME="$cache" x --image -l "$dialect"
		cp "$cache"/x/images/*/"$dialect.boot.x.ximg" "$share/images/"
	done
	rm -rf "$cache"
}

# The image loader, the applet stream, a stream for each command, process 1's,
# and the power commands'.
write_streams() {
	commands_file="$1"
	init_dir="$2"

	sh "$here/stream.sh" --loader
	sh "$here/stream.sh" coreutils coreutils
	command_rows "$commands_file" | while read -r name lang; do
		sh "$here/stream.sh" "$lang" "$name"
	done
	sh "$here/stream.sh" ash init "$init_dir/init.x"
	for how in poweroff reboot halt; do
		sh "$here/stream.sh" ash "$how" "$init_dir/power.x" "(def %power-how (lit $how))"
	done
}

# Link a command to the launcher, among the commands: link_command ROOT NAME
link_command() {
	ln -s "$launcher" "$1/usr/bin/$2"
}

# The root: the loader, the engine, the library, the langs, and the links.
# The commands are in /usr/bin, and /bin is a link to it: the state images
# record the library as /usr/bin/../share/x, where the wrapper that wrote
# them stood, and that path resolves only through a real /usr/bin.
# Each applet gets a link unless a command of its own has the name.
assemble_root() {
	root="$1"
	commands_file="$2"
	etc_dir="$3"

	mkdir -p "$root/lib" "$root/usr/bin" "$root/usr/libexec" "$root/usr/share" \
		"$root/tmp" "$root/root" "$root/proc" "$root/sys" "$root/dev" \
		"$root/etc" "$root/run"
	chmod 1777 "$root/tmp"
	ln -s usr/bin "$root/bin"
	cp /lib/ld-musl-*.so.1 "$root/lib/"
	cp -R /usr/libexec/x "$root/usr/libexec/x"
	cp -R "$share" "$root/usr/share/x"
	rm -rf "$root/usr/share/x/tests"

	ln -s "$launcher" "$root/init"
	link_command "$root" x
	command_rows "$commands_file" | while read -r name lang; do
		link_command "$root" "$name"
	done
	for how in poweroff reboot halt; do
		link_command "$root" "$how"
	done
	sh "$here/stream.sh" --applets | while read -r applet; do
		if [ ! -e "$root/usr/bin/$applet" ]; then
			link_command "$root" "$applet"
		fi
	done

	printf 'root:x:0:0:root:/root:/bin/sh\n' > "$root/etc/passwd"
	printf 'root:x:0:\ndaemon:x:1:\n' > "$root/etc/group"
	cp "$etc_dir"/* "$root/etc/"
}

if [ $# -lt 1 ]; then
	fail 2 "usage: build.sh STEP ARG..."
fi
step="$1"
shift

case "$step" in
	install-langs)
		install_langs "$@"
		;;
	image-langs)
		image_langs "$@"
		;;
	image-dialects)
		image_dialects "$@"
		;;
	streams)
		write_streams "$@"
		;;
	root)
		assemble_root "$@"
		;;
	*)
		fail 2 "no step named $step"
		;;
esac
