if typeset -f _devhaven_source_user_zsh_file >/dev/null 2>&1; then
  _devhaven_source_user_zsh_file ".zprofile"
else
  _devhaven_user_zdotdir="${DEVHAVEN_RESOLVED_USER_ZDOTDIR:-${DEVHAVEN_USER_ZDOTDIR:-}}"
  if [[ -n "${_devhaven_user_zdotdir:-}" && -r "${_devhaven_user_zdotdir}/.zprofile" ]]; then
    source "${_devhaven_user_zdotdir}/.zprofile"
  fi
fi

unset _devhaven_user_zdotdir
