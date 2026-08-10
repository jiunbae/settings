---
name: stale-worktree-dev-server-cleanup
description: "Safe procedure for reclaiming memory in june's dev container by killing stale per-worktree dev stacks and leaked chrome-devtools-mcp browsers"
metadata: 
  node_type: memory
  type: project
  originSessionId: ace8b4d9-f66e-4541-85d3-061ce5e20ed4
---

june's dev container fills up because per-worktree dev stacks and MCP browsers accumulate without cleanup. Proven safe cleanup steps (used 2026-05-29, freed ~21GB):

1. **Stale dev servers** — under `~/workspace-agent/<ticket>/callabo-webapp` (next-server, ~2.8GB) and `.../callabo-server` (python, ~1.3GB × 2). Identify each process's own `etime`; kill those running ≥3 days (finished tickets). SIGTERM is enough; their bash/npm launcher parents are tiny and harmless if left.
2. **chrome-devtools-mcp** — `npm exec chrome-devtools-mcp@latest` spawns one headless Chrome per session (comm `chrome-devtools` ~80-180MB + child `chrome` subprocs). They leak one-per-session; safe to kill ALL (the MCP server relaunches on next tool call). Killing them cascades and also reaps parent node/npm/sh wrappers.

**Why:** there is no auto-teardown when a ticket/session ends, so memory climbs toward the 112GB cgroup limit over ~days.

**How to apply:** confirm scope with the user before killing (these are live dev servers / sessions — work can be lost). Don't touch the 270+ zsh login shells in the container — they're only ~1.5GB and killing them can drop active tmux/SSH/agent sessions. The biggest remaining lever after servers is old `claude` sessions (e.g. a 10-day-old one was 3.7GB). Measure success via `/sys/fs/cgroup/memory.current`, not `free`. See [[dev-container-memory-topology]].
