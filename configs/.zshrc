# Jiun Bae
# ZSH Settings (zinit + Powerlevel10k)
# github.com/jiunbae/settings.git
################################

# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

################################
# Zinit initialization
ZINIT_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}/zinit/zinit.git"

if [[ ! -f "${ZINIT_HOME}/zinit.zsh" ]]; then
  print -P "%F{red}zinit not found.%f Please run the installer or clone it manually:%F{yellow}\n  git clone https://github.com/zdharma-continuum/zinit.git \"$ZINIT_HOME\"%f"
  return 1
fi

source "${ZINIT_HOME}/zinit.zsh"

################################
# Plugins

# Powerlevel10k theme (load immediately)
zinit ice depth=1
zinit light romkatv/powerlevel10k

typeset -U path fpath PATH

# Completion settings (case-insensitive, partial matching)
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}' 'r:|[._-]=* r:|=*' 'l:|=* r:|=*'
zstyle ':completion:*' menu select
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"

[[ -d ~/.grok/completions/zsh ]] && fpath=(~/.grok/completions/zsh $fpath)

# Completions - cached compinit (regenerate once per day)
autoload -Uz compinit
_zcompdump="${XDG_CACHE_HOME:-$HOME/.cache}/.zcompdump"
# Regenerate at most once a day (glob qualifier: plain file, mtime < 24h)
if [[ -n ${_zcompdump}(#qN.mh-24) ]]; then
  compinit -C -d "$_zcompdump"
else
  compinit -i -d "$_zcompdump"
fi
unset _zcompdump _zcompdump_day

# Completion plugins (turbo mode with blockf to track fpath changes)
# Disable ZSH_TMUX_FIXTERM to avoid tmux.extra.conf error
export ZSH_TMUX_FIXTERM=false
zinit wait lucid blockf for \
    zsh-users/zsh-completions \
    OMZP::tmux

# fzf-tab must load after compinit, use atload to replay compdefs
zinit wait lucid atload"zicdreplay" for \
    Aloxaf/fzf-tab

# Other plugins with turbo mode (deferred loading after prompt)
zinit wait lucid for \
    atload"_zsh_autosuggest_start" \
        zsh-users/zsh-autosuggestions \
    z-shell/fast-syntax-highlighting \
    OMZP::git \
    unixorn/git-extra-commands

################################
# Zsh options
setopt PROMPT_SUBST
setopt AUTO_CD
setopt EXTENDED_GLOB        # Extended glob patterns (e.g., ^, ~, #)
setopt NO_CASE_GLOB         # Case-insensitive globbing

# Directory stack (use with cd -<TAB> to see history)
setopt AUTO_PUSHD           # Push directory to stack on cd
setopt PUSHD_IGNORE_DUPS    # No duplicates in stack
setopt PUSHD_SILENT         # Don't print stack after pushd/popd

# History
setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_SPACE
setopt SHARE_HISTORY
setopt EXTENDED_HISTORY     # Save timestamp
setopt HIST_FIND_NO_DUPS    # No duplicates in search
setopt HIST_REDUCE_BLANKS   # Remove extra blanks
setopt INC_APPEND_HISTORY   # Add immediately, not on exit

HISTFILE=~/.zsh_history
HISTSIZE=500000
SAVEHIST=500000

################################
# Key bindings
bindkey -e                            # Emacs mode (Ctrl+A, Ctrl+E, etc.)
WORDCHARS=''                          # Word boundary at special chars (ESC+Backspace)
bindkey '^[[H' beginning-of-line      # Home
bindkey '^[[F' end-of-line            # End
bindkey '^[[3~' delete-char           # Delete
bindkey '^[[1;5C' forward-word        # Ctrl+Right
bindkey '^[[1;5D' backward-word       # Ctrl+Left
bindkey '^[[A' history-search-backward # Up arrow (prefix search)
bindkey '^[[B' history-search-forward  # Down arrow (prefix search)

################################
# Useful aliases
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias -- -='cd -'

# mkdir + cd
mkcd() { mkdir -p "$1" && cd "$1" }

################################
# Autosuggestions config
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=7'

################################
# PATH
export PATH=$HOME/bin:$HOME/.local/bin:$HOME/.scripts:$PATH

################################
# Scoped environment file loader.
# Do not source every ~/.envs/*.env at shell startup; most of those files hold
# secrets that would be inherited by every child process.
_source_env_file() {
  local env_file="$1"
  [[ -f "$env_file" ]] && source "$env_file"
}

################################
# OS Based settings
case `uname` in
  Darwin)
    # macos settings
    alias zaa="arch -arch arm64e /bin/zsh"
    alias zx="arch -arch x86_64 /bin/zsh"
    if [[ $(arch) == "arm64" ]]; then
      export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin:$PATH"
    else
      export PATH="/usr/local/bin:/usr/local/sbin:/opt/homebrew/bin:/opt/homebrew/sbin:$PATH"
    fi
    export PATH="/opt/homebrew/opt/openjdk/bin:$PATH"
    # Homebrew (direct env setup - faster than eval)
    export HOMEBREW_PREFIX="/opt/homebrew"
    export HOMEBREW_CELLAR="/opt/homebrew/Cellar"
    export HOMEBREW_REPOSITORY="/opt/homebrew"
    fpath=("/opt/homebrew/share/zsh/site-functions" $fpath)
    [[ -z "${MANPATH-}" ]] || export MANPATH=":${MANPATH#:}"
    export INFOPATH="/opt/homebrew/share/info:${INFOPATH:-}"
    ;;
  Linux)
    # Linux settings
    if [[ -f /proc/version ]] && grep -q microsoft /proc/version 2>/dev/null; then
      # wsl settings
      export PATH=/usr/lib/wsl/lib:$PATH

      # Docker auto-start for WSL2
      if command -v docker &> /dev/null; then
        if ! pgrep -x "dockerd" > /dev/null; then
          sudo -n service docker start > /dev/null 2>&1 || true
        fi
      fi
    fi

    # CUDA settings
    if [[ -d /usr/local/cuda ]]; then
      if [[ -z "$LD_LIBRARY_PATH" ]]; then
        LD_LIBRARY_PATH=/usr/local/cuda/lib64:/usr/local/cuda/lib
      else
        LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/usr/local/cuda/lib64:/usr/local/cuda/lib
      fi
      export LD_LIBRARY_PATH
      export PATH=/usr/local/cuda/bin:$PATH
    fi
    ;;
esac

################################
# FZF
# Linux manual install: source ~/.fzf.zsh first (adds ~/.fzf/bin to PATH)
if [[ -f ~/.fzf.zsh ]]; then
  source ~/.fzf.zsh
# macOS with Homebrew (Apple Silicon)
elif [[ -f /opt/homebrew/opt/fzf/shell/completion.zsh ]]; then
  source /opt/homebrew/opt/fzf/shell/completion.zsh
  source /opt/homebrew/opt/fzf/shell/key-bindings.zsh
# macOS with Homebrew (Intel)
elif [[ -f /usr/local/opt/fzf/shell/completion.zsh ]]; then
  source /usr/local/opt/fzf/shell/completion.zsh
  source /usr/local/opt/fzf/shell/key-bindings.zsh
# Linux system package
elif [[ -f /usr/share/fzf/completion.zsh ]]; then
  source /usr/share/fzf/completion.zsh
  source /usr/share/fzf/key-bindings.zsh
fi

################################
# Alias
alias vim="nvim"
alias vi="nvim"
alias vimdiff="nvim -d"

# Keep exact-path Codex trust in sync with disposable workspace-agent clones.
codex() {
  if [[ "$PWD" == "$HOME/workspace-agent" || "$PWD" == "$HOME/workspace-agent/"* ]]; then
    "$HOME/.local/bin/codex-workspace-trust-sync" "$PWD" || return
  fi
  command codex "$@"
}

alias cx="codex --yolo"
alias c="claude --dangerously-skip-permissions"
alias oc="opencode"

# Zellij (terminal multiplexer)
alias zs='zellij -s'
alias za='zellij attach'
alias zl='zellij list-sessions'
unalias zx 2>/dev/null
zx() {
  if [[ -z "$1" ]]; then
    echo "Usage: zx <session-name>"
    zellij list-sessions 2>/dev/null
    return 1
  fi
  local removed=0
  zellij kill-session "$1" 2>/dev/null && removed=1
  zellij delete-session "$1" 2>/dev/null && removed=1
  # Kill orphaned server process that ignores kill-session
  local pid
  pid=$(command ps ax -o pid=,args= | command grep "[z]ellij --server.*/$1\$" | awk '{print $1}')
  if [[ -n "$pid" ]]; then
    kill -9 "$pid" 2>/dev/null && removed=1
  fi
  if (( removed )); then
    echo "Session '$1' removed."
  else
    echo "Session '$1' not found."
    return 1
  fi
}
alias zda='zellij delete-all-sessions'
alias zq='zellij kill-all-sessions'
_zellij_sessions() { compadd $(zellij list-sessions 2>/dev/null | command grep -oE '^\S+') }
compdef _zellij_sessions za zs zx zd
export EDITOR=nvim
export GPG_TTY=$(tty)
gpg-connect-agent updatestartuptty /bye >/dev/null 2>&1

export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

################################
# Rust/Cargo (must be before Modern CLI Tools for eza, fd, rg, etc.)
[ -f "$HOME/.cargo/env" ] && source "$HOME/.cargo/env"

################################
# Modern CLI Tools (using $+commands for faster lookup)
## eza (ls replacement)
if (( $+commands[eza] )); then
  alias ls='eza --icons'
  alias ll='eza -la --icons --git'
  alias la='eza -a --icons'
  alias lt='eza -T --icons'
fi

## fd (find replacement)
(( $+commands[fd] )) && alias find='fd'

## ripgrep (grep replacement)
(( $+commands[rg] )) && alias grep='rg'

## delta (git diff)
(( $+commands[delta] )) && export GIT_PAGER='delta'

## dust (du replacement)
(( $+commands[dust] )) && alias du='dust'

## procs (ps replacement)
(( $+commands[procs] )) && alias ps='procs'

## bottom (htop replacement)
if (( $+commands[btm] )); then
  alias top='btm'
  alias htop='btm'
fi

################################
# Node.js (NVM) - Lazy loading for faster shell startup
export NVM_DIR="$HOME/.nvm"

# Lazy load nvm - only load when node/npm/npx/nvm commands are first used
if [[ -s "$NVM_DIR/nvm.sh" ]]; then
  # Add node to PATH for immediate availability (uses default version if set via `nvm alias default`)
  if [[ -f "$NVM_DIR/alias/default" ]]; then
    nvm_default_alias=$(<"$NVM_DIR/alias/default")
    # Resolve alias to actual version directory (e.g., "22" -> "v22.13.1")
    _nvm_dirs=("$NVM_DIR"/versions/node/v${nvm_default_alias}*(N))
    [[ -n "${_nvm_dirs[1]}" ]] && PATH="${_nvm_dirs[1]}/bin:$PATH"
    unset _nvm_dirs
  fi

  _nvm_lazy_load() {
    unfunction _nvm_lazy_load node npm npx pnpm nvm 2>/dev/null
    source "$NVM_DIR/nvm.sh"
  }

  node() { _nvm_lazy_load; command node "$@" }
  npm() { _nvm_lazy_load; command npm "$@" }
  npx() { _nvm_lazy_load; command npx "$@" }
  pnpm() { _nvm_lazy_load; command pnpm "$@" }
  nvm() { _nvm_lazy_load; nvm "$@" }
  tsx() { _nvm_lazy_load; command tsx "$@" }
fi
# NOTE: homebrew 기본 nvm 스니펫(아래)은 매 시작마다 nvm.sh 를 즉시 source 하여
# 위 lazy-load 를 무력화하고 시작 시간을 ~2초 늘렸기에 제거함 (2026-06-25).
# nvm completion 은 `nvm` 최초 사용 시 nvm.sh 와 함께 로드됨.

################################
# uv (Python package manager) - cached completion
if (( $+commands[uv] )); then
  _uv_comp="${XDG_CACHE_HOME:-$HOME/.cache}/.uv-completion.zsh"
  # Check if regeneration needed (once per day)
  _uv_regen=1
  [[ -n ${_uv_comp}(#qN.mh-24) ]] && _uv_regen=0
  if (( _uv_regen )); then
    uv generate-shell-completion zsh > "$_uv_comp" 2>/dev/null
  fi
  [[ -f "$_uv_comp" ]] && source "$_uv_comp"
  unset _uv_comp _uv_comp_day _uv_regen
fi


################################
# agt (agent skills CLI) - cached completion
if (( $+commands[agt] )); then
  _agt_comp="${XDG_CACHE_HOME:-$HOME/.cache}/.agt-completion.zsh"
  _agt_regen=1
  [[ -n ${_agt_comp}(#qN.mh-24) ]] && _agt_regen=0
  if (( _agt_regen )); then
    agt completions zsh > "$_agt_comp" 2>/dev/null
  fi
  [[ -f "$_agt_comp" ]] && source "$_agt_comp"
  unset _agt_comp _agt_comp_day _agt_regen
fi


[[ -f "$HOME/.local/bin/env" ]] && . "$HOME/.local/bin/env"

################################
# Bun
export BUN_INSTALL="$HOME/.bun"
[[ -d "$BUN_INSTALL" ]] && {
  export PATH="$BUN_INSTALL/bin:$PATH"
  [[ -s "$BUN_INSTALL/_bun" ]] && source "$BUN_INSTALL/_bun"
}

################################
# OpenCode
[[ -d "$HOME/.opencode/bin" ]] && export PATH="$HOME/.opencode/bin:$PATH"

################################
# hishtory (better shell history)
# Configure via ~/.envs/hishtory.env:
#   HISHTORY_SERVER="https://hishtory.example.com"
#   HISHTORY_SECRET="your-secret-key"
# Without these, hishtory runs in local-only mode
_source_env_file "$HOME/.envs/hishtory.env"
if [[ -f "$HOME/.hishtory/hishtory" ]] || (( $+commands[hishtory] )); then
  [[ -f "$HOME/.hishtory/hishtory" ]] && export PATH="$HOME/.hishtory:$PATH"
  # Auto-init with secret if configured but not yet initialized
  if [[ -n "$HISHTORY_SECRET" && ! -f "$HOME/.hishtory/.hishtory.db" ]]; then
    (hishtory init "$HISHTORY_SECRET" &>/dev/null &)
  fi
  # Record history: two-phase capture
  # Phase 1: After Enter, before execution (captures command)
  _hishtory_addhistory() {
    _hishtory_cmd="$1"
    _hishtory_start=$(date +%s%N)
    (hishtory presaveHistoryEntry zsh "$_hishtory_cmd" &>/dev/null &)
  }
  [[ -z "${zshaddhistory_functions[(r)_hishtory_addhistory]}" ]] && zshaddhistory_functions+=(_hishtory_addhistory)
  # Phase 2: After execution (captures exit code)
  _hishtory_precmd() {
    local exit_code=$?
    [[ -n "$_hishtory_cmd" ]] && (hishtory saveHistoryEntry zsh $exit_code "$_hishtory_cmd" "$_hishtory_start" &>/dev/null &)
    unset _hishtory_cmd _hishtory_start
  }
  [[ -z "${precmd_functions[(r)_hishtory_precmd]}" ]] && precmd_functions+=(_hishtory_precmd)
  # Ctrl+R binding for interactive search
  _hishtory_search() {
    BUFFER="$(HISHTORY_TERM_INTEGRATION=1 hishtory tquery "$BUFFER")"
    CURSOR=${#BUFFER}
    zle reset-prompt
  }
  zle -N _hishtory_search
  bindkey '^R' _hishtory_search
fi

# Bitwarden session helper. Keep BW_SESSION out of the global shell env so
# arbitrary child processes cannot unlock the vault via inherited variables.
bw_with_session() {
  local session
  session="$(cat "$HOME/.bw_session" 2>/dev/null)" || return 1
  BW_SESSION="$session" command bw "$@"
}
alias bwx='bw_with_session'

# pnpm
export PNPM_HOME="${PNPM_HOME:-$HOME/.local/share/pnpm}"
case ":$PATH:" in
  *":$PNPM_HOME:"*) ;;
  *) export PATH="$PNPM_HOME:$PATH" ;;
esac

if [[ "$(uname)" == "Darwin" ]]; then
  export AWS_VAULT_BACKEND=keychain
else
  export AWS_VAULT_BACKEND=file
fi

# Warm gpg-agent cache so signing works in headless contexts
[ -r "$HOME/.gnupg/passphrase" ] && gpg --pinentry-mode loopback --passphrase-file "$HOME/.gnupg/passphrase" --batch --sign </dev/null >/dev/null 2>&1 &!

# Kimi K3 (Kimi Code subscription) — https://www.kimi.com/code/docs/en/third-party-tools/claude-code.html
claude_with_kimi_env() {
    [[ -f "$HOME/.envs/kimi.env" ]] && source "$HOME/.envs/kimi.env"
    if [[ -z "${KIMI_K3_TOKEN}" ]]; then
        echo "KIMI_K3_TOKEN is not set (expected in ~/.envs/kimi.env)." >&2
        echo "Create a key at https://www.kimi.com/code (Kimi Code Console)." >&2
        return 1
    fi
    local _model="${KIMI_MODEL:-k3[1m]}"
    local _ctx="${KIMI_CONTEXT_TOKENS:-1048576}"
    BASH_ENV="" \
    ENV="" \
    ANTHROPIC_BASE_URL="${KIMI_BASE_URL:-https://api.kimi.com/coding/}" \
    ANTHROPIC_API_KEY="" \
    CLAUDE_CODE_OAUTH_TOKEN="" \
    ANTHROPIC_AUTH_TOKEN="${KIMI_K3_TOKEN}" \
    ANTHROPIC_MODEL="${_model}" \
    ANTHROPIC_DEFAULT_FABLE_MODEL="${_model}" \
    ANTHROPIC_DEFAULT_OPUS_MODEL="${_model}" \
    ANTHROPIC_DEFAULT_SONNET_MODEL="${_model}" \
    ANTHROPIC_DEFAULT_HAIKU_MODEL="${_model}" \
    CLAUDE_CODE_SUBAGENT_MODEL="${_model}" \
    CLAUDE_CODE_EFFORT_LEVEL="high" \
    CLAUDE_CODE_AUTO_COMPACT_WINDOW="${_ctx}" \
    CLAUDE_CODE_MAX_CONTEXT_TOKENS="${_ctx}" \
    API_TIMEOUT_MS="3000000" \
    command claude --dangerously-skip-permissions "$@"
}
unalias cmk 2>/dev/null
alias cck='claude_with_kimi_env'

# GLM (Anthropic-compatible internal proxy)
claude_with_glm_env() {
    [[ -f "$HOME/.envs/glm.env" ]] && source "$HOME/.envs/glm.env"
    if [[ -z "${GLM_AUTH_TOKEN}" || -z "${GLM_BASE_URL}" ]]; then
        echo "GLM_AUTH_TOKEN and GLM_BASE_URL must be set in ~/.envs/glm.env." >&2
        return 1
    fi
    local _model="${GLM_MODEL:-glm-5.2-superglm}"
    local _ctx="${GLM_CONTEXT_TOKENS:-262144}"
    command env \
        BASH_ENV="" \
        ENV="" \
        ANTHROPIC_BASE_URL="${GLM_BASE_URL}" \
        ANTHROPIC_API_KEY="" \
        CLAUDE_CODE_OAUTH_TOKEN="" \
        ANTHROPIC_AUTH_TOKEN="${GLM_AUTH_TOKEN}" \
        API_TIMEOUT_MS="3000000" \
        ANTHROPIC_MODEL="${_model}" \
        ANTHROPIC_DEFAULT_FABLE_MODEL="${_model}" \
        ANTHROPIC_DEFAULT_OPUS_MODEL="${_model}" \
        ANTHROPIC_DEFAULT_SONNET_MODEL="${_model}" \
        ANTHROPIC_DEFAULT_HAIKU_MODEL="${_model}" \
        CLAUDE_CODE_SUBAGENT_MODEL="${_model}" \
        CLAUDE_CODE_AUTO_COMPACT_WINDOW="${_ctx}" \
        CLAUDE_CODE_MAX_CONTEXT_TOKENS="${_ctx}" \
        claude --dangerously-skip-permissions \
        --append-system-prompt "This Claude Code session uses the API backend model ${_model}. If asked for your model name or identity, report the API model identifier ${_model}; do not claim to be Claude Fable." \
        "$@"
}
unalias cglm ccm 2>/dev/null
unfunction claude_with_motif_env 2>/dev/null
alias ccg='claude_with_glm_env'

# >>> muxa managed (muxad-shellrc) >>>
# Auto-start muxad if it isn't running. Generated by `muxa init`.
# Backgrounded: the daemon start does not need to block the prompt.
if command -v muxa >/dev/null 2>&1; then
  ( muxa daemon start --quiet >/dev/null 2>&1 & ) >/dev/null 2>&1
fi
# <<< muxa managed (muxad-shellrc) <<<

# >>> tmux-deathwatch >>>
# Forensic watchdog: snapshots context when the tmux server dies.
# (core dumps impossible in this container — see script header.)
# The script self-guards with flock, so no pgrep probe is needed here; the
# probe cost ~110ms per shell because this box runs ~1900 processes.
# Remove: delete ~/.local/bin/tmux-deathwatch.sh + this block, then
#         `pkill -f tmux-deathwatch.sh`.
if [ -x "$HOME/.local/bin/tmux-deathwatch.sh" ]; then
  ( nohup "$HOME/.local/bin/tmux-deathwatch.sh" >/dev/null 2>&1 & ) >/dev/null 2>&1
fi
# <<< tmux-deathwatch <<<

# ── rbenv (Ruby version manager) ──
# `rbenv init` is not needed: p10k only tests $commands[rbenv], and the workspace
# tooling that needs Ruby prepends the shims dir itself. Shims on PATH is enough.
export PATH="$HOME/.rbenv/bin:$HOME/.rbenv/shims:$PATH"

# >>> grok installer >>>
# fpath for _grok is set above, before compinit, so the completion registers.
export PATH="$HOME/.grok/bin:$PATH"
# <<< grok installer <<<

################################
# Machine-local additions. This file is a symlink into a PUBLIC repo, so anything
# work-specific — and anything an installer wants to append — belongs here instead.
[[ -f ~/.zshrc.local ]] && source ~/.zshrc.local
