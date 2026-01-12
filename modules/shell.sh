#!/bin/bash
# shell.sh - Zsh + zinit + Powerlevel10k installation
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
readonly ZINIT_HOME="${XDG_DATA_HOME:-$HOME/.local/share}/zinit/zinit.git"

# ==============================================================================
# Installation Functions
# ==============================================================================

install_zsh_package() {
    print_section "Installing Zsh"

    if command_exists zsh; then
        log_info "Zsh is already installed: $(zsh --version)"
        track_skipped "Zsh"
        return 0
    fi

    pkg_install zsh
    track_installed "Zsh"
    log_success "Zsh installed"
}

install_zinit() {
    print_section "Installing zinit"

    if [[ -d "$ZINIT_HOME" ]]; then
        if [[ "$FORCE" == "true" ]]; then
            log_info "Removing existing zinit..."
            rm -rf "$ZINIT_HOME"
        else
            echo -e "${GREEN}✓${NC} zinit (already installed)"
            track_skipped "zinit"
            return 0
        fi
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would install zinit"
        return 0
    fi

    # Install zinit
    mkdir -p "$(dirname "$ZINIT_HOME")"
    run_with_spinner "Installing zinit" \
        git clone --depth 1 https://github.com/zdharma-continuum/zinit.git "$ZINIT_HOME"
    track_installed "zinit"
    log_success "zinit installed"
}

install_powerlevel10k() {
    print_section "Installing Powerlevel10k Theme"

    # Note: Powerlevel10k will be installed by zinit on first shell start
    # This function just ensures the fonts are available

    log_info "Powerlevel10k will be installed automatically by zinit on first shell start"
    log_info "Make sure you have a Nerd Font installed for the best experience"
    track_skipped "Powerlevel10k (managed by zinit)"
}

link_zsh_configs() {
    print_section "Linking Zsh Configuration Files"

    local root_dir
    root_dir=$(get_root_dir)
    local configs_dir="$root_dir/configs"

    # Link .zshrc
    if [[ -f "$configs_dir/.zshrc" ]]; then
        backup_and_link "$configs_dir/.zshrc" "$HOME/.zshrc"
    elif [[ -f "$root_dir/.zshrc" ]]; then
        backup_and_link "$root_dir/.zshrc" "$HOME/.zshrc"
    else
        log_warn ".zshrc not found in configs directory"
    fi

    # Link .p10k.zsh
    if [[ -f "$configs_dir/.p10k.zsh" ]]; then
        backup_and_link "$configs_dir/.p10k.zsh" "$HOME/.p10k.zsh"
    elif [[ -f "$root_dir/.p10k.zsh" ]]; then
        backup_and_link "$root_dir/.p10k.zsh" "$HOME/.p10k.zsh"
    else
        log_warn ".p10k.zsh not found in configs directory"
    fi

    log_success "Zsh configuration files linked"
}

# ==============================================================================
# Main Installation
# ==============================================================================

install_shell() {
    log_info "Starting shell environment installation..."

    install_zsh_package
    install_zinit
    install_powerlevel10k
    link_zsh_configs
    change_default_shell

    log_success "Shell environment installation complete!"
    log_info "Open a new terminal to initialize zinit and plugins"
}

# ==============================================================================
# Standalone Execution
# ==============================================================================
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    setup_error_handling
    install_shell
fi
