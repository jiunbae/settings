#!/bin/bash
# claude.sh - Claude Code configuration (settings, hooks, skills index, memory)
# Can be run standalone or sourced by install.sh

# ==============================================================================
# Standalone execution support
# ==============================================================================
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "$SCRIPT_DIR/../lib/core.sh"
    source "$SCRIPT_DIR/../lib/platform.sh"
    detect_platform
    setup_package_manager
fi

# ==============================================================================
# Configuration
#
# Unlike Codex, Claude Code never rewrites settings.json on its own — verified
# by symlinking it and running both a full session and the /config UI, after
# which the link and the file were untouched. So the repo copy can be the real
# file and the machine just points at it.
#
# Every path inside settings.json is written as $HOME/... rather than an
# absolute path. Hook commands and statusLine.command are executed through a
# shell, so the expansion happens at run time and the same file works under any
# username — confirmed by rendering the statusline from a $HOME-based config.
#
# What this module deliberately does NOT manage:
#   ~/.claude.json     MCP registrations live here alongside per-project state
#                      that Claude Code rewrites constantly; `claude mcp add`
#                      below is the supported way in.
#   .credentials.json  OAuth tokens. Never in a repo.
# ==============================================================================
readonly CLAUDE_HOME="$HOME/.claude"
readonly CLAUDE_HOOKS_DIR="$CLAUDE_HOME/hooks"
readonly CLAUDE_SKILLS_DIR="$CLAUDE_HOME/skills"
readonly AGENT_SKILLS_REPO="$HOME/personal/agent-skills"

# Hook scripts live in the agent-skills repo, not here — they are shared with
# Codex and evolve with the oh-my-prompt tooling.
readonly CLAUDE_HOOK_SCRIPTS=(english-coach.sh prompt-logger.sh stop-capture.sh)

# MCP servers to register if missing. Kept as "name|command|args..." so the
# whole list stays greppable.
readonly CLAUDE_MCP_SERVERS=(
    "muxa|muxa|mcp"
)

# ==============================================================================
# Helpers
# ==============================================================================

_claude_content_matches() {
    local source=$1 target=$2

    # diff follows directory symlinks and reports identical broken links as
    # errors. Compare link metadata explicitly so copied skill trees remain
    # idempotent even when they intentionally contain unresolved model links.
    if command_exists python3; then
        python3 - "$source" "$target" <<'PY'
import filecmp
import os
import stat
import sys


def same(left: str, right: str) -> bool:
    try:
        left_stat = os.lstat(left)
        right_stat = os.lstat(right)
    except OSError:
        return False

    if stat.S_IFMT(left_stat.st_mode) != stat.S_IFMT(right_stat.st_mode):
        return False
    if stat.S_ISLNK(left_stat.st_mode):
        return os.readlink(left) == os.readlink(right)
    if stat.S_ISDIR(left_stat.st_mode):
        try:
            names = sorted(os.listdir(left))
            if names != sorted(os.listdir(right)):
                return False
        except OSError:
            return False
        return all(same(os.path.join(left, name), os.path.join(right, name)) for name in names)
    if stat.S_ISREG(left_stat.st_mode):
        if bool(left_stat.st_mode & 0o111) != bool(right_stat.st_mode & 0o111):
            return False
        return filecmp.cmp(left, right, shallow=False)
    return False


raise SystemExit(0 if same(sys.argv[1], sys.argv[2]) else 1)
PY
        return $?
    fi

    diff -rq "$source" "$target" >/dev/null 2>&1
}

_claude_link() {
    local source=$1 target=$2 label=$3

    if [[ ! -e "$source" ]]; then
        log_error "$label source missing: $source"
        return 1
    fi

    # In copy mode the target is a real file, so a readlink check would never
    # match and every run would re-warn. Compare contents instead.
    if [[ "$LINK_MODE" == "copy" ]]; then
        if _claude_content_matches "$source" "$target"; then
            log_info "$label already up to date"
            track_skipped "$label"
            return 0
        fi
        FORCE=true backup_and_link "$source" "$target"
        return 0
    fi

    if [[ -L "$target" && "$(readlink "$target")" == "$source" ]]; then
        log_info "$label already linked"
        track_skipped "$label"
        return 0
    fi

    backup_and_link "$source" "$target"
}

# ==============================================================================
# Installation Functions
# ==============================================================================

install_claude_settings() {
    print_section "Setting up Claude Code settings"

    local root_dir
    root_dir=$(get_root_dir)

    mkdir -p "$CLAUDE_HOME"
    _claude_link "$root_dir/configs/claude/settings.json" \
                 "$CLAUDE_HOME/settings.json" "Claude settings.json"
}

install_claude_hooks() {
    print_section "Linking Claude Code hooks"

    if [[ ! -d "$AGENT_SKILLS_REPO/hooks" ]]; then
        log_warn "agent-skills repo not found at $AGENT_SKILLS_REPO"
        log_info "Clone it first — settings.json references these hooks by path:"
        log_info "  git clone git@github.com:jiunbae/agent-skills.git $AGENT_SKILLS_REPO"
        track_skipped "Claude hooks (agent-skills repo absent)"
        return 0
    fi

    mkdir -p "$CLAUDE_HOOKS_DIR"
    local hook
    for hook in "${CLAUDE_HOOK_SCRIPTS[@]}"; do
        _claude_link "$AGENT_SKILLS_REPO/hooks/$hook" \
                     "$CLAUDE_HOOKS_DIR/$hook" "Claude hook $hook" || return 1
    done
}

install_claude_skill_index() {
    print_section "Setting up Claude Code skill index"

    local root_dir
    root_dir=$(get_root_dir)

    # Claude Code only auto-discovers ~/.claude/skills/<name>/SKILL.md, one level
    # deep. The category trees below it are invisible to the harness, so this
    # index is the entry point that makes them reachable.
    mkdir -p "$CLAUDE_SKILLS_DIR"
    _claude_link "$root_dir/configs/claude/skill-index" \
                 "$CLAUDE_SKILLS_DIR/skill-index" "Claude skill-index"
}

install_claude_skills() {
    print_section "Restoring Claude Code skill farm"

    local root_dir
    root_dir=$(get_root_dir)
    local manifest="$root_dir/configs/claude/skills.manifest"

    if [[ ! -f "$manifest" ]]; then
        log_warn "skills manifest not found: $manifest"
        track_skipped "Claude skills (no manifest)"
        return 0
    fi

    local created=0 skipped=0 missing=0 conflicts=0
    local slot repo rel source target repo_root

    while IFS=$'\t' read -r slot repo rel; do
        [[ -z "$slot" || "$slot" == \#* ]] && continue

        if [[ ! "$slot" =~ ^[a-z0-9][a-z0-9-]*/[a-z0-9][a-z0-9-]*$ ]]; then
            log_warn "unsafe skill slot in manifest: $slot"
            conflicts=$((conflicts + 1))
            continue
        fi
        if [[ ! "$rel" =~ ^[A-Za-z0-9._-]+(/[A-Za-z0-9._-]+)*$ || "/$rel/" == *"/../"* ]]; then
            log_warn "unsafe skill source path for $slot: $rel"
            conflicts=$((conflicts + 1))
            continue
        fi

        case "$repo" in
            agents)       repo_root="$HOME/workspace/agents" ;;
            agent-skills) repo_root="$AGENT_SKILLS_REPO" ;;
            *)
                log_warn "unknown repo token '$repo' for $slot"
                conflicts=$((conflicts + 1))
                continue
                ;;
        esac

        source="$repo_root/$rel"
        target="$CLAUDE_SKILLS_DIR/$slot"

        if [[ ! -f "$source/SKILL.md" ]]; then
            missing=$((missing + 1))
            continue
        fi

        local repo_root_real source_real
        repo_root_real=$(cd "$repo_root" && pwd -P)
        source_real=$(cd "$source" && pwd -P)
        if [[ "$source_real" != "$repo_root_real/"* ]]; then
            log_warn "skill source escapes its declared repo for $slot: $source"
            conflicts=$((conflicts + 1))
            continue
        fi

        if [[ "$LINK_MODE" == "copy" ]]; then
            if _claude_content_matches "$source" "$target"; then
                skipped=$((skipped + 1))
                continue
            fi
        elif [[ -L "$target" && "$(readlink "$target")" == "$source" ]]; then
            skipped=$((skipped + 1))
            continue
        fi

        if [[ "$DRY_RUN" == "true" ]]; then
            if [[ "$LINK_MODE" == "copy" ]]; then
                log_info "[DRY-RUN] Would copy $slot <- $source"
            else
                log_info "[DRY-RUN] Would link $slot -> $source"
            fi
            created=$((created + 1))
            continue
        fi

        # Never delete a real local skill directory. backup_and_link moves it
        # aside with a timestamp before deploying the manifest-owned entry.
        # A different symlink is derived state and can be safely relinked.
        FORCE=true backup_and_link "$source" "$target"

        if [[ "$LINK_MODE" == "copy" ]]; then
            if _claude_content_matches "$source" "$target"; then
                created=$((created + 1))
            else
                log_warn "failed to copy Claude skill $slot"
                conflicts=$((conflicts + 1))
            fi
        elif [[ -L "$target" && "$(readlink "$target")" == "$source" ]]; then
            created=$((created + 1))
        else
            log_warn "failed to link Claude skill $slot"
            conflicts=$((conflicts + 1))
        fi
    done < "$manifest"

    if (( missing > 0 )); then
        log_warn "$missing skill(s) missing from their source repo — clone or update:"
        log_warn "  $HOME/workspace/agents  (private shared-skill repo)"
        log_warn "  $AGENT_SKILLS_REPO  (github.com/jiunbae/agent-skills)"
    fi

    if (( conflicts > 0 )); then
        log_error "$conflicts skill mapping(s) could not be restored"
        return 1
    fi

    if (( created > 0 )); then
        if [[ "$LINK_MODE" == "copy" ]]; then
            track_installed "Claude skills ($created copied)"
            log_success "Copied $created skill(s), $skipped already in place"
        else
            track_installed "Claude skills ($created linked)"
            log_success "Linked $created skill(s), $skipped already in place"
        fi
    else
        log_info "Claude skills already in place ($skipped)"
        track_skipped "Claude skills"
    fi
}

install_claude_memory() {
    print_section "Setting up Claude Code memory"

    local root_dir
    root_dir=$(get_root_dir)
    # Auto-memory is keyed by the project directory with slashes turned into
    # dashes: $HOME=/home/alice becomes projects/-home-alice.
    local slug="${HOME//\//-}"
    local project_dir="$CLAUDE_HOME/projects/$slug"

    mkdir -p "$project_dir"
    _claude_link "$root_dir/configs/claude/memory" \
                 "$project_dir/memory" "Claude memory"
}

install_claude_mcp() {
    print_section "Registering Claude Code MCP servers"

    if ! command_exists claude; then
        log_warn "claude CLI not found — skipping MCP registration"
        track_skipped "Claude MCP servers (claude CLI absent)"
        return 0
    fi

    local entry name cmd
    for entry in "${CLAUDE_MCP_SERVERS[@]}"; do
        IFS='|' read -r name cmd args <<< "$entry"

        if claude mcp list 2>/dev/null | grep -q "^${name}:"; then
            log_info "MCP server '$name' already registered"
            track_skipped "MCP $name"
            continue
        fi

        if ! command_exists "$cmd"; then
            log_warn "MCP server '$name' needs '$cmd' in PATH — skipping"
            track_skipped "MCP $name ($cmd missing)"
            continue
        fi

        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[DRY-RUN] Would register MCP server: $name ($cmd $args)"
            continue
        fi

        # shellcheck disable=SC2086
        if claude mcp add --scope user "$name" -- "$cmd" $args >/dev/null 2>&1; then
            track_installed "MCP $name"
            log_success "Registered MCP server: $name"
        else
            log_warn "Failed to register MCP server: $name"
        fi
    done
}

# ==============================================================================
# Main Installation
# ==============================================================================

install_claude() {
    log_info "Starting Claude Code configuration..."

    install_claude_hooks || return 1
    install_claude_settings || return 1
    install_claude_skill_index || return 1
    install_claude_skills || return 1
    install_claude_memory || return 1
    install_claude_mcp || return 1

    log_success "Claude Code configuration complete!"
    log_info "Run './install.sh cship' for the statusline it references"
}

# ==============================================================================
# Standalone Execution
# ==============================================================================
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    setup_error_handling
    install_claude
fi
