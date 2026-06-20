# AGENTS.md

Instructions for coding agents (Codex and friends) working in this repo.

## How work is picked up

- Only issues labeled **both** `ready` and a lane label (`lane:cdx-any` or a machine
  lane like `lane:cdx-mini`) are eligible for automation. Everything else is ignored.
- One issue = one focused, **agent-sized** unit of work: roughly 30 minutes of straight
  coding, leaving room for review and iteration. If a ticket is bigger than that, it was
  scoped wrong - note it on the issue rather than ballooning the PR.

## Working agreement

- Implement on a branch, never commit to `main`. Open a PR wired back to the issue.
- Run the tests before opening the PR.
- Frontend changes are graded by the Design Review against `docs/DESIGN.md`.
  Compose existing components and respect the spacing/color/typography rules - don't
  invent one-off patterns.
- On your next run, check open PRs in your lane for review feedback and address it
  **before** claiming a new issue.

## Guardrails

- Never commit secrets, credentials, account IDs, or production connection strings.
- You cannot merge to `main` - branch protection requires passing checks and a review.
