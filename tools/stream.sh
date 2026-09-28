#!/bin/sh
# stream.sh -- write the boot stream the launcher hands the engine.
#
#   sh stream.sh LANG NAME          write <share>/launch/NAME for the installed LANG
#   sh stream.sh LANG NAME ENTRY    the same, running ENTRY in place of the lang's own
#   sh stream.sh LANG NAME ENTRY FORM   with FORM, one line of x, ahead of ENTRY
#   sh stream.sh --applets          print the coreutils applet names, one a line
#
# The stream is what the wrapper pipes for a lang booted from its state image:
# the image's path, the image loader with its includes rooted, the batch reset,
# and the lang's entry.  Every part is fixed once the tree is installed.
set -e
share="${SHARE:-/usr/share/x}"

if [ "$1" = "--applets" ]; then
	sed -n '/^(def %cu-applets/,/^(def %cu-find-applet/s/.*(pair "\([^"]*\)".*/\1/p' \
		"$share/langs/coreutils/cu/cli.x"
	exit 0
fi

lang="$1"; name="$2"
[ -n "$lang" ] && [ -n "$name" ] || { echo "usage: stream.sh LANG NAME [ENTRY [FORM]]" >&2; exit 2; }
entry="${3:-$share/langs/$lang/run.x}"; form="${4:-}"
[ -f "$entry" ] || { echo "stream: no entry at $entry" >&2; exit 1; }
image="$share/langs/$lang/.images/$lang.boot.x.ximg"
[ -f "$image" ] || { echo "stream: no state image at $image" >&2; exit 1; }

mkdir -p "$share/launch"
{
	printf '(def %%IMG-PATH "%s")\n' "$image"
	sed 's|^(include "\([^/]\)|(include "'"$share"'/\1|' \
		"$share/lib/img.x" "$share/tools/dev/image-read.x"
	printf '(set! %%batch? ())\n'
	[ -z "$form" ] || printf '%s\n' "$form"
	cat "$entry"
	cat "$share/lib/x/repl/launch.x"
} > "$share/launch/$name"
echo "stream: $share/launch/$name"
