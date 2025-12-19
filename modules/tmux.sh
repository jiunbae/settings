#!/bin/bash
# tmux.sh - tmux + TPM installation
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
readonly TPM_DIR="$HOME/.tmux/plugins/tpm"

# ==============================================================================
# Installation Functions
# ==============================================================================

install_tmux_package() {
    print_section "Installing tmux"

    if command_exists tmux; then
        log_info "tmux is already installed: $(tmux -V)"
        if [[ "$FORCE" != "true" ]]; then
            track_skipped "tmux"
            return 0
        fi
    fi

    pkg_install tmux
    track_installed "tmux"
    log_success "tmux installed"

    # Install clipboard utility for Linux (required for copy-paste integration)
    if [[ "$PLATFORM" == "linux" || "$PLATFORM" == "wsl" ]]; then
        if ! command_exists xclip; then
            log_info "Installing xclip for clipboard integration..."
            pkg_install xclip
            track_installed "xclip"
        else
            track_skipped "xclip"
        fi
    fi
}

install_tpm() {
    print_section "Installing TPM (Tmux Plugin Manager)"

    if [[ -d "$TPM_DIR" ]]; then
        if [[ "$FORCE" == "true" ]]; then
            log_info "Removing existing TPM..."
            rm -rf "$TPM_DIR"
        else
            log_info "TPM is already installed"
            track_skipped "TPM"
            return 0
        fi
    fi

    git_clone "https://github.com/tmux-plugins/tpm" "$TPM_DIR"
    track_installed "TPM"
    log_success "TPM installed"
}

link_tmux_config() {
    print_section "Linking tmux Configuration"

    local root_dir
    root_dir=$(get_root_dir)
    local config_source

    # Check configs/ first, then root
    if [[ -f "$root_dir/configs/.tmux.conf" ]]; then
        config_source="$root_dir/configs/.tmux.conf"
    elif [[ -f "$root_dir/.tmux.conf" ]]; then
        config_source="$root_dir/.tmux.conf"
    else
        log_warn ".tmux.conf not found"
        return 0
    fi

    backup_and_link "$config_source" "$HOME/.tmux.conf"
    log_success "tmux configuration linked"
}

install_tmux_plugins() {
    print_section "Installing tmux Plugins"

    if [[ ! -d "$TPM_DIR" ]]; then
        log_warn "TPM not installed, skipping plugin installation"
        return 0
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would install tmux plugins"
        return 0
    fi

    # Install plugins via TPM (optional - can be done manually later)
    if [[ -x "$TPM_DIR/bin/install_plugins" ]]; then
        # TPM install_plugins requires TMUX_PLUGIN_MANAGER_PATH
        export TMUX_PLUGIN_MANAGER_PATH="$HOME/.tmux/plugins"
        if run_with_spinner "Installing tmux plugins" "$TPM_DIR/bin/install_plugins"; then
            :  # Success
        else
            log_info "Plugins can be installed later with 'prefix + I' in tmux"
        fi
    else
        log_info "Run 'prefix + I' inside tmux to install plugins"
    fi
}

# ==============================================================================
# Main Installation
# ==============================================================================

install_tmux() {
    log_info "Starting tmux installation..."

    install_tmux_package
    install_tpm
    link_tmux_config
    install_tmux_plugins

    log_success "tmux installation complete!"
}

# ==============================================================================
# Standalone Execution
# ==============================================================================
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    setup_error_handling
    install_tmux
fi
