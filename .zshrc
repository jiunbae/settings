# Maydev ZSH Settings
# github.com/MaybeS/settings.git
############################3###
# Default PATH

export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin"

ZSH_THEME="agnoster"

export ZSH=$HOME/.oh-my-zsh
source $ZSH/oh-my-zsh.sh
setopt PROMPT_SUBST

plugins=(git zsh-autosuggestions fast-syntax-highlighting)
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=7'

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

export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8

##################
# User Custom Path

