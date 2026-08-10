---
name: dev-container-memory-topology
description: "How to correctly measure memory in june's dev environment (it's a container with --pid=host; real limit is the 112GB cgroup, not the host)"
metadata: 
  node_type: memory
  type: reference
  originSessionId: ace8b4d9-f66e-4541-85d3-061ce5e20ed4
---

june works inside a container with hostname `june.rtzr.ai` that runs with `--pid=host` (shares the host PID namespace → `ps`/`/proc` show ALL host processes incl. other tenants like vllm uid 1038, java uid 2000, dockerd) but has its OWN cgroup namespace.

Consequences when investigating "high memory usage":
- `free -h` reads the host (`/proc/meminfo` is not namespaced) → shows host total (~125GB) and host-wide usage incl. other tenants. **This is misleading for june.** 
- The real budget is the container's cgroup: read `/sys/fs/cgroup/memory.max` (= **112 GB** hard limit, OOM-kills above it), `memory.current` (actual usage), `memory.peak`, and `memory.stat` (anon = non-reclaimable process mem; file = reclaimable page cache).
- Container PID 1 appears as host `systemd`; our cgroup shows `0::/`; host processes show `0::/../..` paths. To tell which container a june PID lives in, read `/proc/PID/cgroup` — `0::/` = this dev container (where ~632/639 of june's procs live), other paths = app containers (rtelier=`fedfab8c3ead`, callabo-deploy-board=`c7d0abf37ea3`).
- `ps` is aliased to `procs` (Rust); use `/bin/ps` for standard flags. zsh does NOT word-split unquoted vars — use `${=VAR}` in `for` loops or kills silently no-op.

Root cause of memory growth (recurring): each git worktree under `~/workspace-agent/*` spins up a full dev stack (next-server ~2.8GB + python ~1.3GB) that is never torn down; plus `chrome-devtools-mcp` headless Chrome (one per session) and many long-lived `claude` sessions accumulate. On 2026-05-29 the container had peaked at 93.9GB/112GB (84%, near OOM); killing 3-day+ stale worktree servers and all chrome-devtools-mcp browsers freed ~21GB (down to 62GB). See [[stale-worktree-dev-server-cleanup]].
