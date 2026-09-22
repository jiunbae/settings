#!/bin/bash
# kitbag.sh - install kitbag, the tool this repository's secrets engine is
# being replaced by.
#
# Nothing here changes what `install.sh secrets` does. kitbag is installed
# alongside it, and the two read different things: the bash engine reads the
# `bootstrap` manifest in the vault, kitbag reads its own items. Until a vault
# has been pushed with kitbag, the bash path is still the one that restores a
# machine, and it keeps working exactly as before.
#
#   ./install.sh kitbag                 install it
#   scripts/kitbag-config.sh            build its config from what this repo knows
#
# docs/kitbag.md has the argument and the cutover.

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
# Pinned, like every other download this repository makes: an installer that
# fetches "latest" installs whatever that URL serves on the day it runs.
KITBAG_VERSION="${SETTINGS_KITBAG_VERSION:-v0.15.1}"
KITBAG_INSTALLER="https://raw.githubusercontent.com/Open330/kitbag/main/install.sh"
KITBAG_BIN_DIR="${SETTINGS_KITBAG_BIN_DIR:-$HOME/.local/bin}"

# ==============================================================================
# Installation
# ==============================================================================

_kitbag_installed_version() {
    command_exists kitbag || return 1
    kitbag --version 2>/dev/null | awk '{print "v" $2}'
}

install_kitbag_binary() {
    local have
    have="$(_kitbag_installed_version || true)"

    if [[ "$have" == "$KITBAG_VERSION" ]]; then
        printf "\r${CLEAR_LINE:-}  ${GREEN}✓${NC} kitbag %s (already installed)\n" "$KITBAG_VERSION"
        track_skipped "kitbag"
        return 0
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would install kitbag $KITBAG_VERSION into $KITBAG_BIN_DIR"
        return 0
    fi

    # kitbag's own installer verifies the download against the checksums
    # published with the release, and refuses a release that has none.
    if ! KITBAG_VERSION="$KITBAG_VERSION" KITBAG_BIN_DIR="$KITBAG_BIN_DIR" \
        run_with_spinner "Installing kitbag $KITBAG_VERSION" \
        bash -c "curl -LsSf --proto '=https' --tlsv1.2 '$KITBAG_INSTALLER' | sh"; then
        log_error "kitbag install failed"
        log_info "Install it by hand: curl -LsSf $KITBAG_INSTALLER | sh"
        return 1
    fi

    hash -r
    track_installed "kitbag"

    case ":$PATH:" in
        *":$KITBAG_BIN_DIR:"*) ;;
        *) log_warn "$KITBAG_BIN_DIR is not on PATH yet — open a new shell" ;;
    esac
}

print_kitbag_next_steps() {
    local config="$HOME/.config/kitbag/machine.toml"
    echo
    if [[ -f "$config" ]]; then
        log_info "kitbag config: $config"
        log_info "  kitbag status      what this machine holds"
        log_info "  kitbag doctor      whether it is set up to work"
    else
        log_info "kitbag has no config on this machine yet:"
        log_info "  scripts/kitbag-config.sh    build one from what this repo already knows"
        log_info "  kitbag discover             or let it propose one from scratch"
    fi
    log_info "The vault engine in ./install.sh secrets is unchanged — see docs/kitbag.md"
}

install_kitbag() {
    print_section "kitbag"
    install_kitbag_binary || return 1
    print_kitbag_next_steps
}

# ==============================================================================
# Standalone Execution
# ==============================================================================
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    setup_error_handling
    install_kitbag
fi
