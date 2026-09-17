#!/bin/bash
# git.sh - Git global config (macOS only)
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
#
# ~/.gitconfig stays a real, machine-local file and [include]s the shared
# configs/git/gitconfig at its top. It is not symlinked because `gh auth
# setup-git` and `git config --global` write into it, and those writes (plus
# any company includeIf) must not land in this repo.
#
# The include sits first so anything later in ~/.gitconfig overrides it.
# ==============================================================================
readonly GIT_GLOBAL_CONFIG="$HOME/.gitconfig"
readonly GIT_IGNORE_TARGET="${XDG_CONFIG_HOME:-$HOME/.config}/git/ignore"
readonly GIT_SHARED_COPY="${XDG_CONFIG_HOME:-$HOME/.config}/git/shared.gitconfig"

# ==============================================================================
# Installation Functions
# ==============================================================================

install_git_include() {
    print_section "Including shared git config"

    local root_dir
    root_dir=$(get_root_dir)
    local shared="$root_dir/configs/git/gitconfig"

    # In copy mode the repo may be a temporary extraction (the release bundle
    # deletes it after installing), so include a copy instead of the repo file.
    if [[ "$LINK_MODE" == "copy" ]]; then
        local copied="$GIT_SHARED_COPY"
        if ! cmp -s "$shared" "$copied"; then
            if [[ "$DRY_RUN" == "true" ]]; then
                log_info "[DRY-RUN] Would copy $shared -> $copied"
            else
                mkdir -p "$(dirname "$copied")"
                cp "$shared" "$copied"
                log_success "Copied: $shared -> $copied"
            fi
        fi
        shared="$copied"
    fi

    if [[ -f "$GIT_GLOBAL_CONFIG" ]] && \
       git config --file "$GIT_GLOBAL_CONFIG" --get-all include.path 2>/dev/null | grep -qxF "$shared"; then
        log_info "~/.gitconfig already includes $shared"
        track_skipped "git shared config"
        return 0
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would add [include] path = $shared to the top of ~/.gitconfig"
        return 0
    fi

    local tmp
    tmp=$(mktemp)
    printf '[include]\n\tpath = %s\n' "$shared" > "$tmp"
    if [[ -f "$GIT_GLOBAL_CONFIG" ]]; then
        cp "$GIT_GLOBAL_CONFIG" "$GIT_GLOBAL_CONFIG.backup.$(date +%Y%m%d%H%M%S)"
        cat "$GIT_GLOBAL_CONFIG" >> "$tmp"
    fi
    mv "$tmp" "$GIT_GLOBAL_CONFIG"
    chmod 644 "$GIT_GLOBAL_CONFIG"

    track_installed "git shared config"
    log_success "~/.gitconfig now includes $shared"
}

install_git_ignore() {
    print_section "Linking global gitignore"

    local root_dir
    root_dir=$(get_root_dir)
    local source="$root_dir/configs/git/ignore"

    if [[ "$LINK_MODE" == "copy" ]]; then
        if [[ -f "$GIT_IGNORE_TARGET" && ! -L "$GIT_IGNORE_TARGET" ]] && cmp -s "$source" "$GIT_IGNORE_TARGET"; then
            log_info "Global gitignore already up to date"
            track_skipped "Global gitignore"
            return 0
        fi
    elif [[ -L "$GIT_IGNORE_TARGET" && "$(readlink "$GIT_IGNORE_TARGET")" == "$source" ]]; then
        log_info "Global gitignore already linked"
        track_skipped "Global gitignore"
        return 0
    fi

    FORCE=true backup_and_link "$source" "$GIT_IGNORE_TARGET"
    track_installed "Global gitignore"
}

install_git_signing() {
    print_section "Commit signing"

    local key
    key=$(git config --global --includes user.signingkey 2>/dev/null || true)
    if [[ -z "$key" ]]; then
        log_warn "No user.signingkey configured — leaving commit signing off"
        track_skipped "Commit signing (no key configured)"
        return 0
    fi

    if [[ "$(git config --global commit.gpgsign 2>/dev/null)" == "true" ]]; then
        log_info "Commit signing already enabled"
        track_skipped "Commit signing"
        return 0
    fi

    # Only turn signing on where the secret key actually exists; otherwise
    # every commit on this machine would fail.
    if ! command_exists gpg || ! gpg --list-secret-keys "$key" >/dev/null 2>&1; then
        log_warn "GPG secret key $key not found — restore ~/.gnupg, then re-run: ./install.sh git"
        track_skipped "Commit signing (key $key absent)"
        return 0
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would set commit.gpgsign = true in ~/.gitconfig"
        return 0
    fi

    git config --global commit.gpgsign true
    track_installed "Commit signing"
    log_success "Commit signing enabled with key $key"
}

# ==============================================================================
# Main Installation
# ==============================================================================

install_git() {
    log_info "Starting git configuration..."

    if [[ "$PLATFORM" != "macos" ]]; then
        log_info "git config is macOS-only, skipping on platform: $PLATFORM"
        track_skipped "git config (not macOS)"
        return 0
    fi

    install_git_include
    install_git_ignore
    install_git_signing

    log_success "git configuration complete!"
}

# ==============================================================================
# Standalone Execution
# ==============================================================================
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    setup_error_handling
    install_git
fi
