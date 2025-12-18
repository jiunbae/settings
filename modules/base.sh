#!/bin/bash
# base.sh - Basic packages installation
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

# Basic packages for all platforms
readonly BASE_PACKAGES_COMMON=(
    curl
    wget
    git
)

# Linux-specific packages
readonly BASE_PACKAGES_LINUX=(
    build-essential
    gcc
    g++
    make
    unzip
    zip
)

# macOS-specific (most come with Xcode CLT)
readonly BASE_PACKAGES_MACOS=(
    coreutils
)

# ==============================================================================
# Installation Functions
# ==============================================================================

install_xcode_clt() {
    if [[ "$PLATFORM" != "macos" ]]; then
        return 0
    fi

    print_section "Checking Xcode Command Line Tools"

    if xcode-select -p &>/dev/null; then
        log_info "Xcode Command Line Tools already installed"
        track_skipped "Xcode CLT"
        return 0
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would install Xcode Command Line Tools"
        return 0
    fi

    log_info "Installing Xcode Command Line Tools..."
    xcode-select --install

    # Wait for installation
    log_info "Please complete the Xcode CLT installation dialog..."
    until xcode-select -p &>/dev/null; do
        sleep 5
    done

    track_installed "Xcode CLT"
    log_success "Xcode Command Line Tools installed"
}

install_base_packages() {
    print_section "Installing Base Packages"

    # Update package manager first
    pkg_update

    # Install common packages
    log_info "Installing common packages..."
    pkg_install "${BASE_PACKAGES_COMMON[@]}"
    track_installed "Base packages (curl, wget, git)"

    # Install platform-specific packages
    case "$PLATFORM" in
        macos)
            install_xcode_clt
            log_info "Installing macOS-specific packages..."
            pkg_install "${BASE_PACKAGES_MACOS[@]}"
            track_installed "macOS packages (coreutils)"
            ;;
        linux|wsl)
            log_info "Installing Linux-specific packages..."
            pkg_install "${BASE_PACKAGES_LINUX[@]}"
            track_installed "Linux packages (build-essential, gcc, etc.)"
            ;;
    esac

    log_success "Base packages installed"
}

# ==============================================================================
# Main Installation
# ==============================================================================

install_base() {
    log_info "Starting base packages installation..."

    install_base_packages

    log_success "Base packages installation complete!"
}

# ==============================================================================
# Standalone Execution
# ==============================================================================
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    setup_error_handling
    install_base
fi
