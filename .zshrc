export ZSH=$HOME/.oh-my-zsh

ZSH_THEME="agnoster"

plugins=(git bower sublime brew history node npm sudo web-search)  
plugins=(zsh-autosuggestions)
source ~/.zsh/zsh-autosuggestions/zsh-autosuggestions.zsh

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

export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:$PATH"

source $ZSH/oh-my-zsh.sh
setopt PROMPT_SUBST

export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8

