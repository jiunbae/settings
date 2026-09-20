#!/bin/bash
# kitbag-config.sh - write kitbag's machine file from what this repository
# already knows about this machine.
#
#   scripts/kitbag-config.sh            show what it would write
#   scripts/kitbag-config.sh --write    write ~/.config/kitbag/machine.toml
#
# Nothing here reads a secret. It reads the *shape* of this machine: which
# scopes the bash engine was told to restore, which directories hold tracked
# files, which extra paths were listed, and which applications hold state that
# only they can hand over. The scopes themselves already live in the files, as
# `# scope:` markers - kitbag reads the same markers, which is why this is a
# translation rather than a migration.
#
# The file is written for review, never applied: the next step is `kitbag
# status`, which reads and reports and changes nothing.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/lib/core.sh"

CONFIG="${SETTINGS_KITBAG_CONFIG:-$HOME/.config/kitbag/machine.toml}"
SCOPE_FILE="${SETTINGS_SECRETS_SCOPE_FILE:-$HOME/.config/settings/secrets.scope}"
TRACKED_PATHS="${SETTINGS_TRACKED_PATHS:-$HOME/.config/settings/secrets-paths}"

WRITE=false
[[ "${1:-}" == "--write" ]] && WRITE=true

# ==============================================================================
# What this machine takes
# ==============================================================================
# The scopes this machine can be seen to hold, read off the markers already on
# disk. `mixed` is left out because anyone may take it, and `local` because it
# never travels - neither says anything about what this machine is entitled to.
scopes_on_disk() {
    {
        grep -h -m1 '^# scope:' "$HOME"/.envs/*.env "$HOME"/.ssh/config.d/*.conf 2>/dev/null
        # The extra-paths file names a scope in its second column.
        [[ -f "$TRACKED_PATHS" ]] && awk '!/^#/ && NF > 1 { print "# scope: " $2 }' "$TRACKED_PATHS"
    } | sed 's/^# scope:[[:space:]]*//' | tr ',' '\n' \
      | sed 's/[[:space:]]//g' \
      | grep -vxE 'local|mixed' | grep -v '^$' | sort -u
}

# Resolving sets globals, so it is called once at the top level and never from
# inside `$( )`: a variable assigned in a command substitution dies with the
# subshell, which is the bug that printed an empty skip list for a week.
SCOPE_WORD=""
SCOPE_INFERRED=false

resolve_scope() {
    SCOPE_WORD="${SETTINGS_SECRETS_SCOPE:-}"
    [[ -z "$SCOPE_WORD" && -f "$SCOPE_FILE" ]] &&
        SCOPE_WORD="$(tr -d '[:space:]' < "$SCOPE_FILE")"
    [[ -n "$SCOPE_WORD" ]] && return 0

    # No answer anywhere. The bash engine's default is `personal`, which is
    # right for a machine holding nothing yet and wrong for one already full:
    # this list decides what `push` sends, so a machine holding work files and
    # told `personal` leaves every one of them out of the store, and reports
    # only that it sent what it sent. So ask the disk before falling back.
    SCOPE_WORD="$(scopes_on_disk | paste -sd, -)"
    if [[ -n "$SCOPE_WORD" ]]; then
        SCOPE_INFERRED=true
    else
        SCOPE_WORD="personal"
    fi
}

# Formatting is pure, so it is safe to call from inside the heredoc.
scopes() {
    local scope="$SCOPE_WORD"
    case "$scope" in
        all) printf '"personal", "work", "shared"' ;;
        # printf with a newline: `read` drops a final line that has none, so
        # a single-scope machine would come out with no scopes at all.
        *)   printf '%s\n' "$scope" | tr ',' '\n' | while read -r s; do
                 [[ -n "$s" ]] && printf '"%s", ' "$s"
             done | sed 's/, $//' ;;
    esac
}

# ==============================================================================
# Generation
# ==============================================================================
generate() {
    cat <<EOF
# Written by scripts/kitbag-config.sh from what this machine already holds.
#
# Scopes are not repeated here: every file carries its own '# scope:' marker,
# which is what kitbag reads. A pattern that matches a file with no marker is
# reported rather than guessed at.

scopes = [$(scopes)]
EOF

    # Directories of marked files. The pattern goes in, never the list of what
    # is in it - the same rule this repository follows everywhere else.
    if [[ -d "$HOME/.envs" ]]; then
        cat <<'EOF'

[[track]]
path = "~/.envs/*.env"
EOF
    fi

    local f base
    for f in "$HOME"/.ssh/id_*; do
        [[ -f "$f" ]] || continue
        case "$f" in *.pub|*.scope) continue ;; esac
        cat <<'EOF'

[[track]]
path = "~/.ssh/id_ed25519"
scope = "personal"
EOF
        break
    done

    if [[ -f "$HOME/.ssh/authorized_keys" ]]; then
        cat <<'EOF'

[[track]]
path = "~/.ssh/authorized_keys"
EOF
    fi

    # ssh config fragments this repository does not track in git.
    local tracked
    tracked="$(cd "$ROOT" && git ls-files .ssh/config.d 2>/dev/null | while read -r t; do basename "$t"; done || true)"
    for f in "$HOME"/.ssh/config.d/*.conf; do
        [[ -f "$f" ]] || continue
        base="$(basename "$f")"
        printf '%s\n' "$tracked" | grep -qxF "$base" && continue
        printf '\n[[track]]\npath = "~/.ssh/config.d/%s"\n' "$base"
    done

    # Extra paths, with the scope column the bash engine used. A file that
    # carries its own marker still overrides this.
    if [[ -f "$TRACKED_PATHS" ]]; then
        local path scope owner name
        while read -r path scope owner name; do
            case "${path:-}" in ''|\#*) continue ;; esac
            printf '\n[[track]]\npath = "%s"\n' "$path"
            [[ -n "${scope:-}" ]] && printf 'scope = "%s"\n' "$scope"
            [[ -n "${owner:-}" ]] && printf 'owner = "%s"\n' "$owner"
            [[ -n "${name:-}" ]] && printf 'name = "%s"\n' "$name"
        done < "$TRACKED_PATHS"
    fi

    # State only an application can hand over. Each is listed only if the
    # command that owns it is on this machine: a track whose exporter is
    # missing would be reported as broken on every run.
    if command_exists aas; then
        cat <<'EOF'

# The bundle carries credentials that rotate on their own, so two exports a
# moment apart differ. Nothing can make it stable, so it is marked as what it
# is: kitbag sends it and reports that it cannot tell whether it changed.
[[track]]
name = "app:aas"
scope = "mixed"
spans = ["personal", "work"]
volatile = true
command = { export = "aas export --all", restore = "aas import -" }
EOF
    fi

    if [[ -f "$HOME/Library/Group Containers/group.com.otpeek.app/vault.otpvault" ]]; then
        cat <<'EOF'

# The OTP vault stays encrypted with its own master password inside this.
#
# `gzip -n` rather than `tar -czf`: gzip stamps the current time into its
# header, so the same unchanged files produce different bytes every second and
# the item is reported as changed on every run, forever.
[[track]]
name = "app:otpeek"
scope = "mixed"
spans = ["personal", "work"]
command = { export = "tar -cf - -C \"$HOME\" 'Library/Application Support/otpeek/config.toml' 'Library/Group Containers/group.com.otpeek.app/vault.otpvault' | gzip -n", restore = "tar -xzf - -C \"$HOME\"" }
EOF
    fi

    if [[ -d "$HOME/Library/Application Support/BarShelf" ]]; then
        cat <<'EOF'

[[track]]
name = "app:barshelf"
scope = "personal"
command = { export = "tar -cf - -C \"$HOME/Library/Application Support\" --exclude 'BarShelf/runtime' --exclude 'BarShelf/cache' BarShelf | gzip -n", restore = "tar -xzf - -C \"$HOME/Library/Application Support\"" }
EOF
    fi
}

# ==============================================================================
# Main
# ==============================================================================
print_section "kitbag config"

resolve_scope
OUT="$(generate)"
COUNT="$(printf '%s\n' "$OUT" | grep -c '^\[\[track\]\]' || true)"

# Say when the answer was read off the disk rather than declared. This list is
# what `push` sends and what `restore` takes, so a machine that disagrees with
# it should disagree now, not after a restore comes back short.
if [[ "$SCOPE_INFERRED" == "true" ]]; then
    log_warn "No scope declared for this machine, so it was read off the files here: $SCOPE_WORD"
    log_info "  Declare it instead: echo <scope> > $SCOPE_FILE"
fi

if [[ "$WRITE" != "true" ]]; then
    printf '%s\n' "$OUT"
    echo
    log_info "$COUNT track entries, for $CONFIG"
    log_warn "Nothing written. Re-run with --write."
    exit 0
fi

if [[ -f "$CONFIG" ]]; then
    backup="$CONFIG.backup.$(date +%Y%m%d%H%M%S)"
    cp "$CONFIG" "$backup"
    log_info "Kept the existing config at $backup"
fi

mkdir -p "$(dirname "$CONFIG")"
printf '%s\n' "$OUT" > "$CONFIG"
log_success "Wrote $CONFIG ($COUNT track entries)"
echo
log_info "Next, and it only reads:"
log_info "  kitbag status      what it makes of this machine"
log_info "  kitbag doctor      whether anything is unmarked or loose"
