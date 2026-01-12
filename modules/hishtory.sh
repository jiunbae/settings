#!/bin/bash
# hishtory.sh - hishtory (better shell history) installation
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
HISHTORY_CONFIG_DIR="${HOME}/.hishtory"

# Self-hosted server configuration (optional)
# Set these in your environment or ~/.envs/hishtory.env
# HISHTORY_SERVER - URL of self-hosted hishtory server
# HISHTORY_SECRET - Secret key for syncing across devices

# ==============================================================================
# Installation Functions
# ==============================================================================

install_hishtory_binary() {
    print_section "Installing hishtory"

    if command_exists hishtory; then
        log_info "hishtory is already installed"
        if [[ "$FORCE" != "true" ]]; then
            track_skipped "hishtory"
            return 0
        fi
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would install hishtory"
        return 0
    fi

    log_info "Installing hishtory..."

    # Method 1: Try homebrew on macOS
    if [[ "$PLATFORM" == "macos" ]] && command_exists brew; then
        log_info "Installing via homebrew..."
        if brew install hishtory 2>/dev/null; then
            track_installed "hishtory"
            log_success "hishtory installed via homebrew"
            return 0
        fi
    fi

    # Method 2: Try go install if Go is available
    if command_exists go; then
        log_info "Installing via go install..."
        if go install github.com/ddworken/hishtory@latest 2>/dev/null; then
            track_installed "hishtory"
            log_success "hishtory installed via go install"
            return 0
        fi
    fi

    # Method 3: Download pre-built binary
    log_info "Downloading pre-built binary..."
    local os arch binary_url
    os=$(uname -s | tr '[:upper:]' '[:lower:]')
    arch=$(uname -m)

    case "$arch" in
        x86_64) arch="amd64" ;;
        aarch64|arm64) arch="arm64" ;;
    esac

    binary_url="https://github.com/ddworken/hishtory/releases/latest/download/hishtory-${os}-${arch}"

    mkdir -p "$HISHTORY_CONFIG_DIR"

    if curl -fsSL "$binary_url" -o "$HISHTORY_CONFIG_DIR/hishtory"; then
        chmod +x "$HISHTORY_CONFIG_DIR/hishtory"
        track_installed "hishtory"
        log_success "hishtory installed to $HISHTORY_CONFIG_DIR/hishtory"
        return 0
    else
        log_error "Failed to download hishtory binary"
        return 1
    fi
}

setup_hishtory_env() {
    print_section "Setting up hishtory environment"

    local source_config="$SCRIPT_DIR/../configs/hishtory"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would setup hishtory environment"
        return 0
    fi

    # Copy env template if not exists
    if [[ -f "$source_config/hishtory.env.example" ]]; then
        if [[ ! -f "$HOME/.envs/hishtory.env" ]]; then
            mkdir -p "$HOME/.envs"
            cp "$source_config/hishtory.env.example" "$HOME/.envs/hishtory.env"
            log_info "Created ~/.envs/hishtory.env - configure HISHTORY_SERVER and HISHTORY_SECRET for sync"
        else
            log_info "~/.envs/hishtory.env already exists"
        fi
    fi

    log_success "hishtory environment configured"
}

init_hishtory() {
    print_section "Initializing hishtory"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would initialize hishtory"
        return 0
    fi

    # Load env file if exists
    [[ -f "$HOME/.envs/hishtory.env" ]] && source "$HOME/.envs/hishtory.env"

    local hishtory_bin
    if [[ -f "$HISHTORY_CONFIG_DIR/hishtory" ]]; then
        hishtory_bin="$HISHTORY_CONFIG_DIR/hishtory"
    elif command_exists hishtory; then
        hishtory_bin="hishtory"
    else
        log_warn "hishtory not found, skipping initialization"
        return 0
    fi

    # Only initialize if server and secret are configured
    # Without server, init hangs waiting for api.hishtory.dev
    if [[ -n "${HISHTORY_SERVER:-}" && -n "${HISHTORY_SECRET:-}" ]]; then
        log_info "Initializing with provided secret key..."
        # Use 'yes' to auto-confirm if existing history entries exist
        yes | timeout 10 "$hishtory_bin" init "$HISHTORY_SECRET" 2>/dev/null || true
        log_success "hishtory initialized with sync enabled"
    else
        log_info "Skipping init (configure HISHTORY_SERVER and HISHTORY_SECRET for sync)"
        log_success "hishtory installed (local-only mode)"
    fi
}

# ==============================================================================
# Main Installation
# ==============================================================================

install_hishtory() {
    log_info "Starting hishtory installation..."

    install_hishtory_binary || return 1
    setup_hishtory_env
    init_hishtory

    log_success "hishtory installation complete!"
}

# Print hishtory info
print_hishtory_info() {
    cat << EOF

${BOLD}════════════════════════════════════════════════════════════════${NC}
${BOLD}hishtory - Better Shell History${NC}
${BOLD}════════════════════════════════════════════════════════════════${NC}

${BOLD}Commands:${NC}
  ${CYAN}Ctrl+R${NC}              - Interactive history search (TUI)
  ${CYAN}hishtory query${NC}      - Search history
  ${CYAN}hishtory status${NC}     - Show sync status and secret key
  ${CYAN}hishtory export${NC}     - Export history

${BOLD}Configuration:${NC}
  Edit ${CYAN}~/.envs/hishtory.env${NC}:

    # Self-hosted server URL (optional)
    export HISHTORY_SERVER="https://hishtory.example.com"

    # Secret key for cross-device sync
    export HISHTORY_SECRET="your-secret-key-uuid"

${BOLD}Sync Setup:${NC}
  1. Get your secret key:  ${CYAN}hishtory status${NC}
  2. Add to ~/.envs/hishtory.env on all devices
  3. Restart shell or run: ${CYAN}source ~/.zshrc${NC}

${BOLD}Note:${NC}
  - Without HISHTORY_SERVER, runs in local-only mode
  - Use the same HISHTORY_SECRET on all devices to sync

EOF
}

# ==============================================================================
# Standalone Execution
# ==============================================================================
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    setup_error_handling
    install_hishtory
    print_hishtory_info
fi
