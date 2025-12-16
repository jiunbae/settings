#!/bin/bash
# rust.sh - Rust toolchain + cargo-binstall installation
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
readonly CARGO_HOME="${CARGO_HOME:-$HOME/.cargo}"
readonly CARGO_BIN="$CARGO_HOME/bin"

# ==============================================================================
# Installation Functions
# ==============================================================================

install_rustup() {
    print_section "Installing Rust Toolchain"

    if command_exists rustup; then
        log_info "Rust is already installed: $(rustc --version)"
        if [[ "$FORCE" == "true" ]]; then
            run_with_spinner "Updating Rust" rustup update
        fi
        return 0
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would install Rust via rustup"
        return 0
    fi

    run_with_spinner "Installing Rust via rustup" \
        bash -c "curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path"

    # Source cargo env for current session
    if [[ -f "$CARGO_HOME/env" ]]; then
        # shellcheck source=/dev/null
        source "$CARGO_HOME/env"
    fi

    if command_exists rustc; then
        log_info "Rust version: $(rustc --version)"
    fi
}

install_cargo_binstall() {
    print_section "Installing cargo-binstall"

    # Ensure cargo is available
    if [[ -f "$CARGO_HOME/env" ]]; then
        # shellcheck source=/dev/null
        source "$CARGO_HOME/env"
    fi

    if ! command_exists cargo; then
        log_error "Cargo not found. Please install Rust first."
        return 1
    fi

    if command_exists cargo-binstall; then
        log_info "cargo-binstall is already installed"
        if [[ "$FORCE" != "true" ]]; then
            return 0
        fi
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would install cargo-binstall"
        return 0
    fi

    # Try to install via pre-built binary first (faster)
    local install_script="https://raw.githubusercontent.com/cargo-bins/cargo-binstall/main/install-from-binstall-release.sh"
    if run_with_spinner "Installing cargo-binstall" \
        bash -c "curl -L --proto '=https' --tlsv1.2 -sSf '$install_script' | bash"; then
        :  # Success
    else
        # Fallback to cargo install
        log_warn "Binary install failed, building from source..."
        run_with_spinner "Building cargo-binstall from source" \
            cargo install cargo-binstall
    fi
}

setup_cargo_path() {
    # Path setup is handled in .zshrc
    log_info "Cargo PATH is configured in .zshrc"
    log_debug "CARGO_HOME: $CARGO_HOME"
    log_debug "CARGO_BIN: $CARGO_BIN"
}

# ==============================================================================
# Main Installation
# ==============================================================================

install_rust() {
    log_info "Starting Rust toolchain installation..."

    install_rustup
    install_cargo_binstall
    setup_cargo_path

    log_success "Rust toolchain installation complete!"
}

# ==============================================================================
# Standalone Execution
# ==============================================================================
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    setup_error_handling
    install_rust
fi
