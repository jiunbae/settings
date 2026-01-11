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
  print -P "%F{red}zinit not found.%f Please run the installer or clone it manually:%F{yellow}\n  git clone https://github.com/zinit-zsh/zinit.git \"$ZINIT_HOME\"%f"
  return 1
fi

source "${ZINIT_HOME}/zinit.zsh"

################################
# Plugins

# Powerlevel10k theme (load immediately)
zinit ice depth=1
zinit light romkatv/powerlevel10k

# Completions - fast init (skip security check)
autoload -Uz compinit
compinit -i -d "${XDG_CACHE_HOME:-$HOME/.cache}/.zcompdump"

# Plugins with turbo mode (deferred loading)
zinit wait lucid for \
    atload"_zsh_autosuggest_start" \
        zsh-users/zsh-autosuggestions \
    blockf atpull'zinit creinstall -q .' \
        zsh-users/zsh-completions \
    zdharma-continuum/fast-syntax-highlighting \
    Aloxaf/fzf-tab \
    OMZP::git \
    unixorn/git-extra-commands \
    OMZP::tmux

################################
# Zsh options
setopt PROMPT_SUBST
setopt AUTO_CD
setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_SPACE
setopt SHARE_HISTORY

# History
HISTFILE=~/.zsh_history
HISTSIZE=10000
SAVEHIST=10000

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
    # Homebrew
    if [[ -x /opt/homebrew/bin/brew ]]; then
      eval "$(/opt/homebrew/bin/brew shellenv)"
    fi
    ;;
  Linux)
    # Linux settings
    if [[ -f /proc/version ]] && grep -q microsoft /proc/version 2>/dev/null; then
      # wsl settings
      export PATH=/usr/lib/wsl/lib:$PATH
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
if command -v fzf &> /dev/null; then
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
# Modern CLI Tools
## eza (ls replacement)
if command -v eza &> /dev/null; then
  alias ls='eza --icons'
  alias ll='eza -la --icons --git'
  alias la='eza -a --icons'
  alias lt='eza -T --icons'
fi

## fd (find replacement)
if command -v fd &> /dev/null; then
  alias find='fd'
fi

## ripgrep (grep replacement)
if command -v rg &> /dev/null; then
  alias grep='rg'
fi

## delta (git diff)
if command -v delta &> /dev/null; then
  export GIT_PAGER='delta'
fi

## dust (du replacement)
if command -v dust &> /dev/null; then
  alias du='dust'
fi

## procs (ps replacement)
if command -v procs &> /dev/null; then
  alias ps='procs'
fi

## bottom (htop replacement)
if command -v btm &> /dev/null; then
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

  node() { _nvm_lazy_load; node "$@" }
  npm() { _nvm_lazy_load; npm "$@" }
  npx() { _nvm_lazy_load; npx "$@" }
  nvm() { _nvm_lazy_load; nvm "$@" }
fi

################################
# uv (Python package manager)
export PATH="$HOME/.local/bin:$PATH"
if command -v uv &> /dev/null; then
  eval "$(uv generate-shell-completion zsh 2>/dev/null)" || true
fi

[[ -f "$HOME/.local/bin/env" ]] && . "$HOME/.local/bin/env"

# opencode
export PATH=/Users/jiun/.opencode/bin:$PATH
