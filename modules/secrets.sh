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
# The restore itself is kitbag's now; this file supplies the vault login, the
# 2FA and the per-machine scope, and hands over. Everything from
# `install_secrets_manifest` down is the engine that did the job before, kept
# for a machine that has not moved across: SETTINGS_SECRETS_ENGINE=bash.
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
#     "version": 2,
#     "entries": [
#       {"item":"ssh:id_ed25519","source":"sshkey",              "dest":"~/.ssh/id_ed25519",      "mode":"600", "scope":"personal"},
#       {"item":"ssh:id_ed25519","source":"field:public",        "dest":"~/.ssh/id_ed25519.pub",  "mode":"644", "scope":"personal"},
#       {"item":"ssh:company",   "source":"attachment:20-company.conf",
#                                                                "dest":"~/.ssh/config.d/20-company.conf","mode":"600","scope":"work"},
#       {"item":"gpg:primary",   "source":"notes", "exec":"gpg --batch --quiet --import",   "scope":"mixed"},
#       {"item":"gpg:ownertrust","source":"notes", "exec":"gpg --quiet --import-ownertrust","scope":"mixed"}
#     ]
#   }
#
# source: notes | sshkey | password | field:<name> | attachment:<filename>
# Each entry needs exactly one sink: `dest` (write a file) or `exec` (pipe into
# a command). `mode` applies to `dest` only and defaults to 600.
#
# scope separates the lives that share one vault — personal, work, shared (an
# account someone else owns), mixed (one blob holding several). A machine
# restores only the scopes it asks for, so a personal laptop never has to hold
# an employer's credentials:
#
#   ./install.sh secrets                                  personal only (default)
#   SETTINGS_SECRETS_SCOPE=all ./install.sh secrets       everything
#   SETTINGS_SECRETS_SCOPE=personal,work ./install.sh secrets
#   echo work > ~/.config/settings/secrets.scope          this machine's default
#
# "mixed" entries restore under any scope. Entries without a scope predate this
# and are treated as "mixed", with a warning.

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

# Which scopes this machine restores. Precedence: environment, then the file a
# machine keeps for itself, then the safe default of personal only.
SECRETS_SCOPE_FILE="${SETTINGS_SECRETS_SCOPE_FILE:-$HOME/.config/settings/secrets.scope}"

secrets_scope() {
    local scope="${SETTINGS_SECRETS_SCOPE:-}"
    if [[ -z "$scope" && -f "$SECRETS_SCOPE_FILE" ]]; then
        scope="$(tr -d '[:space:]' < "$SECRETS_SCOPE_FILE")"
    fi
    printf '%s' "${scope:-personal}"
}

# _scope_wanted <entry-scope> <requested>
_scope_wanted() {
    local entry=$1 want=$2
    [[ "$want" == "all" ]] && return 0
    # One blob holding several lives cannot be split on the way out.
    [[ "$entry" == "mixed" || -z "$entry" ]] && return 0
    case ",$want," in *",$entry,"*) return 0 ;; esac
    return 1
}

# Scratch space for secret material in flight. Created by install_secrets.
SECRETS_TMPDIR=""

# ==============================================================================
# Dependencies
# ==============================================================================

# The Bitwarden CLI is pinned. Vaultwarden trails Bitwarden's server API, and a
# newer client can fail against it outright: 2026.9.0 runs a "user key id
# backfill" migration during login that POSTs to an endpoint Vaultwarden
# (API level 2026.6.0 here) answers with 404, so login never yields a session.
# 2026.8.0 is the newest version verified against vault.jiun.dev. Installed
# from npm because Homebrew only carries the latest release.
VAULT_CLI_VERSION="${SETTINGS_BW_CLI_VERSION:-2026.8.0}"

ensure_vault_cli() {
    if [[ "$DRY_RUN" == "true" ]]; then
        command_exists bw && command_exists jq || \
            log_info "[DRY-RUN] Would install: @bitwarden/cli@$VAULT_CLI_VERSION, jq"
        return 0
    fi

    command_exists jq || pkg_install jq

    if command_exists bw; then
        local have
        have="$(bw --version 2>/dev/null | tail -n 1)"
        if [[ "$have" != "$VAULT_CLI_VERSION" ]]; then
            log_warn "bw $have is not the verified $VAULT_CLI_VERSION; newer clients can fail against Vaultwarden."
            log_info "If login fails: bw logout; replace it with npm install -g @bitwarden/cli@$VAULT_CLI_VERSION"
        fi
        return 0
    fi

    if command_exists npm; then
        run_with_spinner "Installing @bitwarden/cli@$VAULT_CLI_VERSION" \
            npm install -g "@bitwarden/cli@$VAULT_CLI_VERSION"
    elif [[ "$PKG_MANAGER" == "brew" ]]; then
        log_warn "npm not found — installing the latest bitwarden-cli from Homebrew (unpinned)."
        log_info "Run './install.sh node' first to get the pinned $VAULT_CLI_VERSION."
        pkg_install bitwarden-cli
    else
        log_error "Bitwarden CLI not found and npm is unavailable."
        log_info "Run './install.sh node' first, or install bw manually."
        return 1
    fi

    hash -r
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

# _vault_item <name> — the item whose name is exactly <name>, as JSON.
# `bw get item <name>` is a search, so a second item whose name merely contains
# <name> (env:foo next to env:foo-staging) would make it fail with "More than
# one result". The list is fetched once per run and matched locally.
VAULT_ITEMS_CACHE=""
_vault_item() {
    local name=$1 json
    [[ -n "$VAULT_ITEMS_CACHE" ]] || VAULT_ITEMS_CACHE="$(bw list items)"
    json="$(printf '%s' "$VAULT_ITEMS_CACHE" | jq -c --arg n "$name" 'map(select(.name == $n)) | .[0] // empty')"
    [[ -n "$json" ]] || { log_error "Vault item not found: $name"; return 1; }
    printf '%s' "$json"
}

# _fetch <item> <source-spec> <outfile>
_fetch() {
    local item=$1 src=$2 out=$3 json
    json="$(_vault_item "$item")" || return 1

    case "$src" in
        notes)
            jq -r '.notes // empty' <<< "$json" > "$out"
            ;;
        sshkey)
            jq -r '.sshKey.privateKey // empty' <<< "$json" > "$out"
            ;;
        password)
            jq -r '.login.password // empty' <<< "$json" > "$out"
            ;;
        field:*)
            jq -r --arg n "${src#field:}" \
                '(.fields // []) | map(select(.name == $n)) | .[0].value // empty' <<< "$json" > "$out"
            ;;
        attachment:*)
            # By attachment id, not name: `bw get attachment <name>` fails with
            # "More than one result" whenever an earlier push left a same-named
            # attachment behind. The last one listed is the newest upload.
            local fname="${src#attachment:}" aid err
            aid="$(jq -r --arg f "$fname" '[(.attachments // [])[] | select(.fileName == $f)] | last | .id // empty' <<< "$json")"
            [[ -n "$aid" ]] || { log_error "No attachment '$fname' on $item"; return 1; }
            err="$(bw get attachment "$aid" --itemid "$(jq -r '.id' <<< "$json")" --output "$out" 2>&1 >/dev/null)" || {
                log_error "bw get attachment failed for $item/$fname: ${err%%$'\n'*}"
                return 1
            }
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

# _platform_matches <space-separated names> — true when this machine is one of
# them. Manifest names are macos, windows and linux; WSL answers to linux too,
# since everything a Linux entry restores works there unchanged.
_platform_matches() {
    local want=$1 self="$PLATFORM" w s
    [[ "$self" == "wsl" ]] && self="linux wsl"
    for w in $want; do
        for s in $self; do
            [[ "$w" == "$s" ]] && return 0
        done
    done
    return 1
}

apply_manifest() {
    print_section "Restoring Secrets"

    local manifest
    manifest="$(_vault_item "$VAULT_MANIFEST" | jq -r '.notes // empty')"
    if [[ -z "$manifest" ]]; then
        log_error "Manifest item '$VAULT_MANIFEST' has no notes"
        return 1
    fi
    if ! printf '%s' "$manifest" | jq -e '.entries | type == "array"' >/dev/null 2>&1; then
        log_error "Manifest '$VAULT_MANIFEST' is not valid JSON with an .entries array"
        return 1
    fi

    local count want legacy
    count="$(printf '%s' "$manifest" | jq '.entries | length')"
    want="$(secrets_scope)"
    log_info "Manifest '$VAULT_MANIFEST': $count entries, scope '$want'"

    legacy="$(printf '%s' "$manifest" | jq '[.entries[] | select(has("scope") | not)] | length')"
    if [[ "$legacy" != "0" ]]; then
        log_warn "$legacy entries carry no scope (written before scopes existed) — restored as 'mixed'"
    fi

    local entry item src dest mode exec_cmd platforms ptype tmp scope skipped=0
    while IFS= read -r entry; do
        item="$(printf '%s' "$entry" | jq -r '.item')"
        src="$(printf '%s' "$entry" | jq -r '.source // "notes"')"
        dest="$(printf '%s' "$entry" | jq -r '.dest // empty')"
        mode="$(printf '%s' "$entry" | jq -r '.mode // "600"')"
        exec_cmd="$(printf '%s' "$entry" | jq -r '.exec // empty')"
        scope="$(printf '%s' "$entry" | jq -r '.scope // empty')"

        if ! _scope_wanted "$scope" "$want"; then
            log_debug "Skipped $item (scope $scope)"
            skipped=$((skipped + 1))
            continue
        fi

        # A bare string is accepted as well as an array; absent means everywhere.
        # The type is read first, on its own: `.platform | type` answers "null"
        # for an absent field, where iterating a number would make jq exit 5 and
        # take the whole install.sh run down with it under `set -e`.
        ptype="$(printf '%s' "$entry" | jq -r '.platform | type')"
        case "$ptype" in
            null)   platforms="" ;;
            string) platforms="$(printf '%s' "$entry" | jq -r '.platform')" ;;
            array)
                # A name that is not a string is a broken manifest. Do not guess
                # in either direction: reading it as "everywhere" would let one
                # typo loose a macOS-only entry on another platform.
                if ! platforms="$(printf '%s' "$entry" | jq -er \
                    '.platform | if all(type == "string") then join(" ") else error end')"; then
                    log_error "Entry '$item' has a non-string platform name; skipping"
                    continue
                fi
                ;;
            *)
                log_error "Entry '$item' has a $ptype platform, expected a string or an array; skipping"
                continue
                ;;
        esac

        if [[ -n "$dest" && -n "$exec_cmd" ]] || [[ -z "$dest" && -z "$exec_cmd" ]]; then
            log_error "Entry '$item' needs exactly one of 'dest' or 'exec'"
            continue
        fi

        # Checked ahead of the dry run, so a dry run reports the skips too.
        if [[ -n "$platforms" ]] && ! _platform_matches "$platforms"; then
            log_info "Skipped $item (platform: $platforms)"
            track_skipped "$item"
            continue
        fi

        dest="${dest/#\~/$HOME}"

        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[DRY-RUN] Would restore $item [${scope:-mixed}] ($src) -> ${dest:-$exec_cmd}"
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

    if [[ "$skipped" -gt 0 ]]; then
        log_info "Skipped $skipped entries outside scope '$want' (SETTINGS_SECRETS_SCOPE=all for everything)"
    fi
}

# ==============================================================================
# Main Installation
# ==============================================================================

# kitbag restores this machine now. Everything below this function is the
# engine that did it before, and it stays reachable by name for a machine that
# has not moved across yet:
#
#   SETTINGS_SECRETS_ENGINE=bash ./install.sh secrets
#
# The two read different things out of the same vault - kitbag its own items,
# the older path the `bootstrap` manifest - so a vault mid-migration holds both
# and neither deletes what the other wrote.
SECRETS_ENGINE="${SETTINGS_SECRETS_ENGINE:-kitbag}"

# The scope this machine was *told*, as opposed to the one it falls back to.
# Empty means nobody said, and then kitbag's own config decides rather than
# this script overriding it with a default.
secrets_scope_declared() {
    local scope="${SETTINGS_SECRETS_SCOPE:-}"
    if [[ -z "$scope" && -f "$SECRETS_SCOPE_FILE" ]]; then
        scope="$(tr -d '[:space:]' < "$SECRETS_SCOPE_FILE")"
    fi
    printf '%s' "$scope"
}

restore_with_kitbag() {
    # Running this module on its own does not source the other one.
    if ! declare -F install_kitbag_binary >/dev/null 2>&1; then
        source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/kitbag.sh"
    fi
    install_kitbag_binary || return 1

    local config="$HOME/.config/kitbag/machine.toml"
    if [[ ! -f "$config" && "$DRY_RUN" != "true" ]]; then
        # A machine being restored holds nothing yet, so there is nothing for
        # the generator to read: what it produces here is the scope line, which
        # is the part restore actually needs.
        "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/kitbag-config.sh" --write || return 1
    fi

    local args=(restore --backend bw)
    local scope
    scope="$(secrets_scope_declared)"
    [[ -n "$scope" ]] && args+=(--scope "$scope")

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would restore from $VAULT_SERVER with kitbag"
        if [[ -n "${BW_SESSION:-}" ]]; then
            kitbag "${args[@]}" --dry-run || return 1
        else
            log_info "[DRY-RUN] Vault locked - run 'bw unlock' first to enumerate items"
        fi
        return 0
    fi

    # The unlock below is the one this repository already had: it knows this
    # server's login, its 2FA method, and how to keep the session key out of
    # the process table. kitbag reads BW_SESSION from the environment, so the
    # two need nothing else from each other.
    vault_unlock || return 1
    export BW_SESSION

    kitbag "${args[@]}" || return 1
    log_info "Vault stays unlocked for this shell. Run 'bw lock' when done."
    log_success "Secrets restore complete!"
}

install_secrets() {
    ensure_vault_cli || return 1

    if [[ "$SECRETS_ENGINE" == "kitbag" ]]; then
        restore_with_kitbag
        return $?
    fi

    log_warn "Using the pre-kitbag engine (SETTINGS_SECRETS_ENGINE=$SECRETS_ENGINE)"
    install_secrets_manifest
}

install_secrets_manifest() {
    log_info "Restoring secrets from $VAULT_SERVER ..."

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
