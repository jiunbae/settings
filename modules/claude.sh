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
#   ~/.claude/skills/  the 46 skills are symlinks into the agents repos; see
#                      the skill-index skill for the layout.
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

_claude_link() {
    local source=$1 target=$2 label=$3

    if [[ ! -e "$source" ]]; then
        log_error "$label source missing: $source"
        return 1
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

install_claude_memory() {
    print_section "Setting up Claude Code memory"

    local root_dir
    root_dir=$(get_root_dir)
    # Auto-memory is keyed by the project directory with slashes turned into
    # dashes: $HOME=/home/june becomes projects/-home-june.
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
