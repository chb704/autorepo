#!/usr/bin/env bash

set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="${ROOT_DIR}/scripts/runner.sh"
ORIGINAL_PATH="$PATH"
TMP_ROOT="$(mktemp -d)"

cleanup() {
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

pass() {
  printf 'ok - %s\n' "$*"
}

state_value() {
  local key="$1" file="$2"
  awk -F= -v key="$key" '$1 == key { print substr($0, index($0, "=") + 1); exit }' "$file"
}

assert_eq() {
  local expected="$1" actual="$2" message="$3"
  [ "$expected" = "$actual" ] || fail "${message}: expected '${expected}', got '${actual}'"
}

assert_file_contains() {
  local file="$1" needle="$2" message="$3"
  grep -F "$needle" "$file" >/dev/null || fail "${message}: missing '${needle}' in ${file}"
}

assert_track() {
  local track="$1" message="$2"

  case "$track" in
    security|performance|tests) ;;
    *) fail "${message}: invalid track '${track}'" ;;
  esac
}

make_case() {
  local name="$1" dir

  dir="${TMP_ROOT}/${name}"
  mkdir -p "${dir}/bin"

  cat > "${dir}/bin/gh" <<'GH'
#!/usr/bin/env bash
set -Eeuo pipefail

printf 'gh %s\n' "$*" >> "${FAKE_GH_LOG:?}"

case "${1:-}" in
  auth)
    [ "${2:-}" = "status" ] && exit 0
    ;;
  repo)
    if [ "${2:-}" = "view" ]; then
      printf '%s\n' "${FAKE_REPO:-owner/repo}"
      exit 0
    fi
    ;;
  pr)
    case "${2:-}" in
      list)
        if [ "${FAKE_GH_PR_REVIEW:-none}" = "changes" ]; then
          printf '77\n'
        fi
        exit 0
        ;;
      create)
        printf 'https://github.com/%s/pull/1\n' "${FAKE_REPO:-owner/repo}"
        exit 0
        ;;
      comment)
        exit 0
        ;;
      view)
        if printf '%s\n' "$*" | grep -F -- "--comments" >/dev/null; then
          printf 'Needs changes\n'
          exit 0
        fi

        json=""
        previous=""
        for arg in "$@"; do
          if [ "$previous" = "--json" ]; then
            json="$arg"
          fi
          previous="$arg"
        done

        case "$json" in
          title)
            printf 'Review fix\n'
            ;;
          headRefName)
            printf 'codex/review-fix\n'
            ;;
          isCrossRepository)
            printf 'false\n'
            ;;
        esac
        exit 0
        ;;
    esac
    ;;
  issue)
    case "${2:-}" in
      list)
        if [ "${FAKE_GH_ISSUE:-none}" = "claimable" ]; then
          printf '123\n'
        fi
        exit 0
        ;;
      view)
        json=""
        previous=""
        for arg in "$@"; do
          if [ "$previous" = "--json" ]; then
            json="$arg"
          fi
          previous="$arg"
        done

        case "$json" in
          title)
            printf 'Fallback reset issue\n'
            ;;
          url)
            printf 'https://github.com/%s/issues/123\n' "${FAKE_REPO:-owner/repo}"
            ;;
          labels)
            printf 'claimed:%s\n' "${CDX_MACHINE:-cdx-test}"
            ;;
          body)
            printf 'Issue body\n'
            ;;
        esac
        exit 0
        ;;
      edit|create)
        exit 0
        ;;
    esac
    ;;
  label)
    if [ "${2:-}" = "create" ]; then
      printf '%s\n' "${3:-}" >> "${FAKE_LABEL_LOG:?}"
      exit 0
    fi
    ;;
esac

printf 'unexpected gh args: %s\n' "$*" >&2
exit 1
GH

  cat > "${dir}/bin/git" <<'GIT'
#!/usr/bin/env bash
set -Eeuo pipefail

printf 'git %s\n' "$*" >> "${FAKE_GIT_LOG:?}"

case "${1:-}" in
  rev-parse)
    [ "${2:-}" = "--is-inside-work-tree" ] && exit 0
    ;;
  status)
    if [ "${2:-}" = "--porcelain" ]; then
      if [ -f "${FAKE_GIT_DIRTY_FILE:?}" ]; then
        printf ' M dirty\n'
      fi
      exit 0
    fi
    ;;
  fetch|merge|switch|pull|add|commit|push)
    exit 0
    ;;
  show-ref)
    last=""
    for arg in "$@"; do
      last="$arg"
    done
    [ "$last" = "refs/heads/main" ] && exit 0
    exit 1
    ;;
  ls-remote)
    exit 2
    ;;
esac

printf 'unexpected git args: %s\n' "$*" >&2
exit 1
GIT

  cat > "${dir}/agent-ok" <<'AGENT'
#!/usr/bin/env bash
set -Eeuo pipefail
cat > "${FAKE_AGENT_PROMPT_FILE:?}"
touch "${FAKE_GIT_DIRTY_FILE:?}"
AGENT

  cat > "${dir}/fallback-ok" <<'FALLBACK'
#!/usr/bin/env bash
set -Eeuo pipefail
cat > "${FAKE_FALLBACK_PROMPT_FILE:?}"
printf '%s\n' "${FALLBACK_TRACK:?}" >> "${FAKE_FALLBACK_LOG:?}"
FALLBACK

  cat > "${dir}/fallback-fail" <<'FALLBACK'
#!/usr/bin/env bash
set -Eeuo pipefail
printf 'called\n' > "${FAKE_FALLBACK_CALLED_FILE:?}"
exit 42
FALLBACK

  cat > "${dir}/fallback-dirty" <<'FALLBACK'
#!/usr/bin/env bash
set -Eeuo pipefail
cat > "${FAKE_FALLBACK_PROMPT_FILE:?}"
touch "${FAKE_GIT_DIRTY_FILE:?}"
FALLBACK

  chmod +x "${dir}/bin/gh" "${dir}/bin/git" "${dir}/agent-ok" \
    "${dir}/fallback-ok" "${dir}/fallback-fail" "${dir}/fallback-dirty"

  printf '%s\n' "$dir"
}

run_runner() {
  local dir="$1"
  shift || true

  (
    export PATH="${dir}/bin:${ORIGINAL_PATH}"
    export CDX_MACHINE="cdx-test"
    export CLAIM_WAIT_SECONDS="0"
    export ISSUE_LIMIT="50"
    export BASE_BRANCH="main"
    export TEST_COMMAND=":"
    export AGENT_COMMAND="${RUNNER_AGENT_COMMAND:-${dir}/agent-ok}"
    export FALLBACK_COMMAND="${RUNNER_FALLBACK_COMMAND:-${dir}/fallback-ok}"
    export CDX_FALLBACK_STATE_FILE="${dir}/state"
    export FAKE_REPO="owner/repo"
    export FAKE_GH_ISSUE="${RUNNER_FAKE_GH_ISSUE:-none}"
    export FAKE_GH_PR_REVIEW="${RUNNER_FAKE_GH_PR_REVIEW:-none}"
    export FAKE_GH_LOG="${dir}/gh.log"
    export FAKE_GIT_LOG="${dir}/git.log"
    export FAKE_LABEL_LOG="${dir}/labels.log"
    export FAKE_GIT_DIRTY_FILE="${dir}/dirty"
    export FAKE_AGENT_PROMPT_FILE="${dir}/agent-prompt.md"
    export FAKE_FALLBACK_PROMPT_FILE="${dir}/fallback-prompt.md"
    export FAKE_FALLBACK_LOG="${dir}/fallback.log"
    export FAKE_FALLBACK_CALLED_FILE="${dir}/fallback-called"

    if [ -n "${RUNNER_FALLBACK_MODE+x}" ]; then
      export FALLBACK_MODE="$RUNNER_FALLBACK_MODE"
    else
      unset FALLBACK_MODE
    fi

    "$RUNNER" "$@"
  )
}

write_valid_state() {
  local dir="$1" consecutive="$2" cooldown="$3" track="$4"

  cat > "${dir}/state" <<STATE
consecutive_fallbacks=${consecutive}
cooldown_until_epoch=${cooldown}
last_fallback_track=${track}
last_fallback_at_epoch=$(date +%s)
STATE
}

test_fallback_invoked_and_records_first_round() {
  local dir track

  dir="$(make_case first)"
  run_runner "$dir" > "${dir}/out" 2>&1

  track="$(cat "${dir}/fallback.log")"
  assert_track "$track" "fallback track"
  assert_eq "1" "$(state_value consecutive_fallbacks "${dir}/state")" "first fallback count"
  assert_eq "0" "$(state_value cooldown_until_epoch "${dir}/state")" "first fallback cooldown"
  assert_eq "$track" "$(state_value last_fallback_track "${dir}/state")" "state fallback track"
  assert_file_contains "${dir}/fallback-prompt.md" "Fallback track: ${track}" "fallback prompt track"
  assert_file_contains "${dir}/fallback-prompt.md" "You may create at most one GitHub Issue" "fallback prompt issue limit"
  assert_file_contains "${dir}/fallback-prompt.md" "fallback:${track}" "fallback prompt labels"
  assert_file_contains "${dir}/fallback-prompt.md" "Do not print, copy, transform, or expose secrets" "fallback prompt secret handling"
  assert_file_contains "${dir}/fallback-prompt.md" "Do not create filler issues" "fallback prompt filler issues"
  assert_file_contains "${dir}/fallback-prompt.md" "project codebase in this repository" "fallback prompt project target"

  pass "no claimable issue invokes fallback and records first round"
}

test_second_fallback_arms_cooldown() {
  local dir before after cooldown first_track second_track

  dir="$(make_case second)"
  run_runner "$dir" > "${dir}/first.out" 2>&1
  before="$(date +%s)"
  run_runner "$dir" > "${dir}/second.out" 2>&1
  after="$(date +%s)"

  cooldown="$(state_value cooldown_until_epoch "${dir}/state")"
  first_track="$(sed -n '1p' "${dir}/fallback.log")"
  second_track="$(sed -n '2p' "${dir}/fallback.log")"

  assert_eq "2" "$(state_value consecutive_fallbacks "${dir}/state")" "second fallback count"
  assert_track "$first_track" "first fallback track"
  assert_track "$second_track" "second fallback track"
  assert_eq "$second_track" "$(state_value last_fallback_track "${dir}/state")" "second state fallback track"
  [ "$cooldown" -ge "$((before + 14400))" ] || fail "cooldown was less than 4 hours out"
  [ "$cooldown" -le "$((after + 21600))" ] || fail "cooldown was more than 6 hours out"

  pass "second fallback arms 4 to 6 hour cooldown"
}

test_active_cooldown_skips_fallback() {
  local dir future

  dir="$(make_case cooldown)"
  future="$(($(date +%s) + 18000))"
  write_valid_state "$dir" "2" "$future" "performance"

  RUNNER_FALLBACK_COMMAND="${dir}/fallback-fail" run_runner "$dir" > "${dir}/out" 2>&1

  [ ! -f "${dir}/fallback-called" ] || fail "fallback command ran during cooldown"
  pass "active cooldown skips fallback command"
}

test_expired_cooldown_starts_fresh_window() {
  local dir past track

  dir="$(make_case expired)"
  past="$(($(date +%s) - 60))"
  write_valid_state "$dir" "2" "$past" "security"

  run_runner "$dir" > "${dir}/out" 2>&1

  track="$(cat "${dir}/fallback.log")"
  assert_track "$track" "expired cooldown fallback track"
  assert_eq "1" "$(state_value consecutive_fallbacks "${dir}/state")" "expired cooldown fresh count"
  assert_eq "0" "$(state_value cooldown_until_epoch "${dir}/state")" "expired cooldown cleared"

  pass "expired cooldown starts a fresh fallback window"
}

test_claimable_issue_clears_fallback_state() {
  local dir future

  dir="$(make_case claimable)"
  future="$(($(date +%s) + 18000))"
  write_valid_state "$dir" "2" "$future" "tests"

  RUNNER_FAKE_GH_ISSUE="claimable" \
    RUNNER_FALLBACK_COMMAND="${dir}/fallback-fail" \
    run_runner "$dir" > "${dir}/out" 2>&1

  [ ! -f "${dir}/state" ] || fail "fallback state was not cleared for claimable issue"
  [ ! -f "${dir}/fallback-called" ] || fail "fallback command ran despite claimable issue"
  assert_file_contains "${dir}/gh.log" "gh pr create" "normal issue path"

  pass "claimable issue clears fallback state"
}

test_review_feedback_clears_fallback_state() {
  local dir future

  dir="$(make_case feedback)"
  future="$(($(date +%s) + 18000))"
  write_valid_state "$dir" "2" "$future" "performance"

  RUNNER_FAKE_GH_PR_REVIEW="changes" \
    RUNNER_FALLBACK_COMMAND="${dir}/fallback-fail" \
    run_runner "$dir" > "${dir}/out" 2>&1

  [ ! -f "${dir}/state" ] || fail "fallback state was not cleared for review feedback"
  [ ! -f "${dir}/fallback-called" ] || fail "fallback command ran despite review feedback"
  assert_file_contains "${dir}/gh.log" "gh pr comment 77" "review feedback path"

  pass "review feedback clears fallback state"
}

test_fallback_mode_off_keeps_noop() {
  local dir

  dir="$(make_case off)"
  RUNNER_FALLBACK_MODE="off" \
    RUNNER_FALLBACK_COMMAND="${dir}/fallback-fail" \
    run_runner "$dir" > "${dir}/out" 2>&1

  [ ! -f "${dir}/fallback-called" ] || fail "fallback command ran with FALLBACK_MODE=off"
  [ ! -f "${dir}/state" ] || fail "fallback state was written with FALLBACK_MODE=off"

  pass "FALLBACK_MODE=off keeps no-op behavior"
}

test_dirty_fallback_exits_nonzero() {
  local dir

  dir="$(make_case dirty)"
  if RUNNER_FALLBACK_COMMAND="${dir}/fallback-dirty" run_runner "$dir" > "${dir}/out" 2>&1; then
    fail "dirty fallback unexpectedly succeeded"
  fi

  assert_file_contains "${dir}/out" "fallback command left the working tree dirty" "dirty fallback error"
  [ ! -f "${dir}/state" ] || fail "dirty fallback wrote state"

  pass "dirty fallback exits nonzero"
}

test_setup_labels_includes_fallback_labels() {
  local dir

  dir="$(make_case labels)"
  run_runner "$dir" --setup-labels > "${dir}/out" 2>&1

  assert_file_contains "${dir}/labels.log" "fallback:security" "setup labels security"
  assert_file_contains "${dir}/labels.log" "fallback:performance" "setup labels performance"
  assert_file_contains "${dir}/labels.log" "fallback:tests" "setup labels tests"

  pass "setup labels includes fallback labels"
}

test_fallback_invoked_and_records_first_round
test_second_fallback_arms_cooldown
test_active_cooldown_skips_fallback
test_expired_cooldown_starts_fresh_window
test_claimable_issue_clears_fallback_state
test_review_feedback_clears_fallback_state
test_fallback_mode_off_keeps_noop
test_dirty_fallback_exits_nonzero
test_setup_labels_includes_fallback_labels
