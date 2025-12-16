#!/bin/bash
# platform.sh - Platform detection and package manager abstraction
# Source this file after core.sh

# ==============================================================================
# Platform Detection
# ==============================================================================

# Detected values (set by detect_platform)
PLATFORM=""
ARCH=""
IS_WSL=false

detect_platform() {
    local os
    os=$(uname -s)

    case "$os" in
        Linux)
            if grep -qi microsoft /proc/version 2>/dev/null; then
                PLATFORM="wsl"
                IS_WSL=true
            else
                PLATFORM="linux"
            fi
            ;;
        Darwin)
            PLATFORM="macos"
            ;;
        *)
            log_error "Unsupported operating system: $os"
            exit 1
            ;;
    esac

    local arch
    arch=$(uname -m)

    case "$arch" in
        x86_64|amd64)
            ARCH="x86_64"
            ;;
        arm64|aarch64)
            ARCH="arm64"
            ;;
        *)
            log_error "Unsupported architecture: $arch"
            exit 1
            ;;
    esac

    export PLATFORM ARCH IS_WSL
    log_info "Detected platform: $PLATFORM ($ARCH)"
}

# ==============================================================================
# Package Manager Abstraction
# ==============================================================================

# Package manager settings (set by setup_package_manager)
PKG_MANAGER=""
PKG_SUDO=""
PKG_UPDATE_CMD=""
PKG_INSTALL_CMD=""
PKG_YES_FLAG=""

setup_package_manager() {
    # Determine if we need sudo
    # - Not needed if running as root (EUID == 0)
    # - Not needed if sudo command doesn't exist
    local need_sudo=""
    if [[ $EUID -ne 0 ]] && command_exists sudo; then
        need_sudo="sudo"
    fi

    case "$PLATFORM" in
        macos)
            PKG_MANAGER="brew"
            PKG_SUDO=""
            PKG_UPDATE_CMD="brew update"
            PKG_INSTALL_CMD="brew install"
            PKG_YES_FLAG=""

            # Check if Homebrew is installed
            if ! command_exists brew; then
                log_warn "Homebrew not found. Installing..."
                install_homebrew
            fi
            ;;
        linux|wsl)
            PKG_MANAGER="apt"
            PKG_SUDO="$need_sudo"
            PKG_UPDATE_CMD="$need_sudo apt update"
            PKG_INSTALL_CMD="$need_sudo apt install"
            PKG_YES_FLAG="-y"
            ;;
    esac

    export PKG_MANAGER PKG_SUDO PKG_UPDATE_CMD PKG_INSTALL_CMD PKG_YES_FLAG
    log_debug "Package manager: $PKG_MANAGER (sudo: ${PKG_SUDO:-none})"
}

# Install Homebrew on macOS
install_homebrew() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would install Homebrew"
        return 0
    fi

    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

    # Add to PATH for current session
    if [[ "$ARCH" == "arm64" ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    else
        eval "$(/usr/local/bin/brew shellenv)"
    fi
}

# Update package manager
pkg_update() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would update package manager"
        return 0
    fi

    case "$PKG_MANAGER" in
        apt)
            run_with_spinner "Updating package lists" $PKG_SUDO apt-get update -qq
            ;;
        brew)
            run_with_spinner "Updating Homebrew" brew update
            ;;
    esac
}

# Install packages
pkg_install() {
    local packages=("$@")

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would install: ${packages[*]}"
        return 0
    fi

    # Install packages one by one for better progress display
    for pkg in "${packages[@]}"; do
        # Check if already installed
        if pkg_installed "$pkg"; then
            printf "\r${CLEAR_LINE:-}  ${GREEN}✓${NC} %s (already installed)\n" "$pkg"
            continue
        fi

        case "$PKG_MANAGER" in
            apt)
                run_with_spinner "Installing $pkg" $PKG_SUDO apt-get install $PKG_YES_FLAG -qq "$pkg"
                ;;
            brew)
                run_with_spinner "Installing $pkg" brew install "$pkg"
                ;;
        esac
    done
}

# Check if a package is installed
pkg_installed() {
    local pkg=$1

    case "$PKG_MANAGER" in
        brew)
            brew list "$pkg" &>/dev/null
            ;;
        apt)
            dpkg -l "$pkg" 2>/dev/null | grep -q "^ii"
            ;;
    esac
}

# ==============================================================================
# Platform-specific helpers
# ==============================================================================

# Get the default shell path
get_zsh_path() {
    if command_exists zsh; then
        command -v zsh
    else
        case "$PLATFORM" in
            macos)
                echo "/bin/zsh"
                ;;
            linux|wsl)
                echo "/usr/bin/zsh"
                ;;
        esac
    fi
}

# Change default shell to zsh
change_default_shell() {
    local zsh_path
    zsh_path=$(get_zsh_path)

    # Check if zsh exists
    if [[ ! -x "$zsh_path" ]]; then
        log_warn "Zsh not found at $zsh_path, skipping shell change"
        return 0
    fi

    if [[ "$SHELL" == "$zsh_path" ]]; then
        log_info "Zsh is already the default shell"
        return 0
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would change default shell to: $zsh_path"
        return 0
    fi

    log_info "Changing default shell to zsh..."

    # Determine sudo command
    local sudo_cmd=""
    if [[ $EUID -ne 0 ]] && command_exists sudo; then
        sudo_cmd="sudo"
    fi

    # Check if chsh command exists
    if ! command_exists chsh; then
        log_warn "chsh command not found. Add to your profile manually:"
        log_info "  export SHELL=$zsh_path"
        log_info "  exec $zsh_path -l"
        return 0
    fi

    # Add zsh to /etc/shells if not present (and file exists)
    if [[ -f /etc/shells ]]; then
        if ! grep -q "$zsh_path" /etc/shells 2>/dev/null; then
            if [[ -n "$sudo_cmd" ]]; then
                echo "$zsh_path" | $sudo_cmd tee -a /etc/shells >/dev/null 2>&1 || true
            elif [[ $EUID -eq 0 ]]; then
                echo "$zsh_path" >> /etc/shells 2>/dev/null || true
            fi
        fi
    fi

    # Get current user
    local current_user="${USER:-$(whoami)}"

    # Change shell
    local chsh_result=0
    case "$PLATFORM" in
        macos)
            chsh -s "$zsh_path" 2>/dev/null || chsh_result=1
            ;;
        linux|wsl)
            if [[ $EUID -eq 0 ]]; then
                # Running as root
                chsh -s "$zsh_path" "$current_user" 2>/dev/null || chsh_result=1
            elif [[ -n "$sudo_cmd" ]]; then
                $sudo_cmd chsh -s "$zsh_path" "$current_user" 2>/dev/null || chsh_result=1
            else
                chsh_result=1
            fi
            ;;
    esac

    if [[ $chsh_result -eq 0 ]]; then
        log_success "Default shell changed to zsh"
    else
        log_warn "Could not change default shell automatically"
        log_info "To change manually, run: chsh -s $zsh_path"
        log_info "Or add to your profile: exec $zsh_path -l"
    fi

    return 0
}

# Get config directory for the script
get_script_dir() {
    cd "$(dirname "${BASH_SOURCE[0]}")" && pwd
}

get_root_dir() {
    local script_dir
    script_dir=$(get_script_dir)
    cd "$script_dir/.." && pwd
}
