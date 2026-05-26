#!/bin/bash
# hammerspoon.sh - Hammerspoon installation (macOS only)
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
# ==============================================================================
readonly HAMMERSPOON_APP="/Applications/Hammerspoon.app"
readonly HAMMERSPOON_CONFIG_DIR="$HOME/.hammerspoon"
readonly HAMMERSPOON_INIT_FILE="$HAMMERSPOON_CONFIG_DIR/init.lua"

# ==============================================================================
# Installation Functions
# ==============================================================================

install_hammerspoon_app() {
    print_section "Installing Hammerspoon.app"

    if [[ -d "$HAMMERSPOON_APP" ]]; then
        if [[ "$FORCE" != "true" ]]; then
            log_info "Hammerspoon.app already installed"
            track_skipped "Hammerspoon.app"
            return 0
        fi
        log_info "Reinstalling Hammerspoon.app (FORCE)..."
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would install Hammerspoon via Homebrew Cask"
        return 0
    fi

    run_with_spinner "Installing Hammerspoon via Homebrew Cask" \
        brew install --cask hammerspoon

    track_installed "Hammerspoon.app"
    log_success "Hammerspoon.app installed"
    log_info "Grant Accessibility permission: System Settings > Privacy & Security > Accessibility"
}

install_hammerspoon_config() {
    print_section "Setting up Hammerspoon config"

    local root_dir
    root_dir=$(get_root_dir)
    local config_source="$root_dir/.hammerspoon/init.lua"

    if [[ ! -f "$config_source" ]]; then
        log_error "Hammerspoon config not found at: $config_source"
        return 1
    fi

    # Ensure config dir exists; never touch the dir itself, only the init.lua
    # link (Hammerspoon Spoons live next to it in the same directory).
    mkdir -p "$HAMMERSPOON_CONFIG_DIR"

    # Short-circuit if init.lua is already a symlink to our repo source
    if [[ -L "$HAMMERSPOON_INIT_FILE" ]]; then
        local current_target
        current_target=$(readlink "$HAMMERSPOON_INIT_FILE")
        if [[ "$current_target" == "$config_source" ]]; then
            log_info "Hammerspoon init.lua already linked"
            track_skipped "Hammerspoon init.lua"
            return 0
        fi
    fi

    backup_and_link "$config_source" "$HAMMERSPOON_INIT_FILE"

    track_installed "Hammerspoon init.lua"
    log_success "Hammerspoon config configured"
    log_info "Open Hammerspoon then choose 'Reload Config' to apply"
}

# ==============================================================================
# Main Installation
# ==============================================================================

install_hammerspoon() {
    log_info "Starting Hammerspoon installation..."

    # Hammerspoon is macOS-only; skip cleanly on Linux/WSL
    if [[ "$PLATFORM" != "macos" ]]; then
        log_info "Hammerspoon is macOS-only, skipping on platform: $PLATFORM"
        track_skipped "Hammerspoon (not macOS)"
        return 0
    fi

    install_hammerspoon_app
    install_hammerspoon_config

    log_success "Hammerspoon installation complete!"
}

# ==============================================================================
# Standalone Execution
# ==============================================================================
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    setup_error_handling
    install_hammerspoon
fi
