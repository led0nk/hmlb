#!/usr/bin/env bash

set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

BASE="${TRIVY_BASE:-main}"

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
	echo "no container image bumps vs $BASE" >&2
	exit 0
fi

imgs=$(echo "$imgs" | sort -u)
echo "$imgs"
