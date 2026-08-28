# Settings

[![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20macOS%20%7C%20WSL-blue)]()
[![Shell](https://img.shields.io/badge/shell-zsh-green)]()
[![License](https://img.shields.io/badge/license-MIT-yellow)]()

Modern dotfiles installer with animated progress display.

<div align="center">
<div><img src="https://quickstart-for-agents.vercel.app/api/header.svg?theme=claude-code&title=Install+dotfiles+from+jiunbae/settings&mascot=wave" width="100%" /></div>

```
Clone and run the dotfiles installer from https://github.com/jiunbae/settings

Quick install:  curl -LsSf https://settings.jiun.dev | bash -s -- --all
Core only:      curl -LsSf https://settings.jiun.dev | bash -s -- --core
Pick & choose:  curl -LsSf https://settings.jiun.dev | bash -s -- zsh nvim tmux tools

Post-install: exec zsh
```
<div><img src="https://quickstart-for-agents.vercel.app/api/footer.svg?theme=claude-code&project=jiunbae/settings" width="100%" /></div>
</div>

```
╔══════════════════════════════════════════════════════════════╗
║  Settings Installer                                          ║
╠══════════════════════════════════════════════════════════════╣
║ [████████████████████████████████████████░░░░░░░░░░]  80%    ║
║  [6/8] Rust toolchain                                        ║
╚══════════════════════════════════════════════════════════════╝

  ✓ Installing Rust via rustup
  ✓ Installing cargo-binstall
  ⠋ Installing eza...
```

## Quick Start

### One-Line Install (Recommended)

```bash
# Install everything
curl -LsSf https://settings.jiun.dev | bash -s -- --all

# Install specific components
curl -LsSf https://settings.jiun.dev | bash -s -- zsh nvim tmux

# Interactive selector
curl -LsSf https://settings.jiun.dev | bash -s -- --interactive
```

### Manual Clone

```bash
git clone https://github.com/jiunbae/settings.git
cd settings
./install.sh --all
```

### Presets

```bash
./install.sh              # Interactive selector (pick components in a menu)
./install.sh --all        # Install everything
./install.sh --core       # Core dev environment (base, zsh, nvim, tmux, tools)
./install.sh --basic      # Minimal (base, zsh, nvim, tmux)
```

## Features

- **Modular Architecture** - Install only what you need
- **Cross-Platform** - Linux, macOS, and WSL support
- **Progress Display** - Animated spinner with progress bar
- **Dry-Run Mode** - Preview changes before applying
- **Idempotent** - Safe to run multiple times

## Usage

```
Usage: install.sh [OPTIONS] [COMPONENTS...]

Options:
  -i, --interactive   Interactive component selector (default when no args)
  -a, --all           Install all components
  --core              Install core dev environment (base, zsh, nvim, tmux, tools)
  -b, --basic         Install basic dev environment (base, zsh, nvim, tmux)
  -f, --force         Force reinstall (overwrite existing)
  -c, --copy          Copy config files instead of symlink
  -l, --link          Create symlinks for config files (default)
  -v, --verbose       Enable verbose output
  -n, --dry-run       Show what would be done
  --no-sudo           Skip commands that require sudo privileges
  -h, --help          Show help message

Components:
  base          Basic packages (curl, wget, git, build-essential)
  zsh           Zsh + zinit + Powerlevel10k
  nvim          NeoVim + LazyVim
  tmux          tmux + TPM (terminal multiplexer)
  zellij        zellij (modern terminal multiplexer)
  rust          Rust toolchain + cargo-binstall
  uv            uv (fast Python package manager)
  tools         CLI tools (eza, fd, bat, ripgrep, fzf)
  tools-extra   Extra CLI tools (delta, dust, procs, bottom)
  ssh           SSH config (copy only, not symlinked)
  hishtory      hishtory (better shell history with sync support)
  hammerspoon   Hammerspoon (macOS-only: window manager + keybindings)
  codex         Codex CLI/App config, hooks, and notify chain
  claude        Claude Code settings, hooks, skill index, memory, MCP
  cship         cship + Starship (fast Claude Code statusline)
  scripts       Personal CLI scripts linked into ~/.local/bin
```

## Components

### Shell Environment
| Component | Description |
|-----------|-------------|
| [Zsh](https://www.zsh.org/) | Modern shell |
| [zinit](https://github.com/zdharma-continuum/zinit) | Fast plugin manager |
| [Powerlevel10k](https://github.com/romkatv/powerlevel10k) | Fast, customizable prompt |
| zsh-syntax-highlighting | Fish-like syntax highlighting |
| zsh-autosuggestions | Fish-like autosuggestions |

### Editor
| Component | Description |
|-----------|-------------|
| [NeoVim](https://neovim.io/) | Hyperextensible Vim-based editor |
| [LazyVim](https://www.lazyvim.org/) | Fast, modern Neovim setup powered by lazy.nvim |

### Terminal
| Component | Description |
|-----------|-------------|
| [tmux](https://github.com/tmux/tmux) | Terminal multiplexer (default) |
| [TPM](https://github.com/tmux-plugins/tpm) | Tmux plugin manager |
| [zellij](https://zellij.dev/) | Terminal multiplexer (alternative) |
| [Windows Terminal](https://aka.ms/terminal) | Modern terminal for Windows |

### AI Coding Agents
| Component | Description |
|-----------|-------------|
| Claude Code | `settings.json`, hooks, skill index and memory, symlinked to this repo — see [Restoring AI agent state](#restoring-ai-agent-state-on-a-new-machine) |
| Codex | `config.toml` managed half, merged over local runtime state |
| [cship](https://github.com/stephenleo/cship) | Claude Code statusline (Rust) — replaces ccstatusline: ~33ms vs ~1,250ms per render, ~18MB vs ~99MB peak RSS |
| [Starship](https://starship.rs) | Required by cship for the `$directory` / `$git_branch` / `$git_metrics` / `$custom.worktree` passthrough segments |

### Development Tools
| Component | Description |
|-----------|-------------|
| [Rust](https://www.rust-lang.org/) | Systems programming language |
| [cargo-binstall](https://github.com/cargo-bins/cargo-binstall) | Binary package installer |
| [uv](https://github.com/astral-sh/uv) | Fast Python package manager (10-100x faster than pip) |

### Modern CLI Tools

**Basic tools** (`tools`):
| Tool | Replaces | Description |
|------|----------|-------------|
| [eza](https://github.com/eza-community/eza) | `ls` | Modern ls with icons and git integration |
| [fd](https://github.com/sharkdp/fd) | `find` | Simple, fast alternative to find |
| [bat](https://github.com/sharkdp/bat) | `cat` | Cat with syntax highlighting |
| [ripgrep](https://github.com/BurntSushi/ripgrep) | `grep` | Fast regex search tool |
| [fzf](https://github.com/junegunn/fzf) | - | Fuzzy finder |

**Extra tools** (`tools-extra`):
| Tool | Replaces | Description |
|------|----------|-------------|
| [delta](https://github.com/dandavison/delta) | `git diff` | Better git diff viewer |
| [dust](https://github.com/bootandy/dust) | `du` | Intuitive disk usage |
| [procs](https://github.com/dalance/procs) | `ps` | Modern process viewer |
| [bottom](https://github.com/ClementTsang/bottom) | `htop` | System monitor |

### Shell History
| Component | Description |
|-----------|-------------|
| [hishtory](https://github.com/ddworken/hishtory) | Better shell history with context, search, and sync |

### AI Coding Tools
| Component | Description |
|-----------|-------------|
| codex | Managed Codex config template. Applies stable model/plugin/MCP/hook settings, disables legacy `~/.codex/hooks.json`, and preserves machine-local runtime sections such as project/hook trust, `notify`, TUI state, and desktop settings. |

**hishtory features:**
- Context-aware history (directory, exit code, duration)
- Fuzzy search with `Ctrl+R`
- E2E encrypted sync across machines
- Self-hosted server support

**Configuration (`~/.envs/hishtory.env`):**
```bash
# Self-hosted server (optional, local-only mode without this)
export HISHTORY_SERVER="https://hishtory.example.com"

# Secret key for cross-device sync (get from `hishtory status`)
export HISHTORY_SECRET="your-secret-key-uuid"
```

Without `HISHTORY_SERVER`, hishtory runs in local-only mode.
To sync across devices, use the same `HISHTORY_SECRET` on all machines.

### macOS Automation
| Component | Description |
|-----------|-------------|
| [Hammerspoon](https://www.hammerspoon.org/) | Lua-scriptable macOS automation (window/screen/keyboard) |

**Installs via Homebrew Cask and symlinks `~/.hammerspoon/init.lua` to this repo.**
Skipped automatically on Linux/WSL. Accessibility permission must be granted manually:
System Settings → Privacy & Security → Accessibility → enable Hammerspoon.

## Restoring AI agent state on a new machine

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

### What each agent stores, and how it is managed

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

### Symlink or copy

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

### Keeping the repo in sync

```bash
# after changing Codex settings by hand or through its UI
./scripts/codex/capture-config.sh && git diff configs/codex

# after adding or removing a nested Claude skill
python3 ~/.claude/skills/skill-index/build.py
./scripts/claude/capture-skills.sh && git diff configs/claude
```

Claude Code needs nothing — `~/.claude/settings.json` *is* the repo file.

### Deliberately not managed

| | Why |
|---|---|
| `~/.envs/*.env` | Secrets. Restore by hand; `~/.agents/*.md` documents which key each integration needs. |
| `agents/{static,<workspace>/static}` personal files | Profile, endpoints and service-specific context. They are gitignored; restore from a secure backup or fill the generated samples. |
| `~/.claude.json` | MCP registrations sit next to per-project state Claude Code rewrites constantly. The `claude` module re-adds servers instead. |
| `~/.claude/.credentials.json`, `~/.codex/auth.json` | OAuth tokens. Re-login on the new machine. |
| `~/.config/muxa/config.toml` | Carries a dashboard auth token; restore it privately after installing muxa. |
| Codex `notify` | Absolute, machine-local Oh My Prompt hook path. Create it with `omp install --cli codex`; later applies preserve it. |
| Codex project trust | Exact-path and per-machine; regenerate with the repo-installed `codex-workspace-trust-sync`. |

## Directory Structure

```
settings/
├── install.sh              # Main entry point
├── bootstrap.sh            # Remote installation bootstrap
├── lib/                    # Core libraries
│   ├── core.sh            #   Logging, spinner, utilities
│   ├── platform.sh        #   Platform detection, package manager
│   └── cli.sh             #   CLI argument parsing
├── modules/                # Installation modules
│   ├── base.sh            #   Basic packages
│   ├── shell.sh           #   Zsh + zinit + P10k
│   ├── editor.sh          #   NeoVim + LazyVim
│   ├── tmux.sh            #   tmux + TPM
│   ├── zellij.sh          #   zellij
│   ├── rust.sh            #   Rust + cargo-binstall
│   ├── python.sh          #   uv
│   ├── tools.sh           #   CLI tools
│   ├── ssh.sh             #   SSH config
│   ├── hishtory.sh        #   hishtory + self-hosted sync
│   ├── hammerspoon.sh     #   Hammerspoon (macOS-only)
│   ├── codex.sh           #   Codex CLI/App config
│   ├── claude.sh          #   Claude Code settings, skills and memory
│   ├── cship.sh           #   cship + Starship statusline
│   └── scripts.sh         #   Personal CLI scripts → ~/.local/bin
├── bin/                    # Personal CLI scripts (linked onto PATH)
│   └── subd               #   Run a command across subdirectories
├── worker/                 # Cloudflare Worker (settings.jiun.dev)
│   ├── index.js           #   Proxy raw GitHub content
│   └── wrangler.toml      #   Wrangler configuration
├── scripts/                # Build scripts
│   ├── bundle.sh          #   Create bundled installer
│   ├── claude/            #   Skill-farm capture helper
│   ├── codex/             #   Config capture/apply + trust sync
│   └── wsl2-network.ps1   #   WSL2 network setup script
├── configs/                # Configuration files
│   ├── .zshrc
│   ├── .p10k.zsh
│   ├── .tmux.conf         #   tmux configuration
│   ├── zellij/            #   zellij config + layouts
│   ├── nvim/              #   NeoVim + LazyVim config
│   ├── hishtory/          #   hishtory config template
│   ├── codex/             #   Codex managed config template
│   ├── claude/            #   Claude settings, manifest, index and memory
│   ├── cship/             #   cship + Starship configs
│   └── windows-terminal/  #   Windows Terminal configuration
└── .github/workflows/      # CI/CD
    └── release.yml         #   Auto-release on tag
```

## Platform Support

| Platform | Package Manager | Architecture |
|----------|-----------------|--------------|
| Ubuntu/Debian | apt | x86_64, arm64 |
| macOS | Homebrew | Intel, Apple Silicon |
| WSL | apt | x86_64 |

## Examples

```bash
# Preview installation (dry-run)
./install.sh --dry-run --all

# Install shell environment only
./install.sh zsh

# Install with verbose output
./install.sh -v zsh nvim tmux

# Force reinstall everything
./install.sh --force --all

# Install Rust and CLI tools
./install.sh rust tools tools-extra
```

## Post-Installation

```bash
# Restart your shell
source ~/.zshrc
# or
exec zsh

# Verify installations
eza --version
fd --version
bat --version
rg --version
```

## Shell Aliases

After installation, these aliases are configured in `.zshrc`:

```bash
# Modern replacements
alias ls='eza --icons'
alias ll='eza -la --icons --git'
alias cat='bat'
alias find='fd'
alias grep='rg'
alias du='dust'
alias ps='procs'
alias top='btm'

# Zellij (terminal multiplexer)
alias zs='zellij -s'        # new session
alias za='zellij attach'    # attach
alias zl='zellij list-sessions'  # list


# Editor
alias vim='nvim'
alias vi='nvim'
```

## Windows Terminal Configuration

Configuration for Windows Terminal is available in `configs/windows-terminal/settings.json`.

### How to apply

1. Open Windows Terminal
2. Press `Ctrl + ,` to open Settings
3. Click **Open JSON file** at the bottom of the left sidebar
4. Copy the contents of `configs/windows-terminal/settings.json` and paste them into your `settings.json`

> [!TIP]
> This configuration uses **JetBrainsMonoNL Nerd Font**. Make sure it's installed on your Windows system for the best experience.

## Troubleshooting

**View installation log:**
```bash
cat ~/.install.log
```

**Force reinstall a component:**
```bash
./install.sh --force zsh
```

**Run in verbose mode:**
```bash
./install.sh --verbose --all
```

## License

MIT
