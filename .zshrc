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
    print -Pn "\xf0\x9f\x90\x8d %F{blue}$(basename $env)"
  fi
}

################################
# Default Settings
export PATH=$PATH:$HOME/.local/bin
alias gdrive.sh='curl gdrive.sh | bash -s'

