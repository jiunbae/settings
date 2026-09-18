#!/bin/bash
# secrets.sh - Restore private material (SSH keys, GPG keys, env files) from a
# Bitwarden-compatible vault (Bitwarden or self-hosted Vaultwarden).
#
# Opt-in only: this component is deliberately absent from COMPONENTS_ORDER, so
# neither --all nor the interactive menu can pull private keys onto a shared or
# throwaway machine by accident. It only runs when named explicitly:
#
#   ./install.sh secrets
#
# Nothing personal lives in this file. WHAT to restore is a JSON manifest stored
# inside the vault itself, so this script stays publishable while the inventory
# of secrets (item names, destination paths, which keys even exist) stays behind
# the vault's master password + TOTP. Point SETTINGS_VAULT_SERVER at your own
# vault and write your own manifest to reuse it as-is.
#
# Manifest format — the `notes` field of the item named by SETTINGS_VAULT_MANIFEST:
#
#   {
#     "version": 1,
#     "entries": [
#       {"item":"ssh:id_ed25519","source":"sshkey",              "dest":"~/.ssh/id_ed25519",      "mode":"600"},
#       {"item":"ssh:id_ed25519","source":"field:public",        "dest":"~/.ssh/id_ed25519.pub",  "mode":"644"},
#       {"item":"ssh:company",   "source":"attachment:20-company.conf",
#                                                                "dest":"~/.ssh/config.d/20-company.conf","mode":"600"},
#       {"item":"gpg:primary",   "source":"notes", "exec":"gpg --batch --quiet --import"},
#       {"item":"gpg:ownertrust","source":"notes", "exec":"gpg --quiet --import-ownertrust"}
#     ]
#   }
#
# source: notes | sshkey | password | field:<name> | attachment:<filename>
# Each entry needs exactly one sink: `dest` (write a file) or `exec` (pipe into
# a command). `mode` applies to `dest` only and defaults to 600.

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
VAULT_SERVER="${SETTINGS_VAULT_SERVER:-https://vault.jiun.dev}"
VAULT_MANIFEST="${SETTINGS_VAULT_MANIFEST:-bootstrap}"
# Bitwarden 2FA method: 0=authenticator app, 1=email, 3=YubiKey OTP
VAULT_2FA_METHOD="${SETTINGS_VAULT_2FA_METHOD:-0}"

# Scratch space for secret material in flight. Created by install_secrets.
SECRETS_TMPDIR=""

# ==============================================================================
# Dependencies
# ==============================================================================

# bw is a regular package like everything else in this repo: brew on macOS, and
# npm on Debian/Ubuntu because Bitwarden ships no apt package.
ensure_vault_cli() {
    if command_exists bw && command_exists jq; then
        return 0
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would install: bitwarden-cli, jq"
        return 0
    fi

    command_exists jq || pkg_install jq

    if ! command_exists bw; then
        case "$PKG_MANAGER" in
            brew)
                pkg_install bitwarden-cli
                ;;
            *)
                # No apt package exists for the Bitwarden CLI.
                if command_exists npm; then
                    run_with_spinner "Installing @bitwarden/cli" npm install -g @bitwarden/cli
                else
                    log_error "Bitwarden CLI not found and npm is unavailable."
                    log_info "Run './install.sh node' first, or install bw manually."
                    return 1
                fi
                ;;
        esac
    fi

    command_exists bw || { log_error "Bitwarden CLI installation failed"; return 1; }
}

# ==============================================================================
# Vault session
# ==============================================================================

# Prompts are read from and written to the terminal directly, never through the
# command substitution that captures --raw output, so the session key stays the
# only thing on stdout.
_prompt() {
    local var=$1 text=$2 silent=${3:-false}
    local value
    if [[ "$silent" == "true" ]]; then
        read -r -s -p "$text" value < /dev/tty
        echo >&2
    else
        read -r -p "$text" value < /dev/tty
    fi
    printf -v "$var" '%s' "$value"
}

# Full login (email, master password, verification code). Sets BW_SESSION.
_vault_login() {
    local email password code
    log_info "Vault login — master password and verification code required"
    _prompt email    "  Email: "
    _prompt password "  Master password: " true
    _prompt code     "  Verification code (TOTP, blank if disabled): "

    if [[ -n "$code" ]]; then
        BW_SESSION="$(BW_PASSWORD="$password" bw login "$email" \
            --passwordenv BW_PASSWORD \
            --method "$VAULT_2FA_METHOD" --code "$code" --raw)" || BW_SESSION=""
    else
        BW_SESSION="$(BW_PASSWORD="$password" bw login "$email" \
            --passwordenv BW_PASSWORD --raw)" || BW_SESSION=""
    fi
    password=""
}

vault_unlock() {
    local status
    status="$(bw status 2>/dev/null | jq -r '.status' 2>/dev/null || echo unauthenticated)"

    # Server can only be pointed elsewhere while logged out.
    if [[ "$status" == "unauthenticated" ]]; then
        local current
        current="$(bw config server 2>/dev/null || echo '')"
        if [[ "$current" != "$VAULT_SERVER" ]]; then
            log_info "Vault server: $VAULT_SERVER"
            bw config server "$VAULT_SERVER" >/dev/null
        fi
    else
        local configured
        configured="$(bw status | jq -r '.serverUrl // empty')"
        if [[ -n "$configured" && "$configured" != "$VAULT_SERVER" ]]; then
            log_warn "Logged into $configured, but SETTINGS_VAULT_SERVER is $VAULT_SERVER"
            log_info "Run 'bw logout' first to switch vaults."
            return 1
        fi
    fi

    local password
    case "$status" in
        unauthenticated)
            _vault_login
            ;;
        locked)
            log_info "Vault is locked"
            _prompt password "  Master password: " true
            BW_SESSION="$(BW_PASSWORD="$password" bw unlock --passwordenv BW_PASSWORD --raw 2>/dev/null)" || BW_SESSION=""
            if [[ -z "$BW_SESSION" ]]; then
                # A saved login the server no longer accepts (expired or revoked
                # refresh token) fails here with invalid_grant, and bw then crashes
                # instead of saying so. A wrong password lands here too. Either way
                # a fresh login is the way out.
                log_warn "Unlock failed — saved login rejected by the server, or wrong password. Logging in again."
                bw logout >/dev/null 2>&1 || true
                bw config server "$VAULT_SERVER" >/dev/null
                _vault_login
            fi
            ;;
        unlocked)
            if [[ -z "${BW_SESSION:-}" ]]; then
                log_info "Vault reports unlocked but BW_SESSION is unset"
                _prompt password "  Master password: " true
                BW_SESSION="$(BW_PASSWORD="$password" bw unlock --passwordenv BW_PASSWORD --raw)"
            fi
            ;;
    esac
    password=""

    [[ -n "${BW_SESSION:-}" ]] || { log_error "Failed to obtain a vault session"; return 1; }
    export BW_SESSION

    run_with_spinner "Syncing vault" bw sync
    log_success "Vault unlocked"
}

# ==============================================================================
# Manifest application
# ==============================================================================

# _fetch <item> <source-spec> <outfile>
_fetch() {
    local item=$1 src=$2 out=$3

    case "$src" in
        notes)
            bw get item "$item" | jq -r '.notes // empty' > "$out"
            ;;
        sshkey)
            bw get item "$item" | jq -r '.sshKey.privateKey // empty' > "$out"
            ;;
        password)
            bw get password "$item" > "$out"
            ;;
        field:*)
            bw get item "$item" \
                | jq -r --arg n "${src#field:}" \
                    '(.fields // []) | map(select(.name == $n)) | .[0].value // empty' > "$out"
            ;;
        attachment:*)
            local id
            id="$(bw get item "$item" | jq -r '.id')"
            bw get attachment "${src#attachment:}" --itemid "$id" --output "$out" >/dev/null
            ;;
        *)
            log_error "Unknown source spec: $src"
            return 1
            ;;
    esac

    [[ -s "$out" ]] || { log_error "Empty payload: $item ($src)"; return 1; }
}

# _place <tmpfile> <dest> <mode>
_place() {
    local tmp=$1 dest=$2 mode=$3

    if [[ -e "$dest" && ! -L "$dest" ]]; then
        if cmp -s "$tmp" "$dest"; then
            printf "\r${CLEAR_LINE:-}  ${GREEN}✓${NC} %s (unchanged)\n" "$dest"
            track_skipped "$dest"
            return 0
        fi
        local backup="${dest}.backup.$(date +%Y%m%d%H%M%S)"
        mv "$dest" "$backup"
        track_backup "$dest" "$backup"
        log_info "Backed up: $dest -> $backup"
    fi

    mkdir -p "$(dirname "$dest")"
    chmod 700 "$(dirname "$dest")" 2>/dev/null || true
    mv "$tmp" "$dest"
    chmod "$mode" "$dest"
    log_success "Restored: $dest"
    track_installed "$(basename "$dest")"
}

apply_manifest() {
    print_section "Restoring Secrets"

    local manifest
    manifest="$(bw get item "$VAULT_MANIFEST" | jq -r '.notes // empty')"
    if [[ -z "$manifest" ]]; then
        log_error "Manifest item '$VAULT_MANIFEST' has no notes"
        return 1
    fi
    if ! printf '%s' "$manifest" | jq -e '.entries | type == "array"' >/dev/null 2>&1; then
        log_error "Manifest '$VAULT_MANIFEST' is not valid JSON with an .entries array"
        return 1
    fi

    local count
    count="$(printf '%s' "$manifest" | jq '.entries | length')"
    log_info "Manifest '$VAULT_MANIFEST': $count entries"

    local entry item src dest mode exec_cmd tmp
    while IFS= read -r entry; do
        item="$(printf '%s' "$entry" | jq -r '.item')"
        src="$(printf '%s' "$entry" | jq -r '.source // "notes"')"
        dest="$(printf '%s' "$entry" | jq -r '.dest // empty')"
        mode="$(printf '%s' "$entry" | jq -r '.mode // "600"')"
        exec_cmd="$(printf '%s' "$entry" | jq -r '.exec // empty')"

        if [[ -n "$dest" && -n "$exec_cmd" ]] || [[ -z "$dest" && -z "$exec_cmd" ]]; then
            log_error "Entry '$item' needs exactly one of 'dest' or 'exec'"
            continue
        fi

        dest="${dest/#\~/$HOME}"

        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[DRY-RUN] Would restore $item ($src) -> ${dest:-$exec_cmd}"
            continue
        fi

        tmp="$SECRETS_TMPDIR/payload"
        if ! _fetch "$item" "$src" "$tmp"; then
            continue
        fi

        if [[ -n "$dest" ]]; then
            _place "$tmp" "$dest" "$mode"
        else
            if bash -c "$exec_cmd" < "$tmp"; then
                log_success "Piped $item -> $exec_cmd"
                track_installed "$item"
            else
                log_error "Command failed for $item: $exec_cmd"
            fi
            rm -f "$tmp"
        fi
    done < <(printf '%s' "$manifest" | jq -c '.entries[]')
}

# ==============================================================================
# Main Installation
# ==============================================================================

install_secrets() {
    log_info "Restoring secrets from $VAULT_SERVER ..."

    ensure_vault_cli || return 1

    # A dry run must not prompt for a master password. With an existing session
    # the manifest can still be enumerated for real; without one, say so and stop
    # rather than pretending to know what the vault holds.
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would unlock $VAULT_SERVER and apply manifest '$VAULT_MANIFEST'"
        if [[ -n "${BW_SESSION:-}" ]]; then
            apply_manifest || return 1
        else
            log_info "[DRY-RUN] Vault locked — run 'bw unlock' first to enumerate entries"
        fi
        return 0
    fi

    # umask so nothing touches disk world-readable, even momentarily.
    local old_umask
    old_umask="$(umask)"
    umask 077
    SECRETS_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/settings-secrets.XXXXXX")"
    umask "$old_umask"
    trap 'rm -rf "$SECRETS_TMPDIR"' EXIT

    vault_unlock || return 1
    apply_manifest || return 1

    rm -rf "$SECRETS_TMPDIR"
    trap - EXIT
    log_info "Vault stays unlocked for this shell. Run 'bw lock' when done."

    log_success "Secrets restore complete!"
}

# ==============================================================================
# Standalone Execution
# ==============================================================================
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    setup_error_handling
    install_secrets
fi
