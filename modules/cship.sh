#!/bin/bash
# cship.sh - Claude Code statusline (cship + Starship passthrough)
# Can be run standalone or sourced by install.sh

# ==============================================================================
# Standalone execution support
# ==============================================================================
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "$SCRIPT_DIR/../lib/core.sh"
    source "$SCRIPT_DIR/../lib/platform.sh"
    detect_platform
    setup_package_manager
fi

# ==============================================================================
# Configuration
#
# Replaces ccstatusline, which cost ~1.25s of CPU and ~99MB peak RSS on every
# render. cship renders the same two-row powerline in ~33ms / ~18MB because
# Claude Code hands it the whole `context_window` object on stdin — no Node
# runtime, no transcript parsing.
#
# Starship is a hard dependency, not a nicety: `$directory`, `$git_branch`,
# `$git_metrics` and `$custom.worktree` in cship.toml are passthrough tokens
# that shell out to `starship module <name>`. Without the binary those four
# segments silently vanish from the statusline.
#
# Versions are pinned so a machine rebuilt months from now gets the layout this
# repo was tested against rather than whatever HEAD renders that day.
# ==============================================================================
readonly CSHIP_VERSION="v1.8.1"
readonly STARSHIP_VERSION="v1.26.0"
readonly CSHIP_BIN_DIR="$HOME/.local/bin"
readonly CSHIP_CONFIG="$HOME/.config/cship.toml"
readonly CSHIP_STARSHIP_CONFIG="$HOME/.config/starship.toml"
readonly CLAUDE_SETTINGS="$HOME/.claude/settings.json"

# ==============================================================================
# Helpers
# ==============================================================================

# Map the detected platform onto the Rust target triple both projects publish.
# Linux uses musl so the binary keeps working on hosts with an older glibc.
_cship_target() {
    local arch
    arch=$(uname -m)
    case "$arch" in
        x86_64|amd64) arch="x86_64" ;;
        arm64|aarch64) arch="aarch64" ;;
        *) log_error "Unsupported architecture for cship: $arch"; return 1 ;;
    esac

    case "$PLATFORM" in
        macos) echo "${arch}-apple-darwin" ;;
        linux) echo "${arch}-unknown-linux-musl" ;;
        *) log_error "Unsupported platform for cship: $PLATFORM"; return 1 ;;
    esac
}

# backup_and_link warns on every re-run once the target exists, even when it is
# already our symlink. Short-circuit that case so `install.sh cship` is quiet
# when there is nothing to do (same shape as the ghostty module).
_cship_link() {
    local source=$1 target=$2 label=$3

    # In copy mode the target is a real file, so a readlink check would never
    # match and every run would re-warn. Compare contents instead.
    if [[ "$LINK_MODE" == "copy" ]]; then
        if diff -rq "$source" "$target" >/dev/null 2>&1; then
            log_info "$label already up to date"
            track_skipped "$label"
            return 0
        fi
        FORCE=true backup_and_link "$source" "$target"
        return 0
    fi

    if [[ -L "$target" && "$(readlink "$target")" == "$source" ]]; then
        log_info "$label already linked"
        track_skipped "$label"
        return 0
    fi

    backup_and_link "$source" "$target"
}

# `starship --version` prints five lines (version, branch, commit, build info);
# only the first carries the number, so stop after it.
_cship_installed_version() {
    local bin=$1
    [[ -x "$bin" ]] || return 1
    "$bin" --version 2>/dev/null | awk 'NR==1 {print $NF; exit}'
}

# ==============================================================================
# Installation Functions
# ==============================================================================

install_cship_binary() {
    print_section "Installing cship"

    local target
    target=$(_cship_target) || return 1
    local dest="$CSHIP_BIN_DIR/cship"
    local want="${CSHIP_VERSION#v}"

    if [[ "$(_cship_installed_version "$dest")" == "$want" && "$FORCE" != "true" ]]; then
        log_info "cship $want already installed"
        track_skipped "cship"
        return 0
    fi

    local url="https://github.com/stephenleo/cship/releases/download/${CSHIP_VERSION}/cship-${target}"
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would install cship $want from $url"
        return 0
    fi

    mkdir -p "$CSHIP_BIN_DIR"
    local tmp
    tmp=$(mktemp)
    download_file "$url" "$tmp" || { rm -f "$tmp"; return 1; }
    install -m 755 "$tmp" "$dest"
    rm -f "$tmp"

    track_installed "cship $want"
    log_success "cship installed: $dest"
}

install_cship_starship() {
    print_section "Installing Starship (cship passthrough dependency)"

    local target
    target=$(_cship_target) || return 1
    local dest="$CSHIP_BIN_DIR/starship"
    local want="${STARSHIP_VERSION#v}"

    if [[ "$(_cship_installed_version "$dest")" == "$want" && "$FORCE" != "true" ]]; then
        log_info "Starship $want already installed"
        track_skipped "Starship"
        return 0
    fi

    local base="https://github.com/starship/starship/releases/download/${STARSHIP_VERSION}"
    local tarball="starship-${target}.tar.gz"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would install Starship $want from $base/$tarball"
        return 0
    fi

    mkdir -p "$CSHIP_BIN_DIR"
    local tmpdir
    tmpdir=$(mktemp -d)
    download_file "$base/$tarball" "$tmpdir/$tarball" || { rm -rf "$tmpdir"; return 1; }

    # The release ships a bare digest (no filename column), so `sha256sum -c`
    # can't read it directly — compare the hashes ourselves.
    if download_file "$base/${tarball}.sha256" "$tmpdir/${tarball}.sha256" 2>/dev/null; then
        local expected actual
        expected=$(tr -d '[:space:]' < "$tmpdir/${tarball}.sha256")
        actual=$(sha256sum "$tmpdir/$tarball" 2>/dev/null | cut -d' ' -f1)
        [[ -z "$actual" ]] && actual=$(shasum -a 256 "$tmpdir/$tarball" 2>/dev/null | cut -d' ' -f1)
        if [[ -n "$expected" && "$expected" != "$actual" ]]; then
            log_error "Starship checksum mismatch (expected $expected, got $actual)"
            rm -rf "$tmpdir"
            return 1
        fi
        log_debug "Starship checksum verified"
    else
        log_warn "Starship checksum not published for $tarball — skipping verification"
    fi

    tar -xzf "$tmpdir/$tarball" -C "$tmpdir"
    install -m 755 "$tmpdir/starship" "$dest"
    rm -rf "$tmpdir"

    track_installed "Starship $want"
    log_success "Starship installed: $dest"
}

install_cship_config() {
    print_section "Setting up cship config"

    local root_dir
    root_dir=$(get_root_dir)
    local cship_src="$root_dir/configs/cship/cship.toml"
    local starship_src="$root_dir/configs/cship/starship.toml"

    for src in "$cship_src" "$starship_src"; do
        if [[ ! -f "$src" ]]; then
            log_error "cship config not found at: $src"
            return 1
        fi
    done

    _cship_link "$cship_src" "$CSHIP_CONFIG" "cship config"

    # starship.toml here is a passthrough-only config (add_newline=false, four
    # modules). If the machine already uses Starship as its shell prompt,
    # linking would replace that prompt wholesale — leave it alone unless the
    # user has looked at both files and asked for it with --force.
    if [[ -f "$CSHIP_STARSHIP_CONFIG" && ! -L "$CSHIP_STARSHIP_CONFIG" && "$FORCE" != "true" ]]; then
        log_warn "Starship already has its own config: $CSHIP_STARSHIP_CONFIG"
        log_warn "It is probably driving your shell prompt — linking would replace it."
        log_info "Merge the modules from $starship_src, then re-run with --force:"
        log_info "  ./install.sh -f cship"
        track_skipped "Starship config (existing config left alone)"
    else
        _cship_link "$starship_src" "$CSHIP_STARSHIP_CONFIG" "Starship config"
    fi
}

# Point Claude Code at cship. Only the statusLine key is touched — this repo
# does not own ~/.claude/settings.json, which carries hooks, permissions and
# model settings that must survive untouched.
install_cship_claude_hook() {
    print_section "Wiring cship into Claude Code"

    if [[ ! -f "$CLAUDE_SETTINGS" ]]; then
        log_info "No Claude Code settings at $CLAUDE_SETTINGS — skipping"
        log_info "Add this once Claude Code is set up:"
        log_info '  "statusLine": { "type": "command", "command": "~/.local/bin/cship", "padding": 0 }'
        track_skipped "Claude Code statusLine (settings.json absent)"
        return 0
    fi

    if ! command_exists python3; then
        log_warn "python3 not available — cannot edit settings.json safely, skipping"
        track_skipped "Claude Code statusLine (no python3)"
        return 0
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would set statusLine.command to \$HOME/.local/bin/cship in $CLAUDE_SETTINGS"
        return 0
    fi

    local result
    # `env` rather than a command-prefix assignment: CLAUDE_SETTINGS is declared
    # readonly above, and bash rejects `CLAUDE_SETTINGS=... cmd` for a readonly name.
    # Written as $HOME/... to match configs/claude/settings.json: statusLine.command
    # runs through a shell, so it expands at run time and the file stays portable.
    result=$(env CLAUDE_SETTINGS="$CLAUDE_SETTINGS" \
                 CSHIP_BIN='$HOME/.local/bin/cship' \
                 CSHIP_BIN_ABS="$CSHIP_BIN_DIR/cship" \
                 FORCE="$FORCE" python3 - <<'PY'
import json, os, shutil, sys, time

path = os.environ["CLAUDE_SETTINGS"]
target = os.environ["CSHIP_BIN"]
force = os.environ.get("FORCE") == "true"

try:
    with open(path) as fh:
        settings = json.load(fh)
except (OSError, ValueError) as exc:
    print(f"error:could not read settings.json ({exc})")
    sys.exit(0)

current = (settings.get("statusLine") or {}).get("command")
# Accept the absolute form too: earlier installs wrote it before the config
# moved to $HOME-relative paths, and both resolve to the same binary.
if current in (target, os.environ.get("CSHIP_BIN_ABS")):
    print("skip:already points at cship")
    sys.exit(0)
if current and not force:
    print(f"conflict:{current}")
    sys.exit(0)

shutil.copy2(path, f"{path}.backup.{time.strftime('%Y%m%d%H%M%S')}")
settings["statusLine"] = {"type": "command", "command": target, "padding": 0}
with open(path, "w") as fh:
    json.dump(settings, fh, indent=2)
    fh.write("\n")
print("ok")
PY
)

    case "$result" in
        ok)
            track_installed "Claude Code statusLine"
            log_success "Claude Code statusLine -> \$HOME/.local/bin/cship"
            log_info "Takes effect in new Claude Code sessions"
            ;;
        skip:*)
            log_info "Claude Code statusLine ${result#skip:}"
            track_skipped "Claude Code statusLine"
            ;;
        conflict:*)
            log_warn "Claude Code already has a statusLine: ${result#conflict:}"
            log_info "Re-run with --force to replace it:  ./install.sh -f cship"
            track_skipped "Claude Code statusLine (existing command left alone)"
            ;;
        error:*)
            log_error "Claude Code statusLine: ${result#error:}"
            return 1
            ;;
        *)
            log_warn "Claude Code statusLine: unexpected result '$result'"
            track_skipped "Claude Code statusLine"
            ;;
    esac
}

# ==============================================================================
# Main Installation
# ==============================================================================

install_cship() {
    log_info "Starting cship statusline configuration..."

    install_cship_binary || return 1
    install_cship_starship || return 1
    install_cship_config || return 1
    install_cship_claude_hook || return 1

    log_success "cship statusline complete!"
    log_info "Requires a Nerd Font for the powerline separators and git glyphs"
}

# ==============================================================================
# Standalone Execution
# ==============================================================================
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    setup_error_handling
    install_cship
fi
