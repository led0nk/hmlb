#!/usr/bin/env bash

set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

BASE="${TRIVY_BASE:-main}"
TRIVY="$PWD/.tools/trivy"

if ! git rev-parse --verify "$BASE" >/dev/null 2>&1; then
	git fetch --depth=1 origin "$BASE" >/dev/null 2>&1 || true
fi
if ! git rev-parse --verify "$BASE" >/dev/null 2>&1; then
	echo "base $BASE not found; skipping image scan"
	exit 0
fi

imgs=$(git diff "$BASE" --unified=0 -- \
	| grep -E '^\+[[:space:]]*image:' \
	| sed -E 's/^\+[[:space:]]*image:[[:space:]]*//' \
	| sed -E 's/^[[:space:]]*-[[:space:]]*//' \
	| sed -E 's/#.*$//' \
	| tr -d '"' \
	| sed -E 's/[[:space:]]+$//' \
	| grep -vE '(\{\{|\$\(|^[[:space:]]*$)' || true)

if [ -z "$imgs" ]; then
	echo "no container image bumps vs $BASE"
	exit 0
fi

echo "scanning bumped container images vs $BASE:"
echo "$imgs"

rc=0
while IFS= read -r img; do
	echo "== trivy $img"
	"$TRIVY" image --scanners vuln --severity HIGH,CRITICAL --ignore-unfixed --exit-code 1 --quiet "$img" || rc=1
done <<EOF
$imgs
EOF

exit "$rc"
