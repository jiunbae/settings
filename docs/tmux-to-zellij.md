# tmux → zellij Migration Guide

## Why zellij?

- Built-in layout system (KDL files) — no plugin needed
- WebAssembly plugin ecosystem
- Floating panes and stacked layouts
- Session manager UI (`Ctrl o` + `w`)
- First-class mouse support

## Installation

```bash
# Using the installer
curl -LsSf https://settings.jiun.dev | bash -s -- zellij

# Or manually
brew install zellij          # macOS
cargo install zellij         # Linux (via Rust)
cargo binstall zellij        # Linux (binary, faster)
```

## Concept Mapping

| tmux | zellij | Notes |
|------|--------|-------|
| Session | Session | Same concept |
| Window | Tab | `Ctrl t` to manage |
| Pane | Pane | `Ctrl p` to manage |
| Prefix key (`Ctrl b`) | Mode system | `Ctrl b` enters tmux mode |
| `.tmux.conf` | `config.kdl` | `~/.config/zellij/config.kdl` |
| — | Layout files | `~/.config/zellij/layouts/*.kdl` |

## Keybinding Comparison

### Pane Navigation

| Action | tmux | zellij |
|--------|------|--------|
| Move left | `Ctrl b` + `h` / `←` | `Alt h` / `Alt ←` |
| Move down | `Ctrl b` + `j` / `↓` | `Alt j` / `Alt ↓` |
| Move up | `Ctrl b` + `k` / `↑` | `Alt k` / `Alt ↑` |
| Move right | `Ctrl b` + `l` / `→` | `Alt l` / `Alt →` |
| Split horizontal | `Ctrl b` + `"` | `Ctrl p` + `d` |
| Split vertical | `Ctrl b` + `%` | `Ctrl p` + `r` |
| Close pane | `Ctrl b` + `x` | `Ctrl p` + `x` |
| Fullscreen toggle | `Ctrl b` + `z` | `Alt f` |
| New pane | — | `Alt n` |
| Floating pane | — | `Alt w` |

### Tab (Window) Management

| Action | tmux | zellij |
|--------|------|--------|
| New tab | `Ctrl b` + `c` | `Ctrl t` + `n` |
| Next tab | `Ctrl b` + `n` | `Ctrl t` + `l` / `→` |
| Prev tab | `Ctrl b` + `p` | `Ctrl t` + `h` / `←` |
| Go to tab N | `Ctrl b` + `N` | `Ctrl t` + `N` |
| Rename tab | `Ctrl b` + `,` | `Ctrl t` + `r` |
| Close tab | `Ctrl b` + `&` | `Ctrl t` + `x` |

### Session Management

| Action | tmux | zellij |
|--------|------|--------|
| New session | `tmux new -s name` | `zellij -s name` |
| Attach | `tmux attach -t name` | `zellij attach name` |
| Detach | `Ctrl b` + `d` | `Ctrl o` + `d` |
| List sessions | `tmux ls` | `zellij ls` |
| Kill session | `tmux kill-session -t name` | `zellij delete-session name` |
| Session manager | — | `Ctrl o` + `w` |

### Other

| Action | tmux | zellij |
|--------|------|--------|
| Scroll mode | `Ctrl b` + `[` | `Ctrl s` |
| Search in scroll | `/` (in copy mode) | `Ctrl s` + `s` |
| Resize mode | `Ctrl b` + `Ctrl ↑↓←→` | `Ctrl n` + `hjkl` |
| Move pane | — | `Ctrl h` + `hjkl` |
| Lock (passthrough) | — | `Ctrl g` |
| Quit | — | `Ctrl q` |

### tmux Compatibility Mode

zellij supports a **tmux mode** (`Ctrl b`) for muscle memory:

| Action | Keybinding |
|--------|------------|
| Enter tmux mode | `Ctrl b` |
| Split down | `Ctrl b` + `"` |
| Split right | `Ctrl b` + `%` |
| Navigate | `Ctrl b` + `hjkl` / arrows |
| New tab | `Ctrl b` + `c` |
| Next/prev tab | `Ctrl b` + `n` / `p` |
| Rename tab | `Ctrl b` + `,` |
| Scroll mode | `Ctrl b` + `[` |
| Detach | `Ctrl b` + `d` |
| Close pane | `Ctrl b` + `x` |
| Fullscreen | `Ctrl b` + `z` |

## Mode System

zellij uses modes instead of a prefix key. Current mode is shown in the status bar.

```
Normal → (use Alt shortcuts directly)
         Ctrl p → Pane mode (manage panes)
         Ctrl t → Tab mode (manage tabs)
         Ctrl n → Resize mode
         Ctrl h → Move mode
         Ctrl s → Scroll mode
         Ctrl o → Session mode
         Ctrl b → Tmux mode (familiar bindings)
         Ctrl g → Locked mode (passthrough all keys)
```

Press `Esc` or `Enter` to return to Normal mode.

## Layout Files

Layouts define pane arrangements and are stored in `~/.config/zellij/layouts/`.

### Basic layout (single pane)

```kdl
layout {
    pane cwd="/path/to/project"
}
```

### Split layout (two panes side by side)

```kdl
layout {
    pane split_direction="horizontal" {
        pane cwd="/path/to/project"
        pane cwd="/path/to/project"
    }
}
```

### Complex layout

```kdl
layout {
    pane split_direction="vertical" {
        pane cwd="/path/to/project" size="70%"
        pane split_direction="horizontal" {
            pane cwd="/path/to/project"
            pane cwd="/path/to/project/subdir"
        }
    }
}
```

### Using layouts

```bash
# Start new session with a layout
zellij -s my-project -n ~/.config/zellij/layouts/my-project.kdl

# Use layout name (looked up from layouts dir)
zellij -s my-project -n my-project
```

> **Note:** Use `-n` (new-session-with-layout), not `-l` (which adds tabs to an existing session).

## Shell Aliases

These aliases are configured in `.zshrc`:

```bash
alias zs='zellij -s'              # new session: zs myproject
alias za='zellij attach'          # attach: za myproject
alias zl='zellij list-sessions'   # list sessions
alias zr='bash ~/.config/zellij/migrate-tmux.sh'  # run migration script
```

Tab completion is configured for `za` and `zs`.

## Migration Steps

### 1. Install zellij

```bash
curl -LsSf https://settings.jiun.dev | bash -s -- zellij
# or
brew install zellij
```

### 2. Apply configuration

```bash
# If using the settings installer (symlinks config automatically)
curl -LsSf https://settings.jiun.dev | bash -s -- zsh zellij

# Or manually copy
cp -r configs/zellij ~/.config/zellij
```

### 3. Create layout files for your projects

```bash
# Example: create a layout for "myproject"
cat > ~/.config/zellij/layouts/myproject.kdl << 'EOF'
layout {
    pane split_direction="horizontal" {
        pane cwd="/path/to/myproject"
        pane cwd="/path/to/myproject"
    }
}
EOF
```

### 4. Migrate existing tmux sessions

```bash
# Automatic migration (reads tmux sessions, creates zellij sessions)
zr

# Or manually create sessions
zellij -s myproject -n ~/.config/zellij/layouts/myproject.kdl
```

### 5. Update muscle memory

Start with **tmux mode** (`Ctrl b`) and gradually adopt native zellij shortcuts (`Alt + hjkl`). The tmux mode provides familiar bindings while you transition.

### 6. Clean up tmux (when ready)

```bash
# Kill all tmux sessions
tmux kill-server

# Optionally remove tmux
brew uninstall tmux
```
