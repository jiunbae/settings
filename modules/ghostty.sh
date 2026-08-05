#!/bin/bash
# ghostty.sh - Ghostty terminal configuration (macOS only)
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
# The GUI app reads ~/Library/Application Support/..., NOT
# ~/.config/ghostty/config. Both are valid search paths, but the
# macOS-specific ones load last and win, so linking the XDG path alone
# would leave whatever is already in Application Support in charge.
# ==============================================================================
readonly GHOSTTY_CONFIG_DIR="$HOME/Library/Application Support/com.mitchellh.ghostty"
readonly GHOSTTY_CONFIG_FILE="$GHOSTTY_CONFIG_DIR/config"

# ==============================================================================
# Installation Functions
# ==============================================================================

install_ghostty_config() {
    print_section "Setting up Ghostty config"

    local root_dir
    root_dir=$(get_root_dir)
    local config_source="$root_dir/configs/ghostty/config"

    if [[ ! -f "$config_source" ]]; then
        log_error "Ghostty config not found at: $config_source"
        return 1
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would link $config_source -> $GHOSTTY_CONFIG_FILE"
        return 0
    fi

    mkdir -p "$GHOSTTY_CONFIG_DIR"

    # Short-circuit if it already points at our source
    if [[ -L "$GHOSTTY_CONFIG_FILE" ]]; then
        local current_target
        current_target=$(readlink "$GHOSTTY_CONFIG_FILE")
        if [[ "$current_target" == "$config_source" ]]; then
            log_info "Ghostty config already linked"
            track_skipped "Ghostty config"
            return 0
        fi
    fi

    backup_and_link "$config_source" "$GHOSTTY_CONFIG_FILE"

    track_installed "Ghostty config"
    log_success "Ghostty config configured"
    log_info "Reload in Ghostty with cmd+shift+, (no restart needed)"
}

# ==============================================================================
# Main Installation
# ==============================================================================

install_ghostty() {
    log_info "Starting Ghostty configuration..."

    # The Application Support path is macOS-only; skip cleanly elsewhere.
    if [[ "$PLATFORM" != "macos" ]]; then
        log_info "Ghostty config is macOS-only, skipping on platform: $PLATFORM"
        track_skipped "Ghostty (not macOS)"
        return 0
    fi

    install_ghostty_config

    log_success "Ghostty configuration complete!"
}

# ==============================================================================
# Standalone Execution
# ==============================================================================
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    setup_error_handling
    install_ghostty
fi
