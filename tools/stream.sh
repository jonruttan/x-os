#!/bin/sh
# stream.sh -- write the boot stream the launcher hands the engine.
#
#   sh stream.sh LANG NAME          write <share>/launch/NAME for the installed LANG
#   sh stream.sh LANG NAME ENTRY    the same, running ENTRY in place of the lang's own
#   sh stream.sh LANG NAME ENTRY FORM   with FORM, one line of x, ahead of ENTRY
#   sh stream.sh --applets          print the coreutils applet names, one a line
#   sh stream.sh --loader           write <share>/launch/image-loader, which x reads
#   sh stream.sh --runs             write <share>/launch/NAME.run for each bundle, which x -l reads
#
# The stream is what the wrapper pipes for a lang booted from its state image:
# the image's path, the image loader with its includes rooted, the batch reset,
# and the lang's entry, or ENTRY.  Every part is fixed once the tree is installed.
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
	# Each applet a static method of Applets, and [ and [[ by def-static!
	sed -n -e 's/^    (method \([^ ]*\) (self argv .*/\1/p' \
		-e 's/^(Applets def-static! (Str8 ->sym "\([^"]*\)").*/\1/p' \
		"$share/bundles/coreutils/lib/coreutils/applets.x"
	exit 0
fi

# A bundle's entry is the module NAME/run: importing it sets the bundle up,
# and the main it provides starts it.  The image has imported it already, so
# here the import is a no-op.  main is called at the top of the stream, never
# inside the import, since a lang's own reader takes the rest of the stream.
run_forms() {
	printf '(import %s/run)\n' "$1"
	printf '((eval (lit main) (Module env (lit %s/run))))\n' "$1"
}

# What x -l NAME feeds after the image loader: <share>/launch/NAME.run for
# each installed bundle with an entry.
if [ "$1" = "--runs" ]; then
	mkdir -p "$share/launch"
	for dir in "$share"/bundles/*/; do
		lang=$(basename "$dir")
		if grep -q '^(entry run)' "$dir/bundle.xon" 2>/dev/null; then
			run_forms "$lang" > "$share/launch/$lang.run"
			echo "stream: $share/launch/$lang.run"
		fi
	done
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
entry="${3:-}"
form="${4:-}"
if [ -n "$entry" ] && [ ! -f "$entry" ]; then
	fail 1 "no entry at $entry"
fi
image="$share/bundles/$lang/.images/$lang.boot.x.ximg"
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
	if [ -n "$entry" ]; then
		cat "$entry"
	else
		run_forms "$lang"
	fi
	cat "$share/lib/x/repl/launch.x"
} > "$share/launch/$name"
echo "stream: $share/launch/$name"
