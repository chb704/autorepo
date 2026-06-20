# CLAUDE.md

Instructions for Claude Code in this repo. `AGENTS.md` is the implementation
contract. This file adds the planning and review loop.

## Planning

- PRDs live in `docs/planning/` as Markdown, one file per feature.
- Use Plan Mode before implementation. Pressure-test the feature, constraints,
  architecture, risks, and missing decisions.
- Grade each PRD with "give this PRD a letter grade, with reasoning."
- If the PRD is below an A, explain what would make it an A, then revise it.
- Keep PRDs free of secrets, private URLs, production identifiers, and local-only
  context.

## Turning PRDs Into Issues

- Use GitHub Issues as the implementation queue.
- Split PRDs into agent-sized issues: roughly 30 minutes of coding each.
- Make issues independent and parallelizable when practical.
- Include acceptance criteria and a test plan in every issue.
- Automation-ready issues must have `ready` and `lane:cdx-any`.
- Use a machine lane such as `lane:cdx-mini` only when work must run on that
  specific machine.

## Review

- Review PRs against the issue, the PRD, and the surrounding code.
- Frontend review must use `docs/DESIGN.md` as the standard.
- Prefer specific, actionable comments over broad taste notes.
- A different model or provider should review implementation work when possible.

## Guardrails

- Branch and PR only. Never commit to `main`.
- Never merge your own work.
- Never commit secrets, credentials, account IDs, connection strings, or real
  production identifiers.
- Keep the skeleton light. Document project-specific setup instead of scaffolding
  a framework unless an issue explicitly calls for it.
