#!/bin/bash
#
# Settings Bootstrap Installer
# https://github.com/jiunbae/settings
#
# One-line installation:
#   curl -fsSL https://raw.githubusercontent.com/jiunbae/settings/master/bootstrap.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/jiunbae/settings/master/bootstrap.sh | bash -s -- --all
#   curl -fsSL https://raw.githubusercontent.com/jiunbae/settings/master/bootstrap.sh | bash -s -- zsh nvim
#

set -euo pipefail

# ==============================================================================
# Configuration
# ==============================================================================
REPO_URL="https://github.com/jiunbae/settings"
REPO_NAME="settings"
INSTALL_DIR="${SETTINGS_INSTALL_DIR:-$HOME/.settings}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ==============================================================================
# Helper Functions
# ==============================================================================
log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

command_exists() { command -v "$1" >/dev/null 2>&1; }

# ==============================================================================
# Main Bootstrap Logic
# ==============================================================================
main() {
    echo ""
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC}  Settings Bootstrap Installer                                ${BLUE}║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    # Check for required tools
    if ! command_exists curl && ! command_exists wget; then
        log_error "curl or wget is required"
        exit 1
    fi

    # Download method selection
    if command_exists git; then
        download_with_git
    else
        download_with_tarball
    fi

    # Run installer
    run_installer "$@"

    # Cleanup option
    if [[ "${SETTINGS_KEEP_SOURCE:-false}" != "true" ]]; then
        log_info "Installation directory: $INSTALL_DIR"
        log_info "Set SETTINGS_KEEP_SOURCE=true to keep source files"
    fi
}

download_with_git() {
    log_info "Downloading via git clone..."

    if [[ -d "$INSTALL_DIR" ]]; then
        log_info "Updating existing installation..."
        cd "$INSTALL_DIR"
        git fetch origin
        git reset --hard origin/master
    else
        git clone --depth 1 "$REPO_URL.git" "$INSTALL_DIR"
    fi

    log_success "Downloaded to $INSTALL_DIR"
}

download_with_tarball() {
    log_info "Downloading via tarball (git not available)..."

    local tarball_url="$REPO_URL/archive/refs/heads/master.tar.gz"
    local tmp_dir=$(mktemp -d)

    # Download
    if command_exists curl; then
        curl -fsSL "$tarball_url" | tar -xz -C "$tmp_dir"
    else
        wget -qO- "$tarball_url" | tar -xz -C "$tmp_dir"
    fi

    # Move to install directory
    rm -rf "$INSTALL_DIR"
    mv "$tmp_dir/$REPO_NAME-master" "$INSTALL_DIR"
    rm -rf "$tmp_dir"

    log_success "Downloaded to $INSTALL_DIR"
}

run_installer() {
    log_info "Running installer..."
    echo ""

    cd "$INSTALL_DIR"
    chmod +x install.sh

    if [[ $# -eq 0 ]]; then
        # Interactive mode - show help
        ./install.sh --help
        echo ""
        log_info "Run with arguments to install components:"
        echo "  cd $INSTALL_DIR && ./install.sh --all"
        echo "  cd $INSTALL_DIR && ./install.sh zsh nvim tmux"
    else
        # Pass arguments to installer
        ./install.sh "$@"
    fi
}

# ==============================================================================
# Entry Point
# ==============================================================================
main "$@"
