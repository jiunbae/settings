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

# Disable hostname
prompt_context() {
  if [[ "$USER" != "$DEFAULT_USER" || -n "$SSH_CLIENT" ]]; then
    prompt_segment black default "%(!.%{%F{yellow}%}.)$USER"
  fi
}

# Display Virtual Environment
prompt_virtualenv() {
  local env='base';

  if [[ -n "$CONDA_DEFAULT_ENV" ]]; then
    env="$CONDA_DEFAULT_ENV"
  elif [[ -n "$VIRTUAL_ENV" ]]; then
    env="$VIRTUAL_ENV"
  fi

  if [[ -n $env ]]; then
    prompt_segment white $PRIMARY_FG
    print -Pn "\xf0\x9f\x90\x8d $(basename $env)"
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

# >>> conda initialize >>>
# !! Contents within this block are managed by 'conda init' !!
__conda_setup="$('$CONDA_HOME/bin/conda' 'shell.zsh' 'hook' 2> /dev/null)"
if [ $? -eq 0 ]; then
    eval "$__conda_setup"
else
    if [ -f "$CONDA_HOME/etc/profile.d/conda.sh" ]; then
        . "$CONDA_HOME/etc/profile.d/conda.sh"
    else
        export PATH="$CONDA_HOME/bin:$PATH"
    fi
fi
unset __conda_setup
# <<< conda initialize <<<

################################
# CUDA Path
export CUDA_HOME=/usr/local/cuda
export PATH=$CUDA_HOME/bin:$PATH
export LD_LIBRARY_PATH=$CUDA_HOME/lib64:LD_LIBRARY_PATH

################################
# User Custom Path
alias top=htop
alias vim=nvim

export server1=166.104.110.143
export server2=166.104.110.144

