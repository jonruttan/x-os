#!/bin/sh
# pins-update.sh -- move each pin in pins.xon to the newest commit its
# (track ...) row names, and say what moved.
#
#   sh tools/pins-update.sh          rewrite pins.xon
#   CHECK=1 sh tools/pins-update.sh  report only; exit 1 when a pin is behind
#
# One line a moved pin on stdout: NAME OLD NEW WHERE.  Nothing on stdout means
# nothing moved.
set -e

cd "$(dirname "$0")/.."
PINS="${PINS:-pins.xon}"

# Report an error and exit with a status: fail STATUS MESSAGE
fail() {
	status="$1"
	shift
	echo "pins-update: $*" >&2
	exit "$status"
}

# The newest commit and where it was found, for a URL and what to track:
# newest_commit URL WHAT
newest_commit() {
	case "$2" in
		release)
			# A version tag names a tag object; the ^{} row under it names the
			# commit.  A tag with no such row is its own commit.
			git ls-remote --tags "$1" 'v*' \
				| sed 's|refs/tags/||' \
				| awk '{
					name = $2
					peeled = sub(/\^\{\}$/, "", name)
					if (peeled || !(name in at)) {
						at[name] = $1
					}
				}
				END {
					for (n in at) {
						print n, at[n]
					}
				}' \
				| sort -V | tail -1 | awk '{ print $2, $1 }'
			;;
		main)
			git ls-remote "$1" refs/heads/main | awk '{ print $1, "main" }'
			;;
		*)
			echo "pins-update: cannot track '$2'" >&2
			return 2
			;;
	esac
}

if [ ! -f "$PINS" ]; then
	fail 2 "no pins at $PINS"
fi

tracks=$(sed -n 's/^(track[[:space:]]\{1,\}\([a-z0-9-]*\)[[:space:]]\{1,\}\([a-z]*\)).*/\1 \2/p' "$PINS")
if [ -z "$tracks" ]; then
	fail 2 "$PINS tracks nothing"
fi

moved=0
for row in $(printf '%s\n' "$tracks" | tr ' ' ':'); do
	name=${row%%:*}
	what=${row#*:}

	line=$(grep -n "^(source[[:space:]]\{1,\}$name[[:space:]]" "$PINS" | cut -d: -f1)
	if [ -z "$line" ]; then
		fail 2 "$name is tracked and not pinned"
	fi
	url=$(sed -n "${line}s/^(source[^\"]*\"\([^\"]*\)\".*/\1/p" "$PINS")
	old=$(sed -n "${line}s/.*\"\([0-9a-f]\{40\}\)\").*/\1/p" "$PINS")

	found=$(newest_commit "$url" "$what")
	new=${found%% *}
	where=${found#* }
	case "$new" in
		????????????????????????????????????????)
			;;
		*)
			fail 1 "$name: no commit found at $url ($what)"
			;;
	esac

	if [ "$new" = "$old" ]; then
		continue
	fi
	moved=1
	echo "$name $old $new $where"
	if [ -n "${CHECK:-}" ]; then
		continue
	fi
	sed "${line}s/\"$old\").*/\"$new\") ; $where/" "$PINS" > "$PINS.tmp"
	mv "$PINS.tmp" "$PINS"
done

if [ -n "${CHECK:-}" ] && [ "$moved" -eq 1 ]; then
	exit 1
fi
exit 0
