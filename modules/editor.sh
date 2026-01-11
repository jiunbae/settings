#!/bin/bash
# editor.sh - NeoVim + LazyVim installation
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
readonly NVIM_CONFIG_DIR="$HOME/.config/nvim"
readonly NVIM_DATA_DIR="$HOME/.local/share/nvim"
readonly NVIM_CACHE_DIR="$HOME/.cache/nvim"

# ==============================================================================
# Installation Functions
# ==============================================================================

install_neovim() {
    print_section "Installing NeoVim"

    if command_exists nvim; then
        log_info "NeoVim is already installed: $(nvim --version | head -1)"
        if [[ "$FORCE" != "true" ]]; then
            track_skipped "NeoVim"
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

    track_installed "NeoVim"
    log_success "NeoVim installed"
}

install_lazyvim() {
    print_section "Setting up LazyVim"

    local root_dir
    root_dir=$(get_root_dir)
    local config_source="$root_dir/configs/nvim"

    # Check if our config exists
    if [[ ! -d "$config_source" ]]; then
        log_error "LazyVim config not found at: $config_source"
        return 1
    fi

    # Handle existing nvim config
    if [[ -e "$NVIM_CONFIG_DIR" ]]; then
        if [[ "$FORCE" == "true" ]]; then
            log_info "Cleaning existing nvim configuration..."
            # Backup existing config if it's not a symlink
            if [[ ! -L "$NVIM_CONFIG_DIR" ]]; then
                local backup="${NVIM_CONFIG_DIR}.backup.$(date +%Y%m%d%H%M%S)"
                log_info "Backing up existing config: $NVIM_CONFIG_DIR -> $backup"
                mv "$NVIM_CONFIG_DIR" "$backup"
                track_backup "$NVIM_CONFIG_DIR" "$backup"
            else
                rm -f "$NVIM_CONFIG_DIR"
            fi
            # Clean nvim data and cache for fresh start
            rm -rf "$NVIM_DATA_DIR"
            rm -rf "$NVIM_CACHE_DIR"
        else
            if [[ -L "$NVIM_CONFIG_DIR" ]]; then
                local current_target
                current_target=$(readlink "$NVIM_CONFIG_DIR")
                if [[ "$current_target" == "$config_source" ]]; then
                    log_info "LazyVim is already configured"
                    track_skipped "LazyVim"
                    return 0
                fi
            fi
            log_warn "nvim config exists (use --force to overwrite)"
            track_skipped "LazyVim"
            return 0
        fi
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would link LazyVim config"
        return 0
    fi

    # Ensure parent directory exists
    mkdir -p "$(dirname "$NVIM_CONFIG_DIR")"

    # Link our config
    backup_and_link "$config_source" "$NVIM_CONFIG_DIR"

    track_installed "LazyVim"
    log_success "LazyVim configured"
    log_info "Run 'nvim' to complete plugin installation"
}

cleanup_spacevim() {
    # Clean up old SpaceVim installation if exists
    local spacevim_dir="$HOME/.SpaceVim"
    local spacevim_config="$HOME/.SpaceVim.d"

    if [[ -d "$spacevim_dir" ]] || [[ -d "$spacevim_config" ]]; then
        log_info "Found old SpaceVim installation"
        if [[ "$FORCE" == "true" ]]; then
            log_info "Removing SpaceVim..."
            rm -rf "$spacevim_dir"
            rm -rf "$spacevim_config"
            # Remove vim symlink if it points to SpaceVim
            if [[ -L "$HOME/.vim" ]]; then
                local vim_target
                vim_target=$(readlink "$HOME/.vim")
                if [[ "$vim_target" == *"SpaceVim"* ]]; then
                    rm -f "$HOME/.vim"
                fi
            fi
            log_success "SpaceVim removed"
        else
            log_warn "SpaceVim still exists (use --force to remove)"
        fi
    fi
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
    cleanup_spacevim
    install_lazyvim
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
