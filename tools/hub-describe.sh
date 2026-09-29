#!/bin/sh
# hub-describe.sh -- give the Docker Hub repository its descriptions.
#
#   DOCKERHUB_USERNAME=... DOCKERHUB_TOKEN=... sh tools/hub-describe.sh FILE SHORT
#
# FILE is the overview, in Markdown; SHORT is the one-line description, of at
# most 100 characters.  The token must be allowed to read, write and delete:
# Docker Hub asks that much of a change to a repository.  Neither the token
# nor what it is exchanged for is printed.
set -e

overview="$1"
short="$2"
hub=https://hub.docker.com/v2

# Report an error and exit with a status: fail STATUS MESSAGE
fail() {
	status="$1"
	shift
	echo "hub-describe: $*" >&2
	exit "$status"
}

if [ -z "$overview" ] || [ -z "$short" ]; then
	fail 2 "usage: hub-describe.sh FILE SHORT"
fi
if [ ! -f "$overview" ]; then
	fail 2 "no overview at $overview"
fi
if [ -z "$DOCKERHUB_USERNAME" ] || [ -z "$DOCKERHUB_TOKEN" ]; then
	fail 2 "DOCKERHUB_USERNAME and DOCKERHUB_TOKEN are not both set"
fi
if [ "${#short}" -gt 100 ]; then
	fail 2 "the short description is ${#short} characters, and 100 is the most"
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

jq -n --arg username "$DOCKERHUB_USERNAME" --arg password "$DOCKERHUB_TOKEN" \
	'{username: $username, password: $password}' > "$work/login"
status=$(curl -s -o "$work/session" -w '%{http_code}' \
	-H 'Content-Type: application/json' --data @"$work/login" "$hub/users/login")
if [ "$status" != 200 ]; then
	fail 1 "Docker Hub refused the login: $status"
fi
session=$(jq -r '.token' "$work/session")

jq -n --arg description "$short" --rawfile full_description "$overview" \
	'{description: $description, full_description: $full_description}' > "$work/change"
status=$(curl -s -o "$work/answer" -w '%{http_code}' -X PATCH \
	-H 'Content-Type: application/json' -H "Authorization: JWT $session" \
	--data @"$work/change" "$hub/repositories/$DOCKERHUB_USERNAME/x-os/")
if [ "$status" != 200 ]; then
	fail 1 "Docker Hub refused the change: $status $(jq -r '.detail // .message // empty' "$work/answer")"
fi
echo "hub-describe: $DOCKERHUB_USERNAME/x-os described"
