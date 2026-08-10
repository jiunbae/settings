---
name: dev-container-memory-topology
description: "How to measure memory in a dev container with a shared host PID namespace and its own cgroup limit"
metadata:
  node_type: memory
  type: reference
---

The development environment can run in a container with `--pid=host`: `ps` and `/proc` show host-wide processes, while the container still has its own cgroup memory budget.

Consequences when investigating "high memory usage":
- `free -h` reads host-wide `/proc/meminfo`, so it is not the source of truth for the container.
- Read `/sys/fs/cgroup/memory.max`, `memory.current`, `memory.peak`, and `memory.stat` for the actual limit and usage.
- Use `/proc/PID/cgroup` to distinguish processes in the dev container from host or sibling-container processes before acting on them.
- If `ps` is aliased, use `/bin/ps` for standard flags. In zsh, remember that unquoted variables do not word-split; use `${=VAR}` only when deliberate splitting is required.

Recurring growth usually comes from per-worktree development stacks, one headless browser tree per MCP session, and long-lived agent sessions that are never torn down. See [[stale-worktree-dev-server-cleanup]].
