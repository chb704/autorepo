# PRD: Basic CDX Fallback Mode

## Problem

The runner exits cleanly when no open issue matches `ready` plus `lane:cdx-any`
or the machine lane. That makes idle automation cheap, but it also leaves useful
maintenance discovery undone until a human creates more issues.

ChrisBoyd.me solves this with fallback work: when no issue is claimable, the lane
performs one bounded opportunistic track, records that it was a fallback run, and
uses cooldown after repeated fallback turns. This repo should adopt the same core
loop, but without the larger ChrisBoyd.me machinery.

## Goal

When no claimable CDX issue exists, the runner should perform one basic fallback
audit in exactly one of three tracks: security, performance, or tests. After two
consecutive fallback rounds, that lane should idle fallback work for a randomized
4 to 6 hour cooldown while still allowing normal issue work to resume as soon as
a claimable issue appears.

## Users

- Repository owners who want idle lanes to find useful follow-up work.
- CDX machine lanes that run `scripts/runner.sh` on a schedule.
- Implementation agents that need a narrow prompt instead of open-ended repo
  spelunking.

## Requirements

- Trigger fallback only after the existing PR feedback check completes and the
  normal issue scan finds no claimable issue.
- Keep normal issue work higher priority than cooldown. Each scheduled run should
  still scan for claimable issues; if one exists, reset fallback state and use the
  normal issue path.
- If no issue is claimable and fallback cooldown is active, log the cooldown
  expiry and exit `0` without invoking an agent.
- If no issue is claimable and cooldown is not active, choose exactly one fallback
  track uniformly at random from:
  - `security`
  - `performance`
  - `tests`
- Invoke `FALLBACK_COMMAND` with a generated fallback prompt. If
  `FALLBACK_COMMAND` is unset, default to `AGENT_COMMAND`.
- The fallback prompt must instruct the agent to create at most one GitHub Issue
  only when it finds a concrete, bounded, evidence-backed improvement.
- Fallback-created issues must be claimable by normal automation:
  - `ready`
  - `lane:cdx-any`
  - one track label: `fallback:security`, `fallback:performance`, or
    `fallback:tests`
- Fallback must not create branches, commits, or PRs. Implementation happens only
  later through the normal issue runner path.
- A fallback round counts even if the agent finds no worthy issue, as long as the
  fallback command exits successfully.
- After two consecutive successful fallback rounds for a lane, write
  `cooldown_until` as now plus a randomized 4 to 6 hours.
- Cooldown state is lane-specific and repo-specific.
- Any non-fallback work decision resets the fallback streak and clears cooldown:
  claimable issue found, issue claimed, review feedback repaired, or normal PR
  path entered.
- If cooldown has expired and no claimable issue exists, clear the cooldown and
  start a fresh two-round fallback window.
- If `FALLBACK_MODE=off`, preserve today's behavior: log no eligible issues and
  exit `0`.

## Track Scope

### `security`

Run a read-only security review of the project codebase in this repository.
Focus on application, package, service, infrastructure, and configuration code
that affects real runtime behavior: authentication, authorization, input
handling, data exposure, dependency/configuration risk, unsafe defaults, secret
handling, and boundaries around external systems.

Create at most one issue when there is a concrete missing control or risky
behavior, with exact file and line references.

### `performance`

Run a static performance audit of the project codebase in this repository. Focus
on application, package, service, infrastructure, and configuration code that
affects real runtime behavior: hot paths, startup cost, build/runtime waste,
queries, caching, bundle size, expensive loops, repeated network calls, and
avoidable serialization.

Create at most one issue only when there is concrete evidence and a small fix
that fits the project.

### `tests`

Audit test and validation gaps for the project codebase in this repository.
Focus on application, package, service, infrastructure, and configuration code
that affects real behavior: business rules, APIs, CLI paths, critical UI flows,
migrations, integrations, and regression-prone contracts.

Create at most one issue with exact acceptance criteria. Do not file broad
"increase coverage" work.

## State Model

Keep v1 local and dependency-free.

- Add `CDX_FALLBACK_STATE_FILE` as an override.
- Default state path should live outside tracked files, for example under
  `${XDG_STATE_HOME:-$HOME/.local/state}/autorepo/<owner-repo>/<machine>.state`.
- Store only simple scalar fields:
  - `consecutive_fallbacks`
  - `cooldown_until_epoch`
  - `last_fallback_track`
  - `last_fallback_at_epoch`
- Do not `source` the state file. Parse known keys defensively.
- If the state file is missing or malformed, treat state as empty and continue.
- The implementation may use shell functions in `scripts/runner.sh`; do not add
  a database, API route, Node package, or new framework for this repo.

## Runner Flow

1. Resolve `CDX_MACHINE`, `LANE_LABEL`, and `CLAIM_LABEL` as today.
2. Run the existing setup, auth, clean-tree, base refresh, and requested-review
   feedback flow.
3. Run the existing issue scan.
4. If an issue is found:
   - clear fallback cooldown state for the lane
   - continue with the existing branch, agent, test, commit, push, and PR path
5. If no issue is found and `FALLBACK_MODE=off`:
   - keep today's no-op exit
6. If no issue is found and fallback cooldown is active:
   - log `fallback cooldown active until <timestamp>`
   - exit `0`
7. If no issue is found and fallback is allowed:
   - choose one track randomly
   - build a fallback prompt with repo, machine, lane, track, and hard rules
   - invoke `FALLBACK_COMMAND` or `AGENT_COMMAND`
   - fail if the working tree becomes dirty
   - increment the lane's fallback streak
   - after the second consecutive fallback, set cooldown to 4 to 6 hours from now
   - exit `0`

## Non-Goals

- No `rsi`, deep research, product ideation, design exploration, dependency
  upgrades, app scaffolding, or broad backlog gardening in v1.
- No API-backed state, Postgres table, activity events, or hosted cooldown
  endpoints.
- No implementation work during fallback.
- No automatic PR creation during fallback.
- No auto-merge behavior.
- No fallback behavior for issues missing trusted labels.

## Constraints

- Preserve the runner's provider-neutral contract. Model-specific behavior stays
  in `AGENT_COMMAND` or `FALLBACK_COMMAND`.
- Keep this repo a skeleton.
- Do not add heavy dependencies.
- Keep public-repo security boring: no secrets in prompts, logs, issues, branch
  names, state files, or docs examples.
- Fallback-created issues must still obey the normal trust boundary: only
  `ready` plus `lane:cdx-any` or a machine lane makes work claimable.
- Track labels should be created by `./scripts/runner.sh --setup-labels`.

## Acceptance Criteria

- [ ] With no claimable issue and fallback enabled, the runner invokes one
      fallback track instead of exiting immediately.
- [ ] Fallback track selection is limited to `security`, `performance`, and
      `tests`.
- [ ] The fallback prompt forbids implementation, branches, commits, PRs,
      production mutation, secret handling, and filler issues.
- [ ] A successful fallback run records one consecutive fallback.
- [ ] Two consecutive fallback runs arm a 4 to 6 hour cooldown for that machine
      lane.
- [ ] During active cooldown, no fallback agent command runs.
- [ ] Claimable issue work resets the fallback streak and clears cooldown.
- [ ] Expired cooldown allows a fresh fallback window when the queue is still
      empty.
- [ ] `FALLBACK_MODE=off` preserves today's no-eligible-issue behavior.
- [ ] `--setup-labels` creates the three fallback track labels.
- [ ] The runner exits nonzero if fallback leaves tracked or untracked working
      tree changes.
- [ ] README documents fallback mode, cooldown, state file location, and the
      opt-out flag.

## Test Plan

- Unit-style shell tests:
  - fake `gh issue list` returns no issues, fallback enabled, command invoked
  - first fallback writes `consecutive_fallbacks=1`
  - second fallback writes a `cooldown_until_epoch` between 4 and 6 hours out
  - active cooldown skips fallback command
  - claimable issue clears fallback state
  - `FALLBACK_MODE=off` keeps the current no-op exit
- Static validation:
  - `bash -n scripts/runner.sh`
  - YAML parse for `.github/workflows/*.yml`
  - `git diff --check`
- Manual checks:
  - run `./scripts/runner.sh --setup-labels` against a test repo and confirm the
    fallback labels exist
  - dry-run a scheduled pass with a fake `FALLBACK_COMMAND` that records stdin
    and exits `0`
- Not covered yet:
  - full GitHub issue creation by a real agent command
  - concurrent hourly runners for the same machine

## Issue Slicing Notes

1. Add runner fallback state and cooldown shell functions, with tests around
   state transitions.
2. Add fallback prompt generation, random track selection, and fallback command
   invocation.
3. Add label setup, README docs, and final validation.

Each slice should stay focused and avoid changing the normal issue claim path
except where fallback state must reset.
