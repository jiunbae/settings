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
# ~/.config/settings/secrets.skip is read too: the items this machine keeps
# for itself, one name per line. kitbag reads its own config, so a skip list
# that is not written into it does nothing when kitbag is run directly.
#
# ~/.config/settings/secrets-paths is read for the extra paths, one per line:
#
#   <path>  <scope>  [owner]  [item-name]  [platforms]
#   ~/.config/gh/hosts.yml               personal  -     -   macos,linux
#   ~/.aws/config                        work  rtzr
#   ~/Library/Keychains/x.keychain-db    work  rtzr  file:x-keychain  macos
#   ~/.config/gh/hosts.yml               personal  -  -  linux,macos
#
# The columns are positional, so "-" is how one is left empty when a later one
# is wanted.
#
# The fifth column is comma-separated and says where the path exists at all.
# Without it every machine takes the item, and a keychain written onto a Linux
# server looks like a restore that worked.
#
# The file is written for review, never applied: the next step is `kitbag
# status`, which reads and reports and changes nothing.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/lib/core.sh"

CONFIG="${SETTINGS_KITBAG_CONFIG:-$HOME/.config/kitbag/machine.toml}"
SCOPE_FILE="${SETTINGS_SECRETS_SCOPE_FILE:-$HOME/.config/settings/secrets.scope}"
SKIP_FILE="${SETTINGS_SECRETS_SKIP_FILE:-$HOME/.config/settings/secrets.skip}"
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
        #
        # An `if` rather than `[[ ... ]] &&`: this is the last command in the
        # group, so its status is the group's, `pipefail` carries that out of
        # the pipeline, and `set -e` ends the run. On a machine with no such
        # file the generator printed its header and stopped, saying nothing.
        if [[ -f "$TRACKED_PATHS" ]]; then
            awk '!/^#/ && NF > 1 { print "# scope: " $2 }' "$TRACKED_PATHS"
        fi
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

    # What this machine keeps for itself. It lives in the file all three
    # engines read, and kitbag reads its own config — so unless it is written
    # here, running `kitbag` directly behaves as though nothing were declared.
    # That is how a machine got asked whether to overwrite its own SSH key.
    if [[ -f "$SKIP_FILE" ]]; then
        local names
        names="$(grep -vE '^[[:space:]]*(#|$)' "$SKIP_FILE" 2>/dev/null |
                 sed 's/[[:space:]]//g' | grep -v '^$' |
                 sed 's/^/"/; s/$/", /' | tr -d '\n' | sed 's/, $//')"
        [[ -n "$names" ]] && printf '\nskip = [%s]\n' "$names"
    fi

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

# This machine's own key, named after this machine.
#
# Four machines derive the same item name from this path and hold four
# different keys. Keeping them apart by refusing to exchange it left three of
# them backed up nowhere, and a key that exists in one place is gone with the
# machine it is on. `per_machine` names it `ssh:id_ed25519@<host>` instead: each
# machine keeps its own, backs its own up, and takes nobody else's.
[[track]]
path = "~/.ssh/id_ed25519"
scope = "personal"
per_machine = true
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
    # The fragments live in chezmoi's source tree now, named for chezmoi:
    # private_00-defaults.conf is placed as 00-defaults.conf. The prefix comes
    # off before comparing — asking git for the old path returned nothing, and
    # "nothing is tracked" sends every fragment to the vault as a second copy.
    tracked="$(cd "$ROOT" && git ls-files home/private_dot_ssh/private_config.d 2>/dev/null | while read -r t; do t="$(basename "$t")"; echo "${t#private_}"; done || true)"
    for f in "$HOME"/.ssh/config.d/*.conf; do
        [[ -f "$f" ]] || continue
        base="$(basename "$f")"
        printf '%s\n' "$tracked" | grep -qxF "$base" && continue
        printf '\n[[track]]\npath = "~/.ssh/config.d/%s"\n' "$base"
    done

    # Extra paths, with the scope column the bash engine used. A file that
    # carries its own marker still overrides this.
    if [[ -f "$TRACKED_PATHS" ]]; then
        local path scope owner name platform
        while read -r path scope owner name platform; do
            case "${path:-}" in ''|\#*) continue ;; esac
            # `-` is a column that does not apply. The columns are
            # positional, so without it a platform written after a bare scope
            # becomes the owner, and nothing would say so. Every column takes
            # it, including scope: a file carrying its own `# scope:` marker
            # has no need to repeat it here.
            [[ "${scope:-}" == "-" ]] && scope=""
            [[ "${owner:-}" == "-" ]] && owner=""
            [[ "${name:-}" == "-" ]] && name=""
            [[ "${platform:-}" == "-" ]] && platform=""
            printf '\n[[track]]\npath = "%s"\n' "$path"
            [[ -n "${scope:-}" ]] && printf 'scope = "%s"\n' "$scope"
            [[ -n "${owner:-}" ]] && printf 'owner = "%s"\n' "$owner"
            [[ -n "${name:-}" ]] && printf 'name = "%s"\n' "$name"
            # A fifth column names the platforms, for a path that only exists
            # on some of them. A keychain is the reason this column exists.
            [[ -n "${platform:-}" ]] &&
                printf 'platform = ["%s"]\n' "$(printf '%s' "$platform" | sed 's/,/", "/g')"
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
platform = ["macos"]
volatile = true
command = { export = "aas export --all", restore = "aas import -" }
EOF
    fi

    if [[ -f "$HOME/Library/Group Containers/group.com.otpeek.app/vault.otpvault" ]]; then
        cat <<'EOF'

# The OTP vault stays encrypted with its own master password inside this.
#
# Only the vault travels. `config.toml` holds one line — `active_vault`, an
# absolute path — and the restore has to rewrite it for the restoring user
# anyway, so shipping it carries no information and one guaranteed difference,
# since these machines do not all run under the same user name.
# The restore writes that line itself, and edits in place if the file is
# already there, so a machine that keeps other settings there keeps them.
#
# Everything else here is about producing the same bytes on four machines that
# hold the same vault. Each of these was a real difference, found by comparing
# the archives machine to machine:
#
#   --format ustar     bsdtar writes pax by default, and pax headers carry
#                      atime and ctime — which differ on every machine that
#                      has so much as read the file. This is the big one.
#   --uid/--gid/       the archive records who owns the file, and these
#   --uname/--gname    machines do not all run under one user name.
#   COPYFILE_DISABLE=1 drops the `._name` companions tar writes for extended
#   --no-mac-metadata  attributes, which differ between identical copies.
#   gzip -n            gzip stamps the current time into its own header, so
#                      the same files differ every second, forever.
#
# With all five, four machines now produce one identical archive, checked.
#
# `set -o pipefail` because a pipeline reports the last command's status: a tar
# that failed halfway would be gzipped successfully and stored as a backup of
# part of the directory, with nothing saying so.
[[track]]
name = "app:otpeek"
scope = "mixed"
spans = ["personal", "work"]
platform = ["macos"]
command = { export = "set -o pipefail; COPYFILE_DISABLE=1 tar --format ustar --no-mac-metadata --uid 0 --gid 0 --uname '' --gname '' -cf - -C \"$HOME\" 'Library/Group Containers/group.com.otpeek.app/vault.otpvault' | gzip -n", restore = 'tar -xzf - -C "$HOME" && c="$HOME/Library/Application Support/otpeek/config.toml" && v="$HOME/Library/Group Containers/group.com.otpeek.app/vault.otpvault" && mkdir -p "$HOME/Library/Application Support/otpeek" && if grep -q "^active_vault = " "$c" 2>/dev/null; then sed -i "" "s#^active_vault = .*#active_vault = \"$v\"#" "$c"; else printf "active_vault = \"%s\"\n" "$v" >> "$c"; fi' }
EOF
    fi

    if [[ -d "$HOME/Library/Application Support/BarShelf" ]]; then
        cat <<'EOF'

# Marked volatile, after trying not to. Every normalisation the OTPeek track
# above uses is applied here too, and four machines still produce four
# archives: the app rewrites its files while it runs — the same bytes, a new
# mtime — and tar records mtimes. macOS tar is bsdtar and has no `--mtime`,
# and there is no GNU tar on any of these machines, so this one cannot be made
# deterministic. `volatile` says what is true: comparing it answers nothing.
#
# Two files are left out because the app rewrites them every time it runs:
# launch-receipt.json says when it last started and refresh-stats.json counts
# what it has fetched. Neither is configuration, and with them in, four
# machines holding identical widgets still conflict forever — whoever opened
# the app last wins. Same shape as the gzip timestamp, one layer further in.
#
# Quit the app before writing over its data, or it writes its own state back
# on the way out and the restore is quietly undone. Started again afterwards,
# but only if it is installed here.
[[track]]
name = "app:barshelf"
scope = "personal"
platform = ["macos"]
volatile = true
command = { export = "set -o pipefail; COPYFILE_DISABLE=1 tar --format ustar --no-mac-metadata --uid 0 --gid 0 --uname '' --gname '' -cf - -C \"$HOME/Library/Application Support\" --exclude 'BarShelf/runtime' --exclude 'BarShelf/cache' --exclude 'BarShelf/launch-receipt.json' --exclude 'BarShelf/refresh-stats.json' BarShelf | gzip -n", restore = 'pkill -f "/BarShelf.app/" 2>/dev/null; mkdir -p "$HOME/Library/Application Support" && tar -xzf - -C "$HOME/Library/Application Support" && { [ ! -d /Applications/BarShelf.app ] || open -a BarShelf; }' }
EOF
    fi

    # What is installed here, as a list rather than as binaries. A kilobyte
    # names what several gigabytes would have carried, and the gigabytes would
    # have been built for one architecture besides.
    #
    # `per_machine`, for the same reason the ssh key is: these four machines
    # hold four different sets, and one shared item means whoever pushed last
    # decides what the others were supposed to have.
    #
    # Restoring this installs what is missing. It removes nothing — the list is
    # what a machine must not lack, not what it may not exceed — but it does
    # reach the network and it can take a while, so a machine that would rather
    # not can name `programs` in secrets.skip like anything else.
    if command_exists brew || command_exists cargo || command_exists npm; then
        cat <<'EOF'

[[track]]
name = "programs"
scope = "personal"
per_machine = true
command = { export = "kitbag programs", restore = "kitbag programs --restore" }
EOF
    fi

    # The escape hatch, and it is the same list this repository has always
    # kept: the things that arrive as `curl … | sh` because nobody packaged
    # them. No manager will ever list these, so the list that says what is
    # installed here is incomplete without them — and a list that is missing
    # the toolchain is a list you cannot rebuild a machine from.
    #
    # Each is written only if it is actually here. A declaration that has never
    # been acted on is a plan, not a fact, and this file records facts.
    #
    # The install line travels with the item and kitbag prints it before it
    # runs it. That is the same trust the app tracks above already ask for, and
    # the same reason: the machine being restored is the one that has to run
    # it, and it has no config yet.
    # A non-interactive shell — which is what an ssh command gets — has none of
    # the profile's PATH additions, so kitbag and claude in ~/.local/bin look
    # absent and the config comes out different depending on how the shell was
    # started. Deploying to four machines over ssh is exactly how that was
    # found: three of them wrote a list missing the tool that wrote it.
    export PATH="$HOME/.local/bin:$HOME/bin:$HOME/.cargo/bin:$PATH"

    declare_program() {
        printf '\n[[program]]\nname = "%s"\ninstall = "%s"\n' "$1" "$2"
        [[ -n "${3:-}" ]] && printf 'version_from = "%s"\n' "$3"
        return 0
    }

    command_exists rustup &&
        declare_program rustup \
            "curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y" \
            "rustup --version"
    command_exists uv &&
        declare_program uv \
            "curl -LsSf https://astral.sh/uv/install.sh | sh" \
            "uv --version"
    command_exists cargo-binstall &&
        declare_program cargo-binstall \
            "curl -L --proto '=https' --tlsv1.2 -sSf https://raw.githubusercontent.com/cargo-bins/cargo-binstall/main/install-from-binstall-release.sh | bash" \
            "cargo-binstall -V"
    command_exists claude &&
        declare_program claude "curl -fsSL https://claude.ai/install.sh | bash" "claude --version"
    command_exists kitbag &&
        declare_program kitbag "curl -LsSf https://raw.githubusercontent.com/Open330/kitbag/main/install.sh | sh" "kitbag --version"

    return 0
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
