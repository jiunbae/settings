#!/bin/bash
# Apply the managed Codex config fragment while preserving selected Codex-owned
# runtime sections such as hook trust state, project trust, marketplaces, TUI
# state, desktop preferences, and the machine-local top-level notify command.
#
# Project trust is preserved rather than templated: the paths are absolute and
# machine-specific, and losing them means re-approving every repo by hand.

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
top_tmp="$(mktemp)"
tail_tmp="$(mktemp)"
trap 'rm -f "$tmp" "$top_tmp" "$tail_tmp"' EXIT

if [[ -f "$TARGET" ]]; then
  backup="$TARGET.backup.$TIMESTAMP"
  cp "$TARGET" "$backup"
  info "backed up existing config -> $backup"

  # `notify` is a machine-local command (typically an absolute Node + wrapper
  # path), so it cannot live in the portable template. Keep it as a top-level
  # key and splice it back before the first TOML table below.
  awk '
    in_notify {
      print
      if ($0 ~ /\][[:space:]]*(#.*)?$/) in_notify = 0
      next
    }
    /^notify[[:space:]]*=/ {
      print
      if ($0 ~ /=[[:space:]]*\[/ && $0 !~ /\][[:space:]]*(#.*)?$/) in_notify = 1
    }
  ' "$TARGET" > "$top_tmp"

  awk '
    function is_header(line) {
      return line ~ /^\[/
    }
    function keep_header(line) {
      return line ~ /^\[hooks\.state(\.|\])/ ||
        line ~ /^\[projects(\.|\])/ ||
        line ~ /^\[marketplaces\./ ||
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

awk -v top="$top_tmp" '
  function emit_top(line, count) {
    while ((getline line < top) > 0) {
      print line
      count++
    }
    close(top)
    if (count > 0) print ""
  }
  !inserted && /^\[/ {
    emit_top()
    inserted = 1
  }
  { print }
  END {
    if (!inserted) emit_top()
  }
' "$TEMPLATE" > "$tmp"
if [[ -s "$tail_tmp" ]]; then
  printf '\n' >> "$tmp"
  cat "$tail_tmp" >> "$tmp"
fi

# Exact duplicate standard tables are always invalid TOML. Catch the merge
# regression even on hosts whose Python predates the standard tomllib module.
if ! awk '
  /^\[[^[]/ {
    header = $0
    sub(/[[:space:]]*#.*/, "", header)
    if (++seen[header] > 1) {
      printf "duplicate TOML table: %s\n", header > "/dev/stderr"
      invalid = 1
    }
  }
  END { exit invalid }
' "$tmp"; then
  warn "generated config has duplicate tables; existing config was left untouched"
  exit 1
fi

# Never replace a working config with invalid TOML. Python 3.11+ ships a TOML
# parser; on older hosts Codex's own doctor below remains the fallback check.
if command -v python3 >/dev/null 2>&1 && python3 -c 'import tomllib' >/dev/null 2>&1; then
  if ! python3 - "$tmp" <<'PY'
import pathlib
import sys
import tomllib

tomllib.loads(pathlib.Path(sys.argv[1]).read_text())
PY
  then
    warn "generated config is invalid TOML; existing config was left untouched"
    exit 1
  fi
fi

mv "$tmp" "$TARGET"
trap - EXIT
rm -f "$top_tmp" "$tail_tmp"

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
