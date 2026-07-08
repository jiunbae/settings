#!/bin/bash
# Apply the managed Codex config fragment while preserving selected Codex-owned
# runtime sections such as hook trust state, marketplaces, plugins, MCP servers,
# TUI state, and desktop preferences.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
TARGET="$CODEX_HOME/config.toml"
TEMPLATE="$REPO_ROOT/configs/codex/config.managed.toml"
TIMESTAMP="$(date +%Y%m%d%H%M%S)"
DRY_RUN="${DRY_RUN:-false}"

info() { printf '%s\n' "codex: $*"; }
warn() { printf '%s\n' "codex: warning: $*" >&2; }

if [[ ! -f "$TEMPLATE" ]]; then
  printf '%s\n' "codex: template not found: $TEMPLATE" >&2
  exit 1
fi

if [[ "$DRY_RUN" == "true" ]]; then
  info "[DRY-RUN] would apply $TEMPLATE to $TARGET"
  if [[ -f "$CODEX_HOME/hooks.json" ]]; then
    info "[DRY-RUN] would move $CODEX_HOME/hooks.json to hooks.json.disabled-$TIMESTAMP"
  fi
  exit 0
fi

mkdir -p "$CODEX_HOME"

if [[ -f "$CODEX_HOME/hooks.json" ]]; then
  mv "$CODEX_HOME/hooks.json" "$CODEX_HOME/hooks.json.disabled-$TIMESTAMP"
  info "disabled legacy hooks.json -> hooks.json.disabled-$TIMESTAMP"
fi

tmp="$(mktemp)"
tail_tmp="$(mktemp)"
trap 'rm -f "$tmp" "$tail_tmp"' EXIT

if [[ -f "$TARGET" ]]; then
  backup="$TARGET.backup.$TIMESTAMP"
  cp "$TARGET" "$backup"
  info "backed up existing config -> $backup"

  awk '
    function is_header(line) {
      return line ~ /^\[/
    }
    function keep_header(line) {
      return line ~ /^\[hooks\.state(\.|\])/ ||
        line ~ /^\[marketplaces\./ ||
        line ~ /^\[plugins\./ ||
        line ~ /^\[mcp_servers\./ ||
        line ~ /^\[shell_environment_policy(\.|\])/ ||
        line ~ /^\[desktop(\.|\])/ ||
        line ~ /^\[tui\./
    }
    is_header($0) {
      copy = keep_header($0)
    }
    copy { print }
  ' "$TARGET" > "$tail_tmp"

  awk '
    /^\[hooks\.state\.".*\/hooks\.json:/ { skip = 1; next }
    /^\[/ { skip = 0 }
    !skip { print }
  ' "$tail_tmp" > "$tmp"
  mv "$tmp" "$tail_tmp"
fi

cp "$TEMPLATE" "$tmp"
if [[ -s "$tail_tmp" ]]; then
  printf '\n' >> "$tmp"
  cat "$tail_tmp" >> "$tmp"
fi

mv "$tmp" "$TARGET"
trap - EXIT
rm -f "$tail_tmp"

if command -v muxa >/dev/null 2>&1; then
  info "muxa found: $(command -v muxa)"
else
  warn "muxa not found; Codex muxa hooks will need it in PATH"
fi

if command -v omp >/dev/null 2>&1; then
  info "omp found: $(command -v omp)"
else
  warn "omp not found; Codex notify wrapper will not ingest prompts"
fi

if command -v codex >/dev/null 2>&1; then
  if codex doctor --summary --no-color --ascii >/dev/null 2>&1; then
    info "codex config validates"
  else
    warn "codex doctor still reports issues; run: codex doctor --summary --no-color --ascii"
  fi
fi

info "applied managed config"
