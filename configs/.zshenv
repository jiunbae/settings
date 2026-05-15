. "$HOME/.cargo/env"

# nvm node default on PATH for non-interactive zsh — .zshrc only loads on interactive shells,
# so child processes (callabo-set, Claude Code Bash tool, etc.) miss pnpm/node otherwise.
# Full nvm lazy-load stays in .zshrc; this is the minimum so `which pnpm` resolves.
export NVM_DIR="$HOME/.nvm"
if [[ -f "$NVM_DIR/alias/default" ]]; then
  _nvm_default_alias=$(<"$NVM_DIR/alias/default")
  _nvm_dirs=("$NVM_DIR"/versions/node/v${_nvm_default_alias}*(N))
  [[ -n "${_nvm_dirs[1]}" ]] && PATH="${_nvm_dirs[1]}/bin:$PATH"
  unset _nvm_dirs _nvm_default_alias
fi
