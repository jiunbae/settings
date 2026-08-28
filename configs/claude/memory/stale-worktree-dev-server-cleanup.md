---
name: stale-worktree-dev-server-cleanup
description: "Safe procedure for reclaiming dev-container memory from stale worktree stacks and leaked MCP browsers"
metadata:
  node_type: memory
  type: project
---

The dev container can fill up because per-worktree stacks and MCP browsers accumulate without cleanup. Safe cleanup procedure:

1. **Stale dev servers** — inspect each process's own `etime`, confirm that its worktree is no longer active, and send SIGTERM before considering stronger signals.
2. **MCP browsers** — identify browser trees owned by inactive MCP sessions. They can be relaunched on the next tool call, but confirm that no active debugging session depends on them before termination.

**Why:** there is no auto-teardown when a ticket/session ends, so memory climbs toward the container's cgroup limit over ~days.

**How to apply:** confirm scope with the user before killing anything because live work can be lost. Do not terminate login shells indiscriminately; doing so can drop active tmux, SSH, or agent sessions. Measure success via `/sys/fs/cgroup/memory.current`, not `free`. See [[dev-container-memory-topology]].
