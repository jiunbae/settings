#!/bin/bash
# zellij.sh - zellij terminal multiplexer installation
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
readonly ZELLIJ_CONFIG_DIR="$HOME/.config/zellij"

# ==============================================================================
# Installation Functions
# ==============================================================================

install_zellij_package() {
    print_section "Installing zellij"

    if command_exists zellij; then
        log_info "zellij is already installed: $(zellij --version)"
        if [[ "$FORCE" != "true" ]]; then
            track_skipped "zellij"
            return 0
        fi
    fi

    if [[ "$PLATFORM" == "macos" ]]; then
        pkg_install zellij
    else
        # Linux: prefer cargo-binstall if available, otherwise brew/cargo
        if command_exists cargo-binstall; then
            cargo binstall -y zellij
        elif command_exists cargo; then
            cargo install zellij
        elif command_exists brew; then
            brew install zellij
        else
            log_warn "No supported package manager found for zellij"
            log_info "Install manually: https://zellij.dev/documentation/installation"
            return 0
        fi
    fi

    track_installed "zellij"
    log_success "zellij installed"
}

link_zellij_config() {
    print_section "Linking zellij Configuration"

    local root_dir
    root_dir=$(get_root_dir)
    local config_source="$root_dir/configs/zellij"

    if [[ ! -d "$config_source" ]]; then
        log_warn "zellij config directory not found"
        return 0
    fi

    # Ensure config directory exists
    mkdir -p "$ZELLIJ_CONFIG_DIR"

    # Link config.kdl
    if [[ -f "$config_source/config.kdl" ]]; then
        backup_and_link "$config_source/config.kdl" "$ZELLIJ_CONFIG_DIR/config.kdl"
        log_success "zellij config.kdl linked"
    fi

    # Link layouts directory
    if [[ -d "$config_source/layouts" ]]; then
        # Link each layout file individually to preserve any user-added layouts
        mkdir -p "$ZELLIJ_CONFIG_DIR/layouts"
        for layout in "$config_source/layouts"/*.kdl; do
            if [[ -f "$layout" ]]; then
                local layout_name
                layout_name=$(basename "$layout")
                backup_and_link "$layout" "$ZELLIJ_CONFIG_DIR/layouts/$layout_name"
            fi
        done
        log_success "zellij layouts linked"
    fi
}

# ==============================================================================
# Main Installation
# ==============================================================================

install_zellij() {
    log_info "Starting zellij installation..."

    install_zellij_package
    link_zellij_config

    log_success "zellij installation complete!"
}

# ==============================================================================
# Standalone Execution
# ==============================================================================
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    setup_error_handling
    install_zellij
fi
