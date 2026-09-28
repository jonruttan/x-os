#!/bin/sh
# stream.sh -- write the boot stream the launcher hands the engine.
#
#   sh stream.sh LANG NAME          write <share>/launch/NAME for the installed LANG
#   sh stream.sh LANG NAME ENTRY    the same, running ENTRY in place of the lang's own
#   sh stream.sh LANG NAME ENTRY FORM   with FORM, one line of x, ahead of ENTRY
#   sh stream.sh --applets          print the coreutils applet names, one a line
#   sh stream.sh --loader           write <share>/launch/image-loader, which x reads
#
# The stream is what the wrapper pipes for a lang booted from its state image:
# the image's path, the image loader with its includes rooted, the batch reset,
# and the lang's entry.  Every part is fixed once the tree is installed.
set -e
share="${SHARE:-/usr/share/x}"

# The image loader: lib/img.x and tools/dev/image-read.x, their includes rooted
# at the installed tree.  What reads an image reads this after its path.
loader() {
	sed 's|^(include "\([^/]\)|(include "'"$share"'/\1|' \
		"$share/lib/img.x" "$share/tools/dev/image-read.x"
}

if [ "$1" = "--loader" ]; then
	mkdir -p "$share/launch"
	loader > "$share/launch/image-loader"
	echo "stream: $share/launch/image-loader"
	exit 0
fi

if [ "$1" = "--applets" ]; then
	sed -n '/^(def %cu-applets/,/^(def %cu-find-applet/s/.*(pair "\([^"]*\)".*/\1/p' \
		"$share/langs/coreutils/cu/cli.x"
	exit 0
fi

# Report an error and exit with a status: fail STATUS MESSAGE
fail() {
	status="$1"
	shift
	echo "stream: $*" >&2
	exit "$status"
}

lang="$1"
name="$2"
if [ -z "$lang" ] || [ -z "$name" ]; then
	fail 2 "usage: stream.sh LANG NAME [ENTRY [FORM]]"
fi
entry="${3:-$share/langs/$lang/run.x}"
form="${4:-}"
if [ ! -f "$entry" ]; then
	fail 1 "no entry at $entry"
fi
image="$share/langs/$lang/.images/$lang.boot.x.ximg"
if [ ! -f "$image" ]; then
	fail 1 "no state image at $image"
fi

mkdir -p "$share/launch"
{
	printf '(def %%IMG-PATH "%s")\n' "$image"
	loader
	printf '(set! %%batch? ())\n'
	if [ -n "$form" ]; then
		printf '%s\n' "$form"
	fi
	cat "$entry"
	cat "$share/lib/x/repl/launch.x"
} > "$share/launch/$name"
echo "stream: $share/launch/$name"
