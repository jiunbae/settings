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
readonly NVIM_VERSION="0.11.2"
readonly NVIM_MIN_VERSION="0.11.0"  # Minimum version for LazyVim

# ==============================================================================
# Installation Functions
# ==============================================================================

# Compare version strings (returns 0 if $1 >= $2)
version_gte() {
    local v1=$1
    local v2=$2
    # Use sort -V for version comparison
    [[ "$(printf '%s\n%s' "$v1" "$v2" | sort -V | head -n1)" == "$v2" ]]
}

# Get current nvim version (e.g., "0.9.5")
get_nvim_version() {
    nvim --version 2>/dev/null | head -1 | sed -n 's/.*v\([0-9.]*\).*/\1/p'
}

# Install NeoVim via tarball (Linux)
# Using tarball instead of AppImage to avoid FUSE dependency
install_neovim_tarball() {
    local install_dir="$HOME/.local"
    local bin_dir="$install_dir/bin"
    local nvim_dir="$install_dir/nvim-linux-x86_64"
    local tarball_url="https://github.com/neovim/neovim/releases/download/v${NVIM_VERSION}/nvim-linux-x86_64.tar.gz"
    local tmp_file="/tmp/nvim-linux-x86_64.tar.gz"

    mkdir -p "$bin_dir"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would download NeoVim tarball to $install_dir"
        return 0
    fi

    # Remove existing nvim installation
    [[ -d "$nvim_dir" ]] && rm -rf "$nvim_dir"
    [[ -L "$bin_dir/nvim" ]] && rm -f "$bin_dir/nvim"

    run_with_spinner "Downloading NeoVim v${NVIM_VERSION}" \
        curl -fsSL "$tarball_url" -o "$tmp_file"

    run_with_spinner "Extracting NeoVim" \
        tar -xzf "$tmp_file" -C "$install_dir"

    rm -f "$tmp_file"

    # Create symlink in bin directory
    ln -sf "$nvim_dir/bin/nvim" "$bin_dir/nvim"

    track_installed "NeoVim v${NVIM_VERSION}"
    log_success "NeoVim installed to $nvim_dir"
    log_info "Symlinked to $bin_dir/nvim"
}

install_neovim() {
    print_section "Installing NeoVim"

    # Check existing installation
    if command_exists nvim; then
        local current_version
        current_version=$(get_nvim_version)
        log_info "NeoVim is already installed: v${current_version}"

        if version_gte "$current_version" "$NVIM_MIN_VERSION"; then
            if [[ "$FORCE" != "true" ]]; then
                log_info "Version meets LazyVim requirement (>= $NVIM_MIN_VERSION)"
                track_skipped "NeoVim"
                return 0
            fi
        else
            log_warn "NeoVim $current_version < $NVIM_MIN_VERSION (required for LazyVim)"
            log_info "Installing newer version..."
        fi
    fi

    case "$PLATFORM" in
        macos)
            pkg_install neovim
            track_installed "NeoVim"
            log_success "NeoVim installed via Homebrew"
            ;;
        linux|wsl)
            install_neovim_tarball
            ;;
    esac
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
                if [[ "$vim_target" == "$spacevim_dir" ]]; then
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
