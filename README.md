# autorepo

A public monorepo skeleton for the agentic development loop from
**[How I Code: Summer 2026 Edition](https://chrisboyd.me/blog/how-i-code-summer-2026-edition/)**.

This is not a sample app. It is the boring substrate: planning docs, agent
instructions, issue labels, lane claiming, an hourly runner, and CI review gates.
Clone it, rename it, and put your product inside it.

## What This Repo Demonstrates

- Plan first in `docs/planning`.
- Turn PRDs into small GitHub Issues.
- Let automation pick up only issues labeled `ready` and `lane:cdx-any`.
- Let each machine claim work with its own lane label, for example `lane:cdx-mini`.
- Run the loop on a schedule, usually hourly.
- Open PRs, never push straight to `main`.
- Review frontend changes against `docs/DESIGN.md`.
- Keep public-repo security boring: no secrets, no trusted labels for strangers,
  no long-lived runners with broad cloud access.

## Structure

```text
autorepo/
├── apps/                         # your applications live here
├── packages/                     # shared libraries live here
├── infra/                        # infrastructure as code lives here
├── docs/
│   ├── DESIGN.md                 # frontend design standard for CI review
│   ├── planning/                 # PRDs, one Markdown file per feature
│   └── prompts/                  # tiny installed-automation prompt examples
├── scripts/
│   └── runner.sh                 # claims an issue, runs an agent, opens a PR
├── .github/workflows/
│   ├── code-review.yml           # cross-provider PR review placeholder
│   └── design-review.yml         # DESIGN.md-based frontend review placeholder
├── SKILL.md                      # optional Codex skill entrypoint
├── AGENTS.md                     # instructions for Codex and similar agents
└── CLAUDE.md                     # planning and review instructions for Claude Code
```

## Quickstart: Clone To First Automated PR

Assumptions:

- You have a GitHub repo with this skeleton pushed to it.
- You have `gh` installed and authenticated.
- You have a non-interactive coding agent available. The example below uses the
  Codex CLI because this repo is about Codex lanes, but the runner only requires
  a shell command that accepts a prompt on stdin.

### 1. Clone and authenticate

```bash
git clone https://github.com/YOUR-ORG/YOUR-REPO.git
cd YOUR-REPO

gh auth login
gh repo view
```

If you use Codex as the implementation agent:

```bash
codex login
```

### 2. Create the labels the runner trusts

Pick a stable machine name. Use lowercase kebab-case. `cdx-mini` and
`cdx-mbp` are good. Your label becomes `lane:<machine>`.

```bash
export CDX_MACHINE=cdx-mini
./scripts/runner.sh --setup-labels
```

That creates:

- `ready`
- `lane:cdx-any`
- `lane:cdx-mini`
- `claimed:cdx-mini`
- `fallback:security`
- `fallback:performance`
- `fallback:tests`

Run the same setup once per machine so each one has its own lane and claim label.

### 3. Write the first PRD

```bash
cp docs/planning/EXAMPLE-prd.md docs/planning/first-automation-smoke-test.md
$EDITOR docs/planning/first-automation-smoke-test.md
```

Keep it agent-sized. A good first issue is a harmless docs change, for example:
add a short "Project conventions" section to `AGENTS.md` or improve
`docs/DESIGN.md`. Do not put secrets, customer data, private URLs, or account IDs
in PRDs.

Commit the PRD if you want planning docs versioned:

```bash
git add docs/planning/first-automation-smoke-test.md
git commit -m "Add first automation PRD"
git push
```

### 4. Turn the PRD into an automation-ready issue

```bash
gh issue create \
  --title "Docs: first automation smoke test" \
  --body-file docs/planning/first-automation-smoke-test.md \
  --label ready \
  --label lane:cdx-any
```

Only issues with both labels are eligible. Missing either label means the runner
ignores the issue.

### 5. Run one lane pass by hand

For a first run, keep the wait short. For real hourly lanes, leave the default
`CLAIM_WAIT_SECONDS=60`.

```bash
export CDX_MACHINE=cdx-mini
export CLAIM_WAIT_SECONDS=10
export AGENT_COMMAND='codex exec --sandbox workspace-write --ask-for-approval never --cd "$PWD" -'
export TEST_COMMAND='bash -n scripts/runner.sh'

./scripts/runner.sh
```

What should happen:

1. The runner refreshes `main`.
2. It finds the oldest open issue with `ready` and `lane:cdx-any`.
3. It adds `lane:cdx-mini` and `claimed:cdx-mini`.
4. It waits, re-reads the issue, and proceeds only if it is still the sole owner.
5. It creates a branch like `codex/issue-12-docs-first-automation-smoke-test`.
6. It sends the issue prompt to `AGENT_COMMAND`.
7. It runs `TEST_COMMAND`.
8. It commits, pushes, and opens a PR with `Closes #<issue-number>`.

If the agent makes no changes, the runner stops and releases the claim.
If there is no claimable issue, the runner may run one small fallback audit
track instead of exiting; see "Fallback Mode" below.

### 6. Put it on an hourly schedule

Keep machine-local config out of git:

```bash
cat > .env.runner <<'EOF'
export CDX_MACHINE=cdx-mini
export AGENT_COMMAND='codex exec --sandbox workspace-write --ask-for-approval never --cd "$PWD" -'
export TEST_COMMAND='bash -n scripts/runner.sh'
EOF
```

Then schedule the loop. Cron is the smallest portable example:

```bash
mkdir -p logs
(crontab -l 2>/dev/null; printf '0 * * * * cd %s && . ./.env.runner && ./scripts/runner.sh >> logs/cdx-runner.log 2>&1\n' "$PWD") | crontab -
```

Use `launchd`, systemd timers, or your scheduler of choice if you prefer. The
important part is one clean run per machine per hour.

### 7. Turn on branch protection before real work

Do this before you let unattended lanes run overnight:

- Require PRs before merging to `main`.
- Require at least one human approval.
- Require the code review workflow once you wire the model call.
- Require the design review workflow only for frontend paths, or use a ruleset
  that handles skipped path-filtered checks correctly.
- Block force pushes to `main`.
- Restrict who can apply `ready` and `lane:*` labels.

Agents may open PRs. They should not be able to merge them.

## Runner Contract

`scripts/runner.sh` is intentionally provider-neutral.

Required env:

- `CDX_MACHINE`: stable machine ID, for example `cdx-mini`.
- `AGENT_COMMAND`: shell command that accepts the generated issue prompt on stdin.

Useful env:

- `TEST_COMMAND`: defaults to `bash -n scripts/runner.sh`. Override this with your
  real test command as soon as the repo has real code.
- `FEEDBACK_COMMAND`: defaults to `AGENT_COMMAND`. Used when an open PR in the
  machine lane has requested changes.
- `FALLBACK_MODE`: set to `off` to keep the old no-issue no-op behavior.
- `FALLBACK_COMMAND`: defaults to `AGENT_COMMAND`. Used for no-issue fallback
  audits.
- `CDX_FALLBACK_STATE_FILE`: overrides the local fallback state file path.
- `CLAIM_WAIT_SECONDS`: defaults to `60`.
- `BASE_BRANCH`: defaults to `main`.
- `BRANCH_PREFIX`: defaults to `codex/issue-`.

The runner exports `ISSUE_NUMBER`, `ISSUE_TITLE`, `ISSUE_URL`,
`ISSUE_BODY_FILE`, `ISSUE_PROMPT_FILE`, `CDX_MACHINE`, `LANE_LABEL`, and
`BRANCH_NAME` before invoking `AGENT_COMMAND`.

Before claiming a new issue, the runner checks open PRs labeled with the machine
lane. If GitHub marks one as `CHANGES_REQUESTED`, it checks out that branch,
sends the PR discussion to `FEEDBACK_COMMAND`, runs tests, commits, pushes, and
exits without taking new work. Plain comments that do not request changes still
need human judgment or a project-specific feedback policy.

## Fallback Mode

When there is no PR with requested changes and no claimable issue, the runner
runs one randomly selected fallback audit track unless `FALLBACK_MODE=off` or a
fallback cooldown is active. Normal claimable issue work always wins and clears
fallback state.

Fallback tracks are deliberately small:

- `security`
- `performance`
- `tests`

The runner sends a generated fallback prompt to `FALLBACK_COMMAND`, which
defaults to `AGENT_COMMAND`. The prompt forbids branches, PRs, commits,
implementation patches, app/API changes, DB changes, package/framework setup,
generated apps, cloud resources, production mutation, secret handling, and filler
issues. It allows at most one GitHub Issue, only for a concrete, bounded,
evidence-backed finding.

Fallback-created issues must use:

- `ready`
- `lane:cdx-any`
- exactly one of `fallback:security`, `fallback:performance`, or
  `fallback:tests`

Fallback state is stored outside tracked files by default at:

```text
${XDG_STATE_HOME:-$HOME/.local/state}/autorepo/<owner-repo>/<machine>.state
```

Use `CDX_FALLBACK_STATE_FILE` to override the path. State is repo-specific and
lane-specific by default, parsed as known key/value fields, and never sourced as
shell code. Missing or malformed state is treated as empty. The v1 state fields
are `consecutive_fallbacks`, `cooldown_until_epoch`, `last_fallback_track`, and
`last_fallback_at_epoch`.

Each successful fallback round must leave the worktree clean. The first clean
round records `consecutive_fallbacks=1`. The second consecutive clean round arms
a randomized cooldown for 4 to 6 hours. While cooldown is active, no fallback
command runs. If a fallback command leaves tracked or untracked changes, the
runner exits nonzero.

## Codex Skill

`SKILL.md` lets this repository double as a Codex skill for bootstrapping or
auditing the workflow in another repo. The skill is intentionally thin: it tells
Codex when to use this pattern, what files to read, what invariants to preserve,
and what validation to run.

If you copy this into a skill directory, copy the whole folder, not just
`SKILL.md`. The skill references `README.md`, `AGENTS.md`, `CLAUDE.md`,
`scripts/runner.sh`, `.github/workflows/`, and `docs/`.

## CI Review Gates

The workflows are valid GitHub Actions and run on GitHub-hosted `ubuntu-latest`
runners. They are placeholders by design:

- `code-review.yml` gathers the PR diff and shows where to call a review model.
- `design-review.yml` gathers the PR diff plus `docs/DESIGN.md` and shows where
  to call the design review model.

They do not use `pull_request_target`. They do not execute project code from the
PR. If you wire provider CLIs into them, keep it that way.

## Security Rules For Public Repos

These are not suggestions:

- Never commit secrets, keys, tokens, account IDs, production URLs, connection
  strings, database dumps, or local-only post drafts.
- Store runtime credentials in GitHub Secrets or local ignored files only.
- In workflows, provider keys must be referenced as `${{ secrets.NAME }}`.
- Treat `ready` plus `lane:cdx-any` as a code-execution trigger. Only trusted
  maintainers should be able to apply those labels.
- Prefer GitHub-hosted runners for public repos.
- If you use self-hosted runners, make them ephemeral and isolated. Do not give a
  long-lived runner broad cloud permissions and then point it at agent-written PRs.
- Keep branch protection on `main`. The lane opens PRs, review decides what merges.

## License

MIT. Use it, fork it, reshape it. No warranty. See [LICENSE](LICENSE).
