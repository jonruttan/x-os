#!/bin/sh
# fetch.sh -- acquire the sources pins.xon names, into build/src/NAME.
#
#   sh tools/fetch.sh            every source
#   PINS=other.xon sh tools/fetch.sh
#
# Shell, because it runs before there is an x to run.  A source already at its
# pinned commit is left alone, so a second run touches no network.
set -e

cd "$(dirname "$0")/.."
PINS="${PINS:-pins.xon}"
OUT="${OUT:-build/src}"
[ -f "$PINS" ] || { echo "fetch: no pins at $PINS" >&2; exit 2; }

# The closed vocabulary: a form this reader does not know is an error.
bad=$(sed -n 's/^(\([a-z-]*\)[ )].*/\1/p' "$PINS" | sort -u | grep -vxE 'source|track' || true)
[ -z "$bad" ] || { echo "fetch: unknown form(s) in $PINS: $bad" >&2; exit 2; }

rows=$(sed -n 's/^(source[[:space:]]\{1,\}\([a-z0-9-]*\)[[:space:]]\{1,\}"\([^"]*\)"[[:space:]]\{1,\}"\([0-9a-f]\{40\}\)").*/\1 \2 \3/p' "$PINS")
want=$(grep -c '^(source' "$PINS" || true)
got=$(printf '%s\n' "$rows" | grep -c . || true)
[ "$want" = "$got" ] || { echo "fetch: $PINS has a (source ...) row this reader cannot parse" >&2; exit 2; }

mkdir -p "$OUT"
printf '%s\n' "$rows" | while read -r name url commit; do
	dest="$OUT/$name"
	if [ -f "$dest/.commit" ] && [ "$(cat "$dest/.commit")" = "$commit" ]; then
		echo "fetch: $name is at $commit"
		continue
	fi
	tmp="$OUT/.fetch.$name.$$"
	rm -rf "$tmp"
	git init -q "$tmp"
	git -C "$tmp" fetch -q --depth 1 "$url" "$commit"
	have=$(git -C "$tmp" rev-parse FETCH_HEAD)
	[ "$have" = "$commit" ] || {
		echo "fetch: $name: asked for $commit, got $have" >&2
		rm -rf "$tmp"
		exit 1
	}
	git -C "$tmp" checkout -q FETCH_HEAD
	rm -rf "$tmp/.git"
	printf '%s\n' "$commit" > "$tmp/.commit"
	rm -rf "$dest"
	mv "$tmp" "$dest"
	echo "fetch: $name fetched at $commit"
done
