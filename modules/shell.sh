#!/bin/bash
# shell.sh - Zsh + Oh-My-Zsh + Powerlevel10k installation
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
readonly ZSH_CUSTOM_DIR="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
readonly P10K_THEME_DIR="$ZSH_CUSTOM_DIR/themes/powerlevel10k"

# Plugins to install
readonly ZSH_PLUGINS=(
    "zsh-syntax-highlighting|https://github.com/zsh-users/zsh-syntax-highlighting.git"
    "zsh-autosuggestions|https://github.com/zsh-users/zsh-autosuggestions.git"
    "git-extra-commands|https://github.com/unixorn/git-extra-commands.git"
)

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

install_oh_my_zsh() {
    print_section "Installing Oh-My-Zsh"

    if [[ -d "$HOME/.oh-my-zsh" ]]; then
        if [[ "$FORCE" == "true" ]]; then
            log_info "Removing existing Oh-My-Zsh..."
            rm -rf "$HOME/.oh-my-zsh"
        else
            echo -e "${GREEN}✓${NC} Oh-My-Zsh (already installed)"
            track_skipped "Oh-My-Zsh"
            return 0
        fi
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would install Oh-My-Zsh"
        return 0
    fi

    # Install silently
    run_with_spinner "Installing Oh-My-Zsh" \
        sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
    track_installed "Oh-My-Zsh"
}

install_powerlevel10k() {
    print_section "Installing Powerlevel10k Theme"

    if [[ -d "$P10K_THEME_DIR" ]]; then
        if [[ "$FORCE" == "true" ]]; then
            log_info "Removing existing Powerlevel10k..."
            rm -rf "$P10K_THEME_DIR"
        else
            log_info "Powerlevel10k is already installed"
            track_skipped "Powerlevel10k"
            return 0
        fi
    fi

    git_clone "https://github.com/romkatv/powerlevel10k.git" "$P10K_THEME_DIR"
    track_installed "Powerlevel10k"
    log_success "Powerlevel10k installed"
}

install_zsh_plugins() {
    print_section "Installing Zsh Plugins"

    local plugins_dir="$ZSH_CUSTOM_DIR/plugins"
    mkdir -p "$plugins_dir"

    for plugin_entry in "${ZSH_PLUGINS[@]}"; do
        local name="${plugin_entry%%|*}"
        local url="${plugin_entry##*|}"
        local plugin_dir="$plugins_dir/$name"

        if [[ -d "$plugin_dir" ]]; then
            if [[ "$FORCE" == "true" ]]; then
                log_info "Removing existing plugin: $name"
                rm -rf "$plugin_dir"
            else
                log_info "Plugin already installed: $name"
                track_skipped "Zsh plugin: $name"
                continue
            fi
        fi

        git_clone "$url" "$plugin_dir"
        track_installed "Zsh plugin: $name"
    done

    log_success "Zsh plugins installed"
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
    install_oh_my_zsh
    install_powerlevel10k
    install_zsh_plugins
    link_zsh_configs
    change_default_shell

    log_success "Shell environment installation complete!"
}

# ==============================================================================
# Standalone Execution
# ==============================================================================
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    setup_error_handling
    install_shell
fi
