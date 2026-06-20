#!/usr/bin/env bash
#
# Per-machine issue runner.
#
# Each machine runs this on a schedule. It claims one eligible issue, waits and
# re-checks the claim, hands the issue prompt to an agent command, runs tests,
# commits the result, pushes a branch, and opens a PR linked to the issue.
#
# Required:
#   - gh, authenticated with repo access
#   - git remote "origin" pointed at GitHub
#   - AGENT_COMMAND set to the non-interactive agent invocation
#
# Useful env:
#   CDX_MACHINE=cdx-mini
#   AGENT_COMMAND='codex exec --sandbox workspace-write --ask-for-approval never --cd "$PWD" -'
#   TEST_COMMAND='bash -n scripts/runner.sh'

set -Eeuo pipefail

BASE_BRANCH="${BASE_BRANCH:-main}"
BRANCH_PREFIX="${BRANCH_PREFIX:-codex/issue-}"
CLAIM_WAIT_SECONDS="${CLAIM_WAIT_SECONDS:-60}"
ISSUE_LIMIT="${ISSUE_LIMIT:-50}"
READY_LABEL="${READY_LABEL:-ready}"
ANY_LANE_LABEL="${ANY_LANE_LABEL:-lane:cdx-any}"
TEST_COMMAND="${TEST_COMMAND:-bash -n scripts/runner.sh}"
FALLBACK_MODE="${FALLBACK_MODE:-on}"

issue=""
CLAIM_LABEL=""
PR_CREATED=0
TMP_DIR="$(mktemp -d)"

cleanup() {
  local code=$?
  rm -rf "$TMP_DIR"

  if [ "$code" -ne 0 ] && [ "$PR_CREATED" -eq 0 ] && [ -n "$issue" ] && [ -n "$CLAIM_LABEL" ]; then
    echo "[runner] releasing claim after failure on issue #${issue}"
    gh issue edit "$issue" --remove-label "$CLAIM_LABEL" >/dev/null 2>&1 || true
  fi

  exit "$code"
}
trap cleanup EXIT

log() {
  printf '[runner] %s\n' "$*"
}

die() {
  printf '[runner] ERROR: %s\n' "$*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

normalize_machine() {
  printf '%s' "$1" \
    | tr '[:upper:]_' '[:lower:]-' \
    | sed -E 's/[^a-z0-9-]+/-/g; s/^-+//; s/-+$//'
}

slugify() {
  printf '%s' "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//' \
    | cut -c 1-48
}

is_uint() {
  case "$1" in
    ''|*[!0-9]*) return 1 ;;
    *) return 0 ;;
  esac
}

is_fallback_track() {
  case "$1" in
    security|performance|tests) return 0 ;;
    *) return 1 ;;
  esac
}

random_fallback_track() {
  local n

  while :; do
    n="$RANDOM"
    [ "$n" -lt 32766 ] && break
  done

  case $((n % 3)) in
    0) printf '%s\n' "security" ;;
    1) printf '%s\n' "performance" ;;
    2) printf '%s\n' "tests" ;;
  esac
}

fallback_track_scope() {
  case "$1" in
    security)
      cat <<'SCOPE'
Track scope:

Run a read-only security review of this skeleton's automation, workflows,
permissions, ignored files, and public-repo guardrails. Do not print secrets,
dump private data, run destructive probes, change auth, change workflow trust
boundaries, or create an issue with exploit steps that would be unsafe in a
public repo.

Create at most one issue when there is a concrete missing control or risky
automation behavior, with exact file and line references.
SCOPE
      ;;
    performance)
      cat <<'SCOPE'
Track scope:

Run a static performance audit of the runner and CI workflow path. Focus on
avoidable slow network calls, needless repeated GitHub queries, serial work that
could be batched, expensive defaults, or scheduled-run waste.

Create at most one issue only when there is concrete evidence and a small fix
that fits this skeleton.
SCOPE
      ;;
    tests)
      cat <<'SCOPE'
Track scope:

Audit test and validation gaps for the runner, workflows, and docs contract.
Focus on missing shell validation, fake-gh scenario coverage, YAML checks, and
contracts that can regress without detection.

Create at most one issue with exact acceptance criteria. Do not file broad
"increase coverage" work.
SCOPE
      ;;
  esac
}

default_fallback_state_file() {
  local repo_slug state_root

  repo_slug="$(normalize_machine "$1")"
  if [ -n "${XDG_STATE_HOME:-}" ]; then
    state_root="$XDG_STATE_HOME"
  elif [ -n "${HOME:-}" ]; then
    state_root="${HOME}/.local/state"
  else
    state_root="${TMPDIR:-/tmp}"
  fi

  printf '%s/autorepo/%s/%s.state\n' "$state_root" "$repo_slug" "$CDX_MACHINE"
}

machine_raw="${CDX_MACHINE:-$(hostname -s)}"
CDX_MACHINE="$(normalize_machine "$machine_raw")"
[ -n "$CDX_MACHINE" ] || die "CDX_MACHINE resolved to an empty identifier"

LANE_LABEL="lane:${CDX_MACHINE}"
CLAIM_LABEL="claimed:${CDX_MACHINE}"

setup_labels() {
  log "creating standard labels if missing"
  gh label create "$READY_LABEL" \
    --color "0e8a16" \
    --description "Issue is ready for an automation lane" >/dev/null 2>&1 || true
  gh label create "$ANY_LANE_LABEL" \
    --color "5319e7" \
    --description "Any CDX machine may claim this issue" >/dev/null 2>&1 || true
  gh label create "$LANE_LABEL" \
    --color "1d76db" \
    --description "Work assigned to machine ${CDX_MACHINE}" >/dev/null 2>&1 || true
  gh label create "$CLAIM_LABEL" \
    --color "bfdadc" \
    --description "Issue is claimed by machine ${CDX_MACHINE}" >/dev/null 2>&1 || true
  gh label create "fallback:security" \
    --color "d73a4a" \
    --description "Fallback audit finding for security" >/dev/null 2>&1 || true
  gh label create "fallback:performance" \
    --color "fbca04" \
    --description "Fallback audit finding for performance" >/dev/null 2>&1 || true
  gh label create "fallback:tests" \
    --color "0e8a16" \
    --description "Fallback audit finding for tests" >/dev/null 2>&1 || true
  log "labels ready: ${READY_LABEL}, ${ANY_LANE_LABEL}, ${LANE_LABEL}, ${CLAIM_LABEL}, fallback:security, fallback:performance, fallback:tests"
}

if [ "${1:-}" = "--setup-labels" ]; then
  require_cmd gh
  gh auth status >/dev/null 2>&1 || die "gh is not authenticated. Run: gh auth login"
  setup_labels
  exit 0
fi

require_cmd git
require_cmd gh
require_cmd sed
require_cmd cut

[ -n "${AGENT_COMMAND:-}" ] || die "AGENT_COMMAND is required. See README.md for examples."

log "machine=${CDX_MACHINE} lane=${LANE_LABEL}"

gh auth status >/dev/null 2>&1 || die "gh is not authenticated. Run: gh auth login"
repo="$(gh repo view --json nameWithOwner --jq '.nameWithOwner')" || die "cannot reach GitHub repo"
log "repo=${repo}"
CDX_FALLBACK_STATE_FILE="${CDX_FALLBACK_STATE_FILE:-$(default_fallback_state_file "$repo")}"

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "not inside a git worktree"
[ -z "$(git status --porcelain)" ] || die "working tree is not clean"

log "refreshing ${BASE_BRANCH}"
git fetch --prune origin "$BASE_BRANCH" >/dev/null
if git show-ref --verify --quiet "refs/heads/${BASE_BRANCH}"; then
  git switch "$BASE_BRANCH" >/dev/null
else
  git switch -c "$BASE_BRANCH" "origin/${BASE_BRANCH}" >/dev/null
fi
git merge --ff-only "origin/${BASE_BRANCH}" >/dev/null

handle_review_feedback() {
  local pr_number pr_title head_ref is_cross feedback_command comments_file feedback_prompt

  pr_number="$(
    gh pr list \
      --state open \
      --label "$LANE_LABEL" \
      --json number,title,headRefName,reviewDecision \
      --jq '.[] | select(.reviewDecision == "CHANGES_REQUESTED") | .number' \
      | head -n 1
  )"

  [ -n "$pr_number" ] || return 0

  pr_title="$(gh pr view "$pr_number" --json title --jq '.title')"
  head_ref="$(gh pr view "$pr_number" --json headRefName --jq '.headRefName')"
  is_cross="$(gh pr view "$pr_number" --json isCrossRepository --jq '.isCrossRepository')"
  feedback_command="${FEEDBACK_COMMAND:-$AGENT_COMMAND}"

  log "PR #${pr_number} has requested changes: ${pr_title}"
  clear_fallback_state

  if [ "$is_cross" = "true" ]; then
    log "PR #${pr_number} comes from another repository. Skipping automation for safety."
    exit 0
  fi

  comments_file="${TMP_DIR}/pr-${pr_number}-comments.txt"
  feedback_prompt="${TMP_DIR}/feedback-prompt.md"

  gh pr view "$pr_number" --comments > "$comments_file"

  cat > "$feedback_prompt" <<PROMPT
You are the coding agent for ${repo}.

Read AGENTS.md first and follow it.

PR: #${pr_number} - ${pr_title}
Machine: ${CDX_MACHINE}
Lane label: ${LANE_LABEL}
Branch: ${head_ref}

This PR has requested changes. Address the review feedback before any new issue
is claimed. Keep the change focused. Do not commit secrets, credentials, account
IDs, production connection strings, or local-only context.

Leave your changes in the working tree. The runner will run tests, commit, and
push the branch.

PR discussion and review context:

PROMPT
  cat "$comments_file" >> "$feedback_prompt"

  if git show-ref --verify --quiet "refs/heads/${head_ref}"; then
    git switch "$head_ref" >/dev/null
    git pull --ff-only origin "$head_ref" >/dev/null
  else
    git fetch origin "${head_ref}:${head_ref}" >/dev/null
    git switch "$head_ref" >/dev/null
  fi

  export PR_NUMBER="$pr_number"
  export PR_TITLE="$pr_title"
  export PR_FEEDBACK_FILE="$comments_file"
  export PR_FEEDBACK_PROMPT_FILE="$feedback_prompt"
  export CDX_MACHINE
  export LANE_LABEL
  export BRANCH_NAME="$head_ref"

  log "handing PR #${pr_number} feedback to FEEDBACK_COMMAND"
  bash -lc "$feedback_command" < "$feedback_prompt"

  if [ -z "$(git status --porcelain)" ]; then
    log "feedback command finished without changing files. Skipping new issue."
    exit 0
  fi

  log "running tests: ${TEST_COMMAND}"
  bash -lc "$TEST_COMMAND"

  log "committing review feedback changes"
  git add -A
  git commit -m "Address review feedback on PR #${pr_number}" >/dev/null

  log "pushing ${head_ref}"
  git push origin "$head_ref" >/dev/null

  gh pr comment "$pr_number" \
    --body "Addressed requested changes from ${LANE_LABEL}. Verification: \`${TEST_COMMAND}\`." >/dev/null

  log "updated PR #${pr_number}"
  exit 0
}

fallback_state_consecutive=0
fallback_state_cooldown_until=0
fallback_state_last_track=""

load_fallback_state() {
  local line key value malformed
  local state_consecutive="" state_cooldown="" state_track="" state_at=""

  fallback_state_consecutive=0
  fallback_state_cooldown_until=0
  fallback_state_last_track=""

  [ -f "$CDX_FALLBACK_STATE_FILE" ] || return 0

  malformed=0
  while IFS= read -r line || [ -n "$line" ]; do
    [ -n "$line" ] || continue
    case "$line" in
      *=*) ;;
      *) malformed=1; break ;;
    esac

    key="${line%%=*}"
    value="${line#*=}"

    case "$key" in
      consecutive_fallbacks)
        if is_uint "$value"; then
          state_consecutive="$value"
        else
          malformed=1
        fi
        ;;
      cooldown_until_epoch)
        if [ -z "$value" ] || is_uint "$value"; then
          state_cooldown="${value:-0}"
        else
          malformed=1
        fi
        ;;
      last_fallback_track)
        if [ -z "$value" ] || is_fallback_track "$value"; then
          state_track="$value"
        else
          malformed=1
        fi
        ;;
      last_fallback_at_epoch)
        if is_uint "$value"; then
          state_at="$value"
        else
          malformed=1
        fi
        ;;
      *)
        ;;
    esac
  done < "$CDX_FALLBACK_STATE_FILE"

  if [ "$malformed" -ne 0 ]; then
    log "ignoring malformed fallback state: ${CDX_FALLBACK_STATE_FILE}"
    return 0
  fi

  fallback_state_consecutive="${state_consecutive:-0}"
  fallback_state_cooldown_until="${state_cooldown:-0}"
  fallback_state_last_track="$state_track"
  : "${state_at:-0}"
}

write_fallback_state() {
  local consecutive cooldown_until last_track state_dir tmp_state

  consecutive="$1"
  cooldown_until="$2"
  last_track="$3"
  state_dir="$(dirname "$CDX_FALLBACK_STATE_FILE")"
  mkdir -p "$state_dir"
  tmp_state="${CDX_FALLBACK_STATE_FILE}.$$"

  {
    printf 'consecutive_fallbacks=%s\n' "$consecutive"
    printf 'cooldown_until_epoch=%s\n' "$cooldown_until"
    printf 'last_fallback_track=%s\n' "$last_track"
    printf 'last_fallback_at_epoch=%s\n' "$(date +%s)"
  } > "$tmp_state"

  mv "$tmp_state" "$CDX_FALLBACK_STATE_FILE"
}

clear_fallback_state() {
  if [ -f "$CDX_FALLBACK_STATE_FILE" ]; then
    rm -f "$CDX_FALLBACK_STATE_FILE"
    log "cleared fallback state"
  fi
}

run_fallback() {
  local now track fallback_label fallback_command fallback_prompt fallback_scope new_consecutive
  local cooldown_seconds cooldown_until

  if [ "$FALLBACK_MODE" = "off" ]; then
    log "fallback mode is off. Exiting without work."
    exit 0
  fi

  load_fallback_state

  now="$(date +%s)"
  if [ "$fallback_state_cooldown_until" -gt 0 ]; then
    if [ "$fallback_state_cooldown_until" -gt "$now" ]; then
      log "fallback cooldown active until epoch ${fallback_state_cooldown_until}. Exiting without work."
      exit 0
    fi

    log "fallback cooldown expired"
    fallback_state_consecutive=0
    fallback_state_cooldown_until=0
  fi

  track="$(random_fallback_track)"
  fallback_label="fallback:${track}"
  fallback_command="${FALLBACK_COMMAND:-$AGENT_COMMAND}"
  fallback_prompt="${TMP_DIR}/fallback-${track}-prompt.md"
  fallback_scope="$(fallback_track_scope "$track")"

  cat > "$fallback_prompt" <<PROMPT
You are the fallback audit agent for ${repo}.

Read AGENTS.md first and follow it.

No claimable issue exists after the runner checked review feedback and scanned
eligible issues.

Fallback track: ${track}
Machine: ${CDX_MACHINE}
Lane label: ${LANE_LABEL}
Repository: ${repo}

Run a small audit for this one track only. Do not create a branch, commit, pull
request, implementation patch, database change, application/API route,
production mutation, Node package change, framework setup, generated app, cloud
resource, or any other tracked-file change.

Do not print, copy, transform, or expose secrets, credentials, account IDs,
production connection strings, private local context, or private data.

You may create at most one GitHub Issue, and only for a concrete, bounded,
evidence-backed finding that a future normal automation lane can finish in about
30 minutes. If there is no such finding, create nothing and exit successfully.
Do not create filler issues, broad backlog items, speculative work, or issues
without exact evidence.

Any fallback-created issue must use all of these labels:

- ${READY_LABEL}
- ${ANY_LANE_LABEL}
- ${fallback_label}

The issue must include:

- the specific evidence you observed, with file paths or commands when useful
- the bounded fix scope
- clear acceptance criteria

${fallback_scope}

Leave the working tree clean. The runner will exit nonzero if fallback leaves
tracked or untracked file changes.
PROMPT

  export FALLBACK_TRACK="$track"
  export FALLBACK_LABEL="$fallback_label"
  export FALLBACK_PROMPT_FILE="$fallback_prompt"
  export CDX_FALLBACK_STATE_FILE
  export CDX_MACHINE
  export LANE_LABEL

  log "running fallback audit track: ${track}"
  if ! bash -lc "$fallback_command" < "$fallback_prompt"; then
    clear_fallback_state
    die "fallback command failed"
  fi

  if [ -n "$(git status --porcelain)" ]; then
    clear_fallback_state
    die "fallback command left the working tree dirty"
  fi

  now="$(date +%s)"
  new_consecutive=$((fallback_state_consecutive + 1))
  cooldown_until=0
  if [ "$new_consecutive" -ge 2 ]; then
    cooldown_seconds=$((14400 + RANDOM % 7201))
    cooldown_until=$((now + cooldown_seconds))
    log "fallback cooldown armed for ${cooldown_seconds}s until epoch ${cooldown_until}"
  else
    log "fallback success recorded; consecutive_fallbacks=${new_consecutive}"
  fi

  write_fallback_state "$new_consecutive" "$cooldown_until" "$track"
  exit 0
}

handle_review_feedback

find_issue() {
  gh issue list \
    --state open \
    --limit "$ISSUE_LIMIT" \
    --label "$READY_LABEL" \
    --json number,title,labels \
    --jq ".[] |
      select(([.labels[].name] | index(\"${ANY_LANE_LABEL}\")) or ([.labels[].name] | index(\"${LANE_LABEL}\"))) |
      select(([.labels[].name | select(startswith(\"claimed:\"))] | length) == 0) |
      .number" \
    | head -n 1
}

issue="$(find_issue)"

if [ -z "$issue" ]; then
  log "no eligible issues. Need labels: ${READY_LABEL} + (${ANY_LANE_LABEL} or ${LANE_LABEL})"
  run_fallback
fi

clear_fallback_state

issue_title="$(gh issue view "$issue" --json title --jq '.title')"
issue_url="$(gh issue view "$issue" --json url --jq '.url')"
log "candidate issue #${issue}: ${issue_title}"

log "claiming issue #${issue} with ${CLAIM_LABEL}"
gh issue edit "$issue" --add-label "${LANE_LABEL},${CLAIM_LABEL}" >/dev/null

log "waiting ${CLAIM_WAIT_SECONDS}s before claim re-check"
sleep "$CLAIM_WAIT_SECONDS"

claims="$(gh issue view "$issue" --json labels \
  --jq '[.labels[].name | select(startswith("claimed:"))] | sort | join(",")')"

if [ "$claims" != "$CLAIM_LABEL" ]; then
  log "lost claim race on issue #${issue}; claims=${claims:-none}"
  gh issue edit "$issue" --remove-label "$CLAIM_LABEL" >/dev/null 2>&1 || true
  exit 0
fi

log "claim confirmed"

slug="$(slugify "$issue_title")"
[ -n "$slug" ] || slug="work"
branch="${BRANCH_PREFIX}${issue}-${slug}"

if git show-ref --verify --quiet "refs/heads/${branch}"; then
  die "local branch already exists: ${branch}"
fi
if git ls-remote --exit-code --heads origin "$branch" >/dev/null 2>&1; then
  die "remote branch already exists: ${branch}"
fi

issue_body_file="${TMP_DIR}/issue-body.md"
prompt_file="${TMP_DIR}/agent-prompt.md"
pr_body_file="${TMP_DIR}/pr-body.md"

gh issue view "$issue" --json body --jq '.body' > "$issue_body_file"

cat > "$prompt_file" <<PROMPT
You are the coding agent for ${repo}.

Read AGENTS.md first and follow it.

Issue: #${issue} - ${issue_title}
Issue URL: ${issue_url}
Machine: ${CDX_MACHINE}
Lane label: ${LANE_LABEL}
Branch: ${branch}

Work only on this issue. Keep the change focused. Do not commit secrets,
credentials, account IDs, production connection strings, or local-only context.

Leave your changes in the working tree. The runner will run tests, commit, push,
and open the pull request.

If the issue is blocked or unsafe, stop and explain the blocker.

Issue body:

PROMPT
cat "$issue_body_file" >> "$prompt_file"

log "creating branch ${branch}"
git switch -c "$branch" "origin/${BASE_BRANCH}" >/dev/null

export ISSUE_NUMBER="$issue"
export ISSUE_TITLE="$issue_title"
export ISSUE_URL="$issue_url"
export ISSUE_BODY_FILE="$issue_body_file"
export ISSUE_PROMPT_FILE="$prompt_file"
export CDX_MACHINE
export LANE_LABEL
export BRANCH_NAME="$branch"

log "handing issue #${issue} to AGENT_COMMAND"
bash -lc "$AGENT_COMMAND" < "$prompt_file"

[ -n "$(git status --porcelain)" ] || die "agent finished without changing files"

log "running tests: ${TEST_COMMAND}"
bash -lc "$TEST_COMMAND"

log "committing changes"
git add -A
git commit -m "Issue #${issue}: ${issue_title}" >/dev/null

log "pushing ${branch}"
git push -u origin "$branch" >/dev/null

cat > "$pr_body_file" <<PRBODY
Closes #${issue}

Automation lane: ${LANE_LABEL}
Machine: ${CDX_MACHINE}

Verification:
- ${TEST_COMMAND}
PRBODY

log "opening PR"
pr_url="$(gh pr create \
  --base "$BASE_BRANCH" \
  --head "$branch" \
  --label "$LANE_LABEL" \
  --title "Issue #${issue}: ${issue_title}" \
  --body-file "$pr_body_file")"

PR_CREATED=1
log "opened PR: ${pr_url}"
