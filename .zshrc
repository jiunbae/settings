# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# Maydev ZSH Settings
# github.com/jiunbae/settings.git
################################
# Default ZSH
export ZSH=$HOME/.oh-my-zsh

ZSH_THEME="powerlevel10k/powerlevel10k"

export FZF_BASE=/opt/homebrew/opt/fzf
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

setopt PROMPT_SUBST
plugins=(
  git
  zsh-autosuggestions
  zsh-syntax-highlighting
  fzf
  tmux
)
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=7'

source $ZSH/oh-my-zsh.sh

export PATH=$HOME/bin:$HOME/conda/bin:$HOME/.local/bin:$PATH

################################
# OS Based settings
if [[ $(grep microsoft /proc/version) ]]; then
  # wsl settings
  export PATH=/usr/lib/wsl/lib:$PATH
fi
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
    eval "$(/opt/homebrew/bin/brew shellenv)"
   ;;
  Linux)
    # Linux settings
    if [ -z $LD_LIBRARY_PATH ]; then
      LD_LIBRARY_PATH=/usr/local/cuda/lib64:/usr/local/cuda/lib
    else
      LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/usr/local/cuda/lib64:/usr/local/cuda/lib
    fi
    export LD_LIBRARY_PATH
    export PATH=/usr/local/cuda/bin:$PATH
  ;;
esac

################################
# Default Settings
alias gdrive.sh='curl gdrive.sh | bash -s'

alias vim="nvim"
alias vi="nvim"
alias vimdiff="nvim -d"
alias ls="exa"
alias cat="bat"
export EDITOR=/usr/local/bin/nvim

export LC_ALL=en_US.UTF-8  
export LANG=en_US.UTF-8

set -g default-command "reattach-to-user-namespace -l zsh"

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

