#!/bin/bash
# secrets-push.sh - publish local private material into the vault that
# `install.sh secrets` restores from. The inverse of modules/secrets.sh.
#
# SUPERSEDED. `kitbag push` does this job now, and `install.sh secrets` restores
# with kitbag. This script still works and still writes the manifest the older
# engine reads, which is what a machine that has not moved across needs; when
# every machine is across, it and the manifest can go. See docs/kitbag.md.
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
#   ~/.ssh/authorized_keys   -> ssh:authorized_keys  (restores by merging, below)
#
# Anything else is tracked by listing it in ~/.config/settings/secrets-paths,
# one per line - because the next secret will not live where this script guessed:
#
#   <path>  <scope>  [owner]  [item-name]  [platforms]
#
# The columns are positional: write `-` for one that does not apply, or a
# platform written after a bare scope becomes the owner.
#   ~/.npmrc                                    personal
#   ~/.aws/config                               work      acme
#   ~/Library/Keychains/x.keychain-db           work      acme   file:x-keychain  macos
#
# The fifth column is comma-separated and says where the path exists at all, so
# a restore elsewhere skips it instead of writing a macOS keychain into a Linux
# home. scripts/kitbag-config.sh reads the same column out of the same file.
#
# A path's own `# scope:` header still wins over the column, so a file that can
# carry the marker keeps carrying it. Text goes up as notes; anything binary
# goes up as an attachment and is written back byte for byte.
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
# All three restore into ~/Library and shell out to macOS-only commands, so each
# is tagged "platform": ["macos"] in the manifest. A restore on another platform
# skips them instead of running `open -a` or writing an Application Support path
# that means nothing there.
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
STATUS=false
case "${1:-}" in
    --push)            PUSH=true ;;
    --status|status)   STATUS=true ;;
    ''|--dry-run)      ;;
    *) printf 'usage: %s [--status | --push]\n' "$(basename "$0")" >&2; exit 2 ;;
esac

# Scratch files. Several of these are written from inside command substitutions,
# where a shell variable would die with the subshell.
COLLECTED="$(mktemp)"   # what to push, one line per item
APPS="$(mktemp)"        # app payload descriptors
UNSCOPED="$(mktemp)"    # files skipped for want of a usable scope
BINARIES="$(mktemp)"    # tracked paths that must travel as attachments
FOLDERS_CACHE="$(mktemp)"
TMPDIR_ROWS="$(mktemp)"  # one display row per collected item
STATES=""                # item<TAB>state, filled by --status
GRAY=$'\033[0;90m'      # core.sh has no dim; unchanged rows should recede
ENTRIES=""              # manifest entries, created by the push
PAYLOADS=""             # staged app payloads, created by the push
FAILED=""                # items this run could not write; set once bw is in play
PENDING=""               # attachments uploaded, hashes not yet recorded
cleanup() { rm -rf "$COLLECTED" "$APPS" "$UNSCOPED" "$BINARIES" "$FOLDERS_CACHE" "$TMPDIR_ROWS" ${STATES:+"$STATES"} ${FAILED:+"$FAILED"} ${ENTRIES:+"$ENTRIES"} ${PENDING:+"$PENDING"} ${PAYLOADS:+"$PAYLOADS"}; }
trap cleanup EXIT

# ==============================================================================
# Scopes
# ==============================================================================
SCOPES_VALID="personal work shared mixed local"

# _scope_of <file> [default] — the scope a file declares, or the default.
_scope_of() {
    local f=$1 def=${2:-} s=""
    # LC_ALL=C: a marker is ASCII, and the files searched for one include a
    # keychain. Without it sed reads those bytes as text in the current locale
    # and stops with "RE error: illegal byte sequence" before it finds nothing.
    s="$(head -5 "$f" 2>/dev/null \
         | LC_ALL=C sed -nE 's/^[[:space:]]*#[[:space:]]*scope:[[:space:]]*([a-zA-Z-]+).*/\1/p' \
         | head -1 | tr '[:upper:]' '[:lower:]')"
    if [[ -z "$s" && -f "$f.scope" ]]; then
        s="$(tr -d '[:space:]' < "$f.scope" | tr '[:upper:]' '[:lower:]')"
    fi
    printf '%s' "${s:-$def}"
}

# _owner_of <file> — the optional owner note, free text.
_owner_of() {
    head -5 "$1" 2>/dev/null \
        | LC_ALL=C sed -nE 's/^[[:space:]]*#[[:space:]]*owner:[[:space:]]*(.+)$/\1/p' | head -1
}

# Where an entry can be restored at all. A name that is not one of these is a
# typo, and a typo here is an entry that restores on no machine ever again -
# which is worth the same treatment as an unknown scope: reported, not pushed.
PLATFORMS_VALID="macos windows linux wsl"

_platform_valid() {
    local p
    for p in ${1//,/ }; do
        case " $PLATFORMS_VALID " in *" $p "*) ;; *) return 1 ;; esac
    done
    return 0
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
# One line per entry:
#   <srcpath> <item> <dest> <mode> <pubpath> <scope> <owner> <platforms>.
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
        printf "%s${SEP}%s${SEP}%s${SEP}%s${SEP}%s${SEP}%s${SEP}%s${SEP}%s\n" \
            "$f" "env:$base" "~/.envs/$base.env" 600 "" "$scope" "$owner" "" >> "$COLLECTED"
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
        printf "%s${SEP}%s${SEP}%s${SEP}%s${SEP}%s${SEP}%s${SEP}%s${SEP}%s\n" \
            "$f" "ssh:$base" "~/.ssh/$base" 600 "$pub" "$scope" "" "" >> "$COLLECTED"
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
        printf "%s${SEP}%s${SEP}%s${SEP}%s${SEP}%s${SEP}%s${SEP}%s${SEP}%s\n" \
            "$f" "ssh:config-${base%.conf}" "~/.ssh/config.d/$base" 600 "" "$scope" "$owner" "" >> "$COLLECTED"
    done

    collect_tracked_paths

    # ~/.ssh/authorized_keys, so a new machine starts out reachable from the
    # ones that already exist. It carries its own '# scope:' header.
    local ak="$HOME/.ssh/authorized_keys"
    if [[ -f "$ak" ]]; then
        if scope="$(_scope_gate "$ak" "ssh:authorized_keys")"; then
            owner="$(_owner_of "$ak")"
            printf "%s${SEP}%s${SEP}%s${SEP}%s${SEP}%s${SEP}%s${SEP}%s${SEP}%s\n" \
                "$ak" "ssh:authorized_keys" "~/.ssh/authorized_keys" 600 "" "$scope" "$owner" "" >> "$COLLECTED"
        fi
    fi
}

# authorized_keys is the one file that must not be written over on restore: a
# machine may hold keys this list has never seen - a CI runner, an agent, a
# phone - and replacing the file would lock them out without a word. So it
# restores through a merge that adds what is missing and removes nothing.
# scripts/ssh-trust.sh is what maintains the list itself.
AUTHORIZED_KEYS_MERGE='umask 077; mkdir -p "$HOME/.ssh"; chmod 700 "$HOME/.ssh"; touch "$HOME/.ssh/authorized_keys"; while IFS= read -r l; do case "$l" in ""|\#*) continue;; esac; m=$(printf "%s\n" "$l" | awk "{print \$1, \$2}"); grep -qF "$m" "$HOME/.ssh/authorized_keys" || printf "%s\n" "$l" >> "$HOME/.ssh/authorized_keys"; done; chmod 600 "$HOME/.ssh/authorized_keys"'

# ------------------------------------------------------------------------------
# Paths this machine was told to track
# ------------------------------------------------------------------------------
TRACKED_PATHS="${SETTINGS_TRACKED_PATHS:-$HOME/.config/settings/secrets-paths}"

# A name that survives being read back: ~/.aws/config -> file:aws-config
_path_item_name() {
    local rel="${1#$HOME/}"
    rel="${rel#.}"
    printf 'file:%s' "$(printf '%s' "$rel" | sed -E 's#^\.##; s#/#-#g; s#^\.##')"
}

# Binary payloads cannot ride in a note. `grep -Iq` is the cheap "is this text"
# test that every platform here agrees on.
_is_text() { grep -Iq . "$1" 2>/dev/null; }

collect_tracked_paths() {
    [[ -f "$TRACKED_PATHS" ]] || return 0
    local line path scope owner name platform expanded
    while IFS= read -r line; do
        case "$line" in ''|\#*) continue ;; esac
        # shellcheck disable=SC2086
        set -- $line
        path=${1:-}; scope=${2:-}; owner=${3:-}; name=${4:-}; platform=${5:-}
        # The columns are positional, so a later one cannot be set without the
        # ones before it. `-` is how a line says "not this one" rather than
        # inventing an owner: without it, a platform written after a bare scope
        # lands in the owner column, and nothing validates an owner.
        [[ "$owner" == "-" ]] && owner=""
        [[ "$name" == "-" ]] && name=""
        [[ "$platform" == "-" ]] && platform=""
        [[ -n "$path" ]] || continue
        expanded="${path/#\~/$HOME}"
        if [[ ! -e "$expanded" ]]; then
            printf '  %s — listed in %s but not on this machine\n' "$path" "$TRACKED_PATHS" >> "$UNSCOPED"
            continue
        fi
        if [[ -d "$expanded" ]]; then
            printf '  %s — is a directory; track the files inside it\n' "$path" >> "$UNSCOPED"
            continue
        fi
        # The file's own marker wins: it travels with the file, the list does not.
        local declared
        declared="$(_scope_of "$expanded" "$scope")"
        if [[ -z "$declared" ]]; then
            printf '  %s — no scope in the file and none in %s\n' "$path" "$TRACKED_PATHS" >> "$UNSCOPED"
            continue
        fi
        if ! _scope_valid "$declared"; then
            printf '  %s — unknown scope '"'"'%s'"'"'\n' "$path" "$declared" >> "$UNSCOPED"
            continue
        fi
        [[ "$declared" == "local" ]] && continue
        if [[ -n "$platform" ]] && ! _platform_valid "$platform"; then
            printf '  %s — unknown platform '"'"'%s'"'"' (want: %s)\n' \
                "$path" "$platform" "${PLATFORMS_VALID// /, }" >> "$UNSCOPED"
            continue
        fi
        platform="${platform//,/ }"
        [[ -n "$name" ]] || name="$(_path_item_name "$expanded")"
        [[ -n "$owner" ]] || owner="$(_owner_of "$expanded")"

        if _is_text "$expanded"; then
            printf "%s${SEP}%s${SEP}%s${SEP}%s${SEP}%s${SEP}%s${SEP}%s${SEP}%s\n" \
                "$expanded" "$name" "$path" 600 "" "$declared" "$owner" "$platform" >> "$COLLECTED"
        else
            # Binary: goes up as an attachment and is placed back as a file.
            printf "%s${SEP}%s${SEP}%s${SEP}%s${SEP}%s${SEP}%s${SEP}%s${SEP}%s\n" \
                "$expanded" "$name" "$path" 600 "" "$declared" "$owner" "$platform" >> "$BINARIES"
        fi
    done < "$TRACKED_PATHS"
}

# App data. Each line:
#   <item> <attachment-file-name> <restore-exec> <kind> <scope> <platforms>
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
        printf "%s${SEP}%s${SEP}%s${SEP}%s${SEP}%s${SEP}%s\n" "app:aas" "aas-bundle.json" \
            'aas import -' aas "$SCOPE_AAS" macos >> "$APPS"
    fi

    if [[ -d "$BARSHELF_DIR" ]]; then
        # Quit the app first so it cannot write its old state back over the restore,
        # then start it again on the restored data.
        printf "%s${SEP}%s${SEP}%s${SEP}%s${SEP}%s${SEP}%s\n" "app:barshelf" "barshelf.tar.gz" \
            'pkill -f "/BarShelf.app/" 2>/dev/null; mkdir -p "$HOME/Library/Application Support" && tar -xzf - -C "$HOME/Library/Application Support" && { [ ! -d /Applications/BarShelf.app ] || open -a BarShelf; }' \
            barshelf "$SCOPE_BARSHELF" macos >> "$APPS"
    fi

    if [[ -f "$HOME/$OTPEEK_CONFIG" && -f "$HOME/$OTPEEK_VAULT" ]]; then
        # The vault is encrypted with the OTPeek master password; it stays that way
        # in the attachment. active_vault is rewritten for the restoring user's home.
        printf "%s${SEP}%s${SEP}%s${SEP}%s${SEP}%s${SEP}%s\n" "app:otpeek" "otpeek.tar.gz" \
            'tar -xzf - -C "$HOME" && sed -i "" "s#^active_vault = .*#active_vault = \"$HOME/Library/Group Containers/group.com.otpeek.app/vault.otpvault\"#" "$HOME/Library/Application Support/otpeek/config.toml"' \
            otpeek "$SCOPE_OTPEEK" macos >> "$APPS"
    fi
}

# _platform_json <space-separated names> - the manifest's platform array, or [].
# jq -R on empty input prints nothing and --argjson refuses an empty string,
# which under `set -e` would abort a push after the attachments are uploaded
# and the old ones pruned, but before the manifest is written.
_platform_json() {
    if [[ -z "${1:-}" ]]; then
        printf '[]'
        return 0
    fi
    printf '%s' "$1" | jq -R 'split(" ") | map(select(length > 0))'
}

_sha256() {   # hashes stdin
    if command_exists shasum; then shasum -a 256 | awk '{print $1}'
    else sha256sum | awk '{print $1}'; fi
}

# app_fingerprint <kind> — what the payload would be built from, hashed without
# building it. Rebuilding is not free: the aas bundle asks the login keychain
# for every credential, and the tarballs read the whole directory.
# Empty output means "cannot tell cheaply" — then the payload itself is hashed.
app_fingerprint() {
    case "$1" in
        barshelf)
            find "$BARSHELF_DIR" -type f \
                -not -path '*/runtime/*' -not -path '*/cache/*' -print0 2>/dev/null \
                | LC_ALL=C sort -z | xargs -0 shasum -a 256 2>/dev/null | _sha256
            ;;
        otpeek)
            shasum -a 256 "$HOME/$OTPEEK_CONFIG" "$HOME/$OTPEEK_VAULT" 2>/dev/null | _sha256
            ;;
        *)
            # aas tokens rotate on their own, so the accounts list says nothing
            # about whether the bundle changed. Build it and hash that.
            printf ''
            ;;
    esac
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

# Like _folder_id, but never creates: `--status` must not write to the vault.
_folder_id_lookup() {
    _folder_list | jq -r --arg n "$1" '.[] | select(.name == $n) | .id' | head -1
}

# Items sitting in the bootstrap folders that this machine no longer sends: a
# file that turned machine-local, was deleted, or lost its marker. They are
# still readable secrets, so say so rather than leave them to rot.
# Reads $ITEMS_CACHE, so load it first. $KEEP is what this run accounts for.
print_stale() {
    local keep="${KEEP:-[]}" stale
    stale="$(_folder_list | jq -r --arg f "$VAULT_FOLDER" \
                '[.[] | select(.name == $f or (.name | startswith($f + "/"))) | .id]' \
            | jq --argjson items "$(printf '%s' "$ITEMS_CACHE" | jq '[.[] | {id, name, folderId}]')" \
                 --argjson keep "$keep" --arg m "$VAULT_MANIFEST" -r \
                 '. as $folders | $items[]
                  | select(.folderId as $fid | $folders | index($fid))
                  | select(.name != $m)
                  | select(.name as $n | $keep | index($n) | not)
                  | "  \(.name)  (bw delete item \(.id))"')"
    [[ -n "$stale" ]] || return 0
    echo
    log_warn "In the vault but not sent by this machine — delete if obsolete:"
    printf '%s\n' "$stale"
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

# Items this engine owns. kitbag writes the same names into the same vault, in
# its own folder and marked with a `kitbag` field, and matching on the name
# alone picked whichever copy the listing happened to return first. Two engines
# then took turns editing each other's items, and every run reported a
# different handful as changed because the one it compared against was not the
# one it had written.
_mine() {
    printf '%s' "$ITEMS_CACHE" | jq -c --arg n "$1" \
        '[.[] | select(.name == $n)
              | select([(.fields // [])[] | select(.name == "kitbag")] | length == 0)]'
}

_item_id() {
    local mine count
    mine="$(_mine "$1")"
    count="$(printf '%s' "$mine" | jq 'length')"
    # More than one left is a duplicate this engine made, which is worth saying:
    # picking one silently means the other drifts and nothing ever converges.
    if [[ "$count" -gt 1 ]]; then
        log_warn "$1: $count items with this name in the vault — editing the first, the rest will drift" >&2
    fi
    printf '%s' "$mine" | jq -r '.[0].id // empty'
}

# The listing already carries every item in full - notes, fields, folder - so
# the item can be compared without asking the server for it again.
_cached_item() {
    _mine "$1" | jq -c '.[0] // empty'
}

# _cached_field <item-name> <field-name>
_cached_field() {
    _cached_item "$1" | jq -r --arg f "$2" '(.fields // []) | map(select(.name == $f)) | .[0].value // empty' 2>/dev/null
}

# upsert_note <name> <notes> <folder-id> [pub-field-value] [scope] [owner]
# The folder is reassigned on every update: an item whose file changed scope has
# to leave the old folder, or the separation is only true for new items.
# The fields an item carries besides its notes. Shared by the writer and by
# `--status`, so what the status reports is exactly what the push would do.
_FIELDS_FILTER='
    def put($n; $v):
        if $v == "" then map(select(.name != $n))
        else map(select(.name != $n)) + [{"name":$n,"value":$v,"type":0}] end;
    .fields = ((.fields // []) | put("public"; $pub) | put("scope"; $scope) | put("owner"; $owner) | put("payload-hash"; $phash))'

# _comparable <item-json> — the part of an item a push would actually change
_comparable() { jq -S -c '{notes, folderId, fields: ((.fields // []) | sort_by(.name))}'; }

# _item_state <name> <notes> <fid> <pub> <scope> <owner> <phash>
# prints: new | changed | unchanged
_item_state() {
    local name=$1 notes=$2 fid=$3 pub=${4:-} scope=${5:-} owner=${6:-} phash=${7:-}
    local current desired
    current="$(_cached_item "$name")"
    if [[ -z "$current" ]]; then printf 'new'; return 0; fi
    desired="$(printf '%s' "$current" | jq \
        --arg notes "$notes" --arg pub "$pub" --arg fid "$fid" \
        --arg scope "$scope" --arg owner "$owner" --arg phash "$phash" \
        ".notes = \$notes | .folderId = \$fid | $_FIELDS_FILTER")"
    if [[ "$(printf '%s' "$current" | _comparable)" == "$(printf '%s' "$desired" | _comparable)" ]]; then
        printf 'unchanged'
    else
        printf 'changed'
    fi
}

upsert_note() {
    local name=$1 notes=$2 fid=$3 pub=${4:-} scope=${5:-} owner=${6:-} phash=${7:-}
    local id payload
    id="$(_item_id "$name")"

    # scope/owner are custom fields as well as folders, so they survive an export
    # and can be searched in the clients.
    local fields_filter="$_FIELDS_FILTER"

    if [[ -n "$id" ]]; then
        local current
        current="$(_cached_item "$name")"
        [[ -n "$current" ]] || current="$(_bw_read bw get item "$id")" || { log_error "could not read $name"; return 1; }
        payload="$(printf '%s' "$current" | jq \
            --arg notes "$notes" --arg pub "$pub" --arg fid "$fid" \
            --arg scope "$scope" --arg owner "$owner" --arg phash "$phash" \
            ".notes = \$notes | .folderId = \$fid | $fields_filter")"
        # Nothing to send when the vault already holds exactly this. Every write
        # is a round trip, so on an unchanged machine a push should cost nothing.
        if [[ "$(printf '%s' "$current" | _comparable)" == "$(printf '%s' "$payload" | _comparable)" ]]; then
            printf "  ${GREEN}=${NC} unchanged %s%s\n" "$name" "${scope:+  [$scope]}"
            return 0
        fi
        _bw_write "$payload" bw edit item "$id" || return 1
        log_success "updated  $name${scope:+  [$scope]}"
    else
        payload="$(bw get template item | jq \
            --arg name "$name" --arg notes "$notes" --arg fid "$fid" --arg pub "$pub" \
            --arg scope "$scope" --arg owner "$owner" --arg phash "$phash" \
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
    local name=$1 file=$2 fid=$3 scope=${4:-} phash=${5:-}
    local id fname old
    fname="$(basename "$file")"
    id="$(_item_id "$name")"
    # The hash is what the next run compares against, so it must not be written
    # until the bytes it describes are in the vault. Writing it here and then
    # failing the upload leaves the item claiming content it does not hold, and
    # every later push reads that claim and reports "unchanged" - the attachment
    # never goes up again, and the manifest points restores at the old bytes.
    # Clearing it first means a run that dies here re-uploads next time, which
    # is the safe direction to be wrong in.
    if [[ -z "$id" ]]; then
        upsert_note "$name" "Restored by 'install.sh secrets' from the attachment $fname." "$fid" "" "$scope" "" "" || return 1
        _load_items
        id="$(_item_id "$name")"
    else
        # Keep folder and scope current even when the attachment is all that changes.
        local notes
        notes="$(_bw_read bw get item "$id" | jq -r '.notes // ""')" || notes=""
        upsert_note "$name" "$notes" "$fid" "" "$scope" "" "" >/dev/null || return 1
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

    # What the vault now holds is recorded after every upload in the run, not
    # after each one. Attaching moves the item on the server and leaves the
    # local copy behind, and bw refuses to edit from a stale copy — so the
    # record needs a resync first, and a resync is the most expensive call this
    # script makes. One of them, not one per attachment.
    if [[ -n "$phash" ]]; then
        printf '%s%s%s%s%s%s%s\n' "$name" "$SEP" "$id" "$SEP" "$fid" "$SEP" "$scope$SEP$phash" >> "$PENDING"
    fi
}


# ==============================================================================
# What was collected
# ==============================================================================
# Grouped by whose secrets these are, because that is the question this script
# exists to answer. What each item holds - variable names, host counts, key
# comments - matters more than its mode, which is 600 for everything but a
# public key.

# _env_keys <file> — the variable names it sets, in file order, no duplicates.
# A file with forty of them is telling you it is a config file with a couple of
# secrets in it, and the first dozen names say that just as well.
ENV_KEYS_SHOWN="${SETTINGS_ENV_KEYS_SHOWN:-12}"
_env_keys() {
    local all n
    all="$(grep -ohE '^[[:space:]]*(export[[:space:]]+)?[A-Za-z_][A-Za-z0-9_]*=' "$1" 2>/dev/null \
        | sed -E 's/^[[:space:]]*(export[[:space:]]+)?//; s/=$//' | awk '!seen[$0]++')"
    n="$(printf '%s\n' "$all" | grep -c . || true)"
    if (( n > ENV_KEYS_SHOWN )); then
        printf '%s +%s more' "$(printf '%s\n' "$all" | head -"$ENV_KEYS_SHOWN" | paste -sd' ' -)" "$(( n - ENV_KEYS_SHOWN ))"
    else
        printf '%s' "$(printf '%s\n' "$all" | paste -sd' ' -)"
    fi
}

# _conf_keys <file> — the left-hand sides of key=value lines, whatever the
# syntax around them. npmrc, ini, toml and plain env files all answer to this.
_conf_keys() {
    local all n
    all="$(grep -E '^[^#[:space:]][^=]*=' "$1" 2>/dev/null \
        | sed -E 's/[[:space:]]*=.*//; s/^[[:space:]]*(export[[:space:]]+)?//' \
        | awk 'length($0) > 0 && length($0) < 60 && !seen[$0]++')"
    n="$(printf '%s\n' "$all" | grep -c . || true)"
    (( n == 0 )) && return 0
    if (( n > ENV_KEYS_SHOWN )); then
        printf '%s +%s more' "$(printf '%s\n' "$all" | head -"$ENV_KEYS_SHOWN" | paste -sd' ' -)" "$(( n - ENV_KEYS_SHOWN ))"
    else
        printf '%s' "$(printf '%s\n' "$all" | paste -sd' ' -)"
    fi
}

# _spans_of <file> — what a "mixed" file is mixed from, as it says itself:
#   # spans: personal, work
_spans_of() {
    LC_ALL=C sed -nE 's/^[[:space:]]*#[[:space:]]*spans:[[:space:]]*(.+)$/\1/p' "$1" 2>/dev/null | head -1
}

# An app blob holds whatever its app holds, and the app is not going to say.
SPANS_AAS="${SETTINGS_SPANS_AAS:-personal, work}"
SPANS_OTPEEK="${SETTINGS_SPANS_OTPEEK:-personal, work}"
SPANS_BARSHELF="${SETTINGS_SPANS_BARSHELF:-}"

_app_spans() {
    case "$1" in
        aas) printf '%s' "$SPANS_AAS" ;;
        otpeek) printf '%s' "$SPANS_OTPEEK" ;;
        barshelf) printf '%s' "$SPANS_BARSHELF" ;;
    esac
}

# _detail <item> <src> <mode> <pubpath> — the one line that says what is inside
_detail() {
    local item=$1 src=$2 mode=$3 pub=$4 d=""
    case "$item" in
        env:*)
            d="$(_env_keys "$src")"
            ;;
        file:*)
            # A tracked file is whatever the user tracked: an rc file, a token
            # store, an ini. If it looks like key = value, name the keys.
            d="$(_conf_keys "$src")"
            [[ -n "$d" ]] || d="$(grep -c . "$src" 2>/dev/null || echo 0) lines"
            ;;
        ssh:authorized_keys)
            local n names
            n="$(grep -cE '^[a-z]' "$src" 2>/dev/null || echo 0)"
            names="$(awk '/^[a-z]/ {c=""; for (i=3; i<=NF; i++) c = c (i>3 ? " " : "") $i; print (c == "" ? "(unnamed)" : c)}' "$src" 2>/dev/null | paste -sd' ' -)"
            d="${n} keys: ${names}"
            ;;
        ssh:config-*)
            d="$(grep -ciE '^[[:space:]]*Host[[:space:]]' "$src" 2>/dev/null || echo 0) hosts"
            ;;
        ssh:*)
            [[ -n "$pub" ]] && d="$(ssh-keygen -lf "$pub" 2>/dev/null | awk '{print $2, $4}')"
            [[ -n "$d" ]] || d="private key"
            ;;
    esac
    [[ -n "$pub" && "$item" != ssh:* ]] && d="$d  +public"
    [[ "$mode" != "600" ]] && d="$d  (mode $mode)"
    printf '%s' "$d"
}

# When $STATES holds "item<TAB>state" lines, each row is marked with what a
# push would do to it.
_state_of() { awk -F'\t' -v i="$1" '$1 == i {print $2; exit}' "$STATES" 2>/dev/null; }

_marker() {
    case "$1" in
        new)       printf '%b+%b ' "$GREEN" "$NC" ;;
        changed)   printf '%b~%b ' "$YELLOW" "$NC" ;;
        unchanged) printf '%b=%b ' "$GRAY" "$NC" ;;
        unknown)   printf '%b?%b ' "$YELLOW" "$NC" ;;
        *)         printf '' ;;
    esac
}

print_collected() {   # <section title>
    print_section "${1:-Collected}"
    local rows="$TMPDIR_ROWS"
    : > "$rows"

    local src item dest mode pub scope owner platforms detail spans group
    while IFS="$SEP" read -r src item dest mode pub scope owner platforms; do
        detail="$(_detail "$item" "$src" "$mode" "$pub")"
        if [[ "$scope" == "mixed" ]]; then
            spans="$(_spans_of "$src")"
            [[ -n "$spans" ]] && detail="${detail:+$detail  }— $spans"
        fi
        [[ -n "$platforms" ]] && detail="$detail  [$platforms]"
        group="$scope"
        [[ -n "$owner" ]] && group="$scope · $owner"
        printf '%s\t%s\t%s\n' "$group" "$item" "$detail" >> "$rows"
    done < "$COLLECTED"

    while IFS="$SEP" read -r src item dest mode pub scope owner platforms; do
        detail="binary, $(wc -c < "$src" | tr -d ' ') bytes → $dest"
        [[ -n "$platforms" ]] && detail="$detail  [$platforms]"
        group="$scope"
        [[ -n "$owner" ]] && group="$scope · $owner"
        printf '%s\t%s\t%s\n' "$group" "$item" "$detail" >> "$rows"
    done < "$BINARIES"

    local fname exec_cmd kind platforms
    while IFS="$SEP" read -r item fname exec_cmd kind scope platforms; do
        detail="$fname"
        if [[ "$scope" == "mixed" ]]; then
            spans="$(_app_spans "$kind")"
            [[ -n "$spans" ]] && detail="$detail  — $spans"
        fi
        # Where it restores, when that is not everywhere. An entry nobody can
        # apply on the machine in front of them should say so before the push,
        # not only in the manifest.
        [[ -n "$platforms" ]] && detail="$detail  [$platforms]"
        printf '%s\t%s\t%s\n' "$scope" "$item" "$detail" >> "$rows"
    done < "$APPS"

    # personal first, mixed last: the clear cases before the ones that need a
    # second thought.
    local order="personal shared work mixed" prefix g n last
    local groups
    groups="$(cut -f1 "$rows" | sort -u)"
    for prefix in $order; do
        local matching
        matching="$(printf '%s\n' "$groups" | awk -v p="$prefix" 'index($0, p) == 1' || true)"
        [[ -n "$matching" ]] || continue
        while IFS= read -r g; do
            [[ -n "$g" ]] || continue
            n="$(awk -F'\t' -v g="$g" '$1 == g' "$rows" | wc -l | tr -d ' ')"
            printf '\n  %b%s%b  (%s)\n' "$BOLD" "$g" "$NC" "$n"
            last="$(awk -F'\t' -v g="$g" '$1 == g {print $2}' "$rows" | tail -1)"
            awk -F'\t' -v g="$g" '$1 == g {print $2 "\t" $3}' "$rows" | while IFS=$'\t' read -r item detail; do
                local branch cont
                if [[ "$item" == "$last" ]]; then branch='  └── '; cont='      '; else branch='  ├── '; cont='  │   '; fi
                # Wrap the detail under itself rather than past the edge of the
                # terminal, where nobody reads it.
                local avail first=true wrapped
                avail=$(( ${COLUMNS:-$(tput cols 2>/dev/null || echo 100)} - 6 - 27 ))
                (( avail < 30 )) && avail=30
                wrapped="$(printf '%s' "$detail" | fold -s -w "$avail")"
                while IFS= read -r line; do
                    if [[ "$first" == "true" ]]; then
                        printf '%s%s%-26s %s\n' "$branch" "$(_marker "$(_state_of "$item")")" "$item" "$line"
                        first=false
                    else
                        printf '%s%s%-26s %s\n' "$cont" "$([[ -s "${STATES:-}" ]] && printf '  ')" "" "$line"
                    fi
                done <<< "$wrapped"
            done
        done <<< "$matching"
        groups="$(printf '%s\n' "$groups" | awk -v p="$prefix" 'index($0, p) != 1' || true)"
    done

    echo
    if [[ -s "${STATES:-}" ]]; then
        local n_new n_changed n_unchanged n_unknown
        n_new="$(awk -F'\t' '$2 == "new"' "$STATES" | wc -l | tr -d ' ')"
        n_changed="$(awk -F'\t' '$2 == "changed"' "$STATES" | wc -l | tr -d ' ')"
        n_unchanged="$(awk -F'\t' '$2 == "unchanged"' "$STATES" | wc -l | tr -d ' ')"
        n_unknown="$(awk -F'\t' '$2 == "unknown"' "$STATES" | wc -l | tr -d ' ')"
        printf '  %b+%b %s new   %b~%b %s changed   %b=%b %s unchanged' \
            "$GREEN" "$NC" "$n_new" "$YELLOW" "$NC" "$n_changed" "$GRAY" "$NC" "$n_unchanged"
        [[ "$n_unknown" != "0" ]] && printf '   %b?%b %s built on push' "$YELLOW" "$NC" "$n_unknown"
        printf '\n'
        echo
    fi
    log_info "$(cat "$COLLECTED" "$BINARIES" "$APPS" | wc -l | tr -d ' ') items, folder '$VAULT_FOLDER', manifest '$VAULT_MANIFEST'"
}

# ==============================================================================
# Main
# ==============================================================================

collect
collect_apps

if [[ ! -s "$COLLECTED" && ! -s "$BINARIES" && ! -s "$APPS" ]]; then
    log_error "Nothing collected. Are ~/.envs and ~/.ssh populated?"
    exit 1
fi

print_collected
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
PENDING="$(mktemp)"
# App payloads are credentials too: stage them where only this user can read.
PAYLOADS="$(umask 077; mktemp -d "${TMPDIR:-/tmp}/settings-push.XXXXXX")"

print_section "Pushing"
while IFS="$SEP" read -r src item dest mode pub scope owner platforms; do
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

    if [[ "$item" == "ssh:authorized_keys" ]]; then
        jq -n --arg item "$item" --arg exec "$AUTHORIZED_KEYS_MERGE" --arg scope "$scope" \
            '{item: $item, source: "notes", exec: $exec, scope: $scope}' >> "$ENTRIES"
    else
        jq -n --arg item "$item" --arg dest "$dest" --arg mode "$mode" --arg scope "$scope" \
            --argjson plat "$(_platform_json "$platforms")" \
            '{item: $item, source: "notes", dest: $dest, mode: $mode, scope: $scope}
             | if ($plat | length) > 0 then .platform = $plat else . end' >> "$ENTRIES"
    fi

    if [[ -n "$pubval" ]]; then
        jq -n --arg item "$item" --arg dest "$dest.pub" --arg scope "$scope" \
            '{item: $item, source: "field:public", dest: $dest, mode: "644", scope: $scope}' >> "$ENTRIES"
    fi
done < "$COLLECTED"

# Tracked paths that are not text: the file itself is the attachment, and the
# restore writes it back byte for byte.
while IFS="$SEP" read -r src item dest mode pub scope owner platforms; do
    fid="$(_folder_id "$(_scope_folder "$scope")")"
    fp="$(_sha256 < "$src")"
    fname="$(basename "$src")"
    if [[ "$fp" != "$(_cached_field "$item" "payload-hash")" ]]; then
        if ! upsert_attachment "$item" "$src" "$fid" "$scope" "$fp"; then
            printf '%s\n' "  $item" >> "$FAILED"
            continue
        fi
    else
        printf "  ${GREEN}=${NC} unchanged %s/%s\n" "$item" "$fname"
    fi
    jq -n --arg item "$item" --arg src "attachment:$fname" --arg dest "$dest" \
          --arg mode "$mode" --arg scope "$scope" \
          --argjson plat "$(_platform_json "$platforms")" \
        '{item: $item, source: $src, dest: $dest, mode: $mode, scope: $scope}
         | if ($plat | length) > 0 then .platform = $plat else . end' >> "$ENTRIES"
done < "$BINARIES"

while IFS="$SEP" read -r item fname exec_cmd kind scope platforms; do
    plat_json="$(_platform_json "$platforms")"
    manifest_entry() {
        jq -n --arg item "$item" --arg src "attachment:$fname" --arg exec "$exec_cmd" --arg scope "$scope" \
            --argjson plat "$plat_json" \
            '{item: $item, source: $src, exec: $exec, scope: $scope}
             | if ($plat | length) > 0 then .platform = $plat else . end' >> "$ENTRIES"
    }

    fid="$(_folder_id "$(_scope_folder "$scope")")"
    known="$(_cached_field "$item" "payload-hash")"

    # Cheap check first: if the files behind the payload are untouched there is
    # nothing to build, nothing to upload, and no keychain prompt.
    fp="$(app_fingerprint "$kind")"
    if [[ -n "$fp" && "$fp" == "$known" ]]; then
        printf "  ${GREEN}=${NC} unchanged %s/%s\n" "$item" "$fname"
        manifest_entry
        continue
    fi

    payload="$PAYLOADS/$fname"
    if ! (umask 077; make_app_payload "$kind" "$payload"); then
        log_warn "skipped  $item (could not produce $fname)"
        continue
    fi
    [[ -n "$fp" ]] || fp="$(_sha256 < "$payload")"

    if [[ "$fp" == "$known" ]]; then
        printf "  ${GREEN}=${NC} unchanged %s/%s\n" "$item" "$fname"
        rm -f "$payload"
        manifest_entry
        continue
    fi

    if ! upsert_attachment "$item" "$payload" "$fid" "$scope" "$fp"; then
        printf '%s\n' "  $item" >> "$FAILED"
        rm -f "$payload"
        continue
    fi
    rm -f "$payload"
    manifest_entry
done < "$APPS"

# Record the hashes of everything attached this run. Until this happens the
# vault holds the payloads but cannot say what is in them, and the next push
# uploads all of them again — which is what it did, every time, for as long as
# this edit was attempted from a copy that attaching had just made stale.
if [[ -s "$PENDING" ]]; then
    # Two caches, and both are behind. `bw sync` refreshes the client's own
    # store, which is what stops the server rejecting the edit — but the edit
    # is built from ITEMS_CACHE, read once at the start of the run, and that
    # copy still carries the revision these items had before they were attached
    # to. Syncing without reloading was the whole of the last attempt at this,
    # and it changed nothing.
    bw sync >/dev/null 2>&1 || log_warn "could not resync before recording what was attached"
    _load_items
    while IFS="$SEP" read -r pname pid pfid pscope pphash; do
        [[ -n "$pname" ]] || continue
        pnotes="$(_cached_item "$pname" | jq -r '.notes // ""')"
        [[ -n "$pnotes" ]] || pnotes="$(_bw_read bw get item "$pid" | jq -r '.notes // ""')" || pnotes=""
        if ! upsert_note "$pname" "$pnotes" "$pfid" "" "$pscope" "" "$pphash" >/dev/null; then
            log_warn "$pname: the attachment is up but its payload-hash was not written; the next push re-uploads it"
        fi
    done < "$PENDING"
fi

# GPG is not collected from disk - exporting a secret key needs the passphrase,
# so those two items are maintained by hand. Preserve them if already present,
# but not the exec entries this run just rewrote, or every push would add a copy.
print_section "Manifest"
PUSHED_ITEMS="$(jq -s '[.[].item]' < "$ENTRIES")"
# An item this run failed to write is not "not sent by this machine" - it is
# "sent, and did not land". Leaving it out of KEEP puts it in the stale report
# with a ready-made `bw delete item`, which is an offer to destroy the vault's
# only copy of a secret that is still on this disk and still being pushed.
KEEP="$PUSHED_ITEMS"
if [[ -s "$FAILED" ]]; then
    KEEP="$(jq -n --argjson pushed "$PUSHED_ITEMS" \
        --argjson failed "$(sed 's/^[[:space:]]*//' "$FAILED" | jq -Rs 'split("\n") | map(select(length > 0))')" \
        '$pushed + $failed')"
fi
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

_load_items
print_stale

if [[ -s "$FAILED" ]]; then
    echo
    log_error "These items could not be written and are NOT in the manifest:"
    cat "$FAILED"
    log_info "Run the push again — it updates in place, so nothing is duplicated."
    exit 1
fi

log_info "Verify with: ./install.sh -n secrets"
