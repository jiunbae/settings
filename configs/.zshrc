# Jiun Bae
# ZSH Settings
# github.com/jiunbae/settings.git
################################
# Default ZSH
export ZSH=$HOME/.oh-my-zsh

ZSH_THEME="powerlevel10k/powerlevel10k"

setopt PROMPT_SUBST
plugins=(
  git
  git-extra-commands
  zsh-autosuggestions
  zsh-syntax-highlighting
  fzf
  tmux
)
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=7'

source $ZSH/oh-my-zsh.sh

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
      export FZF_BASE=/opt/homebrew/opt/fzf
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

    # FZF
    [ -f ~/.fzf.zsh ] && source ~/.fzf.zsh
    ;;
esac

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
# Node.js (NVM)
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

################################
# uv (Python package manager)
export PATH="$HOME/.local/bin:$PATH"
if command -v uv &> /dev/null; then
  eval "$(uv generate-shell-completion zsh 2>/dev/null)" || true
fi

[[ -f "$HOME/.local/bin/env" ]] && . "$HOME/.local/bin/env"

# opencode
export PATH=/Users/jiun/.opencode/bin:$PATH
