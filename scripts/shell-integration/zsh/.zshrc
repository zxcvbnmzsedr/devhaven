if typeset -f _devhaven_source_user_zsh_file >/dev/null 2>&1; then
  _devhaven_source_user_zsh_file ".zshrc"
else
  _devhaven_user_zdotdir="${DEVHAVEN_RESOLVED_USER_ZDOTDIR:-${DEVHAVEN_USER_ZDOTDIR:-}}"
  if [[ -n "${_devhaven_user_zdotdir:-}" && -r "${_devhaven_user_zdotdir}/.zshrc" ]]; then
    source "${_devhaven_user_zdotdir}/.zshrc"
  fi
fi

if [[ -n "${DEVHAVEN_SHELL_INTEGRATION_DIR:-}" && -r "${DEVHAVEN_SHELL_INTEGRATION_DIR}/devhaven-zsh-bootstrap.zsh" ]]; then
  source "${DEVHAVEN_SHELL_INTEGRATION_DIR}/devhaven-zsh-bootstrap.zsh"
  _devhaven_run_zsh_bootstrap
fi

unset _devhaven_user_zdotdir
