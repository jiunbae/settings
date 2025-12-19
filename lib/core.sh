#!/bin/bash
# core.sh - Core utilities, logging, and error handling
# Source this file at the beginning of other scripts

set -euo pipefail

# ==============================================================================
# Colors & Terminal Control
# ==============================================================================
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m' # No Color
readonly BOLD='\033[1m'

# ANSI escape sequences
readonly ESC=$'\033'
readonly CLEAR_LINE="${ESC}[2K"
readonly CURSOR_UP="${ESC}[A"
readonly CURSOR_DOWN="${ESC}[B"
readonly CURSOR_SAVE="${ESC}[s"
readonly CURSOR_RESTORE="${ESC}[u"
readonly CURSOR_HIDE="${ESC}[?25l"
readonly CURSOR_SHOW="${ESC}[?25h"

# ==============================================================================
# Global Variables
# ==============================================================================
VERBOSE=${VERBOSE:-false}
DRY_RUN=${DRY_RUN:-false}
FORCE=${FORCE:-false}
LINK_MODE=${LINK_MODE:-symlink}  # symlink or copy
LOG_FILE="${LOG_FILE:-$HOME/.install.log}"

# Progress state (initialized here, used by logging)
PROGRESS_TOTAL=0
PROGRESS_CURRENT=0
PROGRESS_COMPONENT=""

# Installation tracking (for summary)
INSTALLED_ITEMS=()      # Newly installed items
SKIPPED_ITEMS=()        # Already installed (skipped)
LINKED_ITEMS=()         # Created symlinks
BACKUP_ITEMS=()         # Backed up files

# ==============================================================================
# Logging Functions
# ==============================================================================
_log() {
    local level=$1
    local color=$2
    shift 2
    local message="$*"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    # File output (always)
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"

    # Console output - use progress style if active
    if [[ $PROGRESS_TOTAL -gt 0 ]]; then
        case "$level" in
            INFO)
                printf "\r${CLEAR_LINE}  ${BLUE}ℹ${NC} %s\n" "$message"
                ;;
            OK)
                printf "\r${CLEAR_LINE}  ${GREEN}✓${NC} %s\n" "$message"
                ;;
            WARN)
                printf "\r${CLEAR_LINE}  ${YELLOW}⚠${NC} %s\n" "$message"
                ;;
            ERROR)
                printf "\r${CLEAR_LINE}  ${RED}✗${NC} %s\n" "$message" >&2
                ;;
        esac
    else
        echo -e "${color}[${level}]${NC} ${message}"
    fi
}

log_info() {
    _log "INFO" "$BLUE" "$@"
}

log_success() {
    _log "OK" "$GREEN" "$@"
}

log_warn() {
    _log "WARN" "$YELLOW" "$@"
}

log_error() {
    _log "ERROR" "$RED" "$@" >&2
}

log_debug() {
    if [[ "$VERBOSE" == "true" ]]; then
        _log "DEBUG" "$CYAN" "$@"
    fi
}

# ==============================================================================
# Error Handling
# ==============================================================================
error_handler() {
    local line_no=$1
    local error_code=$2
    local command="${BASH_COMMAND:-unknown}"
    log_error "Command failed at line $line_no (exit code: $error_code)"
    log_error "Failed command: $command"
}

cleanup() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        log_error "Installation failed! Check log: $LOG_FILE"
    fi
}

setup_error_handling() {
    trap 'error_handler ${LINENO} $?' ERR
    trap cleanup EXIT
}

# ==============================================================================
# Utility Functions
# ==============================================================================

# Check if a command exists
command_exists() {
    command -v "$1" &>/dev/null
}

# Download a file with curl
download_file() {
    local url=$1
    local dest=$2

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would download: $url -> $dest"
        return 0
    fi

    log_debug "Downloading: $url"
    curl -fsSL "$url" -o "$dest" || {
        log_error "Failed to download: $url"
        return 1
    }
    log_debug "Downloaded to: $dest"
}

# Backup existing file and deploy config (symlink or copy based on LINK_MODE)
backup_and_link() {
    local source=$1
    local target=$2

    if [[ "$DRY_RUN" == "true" ]]; then
        if [[ "$LINK_MODE" == "copy" ]]; then
            log_info "[DRY-RUN] Would copy: $source -> $target"
        else
            log_info "[DRY-RUN] Would link: $source -> $target"
        fi
        return 0
    fi

    # Create backup if target exists and is not a symlink
    if [[ -e "$target" && ! -L "$target" ]]; then
        local backup="${target}.backup.$(date +%Y%m%d%H%M%S)"
        log_info "Backing up existing file: $target -> $backup"
        mv "$target" "$backup"
        track_backup "$target" "$backup"
    fi

    # Remove existing symlink or file if force mode
    if [[ -L "$target" || -e "$target" ]]; then
        if [[ "$FORCE" == "true" ]]; then
            rm -rf "$target"
        else
            log_warn "Target already exists: $target (use --force to overwrite)"
            return 0
        fi
    fi

    # Create parent directory if needed
    mkdir -p "$(dirname "$target")"

    # Deploy based on mode
    if [[ "$LINK_MODE" == "copy" ]]; then
        cp -r "$source" "$target"
        log_success "Copied: $source -> $target"
    else
        ln -sf "$source" "$target"
        track_linked "$source" "$target"
        log_success "Linked: $source -> $target"
    fi
}

# Run a command with optional dry-run support
run_cmd() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would run: $*"
        return 0
    fi

    log_debug "Running: $*"
    "$@"
}

# Clone a git repository if not exists
git_clone() {
    local url=$1
    local dest=$2
    local depth=${3:-1}

    # Extract repo name for display
    local repo_name
    repo_name=$(basename "$url" .git)

    if [[ -d "$dest" ]]; then
        if [[ "$FORCE" == "true" ]]; then
            log_info "Removing existing directory: $dest"
            rm -rf "$dest"
        else
            echo -e "${GREEN}✓${NC} $repo_name (already cloned)"
            return 0
        fi
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would clone: $url"
        return 0
    fi

    run_with_spinner "Cloning $repo_name" git clone --depth="$depth" "$url" "$dest"
}

# ==============================================================================
# Terminal Control
# ==============================================================================

# Check if we're in a TTY
is_tty() {
    [[ -t 1 ]]
}

# Spinner characters
readonly SPINNER_FRAMES=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
readonly SPINNER_SIMPLE=('|' '/' '-' '\')

# ==============================================================================
# Progress Display System
# ==============================================================================

# Initialize progress display
progress_init() {
    local total=$1
    shift
    PROGRESS_TOTAL=$total
    PROGRESS_CURRENT=0

    if is_tty; then
        # Clear screen and move to top
        printf "${ESC}[2J${ESC}[H"
        # Hide cursor during installation
        printf "$CURSOR_HIDE"
        # Setup cleanup on exit
        trap 'printf "$CURSOR_SHOW"' EXIT
    fi

    progress_draw_header
}

# Draw the header with progress bar
progress_draw_header() {
    if ! is_tty; then
        return
    fi

    # Save cursor position
    printf "$CURSOR_SAVE"
    # Move to top
    printf "${ESC}[H"

    # Draw header
    printf "${BOLD}${BLUE}"
    printf "╔══════════════════════════════════════════════════════════════╗\n"
    printf "║${NC}${BOLD}  Settings Installer                                         ${BLUE}║\n"
    printf "╠══════════════════════════════════════════════════════════════╣\n"
    printf "║${NC}"

    # Progress bar
    local progress=0
    if [[ $PROGRESS_TOTAL -gt 0 ]]; then
        progress=$((PROGRESS_CURRENT * 100 / PROGRESS_TOTAL))
    fi
    local filled=$((progress * 50 / 100))
    local empty=$((50 - filled))

    printf " ["
    printf "${GREEN}"
    for ((i=0; i<filled; i++)); do printf "█"; done
    printf "${NC}"
    for ((i=0; i<empty; i++)); do printf "░"; done
    printf "] %3d%%" "$progress"
    printf "${BLUE}     ║\n"

    printf "║${NC}  ${CYAN}[%d/%d]${NC} %-52s${BLUE}║\n" "$PROGRESS_CURRENT" "$PROGRESS_TOTAL" "$PROGRESS_COMPONENT"
    printf "╚══════════════════════════════════════════════════════════════╝${NC}\n"
    printf "\n"

    # Restore cursor position
    printf "$CURSOR_RESTORE"
}

# Start a new component
progress_start_component() {
    local name=$1
    PROGRESS_CURRENT=$((PROGRESS_CURRENT + 1))
    PROGRESS_COMPONENT="$name"

    progress_draw_header

    # Move cursor below header for task output
    if is_tty; then
        printf "${ESC}[8;1H"  # Move to row 8
        printf "${ESC}[J"     # Clear from cursor to end
    fi
}

# Show current task with spinner
progress_task() {
    local message=$1
    if is_tty; then
        printf "\r${CLEAR_LINE}  ${CYAN}▸${NC} %s..." "$message"
    else
        printf "  ▸ %s...\n" "$message"
    fi
}

# Mark task as done
progress_task_done() {
    local message=$1
    local success=${2:-true}

    if [[ "$success" == "true" ]]; then
        printf "\r${CLEAR_LINE}  ${GREEN}✓${NC} %s\n" "$message"
    else
        printf "\r${CLEAR_LINE}  ${RED}✗${NC} %s\n" "$message"
    fi
}

# Show info message
progress_info() {
    local message=$1
    printf "\r${CLEAR_LINE}  ${BLUE}ℹ${NC} %s\n" "$message"
}

# Finish progress display
progress_finish() {
    if is_tty; then
        printf "$CURSOR_SHOW"
    fi

    printf "\n"
    printf "${BOLD}${GREEN}"
    printf "╔══════════════════════════════════════════════════════════════╗\n"
    printf "║  ✓ Installation Complete!                                    ║\n"
    printf "╚══════════════════════════════════════════════════════════════╝${NC}\n"
    printf "\n"
    printf "  Please restart your shell or run: ${CYAN}source ~/.zshrc${NC}\n"
    printf "  Log file: ${CYAN}$LOG_FILE${NC}\n"
    printf "\n"
}

# ==============================================================================
# Spinner Functions
# ==============================================================================

# Run command with animated spinner
run_with_spinner() {
    local message="$1"
    shift
    local cmd=("$@")

    if [[ "$DRY_RUN" == "true" ]]; then
        progress_info "[DRY-RUN] Would run: ${cmd[*]}"
        return 0
    fi

    # Verbose mode: show full output
    if [[ "$VERBOSE" == "true" ]]; then
        progress_info "$message..."
        "${cmd[@]}" 2>&1 | tee -a "$LOG_FILE"
        local ret=${PIPESTATUS[0]}
        return $ret
    fi

    local output_file
    output_file=$(mktemp)
    local exit_code=0

    # Set non-interactive mode for apt
    export DEBIAN_FRONTEND=noninteractive

    # Start command in background with stdin closed
    "${cmd[@]}" < /dev/null > "$output_file" 2>&1 &
    local pid=$!

    # Show spinner while command runs
    local i=0
    local spin_chars=("${SPINNER_FRAMES[@]}")
    if ! is_tty; then
        spin_chars=("${SPINNER_SIMPLE[@]}")
    fi
    local num_chars=${#spin_chars[@]}

    while kill -0 "$pid" 2>/dev/null; do
        local spin_char="${spin_chars[$((i % num_chars))]}"
        if is_tty; then
            printf "\r${CLEAR_LINE}  ${YELLOW}%s${NC} %s" "$spin_char" "$message"
        fi
        i=$((i + 1))
        sleep 0.1
    done

    # Get exit code
    wait "$pid" || exit_code=$?

    # Read output
    local output
    output=$(<"$output_file")
    rm -f "$output_file"

    # Log output to file
    {
        echo "=== $message ==="
        echo "Command: ${cmd[*]}"
        echo "Exit code: $exit_code"
        echo "$output"
        echo ""
    } >> "$LOG_FILE"

    # Show result
    if [[ $exit_code -eq 0 ]]; then
        progress_task_done "$message" true
    else
        progress_task_done "$message" false
        # Show last few lines of error
        if [[ -n "$output" ]]; then
            echo "$output" | tail -3 >&2
        fi
    fi

    return $exit_code
}

# Run command silently (output to log only)
run_silent() {
    local message="$1"
    shift
    local cmd=("$@")

    if [[ "$DRY_RUN" == "true" ]]; then
        progress_info "[DRY-RUN] Would run: ${cmd[*]}"
        return 0
    fi

    log_debug "Running: ${cmd[*]}"

    local output
    local exit_code
    output=$("${cmd[@]}" 2>&1)
    exit_code=$?

    # Log to file
    {
        echo "=== $message ==="
        echo "${cmd[*]}"
        echo "$output"
        echo ""
    } >> "$LOG_FILE"

    return $exit_code
}

# Print a section header (no-op in progress mode, used for standalone module runs)
print_section() {
    local title=$1
    # Only print if not in progress mode (standalone execution)
    if [[ $PROGRESS_TOTAL -eq 0 ]]; then
        echo ""
        echo -e "${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${BOLD}${BLUE}  $title${NC}"
        echo -e "${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
    fi
}

# Print installation summary (legacy, use progress_finish instead)
print_summary() {
    if [[ $PROGRESS_TOTAL -eq 0 ]]; then
        echo ""
        echo -e "${BOLD}${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${BOLD}${GREEN}  Installation Complete!${NC}"
        echo -e "${BOLD}${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
        echo -e "Please restart your shell or run: ${CYAN}source ~/.zshrc${NC}"
        echo -e "Log file: ${CYAN}$LOG_FILE${NC}"
        echo ""
    fi
}

# ==============================================================================
# Installation Tracking Functions
# ==============================================================================

# Track newly installed item
track_installed() {
    local item="$1"
    INSTALLED_ITEMS+=("$item")
}

# Track skipped item (already installed)
track_skipped() {
    local item="$1"
    SKIPPED_ITEMS+=("$item")
}

# Track created symlink
track_linked() {
    local source="$1"
    local target="$2"
    LINKED_ITEMS+=("$target -> $source")
}

# Track backed up file
track_backup() {
    local original="$1"
    local backup="$2"
    BACKUP_ITEMS+=("$original -> $backup")
}

# Print installation summary report
print_install_summary() {
    echo ""
    printf "${BOLD}${BLUE}"
    printf "╔══════════════════════════════════════════════════════════════╗\n"
    printf "║                    Installation Summary                      ║\n"
    printf "╚══════════════════════════════════════════════════════════════╝${NC}\n"
    echo ""

    # Installed items
    if [[ ${#INSTALLED_ITEMS[@]} -gt 0 ]]; then
        printf "  ${BOLD}${GREEN}✓ Installed (${#INSTALLED_ITEMS[@]})${NC}\n"
        for item in "${INSTALLED_ITEMS[@]}"; do
            printf "    ${GREEN}•${NC} %s\n" "$item"
        done
        echo ""
    fi

    # Skipped items
    if [[ ${#SKIPPED_ITEMS[@]} -gt 0 ]]; then
        printf "  ${BOLD}${YELLOW}○ Already installed (${#SKIPPED_ITEMS[@]})${NC}\n"
        for item in "${SKIPPED_ITEMS[@]}"; do
            printf "    ${YELLOW}•${NC} %s\n" "$item"
        done
        echo ""
    fi

    # Linked items
    if [[ ${#LINKED_ITEMS[@]} -gt 0 ]]; then
        printf "  ${BOLD}${CYAN}⟶ Symlinks created (${#LINKED_ITEMS[@]})${NC}\n"
        for item in "${LINKED_ITEMS[@]}"; do
            printf "    ${CYAN}•${NC} %s\n" "$item"
        done
        echo ""
    fi

    # Backed up items
    if [[ ${#BACKUP_ITEMS[@]} -gt 0 ]]; then
        printf "  ${BOLD}${BLUE}⟳ Backups created (${#BACKUP_ITEMS[@]})${NC}\n"
        for item in "${BACKUP_ITEMS[@]}"; do
            printf "    ${BLUE}•${NC} %s\n" "$item"
        done
        echo ""
    fi

    # Summary line
    local total=$((${#INSTALLED_ITEMS[@]} + ${#SKIPPED_ITEMS[@]}))
    printf "  ${BOLD}Total: %d items processed${NC}\n" "$total"
    echo ""
}
