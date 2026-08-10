# Memory Index

- [Dev container memory topology](dev-container-memory-topology.md) — june runs in a `--pid=host` container; real limit is the 112GB cgroup, not host `free`.
- [Stale worktree dev-server cleanup](stale-worktree-dev-server-cleanup.md) — safe steps to reclaim memory (kill 3day+ worktree stacks, chrome-devtools-mcp browsers).
- [Agent shell missing API keys](agent-shell-missing-api-keys.md) — source `~/.envs/<integration>.env` before linear-issue.sh / Sentry calls.
- [linear-issue.sh --labels](linear-issue-labels-query-too-complex.md) — old "Query too complex" failure is fixed (2026-08-05); use the helper, GraphQL fallback only if it returns.
- [linear-issue.sh get by identifier](linear-issue-get-identifier-broken.md) — issueSearch breakage is fixed (2026-08-05); if it returns, "이슈를 찾을 수 없습니다" ≠ 이슈 없음.
