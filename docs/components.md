# Component notes

Per-component setup that does not belong on the landing page: the parts that need a
decision, a secret, or a manual permission grant. Everything here was in the README
before it was split. Three single-row tables that had lost their headers are prose now;
the rest is unchanged.

| | |
| :--- | :--- |
| [hishtory](#hishtory) | Shell history with cross-device sync |
| [Hammerspoon](#hammerspoon) | macOS automation, needs an Accessibility grant |
| [Codex](#codex) | What the managed config does and does not touch |

## hishtory

[hishtory](https://github.com/ddworken/hishtory) gives shell history context, search and
cross-machine sync.

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

## Hammerspoon

[Hammerspoon](https://www.hammerspoon.org/) is Lua-scriptable macOS automation for
windows, screens and the keyboard.

**Installs via Homebrew Cask and symlinks `~/.hammerspoon/init.lua` to this repo.**
Skipped automatically on Linux/WSL. Accessibility permission must be granted manually:
System Settings → Privacy & Security → Accessibility → enable Hammerspoon.

## Codex

The `codex` component applies a managed half of `config.toml` over whatever is
already there:

It applies stable model, plugin, MCP and hook settings, disables the legacy
`~/.codex/hooks.json`, and preserves machine-local runtime sections — project and hook
trust, `notify`, TUI state, desktop settings.

Restoring Codex and Claude Code state on a new machine — including what is
deliberately left unmanaged — is in [agent-state.md](agent-state.md).
