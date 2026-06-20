# AGENTS.md

Instructions for Codex and other coding agents working in this repo.

## First Move

- Read the issue, this file, and any referenced PRD in `docs/planning/`.
- If you are running in an automation lane, check open PRs in your lane for review
  feedback before claiming a new issue.
- Do not touch work that is not labeled for automation.

## Eligible Work

An issue is eligible only when it has both labels:

- `ready`
- `lane:cdx-any` or a machine lane such as `lane:cdx-mini`

Everything else is out of bounds. If the issue is too large for roughly 30
minutes of implementation work, say that on the issue instead of expanding scope.

## Branch And PR Rules

- Branch from `main`.
- Use a branch name like `codex/issue-123-short-title`.
- Never commit directly to `main`.
- When working manually, open a PR that links the issue with `Closes #123`.
- When invoked by `scripts/runner.sh`, leave changes in the working tree. The
  runner owns testing, committing, pushing, and opening the PR.
- Do not merge your own PR.
- If a PR gets review feedback, address that before claiming new work.

## Implementation Rules

- Keep the change focused on the issue and its acceptance criteria.
- Prefer existing structure and conventions over new abstractions.
- Keep this repo a skeleton unless the issue explicitly asks for real app code.
- Do not add frameworks, heavy dependencies, generated apps, or cloud resources as
  drive-by setup.
- Run the relevant tests before opening or updating the PR. If there are no real
  tests yet, run the narrowest available validation and say what is missing.

## Frontend Rules

- Frontend changes must respect `docs/DESIGN.md`.
- Compose existing components and patterns.
- Do not introduce one-off spacing, colors, typography, or interaction patterns.
- If `docs/DESIGN.md` is too vague for the work, improve the design doc first or
  ask for clarification.

## Security Rules

- Never commit secrets, credentials, keys, tokens, account IDs, production URLs,
  connection strings, database dumps, or private local context.
- Use placeholders in tracked files. Use GitHub Secrets or ignored local files for
  real values.
- Treat `ready` plus `lane:*` labels as a trust boundary. Do not help untrusted
  contributors turn labels into code execution.
- Do not use `pull_request_target` to check out and execute PR code with secrets.
- Agents may open PRs. Branch protection and human review decide what merges.
