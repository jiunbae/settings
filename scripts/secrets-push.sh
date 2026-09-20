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
# Scopes. Every file declares who owns its credentials, so one vault can hold
# several lives without mixing them. The marker lives in the file, not in this
# repository - a public repo must not carry the list of which employer or which
# service each secret belongs to:
#
#   # scope: work          first 5 lines of the file (#-comment, any of them)
#   # owner: acme          optional, free text, kept only as a vault field
#
# For files that cannot hold a comment (private keys), a sidecar works:
#   ~/.ssh/id_ed25519.scope  containing just the scope word
#
# personal | work | shared   go to the vault folder of that name
# mixed                      one blob that cannot be split (aas, otpeek)
# local                      machine-only, never pushed (e.g. a vault session)
# no marker                  skipped and listed, so a new file is never pushed
#                            into the wrong life by default
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

# Scratch files. Several of these are written from inside command substitutions,
# where a shell variable would die with the subshell.
COLLECTED="$(mktemp)"   # what to push, one line per item
APPS="$(mktemp)"        # app payload descriptors
UNSCOPED="$(mktemp)"    # files skipped for want of a usable scope
FOLDERS_CACHE="$(mktemp)"
ENTRIES=""              # manifest entries, created by the push
PAYLOADS=""             # staged app payloads, created by the push
FAILED=""                # items this run could not write; set once bw is in play
cleanup() { rm -rf "$COLLECTED" "$APPS" "$UNSCOPED" "$FOLDERS_CACHE" ${FAILED:+"$FAILED"} ${ENTRIES:+"$ENTRIES"} ${PAYLOADS:+"$PAYLOADS"}; }
trap cleanup EXIT

# ==============================================================================
# Scopes
# ==============================================================================
SCOPES_VALID="personal work shared mixed local"

# _scope_of <file> [default] — the scope a file declares, or the default.
_scope_of() {
    local f=$1 def=${2:-} s=""
    s="$(head -5 "$f" 2>/dev/null \
         | sed -nE 's/^[[:space:]]*#[[:space:]]*scope:[[:space:]]*([a-zA-Z-]+).*/\1/p' \
         | head -1 | tr '[:upper:]' '[:lower:]')"
    if [[ -z "$s" && -f "$f.scope" ]]; then
        s="$(tr -d '[:space:]' < "$f.scope" | tr '[:upper:]' '[:lower:]')"
    fi
    printf '%s' "${s:-$def}"
}

# _owner_of <file> — the optional owner note, free text.
_owner_of() {
    head -5 "$1" 2>/dev/null \
        | sed -nE 's/^[[:space:]]*#[[:space:]]*owner:[[:space:]]*(.+)$/\1/p' | head -1
}

_scope_valid() {
    case " $SCOPES_VALID " in *" $1 "*) return 0 ;; *) return 1 ;; esac
}

# Files that declared nothing, or something unknown, are listed in $UNSCOPED.
# _scope_gate <file> <item> [default] — prints the scope, or fails when the file
# must not be pushed (unmarked, unknown, or machine-local).
_scope_gate() {
    local f=$1 item=$2 def=${3:-} scope
    scope="$(_scope_of "$f" "$def")"
    if [[ -z "$scope" ]]; then
        printf '  %s — no '"'"'# scope:'"'"' marker in %s\n' "$item" "$f" >> "$UNSCOPED"
        return 1
    fi
    if ! _scope_valid "$scope"; then
        printf '  %s — unknown scope '"'"'%s'"'"' in %s\n' "$item" "$scope" "$f" >> "$UNSCOPED"
        return 1
    fi
    [[ "$scope" == "local" ]] && return 1
    printf '%s' "$scope"
}

# ==============================================================================
# Collection
# ==============================================================================
# One line per entry: <srcpath> <item> <dest> <mode> <pubpath> <scope> <owner>.
# Fields are separated by US (0x1f), not by a tab: bash counts a tab as IFS
# whitespace, so a run of them collapses and an empty field - a key with no
# .pub, a file with no owner - would shift every column after it.
SEP=$'\x1f'

collect() {
    local f base scope owner

    # ~/.envs/*.env
    for f in "$HOME"/.envs/*.env; do
        [[ -f "$f" ]] || continue
        base="$(basename "$f" .env)"
        # A leading underscore is how dead drafts are parked in that directory.
        case "$base" in _*) continue ;; esac
        scope="$(_scope_gate "$f" "env:$base")" || continue
        owner="$(_owner_of "$f")"
        printf "%s${SEP}%s${SEP}%s${SEP}%s${SEP}%s${SEP}%s${SEP}%s\n" \
            "$f" "env:$base" "~/.envs/$base.env" 600 "" "$scope" "$owner" >> "$COLLECTED"
    done

    # ~/.ssh/id_* private keys, with the matching .pub carried as a field. A key
    # holds no comments, so its scope comes from an id_*.scope sidecar; without
    # one it is the machine owner's own key.
    for f in "$HOME"/.ssh/id_*; do
        [[ -f "$f" ]] || continue
        case "$f" in *.pub|*.scope) continue ;; esac
        base="$(basename "$f")"
        scope="$(_scope_gate "$f" "ssh:$base" personal)" || continue
        local pub=""
        [[ -f "$f.pub" ]] && pub="$f.pub"
        printf "%s${SEP}%s${SEP}%s${SEP}%s${SEP}%s${SEP}%s${SEP}%s\n" \
            "$f" "ssh:$base" "~/.ssh/$base" 600 "$pub" "$scope" "" >> "$COLLECTED"
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
        scope="$(_scope_gate "$f" "ssh:config-${base%.conf}")" || continue
        owner="$(_owner_of "$f")"
        printf "%s${SEP}%s${SEP}%s${SEP}%s${SEP}%s${SEP}%s${SEP}%s\n" \
            "$f" "ssh:config-${base%.conf}" "~/.ssh/config.d/$base" 600 "" "$scope" "$owner" >> "$COLLECTED"
    done
}

# App data. Each line: <item> <attachment-file-name> <restore-exec> <kind> <scope>
BARSHELF_DIR="$HOME/Library/Application Support/BarShelf"
# OTPeek's app and CLI share one encrypted vault in the app group container; the
# CLI finds it through active_vault in its config, an absolute path.
OTPEEK_CONFIG="Library/Application Support/otpeek/config.toml"
OTPEEK_VAULT="Library/Group Containers/group.com.otpeek.app/vault.otpvault"

# App state is one opaque blob per app, so it carries the scope of its contents
# as a whole. An app holding accounts from more than one life is "mixed": it
# restores under every scope, because the blob cannot be split from out here.
# Override per machine, e.g. SETTINGS_SCOPE_AAS=personal.
SCOPE_AAS="${SETTINGS_SCOPE_AAS:-mixed}"
SCOPE_BARSHELF="${SETTINGS_SCOPE_BARSHELF:-personal}"
SCOPE_OTPEEK="${SETTINGS_SCOPE_OTPEEK:-mixed}"

collect_apps() {
    if command_exists aas && aas list 2>/dev/null | grep -q '@'; then
        printf "%s${SEP}%s${SEP}%s${SEP}%s${SEP}%s\n" "app:aas" "aas-bundle.json" \
            'aas import -' aas "$SCOPE_AAS" >> "$APPS"
    fi

    if [[ -d "$BARSHELF_DIR" ]]; then
        # Quit the app first so it cannot write its old state back over the restore,
        # then start it again on the restored data.
        printf "%s${SEP}%s${SEP}%s${SEP}%s${SEP}%s\n" "app:barshelf" "barshelf.tar.gz" \
            'pkill -f "/BarShelf.app/" 2>/dev/null; mkdir -p "$HOME/Library/Application Support" && tar -xzf - -C "$HOME/Library/Application Support" && { [ ! -d /Applications/BarShelf.app ] || open -a BarShelf; }' \
            barshelf "$SCOPE_BARSHELF" >> "$APPS"
    fi

    if [[ -f "$HOME/$OTPEEK_CONFIG" && -f "$HOME/$OTPEEK_VAULT" ]]; then
        # The vault is encrypted with the OTPeek master password; it stays that way
        # in the attachment. active_vault is rewritten for the restoring user's home.
        printf "%s${SEP}%s${SEP}%s${SEP}%s${SEP}%s\n" "app:otpeek" "otpeek.tar.gz" \
            'tar -xzf - -C "$HOME" && sed -i "" "s#^active_vault = .*#active_vault = \"$HOME/Library/Group Containers/group.com.otpeek.app/vault.otpvault\"#" "$HOME/Library/Application Support/otpeek/config.toml"' \
            otpeek "$SCOPE_OTPEEK" >> "$APPS"
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

# A vault write that survives a blip. The server is on the other side of a
# network: one FetchError used to abort the whole run with `set -e`, leaving
# half the items pushed and no manifest at all.
_bw_write() {   # <payload> <bw-command...>
    local payload=$1; shift
    local attempt=1 err
    while :; do
        if err="$(printf '%s' "$payload" | bw encode | "$@" 2>&1 >/dev/null)"; then
            return 0
        fi
        if (( attempt >= 3 )); then
            log_error "${*}: ${err%%$'\n'*}"
            return 1
        fi
        log_warn "vault write failed (attempt $attempt/3), retrying: ${err%%$'\n'*}"
        sleep $(( attempt * 3 ))
        attempt=$(( attempt + 1 ))
    done
}

# Same for a read, which can fail the same way.
_bw_read() {    # <bw-command...>
    local attempt=1 out
    while :; do
        if out="$("$@" 2>/dev/null)"; then
            printf '%s' "$out"
            return 0
        fi
        if (( attempt >= 3 )); then
            return 1
        fi
        sleep $(( attempt * 3 ))
        attempt=$(( attempt + 1 ))
    done
}

# _folder_id <name> — the id of that vault folder, created on first use.
# Bitwarden folders are flat but a "/" in the name nests them in the clients, so
# scopes appear as bootstrap/personal, bootstrap/work, bootstrap/shared.
# $FOLDERS_CACHE is a file because _folder_id runs inside a command substitution:
# a variable filled there dies with the subshell, leaving the caller with an
# empty cache and one `bw list folders` per item.
_folder_list() {
    [[ -s "$FOLDERS_CACHE" ]] || bw list folders > "$FOLDERS_CACHE"
    cat "$FOLDERS_CACHE"
}

_folder_id() {
    local name=$1 id
    id="$(_folder_list | jq -r --arg n "$name" '.[] | select(.name == $n) | .id' | head -1)"
    if [[ -z "$id" ]]; then
        id="$(bw get template folder | jq --arg n "$name" '.name = $n' \
              | bw encode | bw create folder | jq -r '.id')"
        bw list folders > "$FOLDERS_CACHE"
        # stderr: this function's stdout is captured as the folder id.
        log_info "Created vault folder: $name" >&2
    fi
    printf '%s' "$id"
}

# _scope_folder <scope> — where items of that scope live.
_scope_folder() {
    case "$1" in
        mixed|"") printf '%s' "$VAULT_FOLDER" ;;
        *)        printf '%s/%s' "$VAULT_FOLDER" "$1" ;;
    esac
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

# upsert_note <name> <notes> <folder-id> [pub-field-value] [scope] [owner]
# The folder is reassigned on every update: an item whose file changed scope has
# to leave the old folder, or the separation is only true for new items.
upsert_note() {
    local name=$1 notes=$2 fid=$3 pub=${4:-} scope=${5:-} owner=${6:-}
    local id payload
    id="$(_item_id "$name")"

    # scope/owner are custom fields as well as folders, so they survive an export
    # and can be searched in the clients.
    local fields_filter='
        def put($n; $v):
            if $v == "" then map(select(.name != $n))
            else map(select(.name != $n)) + [{"name":$n,"value":$v,"type":0}] end;
        .fields = ((.fields // []) | put("public"; $pub) | put("scope"; $scope) | put("owner"; $owner))'

    if [[ -n "$id" ]]; then
        local current
        current="$(_bw_read bw get item "$id")" || { log_error "could not read $name"; return 1; }
        payload="$(printf '%s' "$current" | jq \
            --arg notes "$notes" --arg pub "$pub" --arg fid "$fid" \
            --arg scope "$scope" --arg owner "$owner" \
            ".notes = \$notes | .folderId = \$fid | $fields_filter")"
        _bw_write "$payload" bw edit item "$id" || return 1
        log_success "updated  $name${scope:+  [$scope]}"
    else
        payload="$(bw get template item | jq \
            --arg name "$name" --arg notes "$notes" --arg fid "$fid" --arg pub "$pub" \
            --arg scope "$scope" --arg owner "$owner" \
            ".type = 2
             | .name = \$name
             | .notes = \$notes
             | .folderId = \$fid
             | .secureNote = {\"type\": 0}
             | .login = null | .card = null | .identity = null
             | .fields = []
             | $fields_filter")"
        _bw_write "$payload" bw create item || return 1
        log_success "created  $name${scope:+  [$scope]}"
    fi
}

# upsert_attachment <name> <file> <folder-id> [scope]
# Replaces the attachment of the same file name, so re-pushing never stacks copies.
upsert_attachment() {
    local name=$1 file=$2 fid=$3 scope=${4:-}
    local id fname old
    fname="$(basename "$file")"
    id="$(_item_id "$name")"
    if [[ -z "$id" ]]; then
        upsert_note "$name" "Restored by 'install.sh secrets' from the attachment $fname." "$fid" "" "$scope" || return 1
        _load_items
        id="$(_item_id "$name")"
    else
        # Keep folder and scope current even when the attachment is all that changes.
        local notes
        notes="$(_bw_read bw get item "$id" | jq -r '.notes // ""')" || notes=""
        upsert_note "$name" "$notes" "$fid" "" "$scope" >/dev/null || return 1
    fi

    local before after
    before="$(_bw_read bw get item "$id" | jq -r --arg f "$fname" '[(.attachments // [])[] | select(.fileName == $f) | .id] | join(" ")')" || return 1
    local attempt=1
    until bw create attachment --file "$file" --itemid "$id" >/dev/null 2>&1; do
        if (( attempt >= 3 )); then
            log_error "could not upload $fname to $name"
            return 1
        fi
        log_warn "attachment upload failed (attempt $attempt/3), retrying"
        sleep $(( attempt * 3 ))
        attempt=$(( attempt + 1 ))
    done
    # Upload first, then remove every older copy, so a failed upload never
    # leaves the item without one - and a failed delete is reported, not ignored.
    for old in $before; do
        bw delete attachment "$old" --itemid "$id" >/dev/null || log_warn "could not delete old attachment $old on $name"
    done
    after="$(_bw_read bw get item "$id" | jq -r --arg f "$fname" '[(.attachments // [])[] | select(.fileName == $f)] | length')" || after="?"
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
printf '  %-26s %-9s %-8s %s\n' "ITEM" "SCOPE" "MODE" "DEST"
while IFS="$SEP" read -r src item dest mode pub scope owner; do
    printf '  %-26s %-9s %-8s %s%s\n' "$item" "$scope" "$mode" "$dest" \
        "$([[ -n "$pub" ]] && echo "  (+public)")"
done < "$COLLECTED"
while IFS="$SEP" read -r item fname exec_cmd kind scope; do
    printf '  %-26s %-9s %-8s %s\n' "$item" "$scope" "attach" "$fname -> exec"
done < "$APPS"
echo
cut -d"$SEP" -f6 "$COLLECTED" 2>/dev/null | cat - <(cut -d"$SEP" -f5 "$APPS" 2>/dev/null) \
    | sort | uniq -c | while read -r n s; do printf '  %-9s %s\n' "$s" "$n"; done
echo
log_info "$(cat "$COLLECTED" "$APPS" | wc -l | tr -d ' ') items, folder '$VAULT_FOLDER', manifest '$VAULT_MANIFEST'"

if [[ -s "$UNSCOPED" ]]; then
    echo
    log_warn "Not pushed — no usable scope (add '# scope: personal|work|shared' to the file):"
    cat "$UNSCOPED"
fi

if [[ "$PUSH" != "true" ]]; then
    echo
    log_warn "Dry run. Re-run with --push to write to $VAULT_SERVER"
    exit 0
fi

echo
ensure_vault_cli
vault_unlock

_load_items
# A push that half-worked must say so at the end rather than in the middle.
FAILED="$(mktemp)"
ENTRIES="$(mktemp)"
# App payloads are credentials too: stage them where only this user can read.
PAYLOADS="$(umask 077; mktemp -d "${TMPDIR:-/tmp}/settings-push.XXXXXX")"

print_section "Pushing"
while IFS="$SEP" read -r src item dest mode pub scope owner; do
    content="$(cat "$src")"
    if [[ -z "$content" ]]; then
        log_warn "skipped  $item (empty file: $src)"
        continue
    fi

    pubval=""
    [[ -n "$pub" ]] && pubval="$(cat "$pub")"

    fid="$(_folder_id "$(_scope_folder "$scope")")"
    if ! upsert_note "$item" "$content" "$fid" "$pubval" "$scope" "$owner"; then
        printf '%s\n' "  $item" >> "$FAILED"
        continue
    fi

    jq -n --arg item "$item" --arg dest "$dest" --arg mode "$mode" --arg scope "$scope" \
        '{item: $item, source: "notes", dest: $dest, mode: $mode, scope: $scope}' >> "$ENTRIES"

    if [[ -n "$pubval" ]]; then
        jq -n --arg item "$item" --arg dest "$dest.pub" --arg scope "$scope" \
            '{item: $item, source: "field:public", dest: $dest, mode: "644", scope: $scope}' >> "$ENTRIES"
    fi
done < "$COLLECTED"

while IFS="$SEP" read -r item fname exec_cmd kind scope; do
    payload="$PAYLOADS/$fname"
    if ! (umask 077; make_app_payload "$kind" "$payload"); then
        log_warn "skipped  $item (could not produce $fname)"
        continue
    fi
    fid="$(_folder_id "$(_scope_folder "$scope")")"
    if ! upsert_attachment "$item" "$payload" "$fid" "$scope"; then
        printf '%s\n' "  $item" >> "$FAILED"
        rm -f "$payload"
        continue
    fi
    rm -f "$payload"

    jq -n --arg item "$item" --arg src "attachment:$fname" --arg exec "$exec_cmd" --arg scope "$scope" \
        '{item: $item, source: $src, exec: $exec, scope: $scope}' >> "$ENTRIES"
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
    # Hand-maintained entries from before scopes existed: a GPG key that carries
    # every identity at once is exactly what "mixed" means.
    printf '%s\n' "$EXISTING_EXTRA" \
        | jq -c --arg s "${SETTINGS_SCOPE_MANUAL:-mixed}" '.scope = (.scope // $s)' >> "$ENTRIES"
    log_info "Preserved $(printf '%s\n' "$EXISTING_EXTRA" | wc -l | tr -d ' ') exec entries from the existing manifest"
fi

MANIFEST="$(jq -s '{version: 2, entries: .}' < "$ENTRIES")"
# The manifest lists only what actually landed, so a restore never chases an
# item this run failed to write.
if ! upsert_note "$VAULT_MANIFEST" "$MANIFEST" "$(_folder_id "$VAULT_FOLDER")"; then
    log_error "The manifest itself could not be written — run the push again."
    exit 1
fi

echo
log_success "Pushed $(jq '.entries | length' <<< "$MANIFEST") manifest entries to $VAULT_SERVER"
jq -r '.entries | group_by(.scope // "none")[] | "\(.[0].scope // "none") \(length)"' <<< "$MANIFEST" \
    | while read -r s n; do printf '  %-9s %s entries\n' "$s" "$n"; done

# Items left in the bootstrap folders that this push did not write: a file that
# turned machine-local (# scope: local), was deleted, or lost its marker. They
# are still readable secrets, so say so rather than leave them to rot.
_load_items
STALE="$(_folder_list | jq -r --arg f "$VAULT_FOLDER" \
            '[.[] | select(.name == $f or (.name | startswith($f + "/"))) | .id]' \
        | jq --argjson items "$(printf '%s' "$ITEMS_CACHE" | jq '[.[] | {id, name, folderId}]')" \
             --argjson pushed "$PUSHED_ITEMS" --arg m "$VAULT_MANIFEST" -r \
             '. as $folders | $items[]
              | select(.folderId as $fid | $folders | index($fid))
              | select(.name != $m)
              | select(.name as $n | $pushed | index($n) | not)
              | "  \(.name)  (bw delete item \(.id))"')"
if [[ -n "$STALE" ]]; then
    echo
    log_warn "In the vault but not pushed by this machine — delete if obsolete:"
    printf '%s\n' "$STALE"
fi

if [[ -s "$FAILED" ]]; then
    echo
    log_error "These items could not be written and are NOT in the manifest:"
    cat "$FAILED"
    log_info "Run the push again — it updates in place, so nothing is duplicated."
    exit 1
fi

log_info "Verify with: ./install.sh -n secrets"
