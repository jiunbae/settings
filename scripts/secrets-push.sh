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
# App data, stored as attachments (Bitwarden notes stop at ~10k characters) and
# restored by piping into a command rather than writing a file:
#   aas accounts             -> app:aas       aas-bundle.json  | aas import -
#   BarShelf data            -> app:barshelf  barshelf.tar.gz  | tar -x into Application Support
#   OTPeek CLI config+vault  -> app:otpeek    otpeek.tar.gz    | tar -x into $HOME, repoint the vault path
# `aas export` reads the Claude credential from the login keychain, so run this
# from a Terminal on the Mac itself, not over SSH.
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

# App data. Each line: <item> <attachment-file-name> <restore-exec> <kind>
APPS="$(mktemp)"
trap 'rm -f "$COLLECTED" "$APPS"' EXIT

BARSHELF_DIR="$HOME/Library/Application Support/BarShelf"
# OTPeek's app and CLI share one encrypted vault in the app group container; the
# CLI finds it through active_vault in its config, an absolute path.
OTPEEK_CONFIG="Library/Application Support/otpeek/config.toml"
OTPEEK_VAULT="Library/Group Containers/group.com.otpeek.app/vault.otpvault"

collect_apps() {
    if command_exists aas && aas list 2>/dev/null | grep -q '@'; then
        printf '%s\t%s\t%s\t%s\n' "app:aas" "aas-bundle.json" \
            'aas import -' aas >> "$APPS"
    fi

    if [[ -d "$BARSHELF_DIR" ]]; then
        # Quit the app first so it cannot write its old state back over the restore,
        # then start it again on the restored data.
        printf '%s\t%s\t%s\t%s\n' "app:barshelf" "barshelf.tar.gz" \
            'pkill -f "/BarShelf.app/" 2>/dev/null; mkdir -p "$HOME/Library/Application Support" && tar -xzf - -C "$HOME/Library/Application Support" && { [ ! -d /Applications/BarShelf.app ] || open -a BarShelf; }' \
            barshelf >> "$APPS"
    fi

    if [[ -f "$HOME/$OTPEEK_CONFIG" && -f "$HOME/$OTPEEK_VAULT" ]]; then
        # The vault is encrypted with the OTPeek master password; it stays that way
        # in the attachment. active_vault is rewritten for the restoring user's home.
        printf '%s\t%s\t%s\t%s\n' "app:otpeek" "otpeek.tar.gz" \
            'tar -xzf - -C "$HOME" && sed -i "" "s#^active_vault = .*#active_vault = \"$HOME/Library/Group Containers/group.com.otpeek.app/vault.otpvault\"#" "$HOME/Library/Application Support/otpeek/config.toml"' \
            otpeek >> "$APPS"
    fi
}

# make_app_payload <kind> <out-file>
make_app_payload() {
    local kind=$1 out=$2
    case "$kind" in
        aas)
            aas export --all -o "$out" >/dev/null
            ;;
        barshelf)
            # runtime/ and cache/ are rebuilt by the app and hold nothing to keep.
            tar -czf "$out" -C "$HOME/Library/Application Support" \
                --exclude 'BarShelf/runtime' --exclude 'BarShelf/cache' BarShelf
            ;;
        otpeek)
            tar -czf "$out" -C "$HOME" "$OTPEEK_CONFIG" "$OTPEEK_VAULT"
            ;;
        *)
            log_error "Unknown app payload: $kind"
            return 1
            ;;
    esac
    [[ -s "$out" ]]
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
        # stderr: this function's stdout is captured as the folder id.
        log_info "Created vault folder: $VAULT_FOLDER" >&2
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

# upsert_attachment <name> <file> <folder-id>
# Replaces the attachment of the same file name, so re-pushing never stacks copies.
upsert_attachment() {
    local name=$1 file=$2 fid=$3
    local id fname old
    fname="$(basename "$file")"
    id="$(_item_id "$name")"
    if [[ -z "$id" ]]; then
        upsert_note "$name" "Restored by 'install.sh secrets' from the attachment $fname." "$fid"
        _load_items
        id="$(_item_id "$name")"
    fi

    local before after
    before="$(bw get item "$id" | jq -r --arg f "$fname" '[(.attachments // [])[] | select(.fileName == $f) | .id] | join(" ")')"
    bw create attachment --file "$file" --itemid "$id" >/dev/null
    # Upload first, then remove every older copy, so a failed upload never
    # leaves the item without one - and a failed delete is reported, not ignored.
    for old in $before; do
        bw delete attachment "$old" --itemid "$id" >/dev/null || log_warn "could not delete old attachment $old on $name"
    done
    after="$(bw get item "$id" | jq -r --arg f "$fname" '[(.attachments // [])[] | select(.fileName == $f)] | length')"
    if [[ "$after" == "1" ]]; then
        log_success "attached $name/$fname"
    else
        log_warn "attached $name/$fname, but the item now has $after attachments with that name"
    fi
}

# ==============================================================================
# Main
# ==============================================================================

collect
collect_apps

if [[ ! -s "$COLLECTED" && ! -s "$APPS" ]]; then
    log_error "Nothing collected. Are ~/.envs and ~/.ssh populated?"
    exit 1
fi

print_section "Collected"
printf '  %-26s %-8s %s\n' "ITEM" "MODE" "DEST"
while IFS=$'\t' read -r src item dest mode pub; do
    printf '  %-26s %-8s %s%s\n' "$item" "$mode" "$dest" \
        "$([[ -n "$pub" ]] && echo "  (+public)")"
done < "$COLLECTED"
while IFS=$'\t' read -r item fname exec_cmd kind; do
    printf '  %-26s %-8s %s\n' "$item" "attach" "$fname -> exec"
done < "$APPS"
echo
log_info "$(cat "$COLLECTED" "$APPS" | wc -l | tr -d ' ') items, folder '$VAULT_FOLDER', manifest '$VAULT_MANIFEST'"

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
# App payloads are credentials too: stage them where only this user can read.
PAYLOADS="$(umask 077; mktemp -d "${TMPDIR:-/tmp}/settings-push.XXXXXX")"
trap 'rm -rf "$COLLECTED" "$APPS" "$ENTRIES" "$PAYLOADS"' EXIT

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

while IFS=$'\t' read -r item fname exec_cmd kind; do
    payload="$PAYLOADS/$fname"
    if ! (umask 077; make_app_payload "$kind" "$payload"); then
        log_warn "skipped  $item (could not produce $fname)"
        continue
    fi
    upsert_attachment "$item" "$payload" "$FOLDER_ID"
    rm -f "$payload"

    jq -n --arg item "$item" --arg src "attachment:$fname" --arg exec "$exec_cmd" \
        '{item: $item, source: $src, exec: $exec}' >> "$ENTRIES"
done < "$APPS"

# GPG is not collected from disk - exporting a secret key needs the passphrase,
# so those two items are maintained by hand. Preserve them if already present,
# but not the exec entries this run just rewrote, or every push would add a copy.
print_section "Manifest"
PUSHED_ITEMS="$(jq -s '[.[].item]' < "$ENTRIES")"
MANIFEST_ID="$(_item_id "$VAULT_MANIFEST")"
EXISTING_EXTRA="$([[ -n "$MANIFEST_ID" ]] && bw get item "$MANIFEST_ID" 2>/dev/null \
    | jq -r '.notes // empty' 2>/dev/null \
    | jq -c --argjson pushed "$PUSHED_ITEMS" \
        '.entries[]? | select(.exec != null) | select(.item as $i | $pushed | index($i) | not)' 2>/dev/null || true)"
if [[ -n "$EXISTING_EXTRA" ]]; then
    printf '%s\n' "$EXISTING_EXTRA" >> "$ENTRIES"
    log_info "Preserved $(printf '%s\n' "$EXISTING_EXTRA" | wc -l | tr -d ' ') exec entries from the existing manifest"
fi

MANIFEST="$(jq -s '{version: 1, entries: .}' < "$ENTRIES")"
upsert_note "$VAULT_MANIFEST" "$MANIFEST" "$FOLDER_ID"

echo
log_success "Pushed $(jq '.entries | length' <<< "$MANIFEST") manifest entries to $VAULT_SERVER"
log_info "Verify with: ./install.sh -n secrets"
