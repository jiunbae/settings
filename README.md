# Settings

[![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20macOS%20%7C%20Windows%20%7C%20WSL-blue)]()
[![Shell](https://img.shields.io/badge/shell-zsh%20%7C%20pwsh-green)]()
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

```bash
# everything
curl -LsSf https://settings.jiun.dev | bash -s -- --all

# pick components
curl -LsSf https://settings.jiun.dev | bash -s -- zsh nvim tmux

# choose from a menu
curl -LsSf https://settings.jiun.dev | bash -s -- --interactive
```

Or clone it first:

```bash
git clone https://github.com/jiunbae/settings.git && cd settings
./install.sh --all
```

| Preset | Installs |
| :--- | :--- |
| `--all` | everything |
| `--core` | base, zsh, nvim, tmux, tools |
| `--basic` | base, zsh, nvim, tmux |
| *(no args)* | interactive selector |

## What's inside

| Area | Components |
| :--- | :--- |
| **Shell** | [zsh](https://www.zsh.org/) + [zinit](https://github.com/zdharma-continuum/zinit) + [Powerlevel10k](https://github.com/romkatv/powerlevel10k), with [autosuggestions](https://github.com/zsh-users/zsh-autosuggestions) and [fast-syntax-highlighting](https://github.com/z-shell/fast-syntax-highlighting) · PowerShell 7 + [starship](https://starship.rs/) + [PSFzf](https://github.com/kelleyma49/PSFzf) on Windows |
| **Editor** | [NeoVim](https://neovim.io/) + [LazyVim](https://www.lazyvim.org/), with the [tree-sitter CLI](https://github.com/tree-sitter/tree-sitter) for parsers |
| **Multiplexer** | [tmux](https://github.com/tmux/tmux) + [TPM](https://github.com/tmux-plugins/tpm) · [zellij](https://zellij.dev/) · [rmux](https://github.com/Helvesec/rmux) on Windows |
| **CLI tools** | [eza](https://github.com/eza-community/eza) `ls` · [fd](https://github.com/sharkdp/fd) `find` · [bat](https://github.com/sharkdp/bat) `cat` · [ripgrep](https://github.com/BurntSushi/ripgrep) `grep` · [fzf](https://github.com/junegunn/fzf) |
| **CLI extras** | [delta](https://github.com/dandavison/delta) `git diff` · [dust](https://github.com/bootandy/dust) `du` · [procs](https://github.com/dalance/procs) `ps` · [bottom](https://github.com/ClementTsang/bottom) `htop` |
| **Toolchains** | [Rust](https://www.rust-lang.org/) + [cargo-binstall](https://github.com/cargo-bins/cargo-binstall) · [uv](https://github.com/astral-sh/uv) · [fnm](https://github.com/Schniz/fnm) |
| **AI agents** | Claude Code · Codex · [cship](https://github.com/stephenleo/cship) statusline — see [agent-state.md](docs/agent-state.md) |
| **History** | [hishtory](https://github.com/ddworken/hishtory) — context, search, cross-device sync |
| **macOS** | [Hammerspoon](https://www.hammerspoon.org/) — window, screen and keyboard automation |

Every component is independent, safe to re-run, and has a `--dry-run`.

## Platform Support

| Platform | Package manager | Architecture | Installer |
| :--- | :--- | :--- | :--- |
| Ubuntu/Debian | apt | x86_64, arm64 | `install.sh` |
| macOS | Homebrew | Intel, Apple Silicon | `install.sh` |
| WSL | apt | x86_64 | `install.sh` |
| Windows | winget | x86_64 | manual — [windows.md](docs/windows.md) |

> [!NOTE]
> `install.sh` does not run on Windows: `lib/platform.sh` `detect_platform` exits on
> anything that is not Linux or Darwin. Windows configs live in `configs/` and are
> placed by hand, following the same pattern as `configs/windows-terminal/`.

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

```bash
./install.sh --dry-run --all       # preview, change nothing
./install.sh -v zsh                # one component, verbose
./install.sh --force zsh           # reinstall over an existing setup
cat ~/.install.log                 # what actually happened
```

## After installing

```bash
exec zsh                           # or: source ~/.zshrc
eza --version && rg --version      # sanity check
```

The aliases come from `configs/.zshrc`: `ls`/`ll`/`la`/`lt` → eza, `find` → fd,
`grep` → rg, `du` → dust, `ps` → procs, `top`/`htop` → btm, `vim`/`vi` → nvim, and
`zs`/`za`/`zl` for zellij sessions. The PowerShell profile mirrors these, except that
the ones shadowing an existing command stay interactive-only — see
[windows.md](docs/windows.md#powershell).

## Repo layout

```text
settings/
├── install.sh              # Main installer
├── bootstrap.sh            # One-line installer (also published to gh-pages)
├── lib/                    # Shared: cli, core, platform
├── modules/                # One file per component
├── configs/                # The dotfiles themselves
│   ├── .zshrc .p10k.zsh .tmux.conf .rmux.conf
│   ├── nvim/ zellij/ powershell/ windows-terminal/
│   └── claude/ codex/ cship/ hishtory/
├── bin/                    # Personal CLI scripts, linked onto PATH
│   └── windows/            #   Windows-only; install.sh never sees this dir
├── scripts/                # Build and maintenance helpers
├── docs/                   # The guides linked below
├── .gitea/workflows/       # Releases run on the self-hosted Gitea runner
└── worker/                 # Cloudflare Worker — written, never deployed
```

## Documentation

| | |
| :--- | :--- |
| [components.md](docs/components.md) | hishtory sync, Hammerspoon permissions, the managed Codex config |
| [windows.md](docs/windows.md) | rmux, PowerShell, NeoVim, Windows Terminal, Nextcloud upload |
| [powershell.md](docs/powershell.md) | How the PowerShell profile went from 1354ms to 394ms |
| [agent-state.md](docs/agent-state.md) | Restoring Claude Code / Codex state on a new machine |
| [tmux-to-zellij.md](docs/tmux-to-zellij.md) | Migration notes |

## Maintaining this repo

`settings.jiun.dev` is **GitHub Pages from the `gh-pages` branch**, not the Worker in
`worker/` — that was written but never deployed. `gh-pages` carries its own copy of
`bootstrap.sh`, duplicated as `index.html` so the pathless one-liner works, and nothing
syncs it automatically.

> [!IMPORTANT]
> After changing `bootstrap.sh`, run `scripts/sync-gh-pages.sh --push`. The copy once
> went stale for five months — long enough that the published installer was missing the
> guard that refuses to `git reset --hard` over uncommitted local changes.

## License

MIT
