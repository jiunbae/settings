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
HISHTORY_VERSION="${HISHTORY_VERSION:-latest}"
HISHTORY_CONFIG_DIR="${HOME}/.hishtory"

# S3 backend configuration (for self-hosted MinIO)
# Set these in your environment or ~/.envs/hishtory.env
HISHTORY_S3_ENDPOINT="${HISHTORY_S3_ENDPOINT:-}"
HISHTORY_S3_BUCKET="${HISHTORY_S3_BUCKET:-hishtory}"
HISHTORY_S3_ACCESS_KEY="${HISHTORY_S3_ACCESS_KEY:-}"
HISHTORY_S3_SECRET_KEY="${HISHTORY_S3_SECRET_KEY:-}"

# ==============================================================================
# Installation Functions
# ==============================================================================

install_hishtory_binary() {
    print_section "Installing hishtory"

    if command_exists hishtory; then
        local current_version
        current_version=$(hishtory version 2>/dev/null || echo "unknown")
        log_info "hishtory is already installed: $current_version"
        if [[ "$FORCE" != "true" ]]; then
            track_skipped "hishtory"
            return 0
        fi
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would install hishtory"
        return 0
    fi

    # Install via Go install or download binary
    log_info "Installing hishtory..."

    # Method 1: Try go install if Go is available
    if command_exists go; then
        log_info "Installing via go install..."
        if go install github.com/ddworken/hishtory@latest 2>/dev/null; then
            track_installed "hishtory"
            log_success "hishtory installed via go install"
            return 0
        fi
    fi

    # Method 2: Download pre-built binary
    log_info "Downloading pre-built binary..."
    local os arch binary_url
    os=$(uname -s | tr '[:upper:]' '[:lower:]')
    arch=$(uname -m)

    case "$arch" in
        x86_64) arch="amd64" ;;
        aarch64|arm64) arch="arm64" ;;
    esac

    binary_url="https://github.com/ddworken/hishtory/releases/latest/download/hishtory-${os}-${arch}"

    local install_dir="$HOME/.hishtory"
    mkdir -p "$install_dir"

    if curl -fsSL "$binary_url" -o "$install_dir/hishtory"; then
        chmod +x "$install_dir/hishtory"

        # Add to PATH if not already
        if [[ ":$PATH:" != *":$install_dir:"* ]]; then
            export PATH="$install_dir:$PATH"
        fi

        track_installed "hishtory"
        log_success "hishtory installed to $install_dir/hishtory"
        return 0
    else
        log_error "Failed to download hishtory binary"
        return 1
    fi
}

configure_hishtory_s3() {
    print_section "Configuring hishtory S3 backend"

    # Check if S3 configuration is provided
    if [[ -z "$HISHTORY_S3_ENDPOINT" ]]; then
        log_info "S3 endpoint not configured, skipping S3 backend setup"
        log_info "Set HISHTORY_S3_ENDPOINT to configure S3 backend"
        return 0
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would configure hishtory S3 backend"
        return 0
    fi

    # Create config directory
    mkdir -p "$HISHTORY_CONFIG_DIR"

    # Create config.json with S3 backend
    local config_file="$HISHTORY_CONFIG_DIR/config.json"

    # Backup existing config
    if [[ -f "$config_file" ]]; then
        cp "$config_file" "${config_file}.backup.$(date +%Y%m%d%H%M%S)"
    fi

    cat > "$config_file" << EOF
{
    "beta_mode": true,
    "custom_s3_endpoint": "${HISHTORY_S3_ENDPOINT}",
    "s3_bucket": "${HISHTORY_S3_BUCKET}",
    "s3_access_key": "${HISHTORY_S3_ACCESS_KEY}",
    "s3_secret_key": "${HISHTORY_S3_SECRET_KEY}"
}
EOF

    chmod 600 "$config_file"
    log_success "hishtory S3 backend configured"
}

setup_hishtory_shell_integration() {
    print_section "Setting up hishtory shell integration"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would setup shell integration"
        return 0
    fi

    # hishtory init will add shell integration
    if command_exists hishtory; then
        # Initialize hishtory (this adds to .zshrc automatically)
        hishtory init zsh 2>/dev/null || true
        log_success "hishtory shell integration configured"
    else
        log_warn "hishtory not found, skipping shell integration"
    fi
}

link_hishtory_config() {
    print_section "Linking hishtory configuration"

    local source_config="$SCRIPT_DIR/../configs/hishtory"
    local target_config="$HISHTORY_CONFIG_DIR"

    if [[ ! -d "$source_config" ]]; then
        log_info "No hishtory config in dotfiles, skipping"
        return 0
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would link hishtory config"
        return 0
    fi

    mkdir -p "$target_config"

    # Link env template if exists
    if [[ -f "$source_config/hishtory.env.example" ]]; then
        if [[ ! -f "$HOME/.envs/hishtory.env" ]]; then
            mkdir -p "$HOME/.envs"
            cp "$source_config/hishtory.env.example" "$HOME/.envs/hishtory.env"
            log_info "Created ~/.envs/hishtory.env - please configure your S3 credentials"
        fi
    fi

    log_success "hishtory configuration linked"
}

# ==============================================================================
# Main Installation
# ==============================================================================

install_hishtory() {
    log_info "Starting hishtory installation..."

    install_hishtory_binary || return 1
    link_hishtory_config
    configure_hishtory_s3
    setup_hishtory_shell_integration

    log_success "hishtory installation complete!"
}

# Print hishtory info
print_hishtory_info() {
    cat << EOF

${BOLD}hishtory - Better Shell History${NC}

Commands:
  ${CYAN}hishtory query${NC}      - Search history (Ctrl+R)
  ${CYAN}hishtory export${NC}     - Export history
  ${CYAN}hishtory status${NC}     - Show sync status
  ${CYAN}hishtory config-get${NC} - View configuration

S3 Backend:
  Configure in ~/.envs/hishtory.env:
    HISHTORY_S3_ENDPOINT=https://minio.internal.jiun.dev
    HISHTORY_S3_BUCKET=hishtory
    HISHTORY_S3_ACCESS_KEY=your-access-key
    HISHTORY_S3_SECRET_KEY=your-secret-key

  Then run: ./install.sh hishtory

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
