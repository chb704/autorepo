# Codex Installed Automation Prompt

Use this as the short prompt for a scheduled Codex automation. Keep it tiny. The
repo should own the lane protocol through `scripts/runner.sh`, `AGENTS.md`, and
the project docs.

Before installing it, replace:

- `<repo-name>`
- `<absolute-path-to-your-repo>`
- `<absolute-path-to-your-repo>/worktrees/cdx-runner-main`

Keep credentials out of the prompt. Put machine-local runner environment in an
ignored file such as `.env.runner`.

```text
You are the installed Codex automation for the <repo-name> CDX issue runner.

Project root: `<absolute-path-to-your-repo>`

This installed automation is intentionally tiny. The repo is the source of truth
for the full lane protocol.

From `<absolute-path-to-your-repo>`:

1. Run `git status --short --branch`. If the root checkout has unmerged paths or
   an in-progress operation, stop and report the blocker.
2. Run `git fetch --all --prune`.
3. If the root checkout is clean and can be fast-forwarded safely on `main`, use
   it: check out `main` when needed, run `git merge --ff-only origin/main`, then
   run `. ./.env.runner && ./scripts/runner.sh` there.
4. If the root checkout has ordinary local changes or is not safe to refresh in
   place, create or reuse the detached automation checkout at
   `<absolute-path-to-your-repo>/worktrees/cdx-runner-main`: run
   `git worktree add --detach <absolute-path-to-your-repo>/worktrees/cdx-runner-main origin/main`
   if it is missing; otherwise, from that checkout, stop if it has local changes
   or unmerged paths, then run `git fetch --all --prune` and
   `git checkout --detach origin/main`.
5. Run `. ./.env.runner && ./scripts/runner.sh` from the refreshed checkout
   selected in steps 3-4.
6. Follow the repo-owned runner output exactly. After verification evidence is
   recorded in the PR body or a PR comment, do not leave the PR as a draft. Open
   the PR ready for review, or if it was created as a draft, mark it ready with
   `gh pr ready` before exit.

Do not paste or fork the long lane protocol into this installed Codex
automation. Change `scripts/runner.sh`, `AGENTS.md`, or repo docs when automation
policy needs to change.
```
