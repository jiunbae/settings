#!/bin/bash
# fonts.sh - Terminal fonts (macOS only)
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
#
# Fonts are installed, not committed: the set a working machine had in
# ~/Library/Fonts was 413 MB. Everything comes from Homebrew casks except the
# Hangul-merged JetBrains Mono, which has no cask and is pinned to a release
# with a checksum instead.
#
#   JetBrainsMonoHangul Nerd Font Mono  configs/ghostty/config (Ghostty and cmux)
#   JetBrainsMono Nerd Font             general coding font
#   MesloLGS Nerd Font                  Powerlevel10k's recommended font
# ==============================================================================
readonly FONT_CASKS=(
    font-jetbrains-mono-nerd-font
    font-meslo-lg-nerd-font
)

readonly FONTS_DIR="$HOME/Library/Fonts"
readonly JBM_HANGUL_VERSION="20260222"
readonly JBM_HANGUL_FILE="JetBrainsMonoHangulNerdFontMono-${JBM_HANGUL_VERSION}.ttc"
readonly JBM_HANGUL_URL="https://github.com/Jhyub/JetBrainsMonoHangul/releases/download/${JBM_HANGUL_VERSION}/${JBM_HANGUL_FILE}"
readonly JBM_HANGUL_SHA256="44a75d24c1a35ae149deffe2efabb795b95777dc8e56eba7879b692c8208f7cd"

# ==============================================================================
# Installation Functions
# ==============================================================================

install_font_casks() {
    print_section "Installing Nerd Fonts"

    local cask
    for cask in "${FONT_CASKS[@]}"; do
        if brew list --cask "$cask" &>/dev/null; then
            log_info "$cask already installed"
            track_skipped "$cask"
            continue
        fi
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[DRY-RUN] Would install cask: $cask"
            continue
        fi
        run_with_spinner "Installing $cask" brew install --cask "$cask"
        track_installed "$cask"
    done
}

install_font_jbm_hangul() {
    print_section "Installing JetBrainsMonoHangul Nerd Font Mono"

    local target="$FONTS_DIR/$JBM_HANGUL_FILE"
    if [[ -f "$target" ]]; then
        log_info "JetBrainsMonoHangul $JBM_HANGUL_VERSION already installed"
        track_skipped "JetBrainsMonoHangul"
        return 0
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would install $JBM_HANGUL_URL"
        return 0
    fi

    local tmp
    tmp=$(mktemp)
    download_file "$JBM_HANGUL_URL" "$tmp" || { rm -f "$tmp"; return 1; }

    local actual
    actual=$(shasum -a 256 "$tmp" | cut -d' ' -f1)
    if [[ "$actual" != "$JBM_HANGUL_SHA256" ]]; then
        rm -f "$tmp"
        log_error "JetBrainsMonoHangul checksum mismatch (expected $JBM_HANGUL_SHA256, got $actual)"
        return 1
    fi

    mkdir -p "$FONTS_DIR"
    install -m 644 "$tmp" "$target"
    rm -f "$tmp"
    track_installed "JetBrainsMonoHangul $JBM_HANGUL_VERSION"
    log_success "Installed $target"
}

# ==============================================================================
# Main Installation
# ==============================================================================

install_fonts() {
    log_info "Starting font installation..."

    if [[ "$PLATFORM" != "macos" ]]; then
        log_info "Fonts are macOS-only, skipping on platform: $PLATFORM"
        track_skipped "Fonts (not macOS)"
        return 0
    fi

    install_font_casks
    install_font_jbm_hangul || return 1

    log_success "Font installation complete!"
}

# ==============================================================================
# Standalone Execution
# ==============================================================================
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    setup_error_handling
    install_fonts
fi
