---
name: agentic-development-autorepo
description: Use when bootstrapping, auditing, or adapting an agentic development monorepo that uses PRDs in docs/planning, GitHub Issue labels ready and lane:cdx-any, Codex machine lanes, an hourly issue runner, Design Review, cross-provider code review, and public-repo security guardrails.
---

# Agentic Development Autorepo

Use this skill to help a repo adopt the `autorepo` workflow: plan in PRDs, slice
work into GitHub Issues, let Codex lanes claim eligible work, and keep quality
behind PR review gates.

## Load Order

When working inside this skill/repo, read these files before changing behavior:

1. `README.md` for the clone-to-first-PR path.
2. `AGENTS.md` for implementation agent rules.
3. `CLAUDE.md` for planning and review rules.
4. `scripts/runner.sh` for the lane protocol.
5. `.github/workflows/code-review.yml` and `.github/workflows/design-review.yml`
   for CI review gates.
6. `.gitignore` for public-repo secret hygiene.

Read `docs/DESIGN.md`, `docs/planning/`, or `docs/prompts/` only when the task
touches frontend review, PRD planning, or installed automation prompts.

## Operating Rules

- Keep this as a skeleton. Do not scaffold an app, framework, database, or cloud
  stack unless the user explicitly asks.
- Keep names consistent: `ready`, `lane:cdx-any`, machine lanes like
  `lane:cdx-mini`, claim labels like `claimed:cdx-mini`, `docs/planning`,
  `docs/DESIGN.md`, and `scripts/runner.sh`.
- Make setup paths concrete enough for a stranger to follow from clone to first
  automated PR.
- Leave project-specific steps behind an explicit variable or short TODO only
  when they truly depend on the user's provider, app, or infrastructure.
- Do not quote or publish local-only writing context. Treat files such as
  `POST.md` as private source material if they exist.

## Runner Expectations

The issue runner should:

- Identify the machine from `CDX_MACHINE` or hostname.
- Assert `gh` authentication and GitHub connectivity.
- Refresh `main` by fast-forward only.
- Handle requested PR changes in the machine lane before claiming new work.
- Find open issues labeled `ready` plus `lane:cdx-any` or the machine lane.
- Claim with `claimed:<machine>`, wait, and re-check that it is the sole claim.
- Hand the issue prompt to `AGENT_COMMAND`.
- Run `TEST_COMMAND`.
- Commit, push, and open a PR linked with `Closes #<issue>`.

Keep the runner provider-neutral. Model-specific commands belong in local
environment variables or docs examples, not hard-coded into the protocol.

## Public-Repo Security Bar

Before finishing any change, check that:

- No secrets, keys, tokens, account IDs, production URLs, connection strings,
  database dumps, or private local paths are tracked.
- Secrets in workflows are referenced only as `${{ secrets.NAME }}`.
- Workflows run on GitHub-hosted runners by default.
- Workflows do not use `pull_request_target` to check out and execute PR code
  with secrets.
- `.gitignore` covers local env files, keys, dumps, logs, and `POST.md`.
- The docs call out branch protection, label trust boundaries, and runner
  isolation.

## Validation

Run the narrowest useful checks for the change. For this skeleton, default to:

```bash
bash -n scripts/runner.sh
ruby -e 'require "yaml"; ARGV.each { |f| YAML.load_file(f); puts "ok #{f}" }' .github/workflows/*.yml
git diff --check
```

Also scan for private names, private paths, obvious token formats, and banned
workflow patterns before calling the repo public-safe.
