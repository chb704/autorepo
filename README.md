# autorepo - the Summer 2026 skeleton

A clone-and-go monorepo skeleton for the agentic development workflow I describe in
**[How I Code: Summer 2026 Edition](https://chrisboyd.me)**.

If you landed here from the post: this is the "core monorepo you can clone and use to keep
things simple." Fork it, gut what you don't need, and make it yours.

More of my writing lives at **[chrisboyd.me](https://chrisboyd.me)**.

> **Heads up:** this is a *skeleton*, not a turnkey product. It's the shape of a workflow,
> meant to be read and adapted - not cloned and pointed at production on day one. Read the
> [Guardrails](#guardrails-read-this-before-you-automate-anything) section before you wire
> any of it up to real infrastructure.

---

## The idea in one paragraph

You're not the coder anymore - you're the operator. You plan in PRDs, turn PRDs into
agent-sized GitHub Issues, and let an hourly automation loop on a few cheap machines pick up
labeled issues, write the code, and open PRs. Quality gates (a frontend Design Review, tests,
and a cross-provider code review) keep the slop out. You review on your own schedule. The repo
below is the substrate that makes that loop boring and repeatable.

## Structure

```
autorepo/
├── docs/
│   ├── planning/          # PRDs live here - one Markdown file per feature
│   └── DESIGN.md           # the standard the frontend Design Review grades against
├── apps/                   # your actual applications
├── packages/               # shared libraries
├── infra/                  # CDK stacks - nothing deploys by hand
├── scripts/
│   └── runner.sh           # the per-machine automation runner (claims an issue, runs the agent)
├── .github/
│   └── workflows/
│       ├── design-review.yml   # Opus + DESIGN.md gate on frontend PRs
│       └── code-review.yml      # automated cross-provider PR review
├── AGENTS.md               # instructions Codex reads
└── CLAUDE.md               # instructions Claude Code reads
```

> The tree above is the target layout. The repo ships as a skeleton - directories and stub
> files you fill in for your own project.

## Quickstart

```bash
git clone https://github.com/chb704/autorepo.git
cd autorepo
# 1. Drop a first PRD into docs/planning/
# 2. Describe how "good" looks in docs/DESIGN.md
# 3. Wire scripts/runner.sh into a scheduled automation on each machine
# 4. Turn on branch protection BEFORE you let anything run (see Guardrails)
```

The full walkthrough - planning with Plan Mode, the letter-grade PRD trick, agent-sized
issues, lanes, the hourly loop, and the Design Review gate - is in the
[blog post](https://chrisboyd.me).

## The labels

Automation only touches issues carrying both:

- `ready` - you're done noodling on it; it's safe to pick up.
- `lane:cdx-any` - any machine may claim it. (Pin work to a specific machine with a named
  lane, e.g. `lane:cdx-mini`.)

Anything missing either label is invisible to the automation and safely ignored.

## Guardrails (read this before you automate anything)

Letting agents open PRs against your repo is only as safe as the rails around it. This
skeleton assumes - and you should not remove - the following:

- **Branch protection on `main`.** Required status checks + a review before merge. Agents
  open PRs; they do **not** get to merge on their own authority. Turn this on first.
- **Label as a trust boundary.** On a private solo repo, fine. The moment the repo is open,
  `ready` + `lane:cdx-any` is a code-execution trigger - anyone who can apply those labels can
  make your CI run their code. Scope who can label.
- **Isolated runners.** If you use self-hosted GitHub runners, make them ephemeral, give them
  tightly scoped permissions, and never point a long-lived runner with broad cloud access at
  agent-written PR code. That's how you get popped.
- **No secrets in the repo.** No credentials, no real account IDs, no production connection
  strings. This skeleton ships with none - keep it that way.

## License

MIT. Personal project - use it, fork it, break it, no warranty. See [LICENSE](LICENSE).
