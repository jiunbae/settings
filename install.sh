#!/bin/bash
#
# Settings Installer v2.0.0
# https://github.com/jiunbae/settings
#
# A modern dotfiles installer with CLI interface.
#
# Usage:
#   ./install.sh --all           Install all components
#   ./install.sh zsh nvim tmux   Install specific components
#   ./install.sh --help          Show help
#

set -euo pipefail

# ==============================================================================
# Script Directory Resolution
# ==============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ==============================================================================
# Load Libraries
# ==============================================================================
source "$SCRIPT_DIR/lib/core.sh"
source "$SCRIPT_DIR/lib/platform.sh"
source "$SCRIPT_DIR/lib/cli.sh"

# ==============================================================================
# Load Modules
# ==============================================================================
source "$SCRIPT_DIR/modules/base.sh"
source "$SCRIPT_DIR/modules/shell.sh"
source "$SCRIPT_DIR/modules/editor.sh"
source "$SCRIPT_DIR/modules/tmux.sh"
source "$SCRIPT_DIR/modules/rust.sh"
source "$SCRIPT_DIR/modules/python.sh"
source "$SCRIPT_DIR/modules/tools.sh"
source "$SCRIPT_DIR/modules/ssh.sh"

# ==============================================================================
# Component Names (for display) - bash 3.2 compatible
# ==============================================================================
get_component_name() {
    case "$1" in
        base)        echo "Base packages" ;;
        zsh)         echo "Zsh + zinit + Powerlevel10k" ;;
        nvim)        echo "NeoVim + SpaceVim" ;;
        tmux)        echo "tmux + TPM" ;;
        rust)        echo "Rust toolchain" ;;
        uv)          echo "uv (Python)" ;;
        tools)       echo "CLI tools" ;;
        tools-extra) echo "Extra CLI tools" ;;
        ssh)         echo "SSH config" ;;
        *)           echo "$1" ;;
    esac
}

# ==============================================================================
# Main Function
# ==============================================================================
main() {
    # Initialize logging
    echo "=== Installation started at $(date) ===" >> "$LOG_FILE"

    # Setup error handling
    setup_error_handling

    # Parse command line arguments
    parse_args "$@"

    # Detect platform and setup package manager (silent)
    detect_platform >/dev/null 2>&1 || detect_platform
    setup_package_manager >/dev/null 2>&1 || setup_package_manager

    # Initialize progress display
    local total=${#SELECTED_COMPONENTS[@]}
    progress_init "$total" "${SELECTED_COMPONENTS[@]}"

    # Dry-run notice
    if [[ "$DRY_RUN" == "true" ]]; then
        progress_info "DRY-RUN mode: No changes will be made"
    fi

    # Install selected components
    for component in "${SELECTED_COMPONENTS[@]}"; do
        local display_name
        display_name="$(get_component_name "$component")"
        progress_start_component "$display_name"

        case "$component" in
            base)
                install_base
                ;;
            zsh)
                install_shell
                ;;
            nvim)
                install_editor
                ;;
            tmux)
                install_tmux
                ;;
            rust)
                install_rust
                ;;
            uv)
                install_uv
                ;;
            tools)
                install_tools
                ;;
            tools-extra)
                install_tools_extra
                ;;
            ssh)
                install_ssh
                ;;
            *)
                progress_info "Unknown component: $component"
                ;;
        esac
    done

    # Print progress completion
    progress_finish

    # Print detailed installation summary
    print_install_summary

    # Log completion
    echo "=== Installation completed at $(date) ===" >> "$LOG_FILE"
}

# ==============================================================================
# Entry Point
# ==============================================================================
main "$@"
