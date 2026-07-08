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
    install_codex_config
    log_success "Codex configuration complete!"
}
