#!/bin/bash
#
# Mac Mini K3s Worker Node Setup Script
# ======================================
# This script sets up a Mac Mini M4 as a K3s worker node using OrbStack.
#
# Usage:
#   ./setup-mac-mini.sh [options]
#
# Options:
#   --env ENV        Set environment (dev/prod), overrides config.env
#   --config FILE    Use custom config file (default: config.env)
#   --skip-orbstack  Skip OrbStack installation
#   --skip-vm        Skip VM creation
#   --skip-network   Skip network configuration
#   --skip-k3s       Skip K3s installation
#   --tailscale      Install Tailscale for overlay networking
#   --dry-run        Show what would be done without executing
#   -h, --help       Show this help message
#

set -e

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default values
CONFIG_FILE="${SCRIPT_DIR}/config.env"
DRY_RUN=false
SKIP_ORBSTACK=false
SKIP_VM=false
SKIP_NETWORK=false
SKIP_K3S=false
INSTALL_TAILSCALE=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Show help
show_help() {
    head -30 "$0" | grep -E "^#" | sed 's/^# *//'
    exit 0
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --env)
                NODE_ENV="$2"
                shift 2
                ;;
            --config)
                CONFIG_FILE="$2"
                shift 2
                ;;
            --skip-orbstack)
                SKIP_ORBSTACK=true
                shift
                ;;
            --skip-vm)
                SKIP_VM=true
                shift
                ;;
            --skip-network)
                SKIP_NETWORK=true
                shift
                ;;
            --skip-k3s)
                SKIP_K3S=true
                shift
                ;;
            --tailscale)
                INSTALL_TAILSCALE=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            -h|--help)
                show_help
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                ;;
        esac
    done
}

# Load configuration
load_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        log_error "Configuration file not found: $CONFIG_FILE"
        echo ""
        echo "Please create a config file:"
        echo "  cp config.env.example config.env"
        echo "  vim config.env"
        exit 1
    fi

    log_info "Loading configuration from: $CONFIG_FILE"
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"

    # Validate required settings
    if [ -z "$K3S_URL" ]; then
        log_error "K3S_URL is not set in config"
        exit 1
    fi

    if [ -z "$K3S_TOKEN" ]; then
        log_error "K3S_TOKEN is not set in config"
        echo "Get token from master: sudo cat /var/lib/rancher/k3s/server/node-token"
        exit 1
    fi
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check macOS
    if [[ "$(uname)" != "Darwin" ]]; then
        log_error "This script is for macOS only"
        exit 1
    fi

    # Check Apple Silicon
    if [[ "$(uname -m)" != "arm64" ]]; then
        log_warn "This script is optimized for Apple Silicon (ARM64)"
        log_warn "Running on $(uname -m) may have different behavior"
    fi

    # Check Homebrew
    if ! command -v brew &> /dev/null; then
        log_error "Homebrew is not installed"
        echo "Install from: https://brew.sh"
        exit 1
    fi

    log_success "Prerequisites check passed"
}

# Source library scripts
source_libs() {
    source "${SCRIPT_DIR}/lib/install-orbstack.sh"
    source "${SCRIPT_DIR}/lib/create-vm.sh"
    source "${SCRIPT_DIR}/lib/configure-network.sh"
    source "${SCRIPT_DIR}/lib/join-k3s.sh"
}

# Main setup function
main() {
    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║     Mac Mini K3s Worker Node Setup                         ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""

    parse_args "$@"
    load_config
    source_libs
    check_prerequisites

    # Show configuration
    echo ""
    log_info "Configuration:"
    echo "  K3s URL:      $K3S_URL"
    echo "  Node Name:    ${NODE_NAME:-$VM_NAME}"
    echo "  Environment:  ${NODE_ENV:-dev}"
    echo "  Purpose:      ${NODE_PURPOSE:-general}"
    echo "  VM Name:      ${VM_NAME:-k3s-worker}"
    echo "  Network Mode: ${NETWORK_MODE:-nat}"
    echo ""

    if [ "$DRY_RUN" = true ]; then
        log_warn "Dry run mode - no changes will be made"
        echo ""
        echo "Steps that would be executed:"
        [ "$SKIP_ORBSTACK" != true ] && echo "  1. Install OrbStack"
        [ "$SKIP_VM" != true ] && echo "  2. Create Linux VM"
        [ "$SKIP_NETWORK" != true ] && echo "  3. Configure network"
        [ "$INSTALL_TAILSCALE" = true ] && echo "  4. Install Tailscale"
        [ "$SKIP_K3S" != true ] && echo "  5. Join K3s cluster"
        exit 0
    fi

    # Confirm before proceeding
    read -p "Proceed with setup? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Setup cancelled"
        exit 0
    fi

    echo ""

    # Step 1: Install OrbStack
    if [ "$SKIP_ORBSTACK" != true ]; then
        log_info "Step 1/5: Installing OrbStack..."
        install_orbstack
        log_success "OrbStack installed"
    else
        log_info "Step 1/5: Skipping OrbStack installation"
    fi
    echo ""

    # Step 2: Create VM
    if [ "$SKIP_VM" != true ]; then
        log_info "Step 2/5: Creating Linux VM..."
        create_vm
        log_success "VM created"
    else
        log_info "Step 2/5: Skipping VM creation"
    fi
    echo ""

    # Step 3: Configure network
    if [ "$SKIP_NETWORK" != true ]; then
        log_info "Step 3/5: Configuring network..."
        configure_network
        log_success "Network configured"
    else
        log_info "Step 3/5: Skipping network configuration"
    fi
    echo ""

    # Step 4: Install Tailscale (optional)
    if [ "$INSTALL_TAILSCALE" = true ]; then
        log_info "Step 4/5: Installing Tailscale..."
        setup_tailscale
        log_success "Tailscale installed"
    else
        log_info "Step 4/5: Skipping Tailscale installation"
    fi
    echo ""

    # Step 5: Join K3s cluster
    if [ "$SKIP_K3S" != true ]; then
        log_info "Step 5/5: Joining K3s cluster..."
        join_k3s_cluster
        log_success "Joined K3s cluster"
    else
        log_info "Step 5/5: Skipping K3s installation"
    fi
    echo ""

    # Final verification
    log_info "Running verification..."
    verify_join
    echo ""

    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║     Setup Complete!                                        ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
    echo "Next steps:"
    echo "  1. Verify node from K3s master:"
    echo "     kubectl get nodes -o wide"
    echo ""
    echo "  2. Check node labels:"
    echo "     kubectl get nodes --show-labels"
    echo ""
    echo "  3. Access VM:"
    echo "     orb shell ${VM_NAME:-k3s-worker}"
    echo ""
    echo "  4. View K3s agent logs:"
    echo "     orb -m ${VM_NAME:-k3s-worker} sudo journalctl -u k3s-agent -f"
    echo ""
}

# Run main
main "$@"
