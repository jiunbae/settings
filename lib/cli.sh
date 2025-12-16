#!/bin/bash
# cli.sh - CLI argument parsing and help
# Source this file after core.sh

# ==============================================================================
# Version
# ==============================================================================
readonly VERSION="2.0.0"

# ==============================================================================
# Available Components
# ==============================================================================
declare -A COMPONENTS_DESC=(
    [base]="Basic packages (curl, wget, git, build-essential)"
    [zsh]="Zsh + Oh-My-Zsh + Powerlevel10k"
    [nvim]="NeoVim + SpaceVim"
    [tmux]="tmux + TPM (Tmux Plugin Manager)"
    [rust]="Rust toolchain + cargo-binstall"
    [uv]="uv (fast Python package manager)"
    [tools]="CLI tools (eza, fd, bat, ripgrep)"
    [tools-extra]="Extra CLI tools (delta, dust, procs, bottom)"
)

# Order for display
readonly COMPONENTS_ORDER=(base zsh nvim tmux rust uv tools tools-extra)

# Selected components to install
SELECTED_COMPONENTS=()

# ==============================================================================
# Help
# ==============================================================================
print_help() {
    cat << EOF
${BOLD}Settings Installer v${VERSION}${NC}

A modern dotfiles installer with CLI interface.

${BOLD}USAGE:${NC}
    install.sh [OPTIONS] [COMPONENTS...]

${BOLD}OPTIONS:${NC}
    -a, --all           Install all components
    -f, --force         Force reinstall (overwrite existing)
    -v, --verbose       Enable verbose output
    -n, --dry-run       Show what would be done without making changes
    -h, --help          Show this help message
    --version           Show version

${BOLD}COMPONENTS:${NC}
EOF

    for comp in "${COMPONENTS_ORDER[@]}"; do
        printf "    ${CYAN}%-12s${NC}  %s\n" "$comp" "${COMPONENTS_DESC[$comp]}"
    done

    cat << EOF

${BOLD}EXAMPLES:${NC}
    install.sh --all                    # Install everything
    install.sh zsh nvim tmux            # Install specific components
    install.sh -v tools tools-extra     # Install tools with verbose output
    install.sh -n --all                 # Dry-run to see what would happen
    install.sh -f zsh                   # Force reinstall zsh configuration

${BOLD}MORE INFO:${NC}
    Repository: https://github.com/jiunbae/settings
    Log file:   ~/.install.log

EOF
}

print_version() {
    echo "Settings Installer v${VERSION}"
}

# ==============================================================================
# Argument Parsing
# ==============================================================================
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -a|--all)
                SELECTED_COMPONENTS=("${COMPONENTS_ORDER[@]}")
                shift
                ;;
            -f|--force)
                FORCE=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -n|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -h|--help)
                print_help
                exit 0
                ;;
            --version)
                print_version
                exit 0
                ;;
            -*)
                log_error "Unknown option: $1"
                echo ""
                print_help
                exit 1
                ;;
            *)
                # Check if it's a valid component
                if [[ -n "${COMPONENTS_DESC[$1]:-}" ]]; then
                    SELECTED_COMPONENTS+=("$1")
                else
                    log_error "Unknown component: $1"
                    echo ""
                    echo "Available components:"
                    for comp in "${COMPONENTS_ORDER[@]}"; do
                        echo "  - $comp"
                    done
                    exit 1
                fi
                shift
                ;;
        esac
    done

    # Export global flags
    export VERBOSE DRY_RUN FORCE

    # Check if any component selected
    if [[ ${#SELECTED_COMPONENTS[@]} -eq 0 ]]; then
        log_error "No components specified."
        echo ""
        echo "Use --all to install everything, or specify components:"
        echo "  install.sh --all"
        echo "  install.sh zsh nvim tmux"
        echo ""
        echo "Run 'install.sh --help' for more information."
        exit 1
    fi
}

# ==============================================================================
# Component Helpers
# ==============================================================================

# Check if a component is selected
is_selected() {
    local component=$1
    for selected in "${SELECTED_COMPONENTS[@]}"; do
        if [[ "$selected" == "$component" ]]; then
            return 0
        fi
    done
    return 1
}

# Print selected components
print_selected() {
    echo ""
    log_info "Selected components:"
    for comp in "${SELECTED_COMPONENTS[@]}"; do
        echo "  - $comp: ${COMPONENTS_DESC[$comp]}"
    done
    echo ""

    if [[ "$DRY_RUN" == "true" ]]; then
        log_warn "DRY-RUN mode: No changes will be made"
    fi
    if [[ "$FORCE" == "true" ]]; then
        log_warn "FORCE mode: Existing configurations will be overwritten"
    fi
    echo ""
}
