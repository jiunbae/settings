#!/bin/bash
# codex.sh - Codex CLI/App configuration
# Can be run standalone or sourced by install.sh

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "$SCRIPT_DIR/../lib/core.sh"
    source "$SCRIPT_DIR/../lib/platform.sh"
    detect_platform
    setup_package_manager
fi

SETTINGS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

install_codex_trust_sync() {
    print_section "Installing Codex workspace trust sync"

    local source="$SETTINGS_ROOT/scripts/codex/workspace-trust-sync.sh"
    local target="$HOME/.local/bin/codex-workspace-trust-sync"

    if [[ ! -f "$source" ]]; then
        log_error "Codex trust sync source not found: $source"
        return 1
    fi

    if [[ "$LINK_MODE" == "copy" ]]; then
        if [[ -x "$target" ]] && diff -q "$source" "$target" >/dev/null 2>&1; then
            log_info "Codex workspace trust sync already up to date"
            track_skipped "Codex workspace trust sync"
            return 0
        fi
    elif [[ -L "$target" && "$(readlink "$target")" == "$source" ]]; then
        log_info "Codex workspace trust sync already linked"
        track_skipped "Codex workspace trust sync"
        return 0
    fi

    FORCE=true backup_and_link "$source" "$target"
    track_installed "Codex workspace trust sync"
}

install_codex_config() {
    print_section "Configuring Codex"

    local apply_script="$SETTINGS_ROOT/scripts/codex/apply-config.sh"
    if [[ ! -f "$apply_script" ]]; then
        log_error "Codex apply script not found: $apply_script"
        return 1
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        DRY_RUN=true bash "$apply_script"
        return 0
    fi

    bash "$apply_script"
    track_installed "Codex config"
    log_success "Codex configuration applied"
}

install_codex() {
    log_info "Starting Codex configuration..."
    install_codex_config || return 1
    install_codex_trust_sync || return 1
    log_success "Codex configuration complete!"
}
