#!/bin/bash
# editor.sh - NeoVim + SpaceVim installation
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
readonly SPACEVIM_DIR="$HOME/.SpaceVim"
readonly SPACEVIM_CONFIG_DIR="$HOME/.SpaceVim.d"

# ==============================================================================
# Installation Functions
# ==============================================================================

install_neovim() {
    print_section "Installing NeoVim"

    if command_exists nvim; then
        log_info "NeoVim is already installed: $(nvim --version | head -1)"
        if [[ "$FORCE" != "true" ]]; then
            return 0
        fi
    fi

    case "$PLATFORM" in
        macos)
            pkg_install neovim
            ;;
        linux|wsl)
            # Try to install from apt, fallback to snap if version is too old
            if pkg_install neovim; then
                log_success "NeoVim installed via apt"
            else
                log_warn "apt installation failed, trying snap..."
                run_with_spinner "Installing NeoVim via snap" \
                    sudo snap install nvim --classic
            fi
            ;;
    esac

    log_success "NeoVim installed"
}

install_spacevim() {
    print_section "Installing SpaceVim"

    if [[ -d "$SPACEVIM_DIR" ]]; then
        if [[ "$FORCE" == "true" ]]; then
            log_info "Removing existing SpaceVim..."
            rm -rf "$SPACEVIM_DIR"
            rm -rf "$HOME/.vim"
        else
            log_info "SpaceVim is already installed"
            return 0
        fi
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would install SpaceVim"
        return 0
    fi

    # Clone SpaceVim from GitHub (manual installation)
    git_clone "https://github.com/SpaceVim/SpaceVim.git" "$SPACEVIM_DIR"

    # Create symlink for vim compatibility
    if [[ ! -e "$HOME/.vim" ]]; then
        ln -sf "$SPACEVIM_DIR" "$HOME/.vim"
    fi

    # Create symlink for neovim
    local nvim_config_dir="$HOME/.config/nvim"
    if [[ ! -e "$nvim_config_dir" ]]; then
        mkdir -p "$HOME/.config"
        ln -sf "$SPACEVIM_DIR" "$nvim_config_dir"
    fi

    log_success "SpaceVim installed"
}

link_spacevim_config() {
    print_section "Linking SpaceVim Configuration"

    local root_dir
    root_dir=$(get_root_dir)
    local config_source

    # Check configs/ first, then root
    if [[ -d "$root_dir/configs/.SpaceVim.d" ]]; then
        config_source="$root_dir/configs/.SpaceVim.d"
    elif [[ -d "$root_dir/.SpaceVim.d" ]]; then
        config_source="$root_dir/.SpaceVim.d"
    else
        log_warn "SpaceVim config directory not found"
        return 0
    fi

    # Link entire .SpaceVim.d directory
    if [[ -d "$SPACEVIM_CONFIG_DIR" && ! -L "$SPACEVIM_CONFIG_DIR" ]]; then
        if [[ "$FORCE" == "true" ]]; then
            local backup="${SPACEVIM_CONFIG_DIR}.backup.$(date +%Y%m%d%H%M%S)"
            log_info "Backing up existing config: $SPACEVIM_CONFIG_DIR -> $backup"
            mv "$SPACEVIM_CONFIG_DIR" "$backup"
        else
            log_warn "SpaceVim config directory exists (use --force to overwrite)"
            return 0
        fi
    fi

    backup_and_link "$config_source" "$SPACEVIM_CONFIG_DIR"
    log_success "SpaceVim configuration linked"
}

setup_vim_alias() {
    # This is handled in .zshrc, just log info
    log_info "Vim aliases (vim, vi -> nvim) are configured in .zshrc"
}

# ==============================================================================
# Main Installation
# ==============================================================================

install_editor() {
    log_info "Starting editor installation..."

    install_neovim
    install_spacevim
    link_spacevim_config
    setup_vim_alias

    log_success "Editor installation complete!"
}

# ==============================================================================
# Standalone Execution
# ==============================================================================
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    setup_error_handling
    install_editor
fi
