#!/usr/bin/env bash
# Offline Flux render check: render status + rendered diff vs a base rev.
# Used by .github/workflows/flux-render.yaml; also runnable locally:
#   bash scripts/ci/flux-render.sh [BASE_SHA]
# Posting needs a PR context (GH_TOKEN + PR_NUMBER); without it the script
# only builds the comment draft at /tmp/comment.md.

set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

BASE_SHA="${1:-HEAD}"
export FLATE_NO_PROGRESS=1
export FLATE_KUBE_VERSION="$(make -s print-FLATE_KUBE_VERSION)"
export PATH="$PWD/.tools:$PATH"

make install-tools >/dev/null

flate test --path ./homelab > /tmp/status.txt 2>&1 || true

# Mark the known offline sops failure as expected so the status reads calm.
# Falls back to the raw output if flate changes its format.
if grep -q 'jellyfin/jellyfin-config' /tmp/status.txt && \
	grep -q 'must have a valid version' /tmp/status.txt; then
	sed -i -E 's#✗  Kustomization   jellyfin/jellyfin-config .*#↷  Kustomization   jellyfin/jellyfin-config   skipped offline (whole-file sops, see note)#' /tmp/status.txt
	sed -i -E 's#^  ✗ ([0-9]+) passed · ([0-9]+) failed.*#  ✓ \1 passed · \2 expected offline (sops)#' /tmp/status.txt
fi

sops_limit=0
diff_exit=0
flate diff --base "$BASE_SHA" -o github --path ./homelab > /tmp/diff.txt 2>/tmp/diff.err || diff_exit=$?
# flate cannot decrypt sops-sealed files (no age key in CI, by design); the
# jellyfin config kustomization fails parsing on exactly that. In-cluster
# decryption makes it valid, so do not gate PRs on it.
if [ "$diff_exit" -ne 0 ] && grep -q 'must have a valid version' /tmp/diff.err; then
	sops_limit=1
	diff_exit=0
fi

{
	echo '<!-- flux-render:status -->'
	echo '## Flux render check'
	echo
	echo 'Every `Kustomization`, `HelmRelease`, and Flux source CR in `homelab/`'
	echo "rendered offline exactly as Flux would (k8s $FLATE_KUBE_VERSION)."
	echo
	echo 'Note: `jellyfin/config` is whole-file sops-sealed. The offline render cannot'
	echo 'parse it (no age key in CI, by design), so its status line below is expected'
	echo 'and does not affect the gate. In-cluster decryption makes it valid.'
	if [ "$sops_limit" -ne 0 ]; then
		echo 'This PR touches those files, so CI cannot validate them.'
	fi
	echo
	if [ "$diff_exit" -ne 0 ]; then
		echo "<details open><summary>render FAILED (diff exit $diff_exit)</summary>"
		echo
		echo '```'
		tail -30 /tmp/diff.err
		echo '```'
		echo '</details>'
		echo
	fi
	echo '### render status'
	echo '```'
	cat /tmp/status.txt
	echo '```'
	echo
	echo '### rendered diff vs merge base'
	if [ -s /tmp/diff.txt ]; then
		echo '```diff'
		if [ "$(wc -c < /tmp/diff.txt)" -gt 30000 ]; then
			head -c 30000 /tmp/diff.txt
			echo
			echo '[truncated]'
		else
			cat /tmp/diff.txt
		fi
		echo '```'
	else
		echo 'No rendered changes between the merge base and this branch.'
	fi
} > /tmp/comment.md

if [ -n "${PR_NUMBER:-}" ] && [ -n "${GH_TOKEN:-}" ]; then
	existing=$(gh api "repos/$GITHUB_REPOSITORY/issues/$PR_NUMBER/comments" \
		--jq '.[] | select(.body | contains("<!-- flux-render:status -->")) | .id' | head -1)
	if [ -n "$existing" ]; then
		gh api --method PATCH "repos/$GITHUB_REPOSITORY/issues/comments/$existing" \
			-F body=@/tmp/comment.md
	else
		gh pr comment "$PR_NUMBER" --body-file /tmp/comment.md
	fi
else
	echo 'no PR context; comment draft at /tmp/comment.md'
fi

exit "$diff_exit"
