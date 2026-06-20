# CLAUDE.md

Instructions for Claude Code working in this repo. See [AGENTS.md](AGENTS.md) - the same
working agreement applies. Key points repeated here so they're impossible to miss:

## Planning

- PRDs live in `docs/planning/` as Markdown, one file per feature.
- Use Plan Mode to pressure-test a feature before writing the PRD: what's missing, what's
  ill-advised, what hasn't been thought through.
- Grade PRDs with "give this PRD a letter grade, with reasoning," then iterate to an A.

## Implementation

- Turn PRDs into **agent-sized** GitHub Issues (~30 min of coding each) that are
  independent, non-blocking, and parallelizable.
- Automation-ready issues carry `ready` + a lane label (`lane:cdx-any` or a machine lane).

## Guardrails

- Branch + PR only; never commit to `main` or merge your own work.
- Never commit secrets or real infrastructure identifiers.
- Frontend PRs must pass the Design Review against `docs/DESIGN.md`.
