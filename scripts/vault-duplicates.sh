#!/bin/bash
# vault-duplicates.sh - show items the vault holds more than once.
#
# Reads. Never writes, and never deletes: removal is a person's decision taken
# with the vault's own client, because an item this machine does not recognise
# may be another machine's only copy.
#
#   export BW_SESSION=$(bw unlock --raw)
#   scripts/vault-duplicates.sh
#
# Two engines write to one vault under the same item names — the shell engine
# into bootstrap/<scope>, kitbag into its own folder with a `kitbag` field.
# That pairing is expected and is reported separately. A name appearing twice
# *within* one engine's space is not: whichever copy a run picks, the other
# drifts, and nothing ever converges.
#
# Nothing here prints a value. Names, folders, revision dates and ids only.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/lib/core.sh"

VAULT_FOLDER="${SETTINGS_VAULT_FOLDER:-bootstrap}"

[[ -n "${BW_SESSION:-}" ]] || {
    log_error "BW_SESSION is not set — run: export BW_SESSION=\$(bw unlock --raw)"
    exit 1
}

command_exists bw || { log_error "the Bitwarden CLI is not installed"; exit 1; }
command_exists jq || { log_error "jq is not installed"; exit 1; }

print_section "Vault duplicates"

# One sync, one listing: bw reads its own copy of the vault unless told to go
# and get it, and a stale copy would report duplicates that are not there.
log_info "Syncing, so this is about the vault and not about a cache"
bw sync >/dev/null 2>&1 || log_warn "could not sync — reporting on the local copy"

items="$(bw list items)"
folders="$(bw list folders)"

report="$(printf '%s' "$items" | jq -r --argjson f "$folders" --arg root "$VAULT_FOLDER" '
    def folder_of: . as $id | ($f[] | select(.id == $id) | .name) // "(none)";
    def is_kitbag: [(.fields // [])[] | select(.name == "kitbag")] | length > 0;

    [ .[]
      | select(.name | test("^(env|ssh|file|app|gpg):"))
      | { name, id, rev: (.revisionDate // ""),
          folder: ((.folderId // "") | folder_of),
          engine: (if is_kitbag then "kitbag" else "shell" end) }
    ]
    | group_by(.name + "\u001f" + .engine)
    | map(select(length > 1))
    | sort_by(.[0].name)
    | .[]
    | "\(.[0].engine)\t\(.[0].name)\t\(length)\t" +
      ([.[] | "\(.rev)|\(.folder)|\(.id)"] | sort | reverse | join(" "))
')"

if [[ -z "$report" ]]; then
    log_success "No name is held twice by either engine"
else
    printf '\n'
    while IFS=$'\t' read -r engine name count copies; do
        printf '  %s  %s  — %s copies in the %s engine\n' "${RED}✗${NC}" "$name" "$count" "$engine"
        first=true
        for copy in $copies; do
            IFS='|' read -r rev folder id <<< "$copy"
            if [[ "$first" == "true" ]]; then
                printf '      keep    %s  %s  %s\n' "${rev%%T*}" "$folder" "$id"
                first=false
            else
                printf '      %sdelete%s  %s  %s  %s\n' "$YELLOW" "$NC" "${rev%%T*}" "$folder" "$id"
            fi
        done
        printf '\n'
    done <<< "$report"
    log_warn "The newest of each is marked keep. Check before removing anything:"
    log_info "  bw get item <id> | jq '{name, folderId, revisionDate}'"
    log_info "  bw delete item <id>"
fi

# The pairing across engines, which is not a duplicate but is worth seeing once.
paired="$(printf '%s' "$items" | jq -r '
    def is_kitbag: [(.fields // [])[] | select(.name == "kitbag")] | length > 0;
    [ .[] | select(.name | test("^(env|ssh|file|app|gpg):"))
          | { name, engine: (if is_kitbag then "kitbag" else "shell" end) } ]
    | group_by(.name)
    | map(select((map(.engine) | unique | length) > 1))
    | length
')"
printf '\n'
log_info "$paired name(s) held by both engines — expected while machines move across"
