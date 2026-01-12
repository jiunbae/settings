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

# Completion settings (case-insensitive, partial matching)
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}' 'r:|[._-]=* r:|=*' 'l:|=* r:|=*'
zstyle ':completion:*' menu select
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"

# Completions - cached compinit (regenerate once per day)
autoload -Uz compinit
_zcompdump="${XDG_CACHE_HOME:-$HOME/.cache}/.zcompdump"
if [[ -f "$_zcompdump" && $(date +'%j') == $(stat -f '%Sm' -t '%j' "$_zcompdump" 2>/dev/null || stat -c '%y' "$_zcompdump" 2>/dev/null | cut -d- -f2) ]]; then
  compinit -C -d "$_zcompdump"
else
  compinit -i -d "$_zcompdump"
fi
unset _zcompdump

# Completion plugins (turbo mode with blockf to track fpath changes)
zinit wait lucid blockf for \
    zsh-users/zsh-completions \
    OMZP::tmux

# fzf-tab must load after compinit, use atload to replay compdefs
zinit wait lucid atload"zicompinit; zicdreplay" for \
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
# Load environment files from ~/.envs
# Store secrets in ~/.envs/*.env (not tracked by git)
if [[ -d "$HOME/.envs" ]]; then
  for env_file in "$HOME/.envs"/*.env(N); do
    [[ -f "$env_file" ]] && source "$env_file"
  done
fi

################################
# OS Based settings
case `uname` in
  Darwin)
    # macos settings
    alias za="arch -arch arm64e /bin/zsh"
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
if (( $+commands[fzf] )); then
  # macOS with Homebrew (Apple Silicon)
  if [[ -f /opt/homebrew/opt/fzf/shell/completion.zsh ]]; then
    source /opt/homebrew/opt/fzf/shell/completion.zsh
    source /opt/homebrew/opt/fzf/shell/key-bindings.zsh
  # macOS with Homebrew (Intel)
  elif [[ -f /usr/local/opt/fzf/shell/completion.zsh ]]; then
    source /usr/local/opt/fzf/shell/completion.zsh
    source /usr/local/opt/fzf/shell/key-bindings.zsh
  # Linux or manual install
  elif [[ -f ~/.fzf.zsh ]]; then
    source ~/.fzf.zsh
  elif [[ -f /usr/share/fzf/completion.zsh ]]; then
    source /usr/share/fzf/completion.zsh
    source /usr/share/fzf/key-bindings.zsh
  fi
fi

################################
# Alias
alias vim="nvim"
alias vi="nvim"
alias vimdiff="nvim -d"
alias c="claude --dangerously-skip-permissions"
alias oc="opencode"
export EDITOR=nvim
export GPG_TTY=$(tty)

export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

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
# Rust/Cargo
[ -f "$HOME/.cargo/env" ] && source "$HOME/.cargo/env"

################################
# Node.js (NVM) - Lazy loading for faster shell startup
export NVM_DIR="$HOME/.nvm"

# Lazy load nvm - only load when node/npm/npx/nvm commands are first used
if [[ -s "$NVM_DIR/nvm.sh" ]]; then
  # Add node to PATH for immediate availability (uses default version if set via `nvm alias default`)
  if [[ -f "$NVM_DIR/alias/default" ]]; then
    nvm_default_version=$(<"$NVM_DIR/alias/default")
    nvm_default_path="$NVM_DIR/versions/node/$nvm_default_version/bin"
    [[ -d "$nvm_default_path" ]] && PATH="$nvm_default_path:$PATH"
  fi

  _nvm_lazy_load() {
    unfunction _nvm_lazy_load node npm npx nvm 2>/dev/null
    source "$NVM_DIR/nvm.sh"
  }

  node() { _nvm_lazy_load; command node "$@" }
  npm() { _nvm_lazy_load; command npm "$@" }
  npx() { _nvm_lazy_load; command npx "$@" }
  nvm() { _nvm_lazy_load; nvm "$@" }
fi

################################
# uv (Python package manager) - cached completion
if (( $+commands[uv] )); then
  _uv_comp="${XDG_CACHE_HOME:-$HOME/.cache}/.uv-completion.zsh"
  if [[ ! -f "$_uv_comp" || $(date +'%j') != $(stat -f '%Sm' -t '%j' "$_uv_comp" 2>/dev/null) ]]; then
    uv generate-shell-completion zsh > "$_uv_comp" 2>/dev/null
  fi
  [[ -f "$_uv_comp" ]] && source "$_uv_comp"
  unset _uv_comp
fi

[[ -f "$HOME/.local/bin/env" ]] && . "$HOME/.local/bin/env"

# opencode
export PATH=${HOME}/.opencode/bin:$PATH

# opencode
export PATH=${HOME}/.opencode/bin:$PATH

# bun completions
[ -s "${HOME}/.bun/_bun" ] && source "${HOME}/.bun/_bun"

# bun
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"

################################
# hishtory (better shell history)
# Configure via ~/.envs/hishtory.env:
#   HISHTORY_SERVER="https://hishtory.example.com"
#   HISHTORY_SECRET="your-secret-key"
# Without these, hishtory runs in local-only mode
if [[ -f "$HOME/.hishtory/hishtory" ]] || (( $+commands[hishtory] )); then
  [[ -f "$HOME/.hishtory/hishtory" ]] && export PATH="$HOME/.hishtory:$PATH"
  # Auto-init with secret if configured but not yet initialized
  if [[ -n "$HISHTORY_SECRET" && ! -f "$HOME/.hishtory/.hishtory.db" ]]; then
    (hishtory init "$HISHTORY_SECRET" &>/dev/null &)
  fi
  # Shell hooks for recording history
  __hishtory_preexec() {
    (hishtory saveHistoryEntry zsh "${1:-}" &>/dev/null &)
  }
  [[ -z "${preexec_functions[(r)__hishtory_preexec]}" ]] && preexec_functions+=(__hishtory_preexec)
  # Ctrl+R binding for interactive search
  _hishtory_tquery() {
    BUFFER=$(hishtory tquery "$BUFFER" 2>/dev/null) || true
    CURSOR=${#BUFFER}
    zle redisplay
  }
  zle -N _hishtory_tquery
  bindkey '^R' _hishtory_tquery
fi
