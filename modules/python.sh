#!/bin/bash
# python.sh - uv (fast Python package manager) installation
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
readonly UV_INSTALL_DIR="$HOME/.local/bin"

# ==============================================================================
# Installation Functions
# ==============================================================================

install_uv_package() {
    print_section "Installing uv (Python Package Manager)"

    if command_exists uv; then
        log_info "uv is already installed: $(uv --version)"
        if [[ "$FORCE" == "true" ]]; then
            log_info "Reinstalling uv..."
        else
            track_skipped "uv"
            return 0
        fi
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would install uv"
        return 0
    fi

    # Install via official installer
    run_with_spinner "Installing uv" \
        bash -c "curl -LsSf https://astral.sh/uv/install.sh | sh"

    # Add to PATH for current session
    export PATH="$UV_INSTALL_DIR:$PATH"

    if command_exists uv; then
        log_info "uv version: $(uv --version)"
        track_installed "uv"
    else
        log_error "uv installation failed"
        return 1
    fi
}

setup_uv_shell_completion() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would setup uv shell completion"
        return 0
    fi

    # Shell completion is configured in .zshrc
    log_info "uv shell completion is configured in .zshrc"
}

install_python_version() {
    # Optional: Install a Python version via uv
    if [[ "$DRY_RUN" == "true" ]]; then
        return 0
    fi

    if command_exists uv; then
        log_info "You can install Python versions using: uv python install 3.12"
    fi
}

# ==============================================================================
# Main Installation
# ==============================================================================

install_uv() {
    log_info "Starting uv installation..."

    install_uv_package
    setup_uv_shell_completion
    install_python_version

    log_success "uv installation complete!"
    log_info "To install Python: uv python install 3.12"
    log_info "To create a project: uv init myproject"
}

# ==============================================================================
# Standalone Execution
# ==============================================================================
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    setup_error_handling
    install_uv
fi
