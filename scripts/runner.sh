#!/usr/bin/env bash
#
# runner.sh - per-machine automation runner (skeleton).
#
# Each machine runs this on a schedule (e.g. hourly). It identifies which lane it is,
# finds an eligible issue, claims it with a best-effort race check, then hands the work
# to your coding agent. This is a SKELETON: the claim logic is sketched, the agent
# invocation and PR creation are left as TODOs for you to wire up to your tooling.
#
# Requires: gh (authenticated via `gh auth login`).

set -euo pipefail

# --- Identify this machine / lane -------------------------------------------------
# Override per machine, e.g. CDX_MACHINE=cdx-mini in the machine's environment.
CDX_MACHINE="${CDX_MACHINE:-$(hostname -s | tr '[:upper:]' '[:lower:]')}"
LANE_LABEL="lane:${CDX_MACHINE}"
ANY_LANE_LABEL="lane:cdx-any"
READY_LABEL="ready"

echo "[runner] machine=${CDX_MACHINE} lane=${LANE_LABEL}"

# --- Assert connectivity ----------------------------------------------------------
if ! gh auth status >/dev/null 2>&1; then
  echo "[runner] gh not authenticated - aborting." >&2
  exit 1
fi

# --- Find an eligible issue -------------------------------------------------------
# Eligible = has `ready` AND (this machine's lane OR the any-lane wildcard),
# and is not already claimed.
issue="$(gh issue list \
  --state open \
  --label "${READY_LABEL}" \
  --search "label:${ANY_LANE_LABEL},${LANE_LABEL} -label:claimed" \
  --json number,title --jq '.[0].number' 2>/dev/null || true)"

if [ -z "${issue}" ]; then
  echo "[runner] no eligible issues. Done."
  exit 0
fi

echo "[runner] candidate issue #${issue}"

# --- Claim with a best-effort race check ------------------------------------------
# NOTE: this is best-effort, NOT a distributed lock. Two machines can still double-claim
# within the same minute. Good enough in practice; know the caveat.
gh issue edit "${issue}" --add-label "claimed,claimed:${CDX_MACHINE}" >/dev/null
sleep 60
owner="$(gh issue view "${issue}" --json labels \
  --jq '[.labels[].name | select(startswith("claimed:"))][0]' 2>/dev/null || true)"

if [ "${owner}" != "claimed:${CDX_MACHINE}" ]; then
  echo "[runner] lost claim race on #${issue} (owner=${owner}). Backing off."
  exit 0
fi

echo "[runner] won claim on #${issue}. Starting work."

# --- Do the work ------------------------------------------------------------------
# TODO: hand issue #${issue} to your coding agent (Codex / Claude Code), let it
# implement on a branch, run tests, and open a PR wired back to the issue.
#
#   git switch -c "issue-${issue}"
#   <invoke your agent here>
#   gh pr create --fill --base main
#
echo "[runner] (skeleton) implement + open PR for #${issue} goes here."
