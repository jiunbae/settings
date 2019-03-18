# Maydev ZSH Settings
# github.com/MaybeS/settings.git
################################
# Default ZSH
export ZSH=$HOME/.oh-my-zsh

ZSH_THEME="agnoster"

setopt PROMPT_SUBST
plugins=(git zsh-autosuggestions fast-syntax-highlighting)
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=7'

source $ZSH/oh-my-zsh.sh

# show timer
function preexec() {
  timer=${timer:-$SECONDS}
}

function precmd() {
  if [ $timer ]; then
    timer_show=$(($SECONDS - $timer))
    export RPROMPT="%F{cyan}${timer_show}s %{$reset_color%}"
    unset timer
  fi
}

# disable hostname
prompt_context() {
  if [[ "$USER" != "$DEFAULT_USER" || -n "$SSH_CLIENT" ]]; then
    prompt_segment black default "%(!.%{%F{yellow}%}.)$USER"
  fi
}

################################
# Default Settings
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin"

export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8

################################
# Conda Path
export CONDA_HOME=$HOME/conda
export PATH=$CONDA_HOME/bin:$PATH

################################
# CUDA Path
export CUDA_HOME=/usr/local/cuda
export PATH=$CUDA_HOME/bin:$PATH
export LD_LIBRARY_PATH=$CUDA_HOME/lib64:LD_LIBRARY_PATH

################################
# User Custom Path
alias top=htop
alias cat=bat

alias gcc=gcc-8
alias g++=g++-8

