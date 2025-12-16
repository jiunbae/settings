# Settings

Modern dotfiles installer for [Jiun](https://github.com/jiunbae)

Supports **Linux**, **macOS**, and **WSL** with a clean, modular architecture.

## Quick Start

```bash
# Clone the repository
git clone https://github.com/jiunbae/settings.git
cd settings

# Install everything
./install.sh --all

# Or install specific components
./install.sh zsh nvim tmux
```

## Usage

```bash
Usage: install.sh [OPTIONS] [COMPONENTS...]

Options:
  -a, --all           Install all components
  -f, --force         Force reinstall (overwrite existing)
  -v, --verbose       Enable verbose output
  -n, --dry-run       Show what would be done without making changes
  -h, --help          Show help message
  --version           Show version

Components:
  base                Basic packages (curl, wget, git, build-essential)
  zsh                 Zsh + Oh-My-Zsh + Powerlevel10k
  nvim                NeoVim + SpaceVim
  tmux                tmux + TPM (Tmux Plugin Manager)
  rust                Rust toolchain + cargo-binstall
  uv                  uv (fast Python package manager)
  tools               CLI tools (eza, fd, bat, ripgrep, fzf)
  tools-extra         Extra CLI tools (delta, dust, procs, bottom)
```

## Examples

```bash
# Preview what would be installed (dry-run)
./install.sh -n --all

# Install shell environment only
./install.sh zsh

# Install with verbose output
./install.sh -v zsh nvim tmux

# Force reinstall (overwrite existing configs)
./install.sh -f --all
```

## Components

### Shell (zsh)
- **Zsh** - Modern shell
- **Oh-My-Zsh** - Zsh framework
- **Powerlevel10k** - Fast, customizable theme
- **Plugins**: zsh-syntax-highlighting, zsh-autosuggestions, git-extra-commands

### Editor (nvim)
- **NeoVim** - Hyperextensible Vim-based editor
- **SpaceVim** - Community-driven modular vim distribution

### Terminal Multiplexer (tmux)
- **tmux** - Terminal multiplexer
- **TPM** - Tmux Plugin Manager

### Rust (rust)
- **rustup** - Rust toolchain installer
- **cargo-binstall** - Binary package installer for Cargo

### Python (uv)
- **uv** - Extremely fast Python package manager (10-100x faster than pip)

### CLI Tools (tools)
| Tool | Replaces | Description |
|------|----------|-------------|
| eza | ls | Modern ls with icons and git integration |
| fd | find | Simple, fast alternative to find |
| bat | cat | Cat clone with syntax highlighting |
| ripgrep | grep | Fast regex search tool |
| fzf | - | Fuzzy finder |

### Extra CLI Tools (tools-extra)
| Tool | Replaces | Description |
|------|----------|-------------|
| delta | git diff | Better git diff viewer |
| dust | du | Intuitive disk usage tool |
| procs | ps | Modern replacement for ps |
| bottom | htop | Cross-platform graphical process/system monitor |

## Directory Structure

```
settings/
├── install.sh           # Main entry point
├── lib/                  # Core libraries
│   ├── core.sh          # Logging, error handling, utilities
│   ├── platform.sh      # Platform detection, package manager
│   └── cli.sh           # CLI argument parsing
├── modules/              # Installation modules
│   ├── base.sh          # Basic packages
│   ├── shell.sh         # Zsh + Oh-My-Zsh + P10k
│   ├── editor.sh        # NeoVim + SpaceVim
│   ├── tmux.sh          # tmux + TPM
│   ├── rust.sh          # Rust toolchain
│   ├── python.sh        # uv
│   └── tools.sh         # CLI tools
├── configs/              # Configuration files
│   ├── .zshrc
│   ├── .p10k.zsh
│   ├── .tmux.conf
│   └── .SpaceVim.d/
└── README.md
```

## Platform Support

| Platform | Package Manager | Status |
|----------|-----------------|--------|
| Linux (Ubuntu/Debian) | apt | Fully supported |
| macOS (Intel/Apple Silicon) | brew | Fully supported |
| WSL | apt | Fully supported |

## Post-Installation

After installation, restart your shell:

```bash
source ~/.zshrc
# or
exec zsh
```

## Troubleshooting

### Log File
Installation logs are saved to `~/.install.log`

### Force Reinstall
If you encounter issues, try force reinstalling:
```bash
./install.sh -f <component>
```

## License

MIT
