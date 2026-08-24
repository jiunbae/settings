#!/bin/bash
# scripts.sh - Personal CLI scripts installation
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
# ==============================================================================
# ~/.local/bin is preferred over ~/.scripts: it precedes ~/.scripts on PATH, so
# linking here overrides an older copy (e.g. one shared over NFS) without having
# to delete it. Removing the link rolls straight back to that copy.
readonly SCRIPTS_BIN_DIR="$HOME/.local/bin"

# ==============================================================================
# Installation Functions
# ==============================================================================

install_scripts() {
    log_info "Starting personal scripts installation..."

    local root_dir
    root_dir=$(get_root_dir)
    local source_dir="$root_dir/bin"

    if [[ ! -d "$source_dir" ]]; then
        log_error "Scripts directory not found at: $source_dir"
        return 1
    fi

    print_section "Linking personal scripts"

    if [[ "$DRY_RUN" != "true" ]]; then
        mkdir -p "$SCRIPTS_BIN_DIR"
    fi

    local linked=0 current=0 skipped=0 pruned=0
    local source target name current_target

    # A script dropped from bin/ leaves its link behind, dangling on PATH.
    # Only links that point into our own bin/ are considered.
    for target in "$SCRIPTS_BIN_DIR"/*; do
        [[ -L "$target" ]] || continue
        current_target=$(readlink "$target")
        [[ "$current_target" == "$source_dir"/* ]] || continue
        [[ -e "$current_target" ]] && continue

        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[DRY-RUN] Would remove stale link: $(basename "$target")"
        else
            rm -f "$target"
            log_info "Removed stale link: $(basename "$target")"
        fi
        pruned=$((pruned + 1))
    done

    for source in "$source_dir"/*; do
        [[ -f "$source" ]] || continue

        name="$(basename "$source")"

        # bin/ is a PATH directory, so anything without the execute bit would
        # link in as an unrunnable command. Say so rather than linking it.
        if [[ ! -x "$source" ]]; then
            log_warn "Not executable, skipping: $name (chmod +x to install it)"
            skipped=$((skipped + 1))
            continue
        fi

        target="$SCRIPTS_BIN_DIR/$name"

        # Short-circuit if it already points at our repo source
        if [[ -L "$target" ]]; then
            current_target=$(readlink "$target")
            if [[ "$current_target" == "$source" ]]; then
                log_info "Already linked: $name"
                track_skipped "$name"
                current=$((current + 1))
                continue
            fi
        fi

        # A stale link or a stray copy in ~/.local/bin should give way to the
        # repo version; backup_and_link keeps a backup of any real file.
        FORCE=true backup_and_link "$source" "$target"
        track_installed "$name"
        linked=$((linked + 1))
    done

    log_success "Personal scripts configured ($linked linked, $current current, $skipped skipped, $pruned stale removed)"

    if [[ ":$PATH:" != *":$SCRIPTS_BIN_DIR:"* ]]; then
        log_warn "$SCRIPTS_BIN_DIR is not on PATH; add it to use these scripts"
    fi
}

# ==============================================================================
# Standalone Execution
# ==============================================================================
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    setup_error_handling
    install_scripts
fi
