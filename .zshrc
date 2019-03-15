export ZSH=$HOME/.oh-my-zsh

ZSH_THEME="agnoster"

plugins=(git bower sublime brew history node npm sudo web-search zsh-autosuggestions fast-syntax-highlighting)

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

export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin"

source $ZSH/oh-my-zsh.sh
setopt PROMPT_SUBST

# disable these function if you want to show hostname on zsh
prompt_context() {
  if [[ "$USER" != "$DEFAULT_USER" || -n "$SSH_CLIENT" ]]; then
    prompt_segment black default "%(!.%{%F{yellow}%}.)$USER"
  fi
}

export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8

# alias

# user defined path

