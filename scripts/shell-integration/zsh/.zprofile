_devhaven_user_zdotdir="${DEVHAVEN_RESOLVED_USER_ZDOTDIR:-${DEVHAVEN_USER_ZDOTDIR:-}}"
if [[ -n "${_devhaven_user_zdotdir:-}" && -r "${_devhaven_user_zdotdir}/.zprofile" ]]; then
  source "${_devhaven_user_zdotdir}/.zprofile"
fi

if typeset -f _devhaven_restore_zdotdir >/dev/null 2>&1; then
  _devhaven_restore_zdotdir
fi

unset _devhaven_user_zdotdir
