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
# Component list (bash 3.2 compatible - no associative arrays)
readonly COMPONENTS_ORDER=(base zsh nvim tmux rust uv tools tools-extra ssh hishtory)

# Basic components for --basic option
readonly BASIC_COMPONENTS=(base zsh nvim tmux)

# Core components for --core / interactive default
readonly CORE_COMPONENTS=(base zsh nvim tmux tools)

# Get component description (bash 3.2 compatible alternative to associative array)
get_component_desc() {
    case "$1" in
        base)        echo "Basic packages (curl, wget, git, build-essential)" ;;
        zsh)         echo "Zsh + zinit + Powerlevel10k" ;;
        nvim)        echo "NeoVim + LazyVim" ;;
        tmux)        echo "tmux + TPM (Tmux Plugin Manager)" ;;
        rust)        echo "Rust toolchain + cargo-binstall" ;;
        uv)          echo "uv (fast Python package manager)" ;;
        tools)       echo "CLI tools (eza, fd, ripgrep)" ;;
        tools-extra) echo "Extra CLI tools (delta, dust, procs, bottom)" ;;
        ssh)         echo "SSH config (copy only, not symlinked)" ;;
        hishtory)    echo "hishtory (better shell history with S3 sync)" ;;
        *)           echo "" ;;
    esac
}

# Check if component is valid
is_valid_component() {
    local comp="$1"
    for c in "${COMPONENTS_ORDER[@]}"; do
        [[ "$c" == "$comp" ]] && return 0
    done
    return 1
}

# Selected components to install
SELECTED_COMPONENTS=()

# ==============================================================================
# Interactive Component Selector
# ==============================================================================

# Check if a component is in a preset array
_in_preset() {
    local comp="$1"
    shift
    local preset=("$@")
    for p in "${preset[@]}"; do
        [[ "$p" == "$comp" ]] && return 0
    done
    return 1
}

show_interactive_menu() {
    local num_components=${#COMPONENTS_ORDER[@]}

    # Toggle state array (0=off, 1=on) — default to core preset
    local selected=()
    for ((i=0; i<num_components; i++)); do
        if _in_preset "${COMPONENTS_ORDER[$i]}" "${CORE_COMPONENTS[@]}"; then
            selected+=("1")
        else
            selected+=("0")
        fi
    done

    # Read input from /dev/tty to work even when stdin is redirected
    local input=""
    while true; do
        # Clear screen and draw menu
        printf "${ESC}[2J${ESC}[H"
        printf "${BOLD}${BLUE}Settings Installer v${VERSION}${NC}\n"
        printf "\n"
        printf "${BOLD}Select components to install:${NC}\n"
        printf "\n"
        printf "  Presets: ${CYAN}[a]${NC} all  ${CYAN}[c]${NC} core  ${CYAN}[n]${NC} none\n"
        printf "\n"

        for ((i=0; i<num_components; i++)); do
            local comp="${COMPONENTS_ORDER[$i]}"
            local desc
            desc="$(get_component_desc "$comp")"
            local mark=" "
            if [[ "${selected[$i]}" == "1" ]]; then
                mark="${GREEN}x${NC}"
            fi
            printf "  %2d) [%b] ${CYAN}%-12s${NC} %s\n" "$((i+1))" "$mark" "$comp" "$desc"
        done

        # Count selected
        local count=0
        for ((i=0; i<num_components; i++)); do
            [[ "${selected[$i]}" == "1" ]] && count=$((count+1))
        done

        printf "\n"
        printf "  Toggle: ${BOLD}1-%d${NC} | Presets: ${BOLD}a${NC}=all ${BOLD}c${NC}=core ${BOLD}n${NC}=none\n" "$num_components"
        printf "  Press ${BOLD}Enter${NC} to confirm (%d selected), ${BOLD}q${NC} to quit\n" "$count"
        printf "\n"
        printf "  > "

        # Read single line from terminal
        read -r input < /dev/tty || { echo ""; exit 1; }

        # Handle input
        case "$input" in
            q|Q)
                echo "Aborted."
                exit 0
                ;;
            a|A)
                for ((i=0; i<num_components; i++)); do selected[$i]="1"; done
                ;;
            c|C)
                for ((i=0; i<num_components; i++)); do
                    if _in_preset "${COMPONENTS_ORDER[$i]}" "${CORE_COMPONENTS[@]}"; then
                        selected[$i]="1"
                    else
                        selected[$i]="0"
                    fi
                done
                ;;
            n|N)
                for ((i=0; i<num_components; i++)); do selected[$i]="0"; done
                ;;
            "")
                # Enter pressed — confirm selection
                if [[ $count -eq 0 ]]; then
                    # No selection, loop again
                    continue
                fi
                break
                ;;
            *)
                # Try to parse as number(s) — support "1 3 5" or "1,3,5" or single "3"
                local nums
                nums=$(echo "$input" | tr ',' ' ')
                for num in $nums; do
                    if [[ "$num" =~ ^[0-9]+$ ]] && [[ "$num" -ge 1 ]] && [[ "$num" -le "$num_components" ]]; then
                        local idx=$((num - 1))
                        if [[ "${selected[$idx]}" == "1" ]]; then
                            selected[$idx]="0"
                        else
                            selected[$idx]="1"
                        fi
                    fi
                done
                ;;
        esac
    done

    # Build SELECTED_COMPONENTS from toggle state
    SELECTED_COMPONENTS=()
    for ((i=0; i<num_components; i++)); do
        if [[ "${selected[$i]}" == "1" ]]; then
            SELECTED_COMPONENTS+=("${COMPONENTS_ORDER[$i]}")
        fi
    done

    # Clear screen before starting installation
    printf "${ESC}[2J${ESC}[H"
}

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
    -i, --interactive   Interactive component selector (default when no args)
    -a, --all           Install all components
    --core              Install core dev environment (base, zsh, nvim, tmux, tools)
    -b, --basic         Install basic dev environment (base, zsh, nvim, tmux)
    -f, --force         Force reinstall (overwrite existing)
    -c, --copy          Copy config files instead of symlink
    -l, --link          Create symlinks for config files (default)
    -v, --verbose       Enable verbose output
    -n, --dry-run       Show what would be done without making changes
    --no-sudo           Skip commands that require sudo privileges
    -h, --help          Show this help message
    --version           Show version

${BOLD}COMPONENTS:${NC}
EOF

    for comp in "${COMPONENTS_ORDER[@]}"; do
        printf "    ${CYAN}%-12s${NC}  %s\n" "$comp" "$(get_component_desc "$comp")"
    done

    cat << EOF

${BOLD}EXAMPLES:${NC}
    install.sh                          # Interactive component selector
    install.sh --all                    # Install everything (symlink mode)
    install.sh --core                   # Install core dev environment
    install.sh --basic                  # Install basic dev environment
    install.sh --copy --all             # Install everything (copy mode)
    install.sh zsh nvim tmux            # Install specific components
    install.sh -v tools tools-extra     # Install tools with verbose output
    install.sh -n --all                 # Dry-run to see what would happen
    install.sh -f zsh                   # Force reinstall zsh configuration
    install.sh -c zsh tmux              # Install zsh and tmux with copy mode

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
            -b|--basic)
                SELECTED_COMPONENTS=("${BASIC_COMPONENTS[@]}")
                shift
                ;;
            --core)
                SELECTED_COMPONENTS=("${CORE_COMPONENTS[@]}")
                shift
                ;;
            -i|--interactive)
                show_interactive_menu
                shift
                ;;
            -f|--force)
                FORCE=true
                shift
                ;;
            -c|--copy)
                LINK_MODE=copy
                shift
                ;;
            -l|--link)
                LINK_MODE=symlink
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
            --no-sudo)
                NO_SUDO=true
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
                if is_valid_component "$1"; then
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
    export VERBOSE DRY_RUN FORCE NO_SUDO LINK_MODE

    # No components selected — launch interactive menu if TTY, otherwise error
    if [[ ${#SELECTED_COMPONENTS[@]} -eq 0 ]]; then
        if is_tty; then
            show_interactive_menu
        else
            log_error "No components specified."
            echo ""
            echo "Use --all to install everything, or specify components:"
            echo "  install.sh --all"
            echo "  install.sh --core"
            echo "  install.sh zsh nvim tmux"
            echo ""
            echo "Run 'install.sh --help' for more information."
            exit 1
        fi
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
        echo "  - $comp: $(get_component_desc "$comp")"
    done
    echo ""

    if [[ "$DRY_RUN" == "true" ]]; then
        log_warn "DRY-RUN mode: No changes will be made"
    fi
    if [[ "$FORCE" == "true" ]]; then
        log_warn "FORCE mode: Existing configurations will be overwritten"
    fi
    if [[ "$NO_SUDO" == "true" ]]; then
        log_warn "NO-SUDO mode: Commands requiring sudo will be skipped"
    fi
    if [[ "$LINK_MODE" == "copy" ]]; then
        log_info "COPY mode: Config files will be copied (not symlinked)"
    else
        log_info "SYMLINK mode: Config files will be symlinked"
    fi
    echo ""
}
