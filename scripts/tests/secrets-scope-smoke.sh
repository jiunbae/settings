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

  printf '%s\n' 'KEY' > "$home/.ssh/id_ed25519"      # no marker -> personal
  printf '%s\n' 'PUB' > "$home/.ssh/id_ed25519.pub"
  printf '%s\n' 'KEY' > "$home/.ssh/id_work"
  printf '%s\n' 'work' > "$home/.ssh/id_work.scope"  # sidecar marker
  printf '%s\n' '# scope: work' 'Host office' > "$home/.ssh/config.d/20-company.conf"
}

# A `bw` that keeps folders and items in files, so ids stay stable across calls.
make_bw_stub() {
  local home=$1
  cat > "$home/bin/bw" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
STATE="${BW_STUB_STATE:?}"
mkdir -p "$STATE"
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

DRY="$(run_push "$HOME_A")"
# Only the table of what would be pushed; the skip report below it names the
# same files for the opposite reason.
TABLE="$(sed -n '/ITEM  */,/items, folder/p' <<< "$DRY")"
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
contains "scope column shows work"       "env:work                   work" "$TABLE"
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
check "ssh key keeps its public field" "PUB" \
  "$(jq -r '.[] | select(.name == "ssh:id_ed25519") | .fields[] | select(.name == "public") | .value' "$ITEMS" | tr -d '\n')"
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
  "$(printf '%s' "$STALE_OUT" | sed -n '/In the vault but not pushed/,$p')"

# ------------------------------------------------------------------------------
printf '\nsecrets-push: a server that drops the connection\n'

# Transient: the write fails once, the retry gets through.
HOME_B="$TEST_ROOT/b"
make_home "$HOME_B"
make_bw_stub "$HOME_B"
run_push "$HOME_B" --push >/dev/null            # first push creates everything
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

printf '\n'
if [[ "$FAILURES" -gt 0 ]]; then
  printf '%s test(s) failed\n' "$FAILURES"
  exit 1
fi
printf 'all secrets scope checks passed\n'
