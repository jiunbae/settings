# Settings

[![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20macOS%20%7C%20WSL-blue)]()
[![Shell](https://img.shields.io/badge/shell-zsh-green)]()
[![License](https://img.shields.io/badge/license-MIT-yellow)]()

Modern dotfiles installer with animated progress display.

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
# Install everything with a single command
curl -fsSL https://raw.githubusercontent.com/jiunbae/settings/master/bootstrap.sh | bash -s -- --all

# Or install specific components
curl -fsSL https://raw.githubusercontent.com/jiunbae/settings/master/bootstrap.sh | bash -s -- zsh nvim tmux
```

### Using Release (Bundled Installer)

```bash
# Download and run the bundled installer (no git required)
curl -fsSL https://github.com/jiunbae/settings/releases/latest/download/install-bundled.sh | bash -s -- --all
```

### Manual Clone

```bash
# Clone and install everything
git clone https://github.com/jiunbae/settings.git
cd settings
./install.sh --all

# Or install specific components
./install.sh zsh nvim tmux rust tools
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
  -a, --all           Install all components
  -f, --force         Force reinstall (overwrite existing)
  -v, --verbose       Enable verbose output
  -n, --dry-run       Show what would be done
  -h, --help          Show help message

Components:
  base          Basic packages (curl, wget, git, build-essential)
  zsh           Zsh + zinit + Powerlevel10k
  nvim          NeoVim + SpaceVim
  tmux          tmux + TPM (Tmux Plugin Manager)
  rust          Rust toolchain + cargo-binstall
  uv            uv (fast Python package manager)
  tools         CLI tools (eza, fd, bat, ripgrep, fzf)
  tools-extra   Extra CLI tools (delta, dust, procs, bottom)
  ssh           SSH config (copy only, not symlinked)
  hishtory      hishtory (better shell history with sync support)
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
| [tmux](https://github.com/tmux/tmux) | Terminal multiplexer |
| [TPM](https://github.com/tmux-plugins/tpm) | Tmux Plugin Manager |

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
│   ├── rust.sh            #   Rust + cargo-binstall
│   ├── python.sh          #   uv
│   ├── tools.sh           #   CLI tools
│   ├── ssh.sh             #   SSH config
│   └── hishtory.sh        #   hishtory + self-hosted sync
├── scripts/                # Build scripts
│   ├── bundle.sh          #   Create bundled installer
│   └── wsl2-network.ps1   #   WSL2 network setup script
├── configs/                # Configuration files
│   ├── .zshrc
│   ├── .p10k.zsh
│   ├── .tmux.conf
│   ├── nvim/              #   NeoVim + LazyVim config
│   └── hishtory/          #   hishtory config template
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

# Editor
alias vim='nvim'
alias vi='nvim'
```

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
