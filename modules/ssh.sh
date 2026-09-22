#!/bin/bash
# ssh.sh - SSH config installation (copy only, never symlink for security)
# Can be run standalone or sourced by install.sh

# ==============================================================================
# Standalone execution support
# ==============================================================================
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "$SCRIPT_DIR/../lib/core.sh"
    source "$SCRIPT_DIR/../lib/platform.sh"
    detect_platform
fi

# ==============================================================================
# Configuration
# ==============================================================================
readonly SSH_DIR="$HOME/.ssh"

# ==============================================================================
# Installation Functions
# ==============================================================================

# Copy a file or directory with backup support (always copy, never symlink)
backup_and_copy() {
    local source=$1
    local target=$2

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would copy: $source -> $target"
        return 0
    fi

    # Create backup if target exists and is not a symlink
    if [[ -e "$target" && ! -L "$target" ]]; then
        local backup="${target}.backup.$(date +%Y%m%d%H%M%S)"
        log_info "Backing up existing: $target -> $backup"
        mv "$target" "$backup"
        track_backup "$target" "$backup"
    fi

    # Remove existing symlink if exists
    if [[ -L "$target" ]]; then
        if [[ "$FORCE" == "true" ]]; then
            rm -f "$target"
        else
            log_warn "Target is a symlink: $target (use --force to overwrite)"
            return 0
        fi
    fi

    # Remove existing file/dir if force mode and exists
    if [[ -e "$target" && "$FORCE" == "true" ]]; then
        rm -rf "$target"
    fi

    # Create parent directory if needed
    mkdir -p "$(dirname "$target")"

    # Copy (always copy, never symlink for SSH security)
    if [[ -d "$source" ]]; then
        cp -r "$source" "$target"
    else
        cp "$source" "$target"
    fi
    log_success "Copied: $source -> $target"
}

copy_ssh_config() {
    print_section "Copying SSH Configuration"

    local root_dir
    root_dir=$(get_root_dir)
    # chezmoi's source tree names these for chezmoi: `private_config` is
    # placed as `config` with mode 600. This module copies them for anyone
    # installing with ./install.sh, so it maps the names back by hand.
    local ssh_source="$root_dir/home/private_dot_ssh"

    if [[ ! -d "$ssh_source" ]]; then
        log_warn ".ssh directory not found in settings"
        return 0
    fi

    # Create ~/.ssh if not exists with proper permissions
    if [[ ! -d "$SSH_DIR" ]]; then
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[DRY-RUN] Would create: $SSH_DIR"
        else
            mkdir -p "$SSH_DIR"
            chmod 700 "$SSH_DIR"
            log_success "Created $SSH_DIR with 700 permissions"
        fi
    fi

    # Copy config file
    if [[ -f "$ssh_source/private_config" ]]; then
        backup_and_copy "$ssh_source/private_config" "$SSH_DIR/config"
        if [[ "$DRY_RUN" != "true" ]]; then
            chmod 600 "$SSH_DIR/config"
        fi
        track_installed "SSH config"
    fi

    # Copy config.d directory
    if [[ -d "$ssh_source/private_config.d" ]]; then
        # File by file, not the directory: `cp -r` would carry the `private_`
        # names across, and a config.d the vault also writes into must not be
        # replaced wholesale — 20-company.conf lives there.
        if [[ "$DRY_RUN" != "true" ]]; then
            mkdir -p "$SSH_DIR/config.d"
            local fragment
            for fragment in "$ssh_source/private_config.d"/*; do
                [[ -f "$fragment" ]] || continue
                local name; name="$(basename "$fragment")"
                cp "$fragment" "$SSH_DIR/config.d/${name#private_}"
            done
        fi
        if [[ "$DRY_RUN" != "true" ]]; then
            chmod 700 "$SSH_DIR/config.d"
            find "$SSH_DIR/config.d" -type f -exec chmod 600 {} \;
        fi
        track_installed "SSH config.d"
    fi

    # Copy mux directory (for ControlMaster sockets)
    if [[ -d "$ssh_source/private_mux" ]]; then
        mkdir -p "$SSH_DIR/mux"
        if [[ "$DRY_RUN" != "true" ]]; then
            chmod 700 "$SSH_DIR/mux"
        fi
        track_installed "SSH mux directory"
    fi

    log_success "SSH configuration copied"
}

# ==============================================================================
# Main Installation
# ==============================================================================

install_ssh() {
    log_info "Starting SSH config installation (copy mode)..."

    copy_ssh_config

    log_success "SSH config installation complete!"
}

# ==============================================================================
# Standalone Execution
# ==============================================================================
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    setup_error_handling
    install_ssh
fi
