#!/usr/bin/env bash
# Regression coverage for the restorable Claude/Codex configuration.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT

make_skill_sources() {
  local test_home=$1
  local manifest="$REPO_ROOT/configs/claude/skills.manifest"

  mkdir -p "$test_home/workspace/agents" "$test_home/personal/agent-skills/hooks"
  while IFS=$'\t' read -r slot repo rel; do
    [[ -z "$slot" || "$slot" == \#* ]] && continue
    local source_root
    case "$repo" in
      agents) source_root="$test_home/workspace/agents" ;;
      agent-skills) source_root="$test_home/personal/agent-skills" ;;
      *) printf 'unknown test repo token: %s\n' "$repo" >&2; return 1 ;;
    esac
    mkdir -p "$source_root/$rel"
    printf '%s\n' '---' "name: ${slot##*/}" 'description: restore smoke fixture' '---' \
      > "$source_root/$rel/SKILL.md"
  done < "$manifest"

  local hook
  for hook in english-coach.sh prompt-logger.sh stop-capture.sh; do
    printf '%s\n' '#!/bin/sh' 'exit 0' > "$test_home/personal/agent-skills/hooks/$hook"
    chmod +x "$test_home/personal/agent-skills/hooks/$hook"
  done
}

test_codex_merge() {
  local test_home="$TEST_ROOT/codex"
  mkdir -p "$test_home/.codex"
  printf '%s\n' \
    'notify = [' \
    '  "/machine/node",' \
    '  "/machine/notify.js",' \
    ']' \
    '' \
    '[projects."/machine/repo"]' \
    'trust_level = "trusted"' \
    '' \
    '[plugins."local-only"]' \
    'enabled = true' \
    '' \
    '[mcp_servers.local-only]' \
    'command = "local"' \
    > "$test_home/.codex/config.toml"

  local run
  for run in 1 2 3; do
    env CODEX_HOME="$test_home/.codex" PATH=/usr/bin:/bin \
      bash "$REPO_ROOT/scripts/codex/apply-config.sh" > "$TEST_ROOT/codex-apply-$run.log" 2>&1
  done

  python3 - "$test_home/.codex/config.toml" <<'PY'
import pathlib
import sys
import tomllib

data = tomllib.loads(pathlib.Path(sys.argv[1]).read_text())
assert data["notify"] == ["/machine/node", "/machine/notify.js"]
assert sorted(data["projects"]) == ["/machine/repo"]
assert sorted(data["plugins"]) == [
    "github@openai-curated",
    "linear@openai-curated",
    "notion@openai-curated",
]
assert sorted(data["mcp_servers"]) == ["muxa", "openaiDeveloperDocs"]
PY
}

test_claude_modes() {
  local copy_home="$TEST_ROOT/claude-copy"
  make_skill_sources "$copy_home"
  env HOME="$copy_home" PATH=/usr/bin:/bin \
    "$REPO_ROOT/install.sh" --no-sudo --copy claude >/dev/null 2>&1
  env HOME="$copy_home" PATH=/usr/bin:/bin \
    "$REPO_ROOT/install.sh" --no-sudo --copy claude >/dev/null 2>&1

  [[ $(find "$copy_home/.claude/skills" -mindepth 2 -maxdepth 2 -type l | wc -l) -eq 0 ]]
  [[ $(find "$copy_home/.claude/skills" -mindepth 2 -maxdepth 2 -type d | wc -l) -eq 46 ]]
  [[ $(find "$copy_home" -name '*.backup.*' | wc -l) -eq 0 ]]

  local link_home="$TEST_ROOT/claude-link"
  make_skill_sources "$link_home"
  local occupied="$link_home/.claude/skills/agents/background-implementer"
  mkdir -p "$occupied"
  printf '%s\n' local-only-data > "$occupied/keep.txt"
  env HOME="$link_home" PATH=/usr/bin:/bin \
    "$REPO_ROOT/install.sh" --no-sudo claude >/dev/null 2>&1

  [[ -L "$occupied" ]]
  [[ $(find "$link_home/.claude/skills/agents" -path '*/background-implementer.backup.*/keep.txt' | wc -l) -eq 1 ]]

  HOME="$link_home" "$REPO_ROOT/scripts/claude/capture-skills.sh" --dry-run \
    > "$TEST_ROOT/captured-skills.manifest"
  diff -u "$REPO_ROOT/configs/claude/skills.manifest" "$TEST_ROOT/captured-skills.manifest"
}

test_manifest_path_guard() {
  local guard_home="$TEST_ROOT/manifest-guard-home"
  local fixture="$TEST_ROOT/manifest-guard-fixture"
  mkdir -p "$fixture/configs/claude" "$guard_home/.claude"
  printf '%s\t%s\t%s\n' '../../escaped' agents '../../outside' \
    > "$fixture/configs/claude/skills.manifest"

  if (
    export HOME="$guard_home"
    # shellcheck source=../../lib/core.sh
    source "$REPO_ROOT/lib/core.sh"
    # shellcheck source=../../modules/claude.sh
    source "$REPO_ROOT/modules/claude.sh"
    get_root_dir() { printf '%s\n' "$fixture"; }
    install_claude_skills
  ) >/dev/null 2>&1; then
    printf '%s\n' 'unsafe manifest row was accepted' >&2
    return 1
  fi
  [[ ! -e "$guard_home/.claude/escaped" ]]
}

test_trust_sync_legacy_tables() {
  local test_home="$TEST_ROOT/trust-legacy"
  local workspace="$test_home/workspace-agent"
  local outside="$test_home/preserved-repo"
  mkdir -p "$test_home/.codex" "$workspace/current/.git" "$outside"
  printf '%s\n' \
    'model = "test"' \
    '' \
    "[projects.\"$outside\"]" \
    'trust_level = "trusted"' \
    '' \
    "[projects.\"$test_home/missing-repo\"]" \
    'trust_level = "trusted"' \
    '' \
    '[tui]' \
    'notifications = true' \
    > "$test_home/.codex/config.toml"

  env HOME="$test_home" CODEX_WORKSPACE_ROOT="$workspace" PATH=/usr/bin:/bin \
    "$REPO_ROOT/scripts/codex/workspace-trust-sync.sh"

  python3 - "$test_home/.codex/config.toml" "$workspace" "$outside" <<'PY'
import pathlib
import sys
import tomllib

data = tomllib.loads(pathlib.Path(sys.argv[1]).read_text())
assert sorted(data["projects"]) == sorted([sys.argv[2], f"{sys.argv[2]}/current", sys.argv[3]])
assert data["tui"]["notifications"] is True
PY
}

test_bundle() {
  local bundle="$TEST_ROOT/install-bundled.sh"
  "$REPO_ROOT/scripts/bundle.sh" > "$bundle"
  chmod +x "$bundle"

  local component
  for component in claude codex cship; do
    mkdir -p "$TEST_ROOT/dry-$component"
    env HOME="$TEST_ROOT/dry-$component" PATH=/usr/bin:/bin \
      bash "$bundle" --no-sudo --dry-run "$component" >/dev/null 2>&1
  done

  local bundle_home="$TEST_ROOT/bundle-home"
  mkdir -p "$bundle_home/workspace-agent/repo/.git"
  env HOME="$bundle_home" PATH=/usr/bin:/bin \
    bash "$bundle" --no-sudo codex >/dev/null 2>&1

  [[ -f "$bundle_home/.codex/config.toml" && ! -L "$bundle_home/.codex/config.toml" ]]
  [[ -x "$bundle_home/.local/bin/codex-workspace-trust-sync" ]]
  [[ ! -L "$bundle_home/.local/bin/codex-workspace-trust-sync" ]]
  env HOME="$bundle_home" PATH=/usr/bin:/bin \
    "$bundle_home/.local/bin/codex-workspace-trust-sync"

  python3 - "$bundle_home/.codex/config.toml" <<'PY'
import pathlib
import sys
import tomllib

tomllib.loads(pathlib.Path(sys.argv[1]).read_text())
PY
}

test_codex_merge
test_claude_modes
test_manifest_path_guard
test_trust_sync_legacy_tables
test_bundle
printf '%s\n' 'agent restore smoke tests: ok'
