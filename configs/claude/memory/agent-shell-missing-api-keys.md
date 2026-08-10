---
name: agent-shell-missing-api-keys
description: Agent Bash shells lack LINEAR_API_KEY/SENTRY_AUTH_TOKEN; source the matching ~/.envs/*.env file first.
metadata: 
  node_type: memory
  type: project
  originSessionId: 3934318d-55e9-4d62-a0ec-6dbcd6bad8c1
  modified: 2026-07-27T17:05:28.943Z
---

Agent-spawned Bash shells do NOT inherit june's integration API keys — `linear-issue.sh` fails with "LINEAR_API_KEY 환경변수가 설정되지 않았습니다" and Sentry curls 401. The keys live in per-integration files under `~/.envs/` (`linear.env`, `sentry.env`, `kibana.env`, `github.env`, `metabase.env`, …), and nothing in `.bashrc`/`.zshenv` sources them.

**Why:** the shell is non-login/non-interactive, so whatever normally loads `~/.envs/` never runs.

**How to apply:** prefix the command in the same Bash call, e.g.
`set -a; . /home/june/.envs/linear.env; set +a; linear-issue.sh get CAL-1234 --json`.
Do not report an integration as unavailable before trying this. See [[linear-issue-labels-query-too-complex]].
