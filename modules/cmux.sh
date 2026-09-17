#!/bin/bash
# cmux.sh - cmux terminal (macOS only)
# Can be run standalone or sourced by install.sh

# ==============================================================================
# Standalone execution support
# ==============================================================================
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "$SCRIPT_DIR/../lib/core.sh"
    source "$SCRIPT_DIR/../lib/platform.sh"
    source "$SCRIPT_DIR/ghostty.sh"
    detect_platform
    setup_package_manager
fi

# ==============================================================================
# Configuration
#
# cmux is built on libghostty and reads Ghostty's own config search path —
# ~/Library/Application Support/com.mitchellh.ghostty/config — so the font,
# colors, Option-as-Alt and keybinds all come from configs/ghostty/config via
# the ghostty module. The only cmux-specific file is its theme block, which
# cmux rewrites itself when the theme is changed in its UI; it is seeded once
# and never linked.
# ==============================================================================
readonly CMUX_APP="/Applications/cmux.app"
readonly CMUX_SUPPORT_DIR="$HOME/Library/Application Support/com.cmuxterm.app"

# ==============================================================================
# Installation Functions
# ==============================================================================

install_cmux_app() {
    print_section "Installing cmux"

    if [[ -d "$CMUX_APP" ]]; then
        log_info "cmux.app already installed (it updates itself)"
        track_skipped "cmux.app"
        return 0
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would install cmux via Homebrew Cask"
        return 0
    fi

    run_with_spinner "Installing cmux via Homebrew Cask" brew install --cask cmux
    track_installed "cmux.app"
}

install_cmux_theme() {
    print_section "Seeding cmux theme"

    local root_dir
    root_dir=$(get_root_dir)
    local source="$root_dir/configs/cmux/config.ghostty"
    local target="$CMUX_SUPPORT_DIR/config.ghostty"

    if [[ -f "$target" ]]; then
        log_info "cmux theme already present (managed by cmux from here on)"
        track_skipped "cmux theme"
        return 0
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would copy $source -> $target"
        return 0
    fi

    mkdir -p "$CMUX_SUPPORT_DIR"
    cp "$source" "$target"
    track_installed "cmux theme"
    log_success "Seeded $target"
}

# ==============================================================================
# Main Installation
# ==============================================================================

install_cmux() {
    log_info "Starting cmux installation..."

    if [[ "$PLATFORM" != "macos" ]]; then
        log_info "cmux is macOS-only, skipping on platform: $PLATFORM"
        track_skipped "cmux (not macOS)"
        return 0
    fi

    install_cmux_app
    install_ghostty_config || return 1
    install_cmux_theme

    log_success "cmux installation complete!"
}

# ==============================================================================
# Standalone Execution
# ==============================================================================
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    setup_error_handling
    install_cmux
fi
