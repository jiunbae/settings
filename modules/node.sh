#!/bin/bash
# node.sh - nvm + Node.js LTS + Codex and Claude Code CLIs (macOS only)
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
# nvm comes from Homebrew, but configs/.zshrc looks for $HOME/.nvm/nvm.sh, so
# that path is a symlink into the Homebrew keg (the layout the old machine
# used). The default alias is a bare major version: .zshrc resolves it with a
# v<major>* glob, and `nvm install <major>` always picks that line's latest.
#
# Only two CLIs are installed by default. Codex is an npm package and lives in
# the default Node's global prefix; Claude Code uses its native installer
# (~/.local/bin/claude), which updates itself independently of Node.
# ==============================================================================
readonly NODE_NVM_DIR="$HOME/.nvm"
readonly NODE_DEFAULT_MAJOR="24"
readonly NODE_GLOBAL_PACKAGES=(
    "@openai/codex"
)
readonly CLAUDE_CODE_INSTALLER="https://claude.ai/install.sh"

# ==============================================================================
# Helpers
# ==============================================================================

# nvm.sh is not safe under `set -eu`, so every call runs in its own bash with
# those options off. `_node_run` puts the default Node on PATH first.
_nvm() {
    NVM_DIR="$NODE_NVM_DIR" bash -c 'set +eu; source "$NVM_DIR/nvm.sh"; nvm "$@"' _ "$@"
}

_node_run() {
    NVM_DIR="$NODE_NVM_DIR" bash -c \
        'set +eu; source "$NVM_DIR/nvm.sh"; nvm use --silent default >/dev/null || exit 1; "$@"' _ "$@"
}

# ==============================================================================
# Installation Functions
# ==============================================================================

install_node_nvm() {
    print_section "Installing nvm"

    if pkg_installed nvm; then
        log_info "nvm already installed"
        track_skipped "nvm"
    else
        pkg_install nvm
        track_installed "nvm"
    fi

    local source target="$NODE_NVM_DIR/nvm.sh"
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would link $target -> \$(brew --prefix nvm)/libexec/nvm.sh"
        return 0
    fi

    source="$(brew --prefix nvm)/libexec/nvm.sh"
    if [[ -L "$target" && "$(readlink "$target")" == "$source" ]]; then
        log_info "$target already linked"
        return 0
    fi

    mkdir -p "$NODE_NVM_DIR"
    FORCE=true backup_and_link "$source" "$target"
}

install_node_default() {
    print_section "Installing Node.js $NODE_DEFAULT_MAJOR (default)"

    local current
    current=$(_nvm version default 2>/dev/null || true)
    if [[ "$current" == "v$NODE_DEFAULT_MAJOR."* ]]; then
        log_info "Default Node is already $current"
        track_skipped "Node.js $current"
        return 0
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would run: nvm install $NODE_DEFAULT_MAJOR && nvm alias default $NODE_DEFAULT_MAJOR (default now: ${current:-none})"
        return 0
    fi

    run_with_spinner "Installing Node.js $NODE_DEFAULT_MAJOR" _nvm install "$NODE_DEFAULT_MAJOR"
    _nvm alias default "$NODE_DEFAULT_MAJOR" >/dev/null

    current=$(_nvm version default)
    track_installed "Node.js $current (default)"
    log_success "Default Node is now $current"
}

install_node_globals() {
    print_section "Installing global npm CLIs"

    local pkg
    for pkg in "${NODE_GLOBAL_PACKAGES[@]}"; do
        if [[ "$DRY_RUN" != "true" ]] && _node_run npm ls -g --depth=0 "$pkg" >/dev/null 2>&1; then
            log_info "$pkg already installed"
            track_skipped "$pkg"
            continue
        fi
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[DRY-RUN] Would run: npm install -g $pkg (under Node $NODE_DEFAULT_MAJOR)"
            continue
        fi
        run_with_spinner "Installing $pkg" _node_run npm install -g "$pkg"
        track_installed "$pkg"
    done
}

install_node_claude_code() {
    print_section "Installing Claude Code"

    if command_exists claude || [[ -x "$HOME/.local/bin/claude" ]]; then
        log_info "Claude Code already installed (it updates itself)"
        track_skipped "Claude Code"
        return 0
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would run: curl -fsSL $CLAUDE_CODE_INSTALLER | bash"
        return 0
    fi

    run_with_spinner "Installing Claude Code (native installer)" \
        bash -c "curl -fsSL '$CLAUDE_CODE_INSTALLER' | bash"
    track_installed "Claude Code"
    log_info "Log in with: claude"
}

# ==============================================================================
# Main Installation
# ==============================================================================

install_node() {
    log_info "Starting Node.js installation..."

    if [[ "$PLATFORM" != "macos" ]]; then
        log_info "The node component is macOS-only, skipping on platform: $PLATFORM"
        track_skipped "Node.js (not macOS)"
        return 0
    fi

    install_node_nvm
    install_node_default || return 1
    install_node_globals || return 1
    install_node_claude_code

    log_success "Node.js installation complete!"
}

# ==============================================================================
# Standalone Execution
# ==============================================================================
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    setup_error_handling
    install_node
fi
