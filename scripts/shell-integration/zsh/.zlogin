_devhaven_user_zdotdir="${DEVHAVEN_RESOLVED_USER_ZDOTDIR:-${DEVHAVEN_USER_ZDOTDIR:-}}"
if [[ -n "${_devhaven_user_zdotdir:-}" && -r "${_devhaven_user_zdotdir}/.zlogin" ]]; then
  source "${_devhaven_user_zdotdir}/.zlogin"
fi

if typeset -f _devhaven_restore_zdotdir >/dev/null 2>&1; then
  _devhaven_restore_zdotdir
fi

if [[ -n "${DEVHAVEN_SHELL_INTEGRATION_DIR:-}" && -r "${DEVHAVEN_SHELL_INTEGRATION_DIR}/../devhaven-wrapper-path.sh" ]]; then
  source "${DEVHAVEN_SHELL_INTEGRATION_DIR}/../devhaven-wrapper-path.sh"
fi

unset _devhaven_user_zdotdir
