#!/bin/bash
# ssh-trust.sh - keep one list of the keys your own machines log in with, and
# make every machine agree on it.
#
#   scripts/ssh-trust.sh list                    who is trusted where
#   scripts/ssh-trust.sh register [--new-key]    this machine joins the list
#   scripts/ssh-trust.sh sync [host...]          collect every host's key, give
#                                                every host the union
#   scripts/ssh-trust.sh revoke <fp|comment>...  drop a key here and everywhere
#
# The hosts are not in this repository - they are ssh aliases read from
# ~/.ssh/trusted-hosts (one per line, # comments allowed) or passed as
# arguments. Nothing here names a machine, a user or a network.
#
# Why a list and not one shared key: a key that every machine holds cannot be
# revoked for one machine, and tells you nothing about which machine logged in.
# Each machine keeps its own key; the list says which of them are yours.
#
# Merging never deletes. A host may have keys this list does not know about - a
# CI runner, an agent, a phone - and `sync` leaves them alone. `revoke` is the
# only thing that removes, and only what you name.
#
# ~/.ssh/authorized_keys carries a `# scope: personal` header so that
# scripts/secrets-push.sh picks it up and every new machine gets the list from
# the vault on its first `install.sh secrets` - which is what lets an existing
# machine reach the new one to register it.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/lib/core.sh"

AUTH="$HOME/.ssh/authorized_keys"
HOSTS_FILE="${SETTINGS_TRUSTED_HOSTS:-$HOME/.ssh/trusted-hosts}"
KEY="$HOME/.ssh/id_ed25519"
SSH_OPTS=(-o ConnectTimeout=10 -o BatchMode=yes)

# A machine that has just rotated its key cannot log in with the new one yet -
# no host has seen it. The very command that fixes that is `sync`, so offer the
# retired key alongside the current one and the rotation can finish itself.
_offer_retired_keys() {
    local old
    for old in "$HOME"/.ssh/retired-*/id_ed25519 "$HOME"/.ssh/retired-*/*/id_ed25519; do
        [[ -f "$old" ]] && SSH_OPTS+=(-i "$old")
    done
    [[ -f "$KEY" ]] && SSH_OPTS+=(-i "$KEY")
    return 0
}

# ==============================================================================
# Helpers
# ==============================================================================

hosts() {
    if [[ $# -gt 0 ]]; then
        printf '%s\n' "$@"
    elif [[ -f "$HOSTS_FILE" ]]; then
        grep -vE '^[[:space:]]*(#|$)' "$HOSTS_FILE" || true
    else
        log_error "No hosts given and $HOSTS_FILE does not exist."
        log_info "Write one ssh alias per line there, or pass them as arguments."
        return 1
    fi
}

# For the commands that still do something useful with no hosts at all.
hosts_optional() { hosts "$@" 2>/dev/null || true; }

# The key material - type and base64 - identifies a key. The comment is a label
# and changes freely, so it must not take part in matching.
key_material() { awk '{print $1, $2}'; }

# fingerprint <pubkey-line>
fingerprint() { printf '%s\n' "$1" | ssh-keygen -lf - 2>/dev/null | awk '{print $2}'; }

# comment <pubkey-line> — the trailing label, or "(no comment)"
comment() {
    local c
    c="$(printf '%s\n' "$1" | awk '{$1=""; $2=""; sub(/^  /, ""); print}')"
    printf '%s' "${c:-(no comment)}"
}

ensure_auth() {
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"
    if [[ ! -f "$AUTH" ]]; then
        (umask 077; printf '# scope: personal\n# the machines that may log in as this user\n' > "$AUTH")
    elif ! head -5 "$AUTH" | grep -q '^# scope:'; then
        local tmp
        tmp="$(mktemp)"
        { printf '# scope: personal\n# the machines that may log in as this user\n'; cat "$AUTH"; } > "$tmp"
        (umask 077; cat "$tmp" > "$AUTH")
        rm -f "$tmp"
    fi
    chmod 600 "$AUTH"
}

# merge_into <file> < pubkey lines — adds what is missing, removes nothing.
merge_into() {
    local file=$1 line material added=0
    while IFS= read -r line; do
        case "$line" in ''|\#*) continue ;; esac
        material="$(printf '%s\n' "$line" | key_material)"
        if ! grep -qF "$material" "$file" 2>/dev/null; then
            printf '%s\n' "$line" >> "$file"
            added=$((added + 1))
        fi
    done
    printf '%s' "$added"
}

# ==============================================================================
# Commands
# ==============================================================================

cmd_list() {
    local host line fp cm
    print_section "This machine"
    ensure_auth
    while IFS= read -r line; do
        case "$line" in ''|\#*) continue ;; esac
        printf '  %-52s %s\n' "$(fingerprint "$line")" "$(comment "$line")"
    done < "$AUTH"

    local hs
    hs="$(hosts_optional "$@")"
    [[ -n "$hs" ]] || { echo; log_info "No other hosts listed. Add ssh aliases to $HOSTS_FILE."; return 0; }
    for host in $hs; do
        print_section "$host"
        if ! ssh "${SSH_OPTS[@]}" "$host" 'cat ~/.ssh/authorized_keys' 2>/dev/null > "$TMP/remote"; then
            log_warn "unreachable"
            continue
        fi
        while IFS= read -r line; do
            case "$line" in ''|\#*) continue ;; esac
            printf '  %-52s %s\n' "$(fingerprint "$line")" "$(comment "$line")"
        done < "$TMP/remote"
    done
}

cmd_register() {
    local new_key=false
    [[ "${1:-}" == "--new-key" ]] && new_key=true

    ensure_auth

    if [[ "$new_key" == "true" || ! -f "$KEY" ]]; then
        if [[ -f "$KEY" && "$new_key" == "true" ]]; then
            local retired="$HOME/.ssh/retired-$(date +%Y%m%d%H%M%S)"
            mkdir -p "$retired"
            mv "$KEY" "$retired/" 2>/dev/null || true
            mv "$KEY.pub" "$retired/" 2>/dev/null || true
            log_info "Previous key moved to $retired"
        fi
        ssh-keygen -t ed25519 -N '' -C "${USER}@$(hostname -s)" -f "$KEY" >/dev/null
        log_success "Generated $KEY for ${USER}@$(hostname -s)"
    fi

    local added
    added="$(merge_into "$AUTH" < "$KEY.pub")"
    if [[ "$added" == "0" ]]; then
        log_info "Already in the local list: $(fingerprint "$(cat "$KEY.pub")")"
    else
        log_success "Added to the local list: $(comment "$(cat "$KEY.pub")")"
    fi

    if [[ "$new_key" == "true" ]]; then
        log_warn "No host trusts this new key yet. Run sync now, from this machine,"
        log_warn "while the retired key is still around to get you in."
    fi
    log_info "Next: scripts/ssh-trust.sh sync   (give every host the union)"
    log_info "Then: scripts/secrets-push.sh --push   (put the list in the vault)"
}

cmd_sync() {
    local hs host added total=0
    _offer_retired_keys
    hs="$(hosts "$@")" || return 1
    ensure_auth

    # First collect: every host's own key joins the list, so the list really is
    # "all my machines" no matter which one this runs from.
    print_section "Collecting"
    for host in $hs; do
        if ! ssh "${SSH_OPTS[@]}" "$host" 'cat ~/.ssh/id_ed25519.pub' 2>/dev/null > "$TMP/pub"; then
            log_warn "$host — unreachable, or it has no ed25519 key"
            continue
        fi
        [[ -s "$TMP/pub" ]] || continue
        added="$(merge_into "$AUTH" < "$TMP/pub")"
        if [[ "$added" == "0" ]]; then
            printf '  %s %s (known)\n' "${GREEN}✓${NC}" "$host"
        else
            printf '  %s %s → added %s\n' "${GREEN}✓${NC}" "$host" "$(comment "$(cat "$TMP/pub")")"
            total=$((total + 1))
        fi
    done

    # Then distribute: every host ends up with at least what this list holds.
    print_section "Distributing"
    for host in $hs; do
        if ! ssh "${SSH_OPTS[@]}" "$host" '
            umask 077; mkdir -p ~/.ssh; chmod 700 ~/.ssh; touch ~/.ssh/authorized_keys
            added=0
            while IFS= read -r line; do
                case "$line" in ""|\#*) continue ;; esac
                material=$(printf "%s\n" "$line" | awk "{print \$1, \$2}")
                grep -qF "$material" ~/.ssh/authorized_keys || { printf "%s\n" "$line" >> ~/.ssh/authorized_keys; added=$((added+1)); }
            done
            chmod 600 ~/.ssh/authorized_keys
            echo "$added"
        ' < "$AUTH" 2>/dev/null > "$TMP/added"; then
            log_warn "$host — could not write authorized_keys"
            continue
        fi
        printf '  %s %s → %s new\n' "${GREEN}✓${NC}" "$host" "$(cat "$TMP/added")"
    done

    log_success "Synced ${total} new key(s) into the list"
    log_info "Put the list in the vault so new machines start with it: scripts/secrets-push.sh --push"
}

cmd_revoke() {
    local targets=() rest=()
    local seen_sep=false arg
    for arg in "$@"; do
        if [[ "$arg" == "--" ]]; then seen_sep=true; continue; fi
        if [[ "$seen_sep" == "true" ]]; then rest+=("$arg"); else targets+=("$arg"); fi
    done
    [[ ${#targets[@]} -gt 0 ]] || { log_error "Nothing to revoke. Give a fingerprint or a comment."; return 1; }

    # Build the filter once, locally, then apply the same one everywhere.
    local line fp keep removed=0
    ensure_auth
    : > "$TMP/kept"
    while IFS= read -r line; do
        case "$line" in ''|\#*) printf '%s\n' "$line" >> "$TMP/kept"; continue ;; esac
        fp="$(fingerprint "$line")"
        keep=true
        for arg in "${targets[@]}"; do
            if [[ "$fp" == *"$arg"* ]] || [[ "$line" == *"$arg"* ]]; then keep=false; break; fi
        done
        if [[ "$keep" == "true" ]]; then
            printf '%s\n' "$line" >> "$TMP/kept"
        else
            log_info "revoking $fp $(comment "$line")"
            removed=$((removed + 1))
        fi
    done < "$AUTH"

    if [[ "$removed" == "0" ]]; then
        log_warn "Nothing matched here."
    else
        (umask 077; cat "$TMP/kept" > "$AUTH")
        chmod 600 "$AUTH"
        log_success "Removed $removed key(s) from this machine"
    fi

    local hs host
    hs="$(hosts_optional ${rest[@]+"${rest[@]}"})"
    [[ -n "$hs" ]] || return 0
    print_section "Elsewhere"
    for host in $hs; do
        if ! ssh "${SSH_OPTS[@]}" "$host" "
            f=~/.ssh/authorized_keys
            [ -f \"\$f\" ] || exit 0
            cp \"\$f\" \"\$f.backup.\$(date +%Y%m%d%H%M%S)\"
            tmp=\$(mktemp)
            while IFS= read -r line; do
                case \"\$line\" in ''|\\#*) printf '%s\n' \"\$line\" >> \"\$tmp\"; continue ;; esac
                fp=\$(printf '%s\n' \"\$line\" | ssh-keygen -lf - 2>/dev/null | awk '{print \$2}')
                keep=1
                for a in $(printf '%q ' "${targets[@]}"); do
                    case \"\$fp\" in *\"\$a\"*) keep=0 ;; esac
                    case \"\$line\" in *\"\$a\"*) keep=0 ;; esac
                done
                [ \$keep -eq 1 ] && printf '%s\n' \"\$line\" >> \"\$tmp\"
            done < \"\$f\"
            before=\$(grep -c . \"\$f\"); after=\$(grep -c . \"\$tmp\")
            cat \"\$tmp\" > \"\$f\"; rm -f \"\$tmp\"; chmod 600 \"\$f\"
            echo \$((before - after))
        " 2>/dev/null > "$TMP/n"; then
            log_warn "$host — unreachable"
            continue
        fi
        printf '  %s %s → removed %s\n' "${GREEN}✓${NC}" "$host" "$(cat "$TMP/n")"
    done
}

# ==============================================================================
# Main
# ==============================================================================

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cmd="${1:-list}"
shift || true

case "$cmd" in
    list)     cmd_list "$@" ;;
    register) cmd_register "$@" ;;
    sync)     cmd_sync "$@" ;;
    revoke)   cmd_revoke "$@" ;;
    -h|--help|help)
        sed -n '2,30p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
        ;;
    *)
        log_error "Unknown command: $cmd"
        log_info "Try: list | register | sync | revoke | help"
        exit 1
        ;;
esac
