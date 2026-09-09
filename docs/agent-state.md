<!-- Moved out of README.md; linked from its Documentation section. -->

# Restoring AI agent state on a new machine

Claude Code and Codex keep their configuration in different shapes, so this repo
manages them differently. Follow the order below — step 2 must happen before
step 3, because `configs/claude/settings.json` references hook scripts that live
in the agent-skills repo.

```bash
# 1. this repo
git clone git@github.com:jiunbae/settings.git ~/personal/settings

# 2. hook scripts referenced by Claude settings.json
git clone git@github.com:jiunbae/agent-skills.git ~/personal/agent-skills

# 3. shared skill/static-doc repo, then lay down ~/.agents/
# private shared-skill repo — substitute your own remote
git clone <private-agents-repo> ~/workspace/agents
~/workspace/agents/scripts/install-static.sh
~/workspace/agents/scripts/install-shims.sh

# 4. external runtimes used by the managed hooks (examples)
#    Install and log in to Claude Code and Codex through their official installers.
brew install open330/tap/muxa             # or follow muxa's platform instructions
npm install -g oh-my-prompt               # provides omp

# 5. agents + statusline
cd ~/personal/settings
./install.sh claude cship codex

# Restore Oh My Prompt's Codex notify entry after its own setup. Later Codex
# config applies preserve this machine-local absolute command.
omp install --cli codex

# 6. private state — never in git
#    - ~/.envs/*.env
#    - ~/.config/muxa/config.toml
#    - the gitignored personal files created from agents/*/*.sample.{md,yaml}
#      (restore from a secure backup or replace every {{PLACEHOLDER}})
#    - re-login instead of copying Claude/Codex credential files

# 7. Codex directory trust is exact-path based and per-machine. The codex
#    component installs this helper from scripts/codex/workspace-trust-sync.sh.
~/.local/bin/codex-workspace-trust-sync
```

The three Git clones restore versioned configuration and scripts. They cannot
restore credentials, dashboard tokens, or the personalized `agents/static` and
`agents/<workspace>/static` files because those are deliberately gitignored. A
matching file count under `~/.agents` is therefore only a topology check; verify
the contents and resolve the install-static placeholder warning before use.

> [!WARNING]
> These are personal settings for trusted workspaces. The managed Codex config
> uses `approval_policy = "never"` with `sandbox_mode = "danger-full-access"`,
> and Claude settings skip the dangerous-mode confirmation. Do not install them
> unchanged on an untrusted repository or shared machine. The configured muxa,
> Oh My Prompt, and prompt-logger hooks also receive agent lifecycle events or
> prompt content; review those local tools and their storage policies first.

## What each agent stores, and how it is managed

| Agent | State | Managed as |
|---|---|---|
| Claude Code | `~/.claude/settings.json` | **symlink** → `configs/claude/settings.json` |
| Claude Code | `~/.claude/hooks/*.sh` | **symlink** → `agent-skills/hooks/` |
| Claude Code | `~/.claude/skills/skill-index` | **symlink** → `configs/claude/skill-index` |
| Claude Code | `~/.claude/skills/<category>/<name>` | symlinks rebuilt from `configs/claude/skills.manifest` (public skills only; private ones are restored from their own repo) |
| Claude Code | `~/.claude/projects/<slug>/memory` | **symlink** → `configs/claude/memory` |
| Claude Code | MCP servers | `claude mcp add` (idempotent, run by the module) |
| Codex | `~/.codex/config.toml` | **merge** — managed plugins/MCP/hooks + local trust, notify and UI state |
| Codex | `~/.local/bin/codex-workspace-trust-sync` | symlink/copy from this repo; regenerates exact-path project trust |
| Both | statusline | `cship` module (binaries + `~/.config/{cship,starship}.toml` symlinks) |

**Why Claude Code is symlinked but Codex is not.** Claude Code never rewrites
`settings.json` — a full session and the `/config` UI both left the symlink and
its target untouched, so the repo copy can be the real file. Codex writes into
its config continuously: 137 project-trust entries and 18 hook trust hashes on
this machine. Symlinking it would drag that churn into git, so
`scripts/codex/apply-config.sh` layers the managed half over whatever the local
machine already has instead.

`configs/claude/settings.json` uses `$HOME/...` rather than absolute paths.
Hook commands and `statusLine.command` are run through a shell, so the expansion
happens at run time and the file works under any username. Codex does **not**
expand `$HOME` in TOML values, which is why its per-machine paths are excluded
from the template rather than rewritten.

## Symlink or copy

Symlink is the default and the reason drift cannot happen: `~/.claude/settings.json`
*is* `configs/claude/settings.json`, so editing one edits the other. The cost is
that the live config depends on the repo staying checked out at a branch that
contains it.

`--copy` installs real files and directories instead, including all 46 nested
skills, for machines where that dependency is unwanted:

```bash
./install.sh -c claude cship        # copy instead of symlink
```

Copy mode is idempotent — a second run compares contents and reports
"already up to date" rather than re-copying. The trade-off is that local edits
no longer flow back, so after changing a copied config you have to bring it
into the repo by hand.

The self-extracting release bundle always forces copy mode because its temporary
extraction directory is removed as soon as installation finishes.

No template engine sits in between: after excluding per-machine runtime state,
zero managed values need substitution. `configs/claude/settings.json` and both
cship configs contain no absolute paths at all, and Codex's template contains
none either now that project trust, hook hashes and the version-pinned
`[[skills.config]]` path are captured out.

## Keeping the repo in sync

```bash
# after changing Codex settings by hand or through its UI
./scripts/codex/capture-config.sh && git diff configs/codex

# after adding or removing a nested Claude skill
python3 ~/.claude/skills/skill-index/build.py
./scripts/claude/capture-skills.sh && git diff configs/claude
```

Claude Code needs nothing — `~/.claude/settings.json` *is* the repo file.

## Deliberately not managed

| | Why |
|---|---|
| `~/.envs/*.env` | Secrets. Restore by hand; `~/.agents/*.md` documents which key each integration needs. |
| `agents/{static,<workspace>/static}` personal files | Profile, endpoints and service-specific context. They are gitignored; restore from a secure backup or fill the generated samples. |
| `~/.claude.json` | MCP registrations sit next to per-project state Claude Code rewrites constantly. The `claude` module re-adds servers instead. |
| `~/.claude/.credentials.json`, `~/.codex/auth.json` | OAuth tokens. Re-login on the new machine. |
| `~/.config/muxa/config.toml` | Carries a dashboard auth token; restore it privately after installing muxa. |
| Codex `notify` | Absolute, machine-local Oh My Prompt hook path. Create it with `omp install --cli codex`; later applies preserve it. |
| Codex project trust | Exact-path and per-machine; regenerate with the repo-installed `codex-workspace-trust-sync`. |
