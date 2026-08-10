---
name: agent-shell-missing-api-keys
description: Agent Bash shells lack LINEAR_API_KEY/SENTRY_AUTH_TOKEN; source the matching ~/.envs/*.env file first.
metadata:
  node_type: memory
  type: project
  modified: 2026-07-27T17:05:28.943Z
---

Agent-spawned Bash shells do NOT automatically inherit integration API keys — helpers fail with a missing-variable error or HTTP 401. The keys live in per-integration files under `~/.envs/`, and nothing in `.bashrc`/`.zshenv` sources them.

**Why:** the shell is non-login/non-interactive, so whatever normally loads `~/.envs/` never runs.

**How to apply:** prefix the command in the same Bash call, e.g.
`set -a; . "$HOME/.envs/linear.env"; set +a; linear-issue.sh get <ISSUE-ID> --json`.
Do not report an integration as unavailable before trying this. See [[linear-issue-labels-query-too-complex]].
