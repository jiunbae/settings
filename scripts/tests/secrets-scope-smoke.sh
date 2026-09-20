#!/usr/bin/env bash
# Regression coverage for scoped secrets: which files get pushed, into which
# vault folder, and which entries a machine restores. `bw` is a stub, so the
# test touches no real vault and no real secret.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT

FAILURES=0

fail() { printf '  ✗ %s\n' "$1"; FAILURES=$((FAILURES + 1)); }
pass() { printf '  ✓ %s\n' "$1"; }

check() { # <description> <expected> <actual>
  if [[ "$2" == "$3" ]]; then pass "$1"; else
    fail "$1"; printf '      expected: %s\n      actual:   %s\n' "$2" "$3"
  fi
}

contains() { # <description> <needle> <haystack>
  case "$3" in *"$2"*) pass "$1" ;; *) fail "$1 (missing: $2)" ;; esac
}

lacks() { # <description> <needle> <haystack>
  case "$3" in *"$2"*) fail "$1 (unexpected: $2)" ;; *) pass "$1" ;; esac
}

# ------------------------------------------------------------------------------
# A fake home with one file per scope
# ------------------------------------------------------------------------------
make_home() {
  local home=$1
  mkdir -p "$home/.envs" "$home/.ssh/config.d" "$home/bin"

  printf '%s\n' '# scope: personal' 'export PERSONAL_TOKEN=p' > "$home/.envs/personal.env"
  printf '%s\n' '# scope: work' '# owner: acme' 'export WORK_TOKEN=w' > "$home/.envs/work.env"
  printf '%s\n' '# scope: shared' 'export SHARED_TOKEN=s' > "$home/.envs/shared.env"
  printf '%s\n' '# scope: local' 'export SESSION=abc' > "$home/.envs/sessiononly.env"
  printf '%s\n' 'export UNMARKED=1' > "$home/.envs/unmarked.env"
  printf '%s\n' '# scope: nonsense' 'export BOGUS=1' > "$home/.envs/bogus.env"
  printf '%s\n' '# scope: work' 'export DRAFT=1' > "$home/.envs/_draft.env"
  printf '%s\n' '# scope: mixed' '# spans: personal, work' 'export BOTH_TOKEN=m' > "$home/.envs/both.env"

  # Real keys: the display fingerprints them, and a fake string is not a key.
  ssh-keygen -q -t ed25519 -N '' -C 'device@fixture' -f "$home/.ssh/id_ed25519"  # no marker -> personal
  ssh-keygen -q -t ed25519 -N '' -C 'work@fixture' -f "$home/.ssh/id_work"
  printf '%s\n' 'work' > "$home/.ssh/id_work.scope"  # sidecar marker
  printf '%s\n' '# scope: work' 'Host office' > "$home/.ssh/config.d/20-company.conf"
  printf '%s\n' '# scope: personal' \
    'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa one@host-a' \
    'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb two@host-b' \
    > "$home/.ssh/authorized_keys"
}

# Paths outside the known directories, listed for tracking.
make_tracked() {
  local home=$1
  mkdir -p "$home/.config/settings" "$home/Library/Keychains"
  printf '%s\n' 'registry=https://example.test' '//example.test/:_authToken=abc' > "$home/.npmrc"
  printf '\x00\x01binary payload\x00' > "$home/Library/Keychains/fixture.keychain-db"
  printf '%s\n' '# scope: work' 'k = v' > "$home/self-marked.conf"
  printf '%s\n' \
    '# path                              scope     owner  name' \
    '~/.npmrc                            personal' \
    '~/Library/Keychains/fixture.keychain-db  work  acme  file:fixture-keychain' \
    '~/self-marked.conf                  personal' \
    '~/not-here.conf                     personal' \
    > "$home/.config/settings/secrets-paths"
}

# A `bw` that keeps folders and items in files, so ids stay stable across calls.
make_bw_stub() {
  local home=$1
  cat > "$home/bin/bw" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
STATE="${BW_STUB_STATE:?}"
mkdir -p "$STATE"
case "${1:-}" in
  edit|create|delete) printf '%s %s\n' "$1" "${2:-}" >> "$STATE/calls.log" ;;
esac
[[ -f "$STATE/folders.json" ]] || echo '[]' > "$STATE/folders.json"
[[ -f "$STATE/items.json" ]] || echo '[]' > "$STATE/items.json"

case "${1:-}" in
  --version) echo "2026.8.0" ;;
  status) echo '{"status":"unlocked","serverUrl":"https://vault.test"}' ;;
  sync|logout|lock) : ;;
  config) : ;;
  encode) cat ;;
  list)
    case "$2" in
      folders) cat "$STATE/folders.json" ;;
      items)   cat "$STATE/items.json" ;;
    esac ;;
  get)
    case "$2" in
      template)
        case "$3" in
          folder) echo '{"name":""}' ;;
          item)   echo '{"type":1,"name":"","notes":null,"folderId":null,"fields":[],"login":{},"card":{},"identity":{},"secureNote":null}' ;;
        esac ;;
      item) jq --arg id "$3" '.[] | select(.id == $id)' "$STATE/items.json" ;;
    esac ;;
  create)
    case "$2" in
      folder)
        payload=$(cat)
        id="folder-$(jq 'length + 1' "$STATE/folders.json")"
        jq --argjson f "$(jq --arg id "$id" '.id = $id' <<< "$payload")" '. + [$f]' \
          "$STATE/folders.json" > "$STATE/folders.tmp" && mv "$STATE/folders.tmp" "$STATE/folders.json"
        jq --arg id "$id" '.id = $id' <<< "$payload" ;;
      item)
        payload=$(cat)
        id="item-$(jq 'length + 1' "$STATE/items.json")"
        jq --argjson i "$(jq --arg id "$id" '.id = $id | .attachments = []' <<< "$payload")" '. + [$i]' \
          "$STATE/items.json" > "$STATE/items.tmp" && mv "$STATE/items.tmp" "$STATE/items.json"
        jq --arg id "$id" '.id = $id' <<< "$payload" ;;
      attachment)
        # bw create attachment --file <f> --itemid <id>
        shift 2; file=""; itemid=""
        while [[ $# -gt 0 ]]; do
          case "$1" in --file) file=$2; shift 2 ;; --itemid) itemid=$2; shift 2 ;; *) shift ;; esac
        done
        aid="att-$RANDOM"
        jq --arg id "$itemid" --arg aid "$aid" --arg fn "$(basename "$file")" \
          'map(if .id == $id then .attachments = ((.attachments // []) + [{"id":$aid,"fileName":$fn}]) else . end)' \
          "$STATE/items.json" > "$STATE/items.tmp" && mv "$STATE/items.tmp" "$STATE/items.json"
        echo '{}' ;;
    esac ;;
  edit)
    payload=$(cat)
    if [[ -n "${BW_STUB_FAIL_NAME:-}" ]] && grep -q "\"${BW_STUB_FAIL_NAME}\"" <<< "$payload"; then
      n=$(cat "$STATE/fail.count" 2>/dev/null || echo 0); n=$((n+1)); echo "$n" > "$STATE/fail.count"
      if (( n <= ${BW_STUB_FAIL_TIMES:-99} )); then
        echo "FetchError: request to https://vault.test/api/ciphers/x failed, reason: socket hang up" >&2
        exit 1
      fi
    fi
    jq --arg id "$3" --argjson p "$payload" 'map(if .id == $id then ($p + {id: $id, attachments: (.attachments // [])}) else . end)' \
      "$STATE/items.json" > "$STATE/items.tmp" && mv "$STATE/items.tmp" "$STATE/items.json"
    echo "$payload" ;;
  delete)
    case "$2" in
      attachment)
        jq --arg aid "$3" 'map(.attachments = ((.attachments // []) | map(select(.id != $aid))))' \
          "$STATE/items.json" > "$STATE/items.tmp" && mv "$STATE/items.tmp" "$STATE/items.json" ;;
    esac ;;
  *) echo "bw stub: unhandled $*" >&2; exit 1 ;;
esac
STUB
  chmod +x "$home/bin/bw"
}

run_push() { # <home> [args...]
  local home=$1; shift
  HOME="$home" \
  BW_STUB_STATE="$home/.bwstate" \
  BW_SESSION="stub" \
  SETTINGS_VAULT_SERVER="https://vault.test" \
  BW_STUB_FAIL_NAME="${FAIL_NAME:-}" \
  BW_STUB_FAIL_TIMES="${FAIL_TIMES:-99}" \
  PATH="$home/bin:$PATH" \
    bash "$REPO_ROOT/scripts/secrets-push.sh" "$@" 2>&1
}

# ------------------------------------------------------------------------------
printf '\nsecrets-push: collection and scopes\n'
HOME_A="$TEST_ROOT/a"
make_home "$HOME_A"
make_bw_stub "$HOME_A"

make_tracked "$HOME_A"
DRY="$(run_push "$HOME_A")"
# Only the table of what would be pushed; the skip report below it names the
# same files for the opposite reason.
TABLE="$(sed -n '/Collected/,/items, folder/p' <<< "$DRY")"
contains "personal env collected"        "env:personal" "$TABLE"
contains "work env collected"            "env:work" "$TABLE"
contains "shared env collected"          "env:shared" "$TABLE"
lacks    "local env never pushed"        "env:sessiononly" "$DRY"
lacks    "underscore draft skipped"      "env:_draft" "$DRY"
lacks    "unmarked env not collected"    "env:unmarked" "$TABLE"
lacks    "unknown scope not collected"   "env:bogus" "$TABLE"
contains "unmarked env reported"         "env:unmarked — no '# scope:' marker" "$DRY"
contains "unknown scope reported"        "unknown scope 'nonsense'" "$DRY"
contains "key without marker is personal" "ssh:id_ed25519" "$TABLE"
contains "key sidecar marker read"       "ssh:id_work" "$TABLE"
contains "authorized_keys collected"     "ssh:authorized_keys" "$TABLE"
contains "grouped under its scope"       "work · acme" "$TABLE"
contains "tree branches are drawn"       "└──" "$TABLE"
contains "env keys are named"            "WORK_TOKEN" "$TABLE"
contains "key shows its fingerprint"     "SHA256:" "$TABLE"
contains "authorized_keys counts its keys" "2 keys:" "$TABLE"
contains "a mixed item says what it mixes" "— personal, work" "$TABLE"
lacks    "the mode column is gone"       "MODE" "$TABLE"

# Paths the script never guessed at, tracked by listing them.
contains "a tracked text file is collected"  "file:npmrc" "$TABLE"
contains "its keys are read too"             "_authToken" "$TABLE"
contains "a tracked binary is collected"     "file:fixture-keychain" "$TABLE"
contains "binaries say so"                   "binary," "$TABLE"
contains "the file's own marker wins"        "file:self-marked.conf" "$TABLE"
contains "a missing path is reported"        "not-here.conf — listed in" "$DRY"
lacks    "no phantom public field"       "~/.envs/personal.env  (+public)" "$TABLE"

OUT="$(run_push "$HOME_A" --push)"
ITEMS="$HOME_A/.bwstate/items.json"
FOLDERS="$HOME_A/.bwstate/folders.json"

check "work env lands in the work folder" "bootstrap/work" \
  "$(jq -r --arg n "env:work" '.[] | select(.name == $n) | .folderId' "$ITEMS" \
     | xargs -I{} jq -r --arg id {} '.[] | select(.id == $id) | .name' "$FOLDERS")"
check "personal env lands in the personal folder" "bootstrap/personal" \
  "$(jq -r --arg n "env:personal" '.[] | select(.name == $n) | .folderId' "$ITEMS" \
     | xargs -I{} jq -r --arg id {} '.[] | select(.id == $id) | .name' "$FOLDERS")"
check "scope stored as a field" "work" \
  "$(jq -r '.[] | select(.name == "env:work") | .fields[] | select(.name == "scope") | .value' "$ITEMS")"
check "owner stored as a field" "acme" \
  "$(jq -r '.[] | select(.name == "env:work") | .fields[] | select(.name == "owner") | .value' "$ITEMS")"
contains "ssh key keeps its public field" "ssh-ed25519" \
  "$(jq -r '.[] | select(.name == "ssh:id_ed25519") | .fields[] | select(.name == "public") | .value' "$ITEMS")"
MANIFEST_A="$(jq -r '.[] | select(.name == "bootstrap") | .notes' "$ITEMS")"
check "authorized_keys restores by merging, not overwriting" "" \
  "$(jq -r '.entries[] | select(.item == "ssh:authorized_keys") | .dest // empty' <<< "$MANIFEST_A")"
contains "the merge keeps what it does not know" "grep -qF" \
  "$(jq -r '.entries[] | select(.item == "ssh:authorized_keys") | .exec' <<< "$MANIFEST_A")"
check "a tracked binary restores from its attachment" "attachment:fixture.keychain-db" \
  "$(jq -r '.entries[] | select(.item == "file:fixture-keychain") | .source' <<< "$MANIFEST_A")"
check "and lands back at its path" "~/Library/Keychains/fixture.keychain-db" \
  "$(jq -r '.entries[] | select(.item == "file:fixture-keychain") | .dest' <<< "$MANIFEST_A")"
check "the marked file follows its own header, not the column" "work" \
  "$(jq -r '.entries[] | select(.item == "file:self-marked.conf") | .scope' <<< "$MANIFEST_A")"
check "manifest is version 2" "2" \
  "$(jq -r '.[] | select(.name == "bootstrap") | .notes' "$ITEMS" | jq -r '.version')"
check "manifest entries carry scopes" "" \
  "$(jq -r '.[] | select(.name == "bootstrap") | .notes' "$ITEMS" \
     | jq -r '[.entries[] | select(has("scope") | not)] | length | select(. > 0) // empty')"

# Re-pushing after a scope change must move the item, not leave a second copy.
printf '%s\n' '# scope: work' 'export PERSONAL_TOKEN=p' > "$HOME_A/.envs/personal.env"
run_push "$HOME_A" --push >/dev/null
check "changed scope moves the item" "bootstrap/work" \
  "$(jq -r --arg n "env:personal" '.[] | select(.name == $n) | .folderId' "$ITEMS" \
     | xargs -I{} jq -r --arg id {} '.[] | select(.id == $id) | .name' "$FOLDERS")"
check "changed scope does not duplicate" "1" \
  "$(jq -r '[.[] | select(.name == "env:personal")] | length' "$ITEMS")"

# A file that became machine-local leaves its old copy behind: it must be named.
printf '%s\n' '# scope: local' 'export SHARED_TOKEN=s' > "$HOME_A/.envs/shared.env"
STALE_OUT="$(run_push "$HOME_A" --push)"
contains "stale vault item reported" "env:shared" \
  "$(printf '%s' "$STALE_OUT" | sed -n '/In the vault but not sent/,$p')"

printf '\nauthorized_keys merge (run exactly as a restore runs it)\n'
MERGE_HOME="$TEST_ROOT/merge"
mkdir -p "$MERGE_HOME/.ssh"
LOCAL_ONLY='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIccccccccccccccccccccccccccccccccccccccccccc ci@runner'
printf '%s\n' "$LOCAL_ONLY" > "$MERGE_HOME/.ssh/authorized_keys"
MERGE_CMD="$(jq -r '.entries[] | select(.item == "ssh:authorized_keys") | .exec' <<< "$MANIFEST_A")"
HOME="$MERGE_HOME" bash -c "$MERGE_CMD" < "$HOME_A/.ssh/authorized_keys"
contains "a key the list never saw survives" "ci@runner" "$(cat "$MERGE_HOME/.ssh/authorized_keys")"
contains "the list's keys arrive" "one@host-a" "$(cat "$MERGE_HOME/.ssh/authorized_keys")"
check "merging twice adds nothing" "3" \
  "$(HOME="$MERGE_HOME" bash -c "$MERGE_CMD" < "$HOME_A/.ssh/authorized_keys"; grep -c . "$MERGE_HOME/.ssh/authorized_keys")"
check "comments are not copied in" "0" \
  "$(grep -c '^#' "$MERGE_HOME/.ssh/authorized_keys" || true)"

# ------------------------------------------------------------------------------
printf '\nsecrets-push: a server that drops the connection\n'

# Transient: the write fails once, the retry gets through.
HOME_B="$TEST_ROOT/b"
make_home "$HOME_B"
make_bw_stub "$HOME_B"
run_push "$HOME_B" --push >/dev/null            # first push creates everything
# An unchanged item is never written, so give it something to write.
printf '%s\n' '# scope: work' '# owner: acme' 'export WORK_TOKEN=rotated' > "$HOME_B/.envs/work.env"
RC=0
OUT_B="$(FAIL_NAME="env:work" FAIL_TIMES=1 run_push "$HOME_B" --push)" || RC=$?
check "transient failure is retried, run succeeds" "0" "$RC"
contains "retry is announced" "retrying" "$OUT_B"
check "the item is still written" "1" \
  "$(jq -r '[.[] | select(.name == "env:work")] | length' "$HOME_B/.bwstate/items.json")"

# Permanent: the item is reported, skipped, and left out of the manifest, while
# everything else still goes up.
HOME_C="$TEST_ROOT/c"
make_home "$HOME_C"
make_bw_stub "$HOME_C"
run_push "$HOME_C" --push >/dev/null
printf '%s\n' '# scope: work' '# owner: acme' 'export WORK_TOKEN=rotated' > "$HOME_C/.envs/work.env"
RC=0
OUT_C="$(FAIL_NAME="env:work" run_push "$HOME_C" --push)" || RC=$?
check "a write that keeps failing exits non-zero" "1" "$RC"
contains "the failed item is named" "env:work" \
  "$(sed -n '/could not be written/,$p' <<< "$OUT_C")"
contains "other items still pushed" "env:personal" "$OUT_C"
MANIFEST_C="$(jq -r '.[] | select(.name == "bootstrap") | .notes' "$HOME_C/.bwstate/items.json")"
check "manifest excludes the failed item" "" \
  "$(jq -r '[.entries[] | select(.item == "env:work")] | .[0].item // empty' <<< "$MANIFEST_C")"
check "manifest keeps the others" "env:personal" \
  "$(jq -r '[.entries[] | select(.item == "env:personal")] | .[0].item // empty' <<< "$MANIFEST_C")"

printf '\nsecrets-push: an unchanged push costs nothing\n'
HOME_D="$TEST_ROOT/d"
make_home "$HOME_D"
make_bw_stub "$HOME_D"
run_push "$HOME_D" --push >/dev/null
: > "$HOME_D/.bwstate/calls.log"
OUT_D="$(run_push "$HOME_D" --push)"
contains "the second push reports unchanged" "unchanged env:work" "$OUT_D"
check "nothing is edited" "0" "$(grep -c '^edit' "$HOME_D/.bwstate/calls.log" || true)"
check "nothing is created" "0" "$(grep -c '^create item' "$HOME_D/.bwstate/calls.log" || true)"
check "no attachment is uploaded" "0" "$(grep -c '^create attachment' "$HOME_D/.bwstate/calls.log" || true)"

printf '%s\n' '# scope: personal' 'export PERSONAL_TOKEN=rotated' > "$HOME_D/.envs/personal.env"
: > "$HOME_D/.bwstate/calls.log"
OUT_D2="$(run_push "$HOME_D" --push)"
contains "a changed file is written" "updated  env:personal" "$OUT_D2"
check "and only that one" "1" "$(grep -c '^edit' "$HOME_D/.bwstate/calls.log" || true)"

# ------------------------------------------------------------------------------
printf '\nsecrets restore: scope filter\n'
MANIFEST='{"version":2,"entries":[
  {"item":"env:personal","source":"notes","dest":"~/.envs/personal.env","mode":"600","scope":"personal"},
  {"item":"env:work","source":"notes","dest":"~/.envs/work.env","mode":"600","scope":"work"},
  {"item":"env:shared","source":"notes","dest":"~/.envs/shared.env","mode":"600","scope":"shared"},
  {"item":"app:aas","source":"notes","exec":"cat >/dev/null","scope":"mixed"},
  {"item":"gpg:primary","source":"notes","exec":"cat >/dev/null"}
]}'

restore_list() { # <scope-env> [scope-file-content]
  local home="$TEST_ROOT/r$RANDOM"
  mkdir -p "$home/.config/settings"
  [[ -n "${2:-}" ]] && printf '%s\n' "$2" > "$home/.config/settings/secrets.scope"
  HOME="$home" SETTINGS_SECRETS_SCOPE="${1:-}" DRY_RUN=true bash -c '
    source "'"$REPO_ROOT"'/lib/core.sh"
    source "'"$REPO_ROOT"'/lib/platform.sh"
    detect_platform >/dev/null 2>&1
    source "'"$REPO_ROOT"'/modules/secrets.sh"
    VAULT_ITEMS_CACHE='"'"'[{"name":"bootstrap","notes":'"$(jq -Rs . <<< "$MANIFEST")"'}]'"'"'
    apply_manifest
  ' 2>&1 | grep -o 'Would restore [a-z:]*' | awk '{print $3}' | sort | tr '\n' ' '
}

check "default is personal + mixed" "app:aas env:personal gpg:primary " "$(restore_list)"
check "explicit work adds only work"  "app:aas env:work gpg:primary " "$(restore_list work)"
check "comma list"  "app:aas env:personal env:work gpg:primary " "$(restore_list personal,work)"
check "all"         "app:aas env:personal env:shared env:work gpg:primary " "$(restore_list all)"
check "machine file sets the default" "app:aas env:shared gpg:primary " "$(restore_list "" shared)"

# ------------------------------------------------------------------------------
printf '\nsecrets restore: platform filter\n'

# Which machine this is. The entries below are written around it so the test
# says the same thing wherever it runs.
SELF_PLATFORM="$(bash -c '
  source "'"$REPO_ROOT"'/lib/platform.sh"
  detect_platform >/dev/null 2>&1
  printf "%s" "$PLATFORM"')"

PLAT_MANIFEST='{"version":2,"entries":[
  {"item":"env:everywhere","source":"notes","dest":"~/.envs/a.env","scope":"personal"},
  {"item":"env:here","source":"notes","dest":"~/.envs/b.env","scope":"personal","platform":"'"$SELF_PLATFORM"'"},
  {"item":"env:windowsonly","source":"notes","dest":"~/.envs/c.env","scope":"personal","platform":["windows"]},
  {"item":"env:broken","source":"notes","dest":"~/.envs/d.env","scope":"personal","platform":[5]},
  {"item":"env:empty","source":"notes","dest":"~/.envs/e.env","scope":"personal","platform":[]}
]}'

plat_restore() { # prints the items a restore here would touch
  local home="$TEST_ROOT/p$RANDOM"
  mkdir -p "$home"
  HOME="$home" DRY_RUN=true bash -c '
    source "'"$REPO_ROOT"'/lib/core.sh"
    source "'"$REPO_ROOT"'/lib/platform.sh"
    detect_platform >/dev/null 2>&1
    source "'"$REPO_ROOT"'/modules/secrets.sh"
    VAULT_ITEMS_CACHE='"'"'[{"name":"bootstrap","notes":'"$(jq -Rs . <<< "$PLAT_MANIFEST")"'}]'"'"'
    apply_manifest
  ' 2>&1
}

PLAT_OUT="$(plat_restore)"
PLAT_LIST="$(grep -o 'Would restore [a-z:]*' <<< "$PLAT_OUT" | awk '{print $3}' | sort | tr '\n' ' ')"
check "an untagged entry restores anywhere, a foreign one does not" \
  "env:empty env:everywhere env:here " "$PLAT_LIST"
contains "the foreign entry says why it was skipped" \
  "Skipped env:windowsonly (platform: windows)" "$PLAT_OUT"
contains "a platform that is not a name is an error, not a guess" \
  "env:broken" "$(sed -n '/non-string platform/p' <<< "$PLAT_OUT")"

# The name matching itself, without a manifest in the way.
plat_match() { # <entry-platforms> <this-machine>
  bash -c '
    source "'"$REPO_ROOT"'/lib/core.sh"
    source "'"$REPO_ROOT"'/modules/secrets.sh"
    PLATFORM="'"$2"'"
    _platform_matches "'"$1"'" && echo yes || echo no'
}
check "macos entry on a mac"        "yes" "$(plat_match macos macos)"
check "macos entry on linux"        "no"  "$(plat_match macos linux)"
check "linux entry under wsl"       "yes" "$(plat_match linux wsl)"
check "a list matches on any name"  "yes" "$(plat_match "macos linux" linux)"
check "windows entry nowhere here"  "no"  "$(plat_match windows macos)"

printf '\n'
if [[ "$FAILURES" -gt 0 ]]; then
  printf '%s test(s) failed\n' "$FAILURES"
  exit 1
fi
printf 'all secrets scope checks passed\n'
