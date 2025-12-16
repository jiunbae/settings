#!/bin/bash
# tools.sh - Modern CLI tools installation via cargo-binstall
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

# Basic CLI tools
readonly TOOLS_BASIC=(
    "eza"           # ls replacement with icons and git integration
    "fd-find"       # find replacement
    "bat"           # cat replacement with syntax highlighting
    "ripgrep"       # grep replacement (provides 'rg' command)
)

# Extra CLI tools (optional)
readonly TOOLS_EXTRA=(
    "git-delta"     # Better git diff viewer
    "du-dust"       # du replacement with visualization (provides 'dust' command)
    "procs"         # ps replacement
    "bottom"        # htop replacement (provides 'btm' command)
)

# ==============================================================================
# Helper Functions
# ==============================================================================

ensure_cargo_binstall() {
    # Skip check in dry-run mode
    if [[ "$DRY_RUN" == "true" ]]; then
        return 0
    fi

    # Source cargo env
    if [[ -f "$HOME/.cargo/env" ]]; then
        # shellcheck source=/dev/null
        source "$HOME/.cargo/env"
    fi

    if ! command_exists cargo-binstall; then
        log_error "cargo-binstall not found. Please install rust component first."
        log_info "Run: ./install.sh rust"
        return 1
    fi
}

install_tool_via_binstall() {
    local tool=$1

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would install: $tool"
        return 0
    fi

    # Check if already installed
    local cmd_name="$tool"
    # Handle special cases where command name differs from package name
    case "$tool" in
        fd-find) cmd_name="fd" ;;
        ripgrep) cmd_name="rg" ;;
        git-delta) cmd_name="delta" ;;
        du-dust) cmd_name="dust" ;;
        bottom) cmd_name="btm" ;;
    esac

    if command_exists "$cmd_name"; then
        printf "\r${CLEAR_LINE:-}  ${GREEN}✓${NC} %s (already installed)\n" "$tool"
        return 0
    fi

    # Ensure cargo env is loaded in subshell
    local cargo_env=""
    if [[ -f "$HOME/.cargo/env" ]]; then
        cargo_env="source $HOME/.cargo/env && "
    fi

    if run_with_spinner "Installing $tool" bash -c "${cargo_env}cargo binstall -y '$tool'"; then
        return 0
    else
        log_warn "binstall failed, trying cargo install..."
        if run_with_spinner "Building $tool" bash -c "${cargo_env}cargo install '$tool'"; then
            return 0
        else
            printf "\r${CLEAR_LINE:-}  ${RED}✗${NC} Failed to install %s\n" "$tool"
            return 1
        fi
    fi
}

install_tool_via_package_manager() {
    local tool=$1
    local pkg_name=$2

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would install: $pkg_name via $PKG_MANAGER"
        return 0
    fi

    log_info "Installing $tool via $PKG_MANAGER..."
    if pkg_install "$pkg_name"; then
        log_success "$tool installed"
    else
        log_warn "Failed to install $tool via $PKG_MANAGER"
        return 1
    fi
}

# ==============================================================================
# Installation Functions
# ==============================================================================

install_fzf() {
    print_section "Installing fzf"

    if command_exists fzf; then
        log_info "fzf is already installed: $(fzf --version)"
        if [[ "$FORCE" != "true" ]]; then
            return 0
        fi
    fi

    case "$PLATFORM" in
        macos)
            pkg_install fzf
            ;;
        linux|wsl)
            if [[ -d "$HOME/.fzf" ]]; then
                if [[ "$FORCE" == "true" ]]; then
                    rm -rf "$HOME/.fzf"
                else
                    log_info "fzf directory exists, skipping"
                    return 0
                fi
            fi

            if [[ "$DRY_RUN" == "true" ]]; then
                log_info "[DRY-RUN] Would install fzf"
                return 0
            fi

            run_with_spinner "Cloning fzf" \
                git clone --depth 1 https://github.com/junegunn/fzf.git "$HOME/.fzf"
            run_with_spinner "Installing fzf" \
                "$HOME/.fzf/install" --all --no-bash --no-fish
            ;;
    esac

    log_success "fzf installed"
}

install_basic_tools() {
    print_section "Installing Basic CLI Tools"

    ensure_cargo_binstall || return 1

    for tool in "${TOOLS_BASIC[@]}"; do
        install_tool_via_binstall "$tool"
    done

    # Also install fzf
    install_fzf

    log_success "Basic CLI tools installed"
}

install_extra_tools() {
    print_section "Installing Extra CLI Tools"

    ensure_cargo_binstall || return 1

    for tool in "${TOOLS_EXTRA[@]}"; do
        install_tool_via_binstall "$tool"
    done

    log_success "Extra CLI tools installed"
}

# ==============================================================================
# Main Installation
# ==============================================================================

install_tools() {
    log_info "Starting CLI tools installation..."
    install_basic_tools
    log_success "CLI tools installation complete!"
}

install_tools_extra() {
    log_info "Starting extra CLI tools installation..."
    install_extra_tools
    log_success "Extra CLI tools installation complete!"
}

# Print tool aliases info
print_tools_info() {
    cat << EOF

${BOLD}Installed tools and their commands:${NC}

Basic tools:
  ${CYAN}eza${NC}      - Modern ls replacement (alias: ls, ll)
  ${CYAN}fd${NC}       - Modern find replacement
  ${CYAN}bat${NC}      - Modern cat with syntax highlighting
  ${CYAN}rg${NC}       - ripgrep, fast grep replacement
  ${CYAN}fzf${NC}      - Fuzzy finder

Extra tools:
  ${CYAN}delta${NC}    - Better git diff viewer
  ${CYAN}dust${NC}     - Disk usage analyzer (alias: du)
  ${CYAN}procs${NC}    - Modern ps replacement (alias: ps)
  ${CYAN}btm${NC}      - System monitor (alias: top)

Aliases are configured in .zshrc

EOF
}

# ==============================================================================
# Standalone Execution
# ==============================================================================
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    setup_error_handling

    # If run with "extra" argument, install extra tools
    if [[ "${1:-}" == "extra" ]]; then
        install_tools_extra
    else
        install_tools
    fi

    print_tools_info
fi
