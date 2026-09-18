#!/bin/bash
# secrets-push.sh - publish local private material into the vault that
# `install.sh secrets` restores from. The inverse of modules/secrets.sh.
#
#   scripts/secrets-push.sh              # show what would be pushed, touch nothing
#   scripts/secrets-push.sh --push       # create/update vault items and the manifest
#
# Collection is driven by globs, never by a hardcoded list of services, so this
# script is safe in a public repository: it reveals that ~/.envs/*.env exists,
# not which services live there. The resulting inventory - item names, paths,
# modes - is written only into the vault's manifest item.
#
# Sources:
#   ~/.envs/*.env            -> env:<name>          (skips _-prefixed drafts)
#   ~/.ssh/id_*              -> ssh:<name>          (+ "public" field from <name>.pub)
#   ~/.ssh/config.d/*.conf   -> ssh:config-<name>   (skips files the repo tracks)
#
# Everything is stored as a Secure Note. Bitwarden's native SSH Key item type
# would also work for the key pairs, but the exact shape of its template could
# not be verified against this vault, and a Secure Note behaves identically for
# restore purposes on every server version.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/lib/core.sh"
source "$ROOT/lib/platform.sh"
detect_platform
setup_package_manager
# vault_unlock / ensure_vault_cli live here; sourcing does not run its main.
source "$ROOT/modules/secrets.sh"

VAULT_FOLDER="${SETTINGS_VAULT_FOLDER:-bootstrap}"

PUSH=false
[[ "${1:-}" == "--push" ]] && PUSH=true

# ==============================================================================
# Collection
# ==============================================================================
# Each entry is one TSV line: <srcpath> <item> <dest> <mode> <pubpath>
COLLECTED="$(mktemp)"
trap 'rm -f "$COLLECTED"' EXIT

collect() {
    local f base

    # ~/.envs/*.env
    for f in "$HOME"/.envs/*.env; do
        [[ -f "$f" ]] || continue
        base="$(basename "$f" .env)"
        # A leading underscore is how dead drafts are parked in that directory.
        case "$base" in _*) continue ;; esac
        printf '%s\t%s\t%s\t%s\t%s\n' "$f" "env:$base" "~/.envs/$base.env" 600 "" >> "$COLLECTED"
    done

    # ~/.ssh/id_* private keys, with the matching .pub carried as a field
    for f in "$HOME"/.ssh/id_*; do
        [[ -f "$f" ]] || continue
        case "$f" in *.pub) continue ;; esac
        base="$(basename "$f")"
        local pub=""
        [[ -f "$f.pub" ]] && pub="$f.pub"
        printf '%s\t%s\t%s\t%s\t%s\n' "$f" "ssh:$base" "~/.ssh/$base" 600 "$pub" >> "$COLLECTED"
    done

    # ~/.ssh/config.d/*.conf, minus whatever the repo already manages. Anything
    # git tracks has a source of truth already; duplicating it into the vault
    # would create a second one that silently drifts.
    local tracked
    tracked="$(cd "$ROOT" && git ls-files .ssh/config.d 2>/dev/null | while read -r t; do basename "$t"; done || true)"
    for f in "$HOME"/.ssh/config.d/*.conf; do
        [[ -f "$f" ]] || continue
        base="$(basename "$f")"
        if printf '%s\n' "$tracked" | grep -qxF "$base"; then
            continue
        fi
        printf '%s\t%s\t%s\t%s\t%s\n' "$f" "ssh:config-${base%.conf}" "~/.ssh/config.d/$base" 600 "" >> "$COLLECTED"
    done
}

# ==============================================================================
# Vault upsert
# ==============================================================================

_folder_id() {
    local id
    id="$(bw list folders | jq -r --arg n "$VAULT_FOLDER" '.[] | select(.name == $n) | .id' | head -1)"
    if [[ -z "$id" ]]; then
        id="$(bw get template folder | jq --arg n "$VAULT_FOLDER" '.name = $n' \
              | bw encode | bw create folder | jq -r '.id')"
        log_info "Created vault folder: $VAULT_FOLDER"
    fi
    printf '%s' "$id"
}

# The whole item list is fetched once and matched locally on exact name.
# `bw list items --search` tokenizes, so a name it fails to match would make
# every run create a duplicate instead of updating the item that exists.
ITEMS_CACHE=""

_load_items() {
    ITEMS_CACHE="$(bw list items)"
}

_item_id() {
    printf '%s' "$ITEMS_CACHE" | jq -r --arg n "$1" '.[] | select(.name == $n) | .id' | head -1
}

# upsert_note <name> <notes> <folder-id> [pub-field-value]
upsert_note() {
    local name=$1 notes=$2 fid=$3 pub=${4:-}
    local id payload
    id="$(_item_id "$name")"

    if [[ -n "$id" ]]; then
        payload="$(bw get item "$id" | jq \
            --arg notes "$notes" --arg pub "$pub" \
            '.notes = $notes
             | if $pub == "" then .
               else .fields = (((.fields // []) | map(select(.name != "public")))
                               + [{"name":"public","value":$pub,"type":0}])
               end')"
        printf '%s' "$payload" | bw encode | bw edit item "$id" >/dev/null
        log_success "updated  $name"
    else
        payload="$(bw get template item | jq \
            --arg name "$name" --arg notes "$notes" --arg fid "$fid" --arg pub "$pub" \
            '.type = 2
             | .name = $name
             | .notes = $notes
             | .folderId = $fid
             | .secureNote = {"type": 0}
             | .login = null | .card = null | .identity = null
             | if $pub == "" then .
               else .fields = [{"name":"public","value":$pub,"type":0}] end')"
        printf '%s' "$payload" | bw encode | bw create item >/dev/null
        log_success "created  $name"
    fi
}

# ==============================================================================
# Main
# ==============================================================================

collect

if [[ ! -s "$COLLECTED" ]]; then
    log_error "Nothing collected. Are ~/.envs and ~/.ssh populated?"
    exit 1
fi

print_section "Collected"
printf '  %-26s %-8s %s\n' "ITEM" "MODE" "DEST"
while IFS=$'\t' read -r src item dest mode pub; do
    printf '  %-26s %-8s %s%s\n' "$item" "$mode" "$dest" \
        "$([[ -n "$pub" ]] && echo "  (+public)")"
done < "$COLLECTED"
echo
log_info "$(wc -l < "$COLLECTED" | tr -d ' ') items, folder '$VAULT_FOLDER', manifest '$VAULT_MANIFEST'"

if [[ "$PUSH" != "true" ]]; then
    echo
    log_warn "Dry run. Re-run with --push to write to $VAULT_SERVER"
    exit 0
fi

echo
ensure_vault_cli
vault_unlock

_load_items
FOLDER_ID="$(_folder_id)"
ENTRIES="$(mktemp)"
trap 'rm -f "$COLLECTED" "$ENTRIES"' EXIT

print_section "Pushing"
while IFS=$'\t' read -r src item dest mode pub; do
    content="$(cat "$src")"
    if [[ -z "$content" ]]; then
        log_warn "skipped  $item (empty file: $src)"
        continue
    fi

    pubval=""
    [[ -n "$pub" ]] && pubval="$(cat "$pub")"

    upsert_note "$item" "$content" "$FOLDER_ID" "$pubval"

    jq -n --arg item "$item" --arg dest "$dest" --arg mode "$mode" \
        '{item: $item, source: "notes", dest: $dest, mode: $mode}' >> "$ENTRIES"

    if [[ -n "$pubval" ]]; then
        jq -n --arg item "$item" --arg dest "$dest.pub" \
            '{item: $item, source: "field:public", dest: $dest, mode: "644"}' >> "$ENTRIES"
    fi
done < "$COLLECTED"

# GPG is not collected from disk - exporting a secret key needs the passphrase,
# so those two items are maintained by hand. Preserve them if already present.
print_section "Manifest"
EXISTING_EXTRA="$(bw get item "$VAULT_MANIFEST" 2>/dev/null \
    | jq -r '.notes // empty' 2>/dev/null \
    | jq -c '.entries[]? | select(.exec != null)' 2>/dev/null || true)"
if [[ -n "$EXISTING_EXTRA" ]]; then
    printf '%s\n' "$EXISTING_EXTRA" >> "$ENTRIES"
    log_info "Preserved $(printf '%s\n' "$EXISTING_EXTRA" | wc -l | tr -d ' ') exec entries from the existing manifest"
fi

MANIFEST="$(jq -s '{version: 1, entries: .}' < "$ENTRIES")"
upsert_note "$VAULT_MANIFEST" "$MANIFEST" "$FOLDER_ID"

echo
log_success "Pushed $(jq '.entries | length' <<< "$MANIFEST") manifest entries to $VAULT_SERVER"
log_info "Verify with: ./install.sh -n secrets"
