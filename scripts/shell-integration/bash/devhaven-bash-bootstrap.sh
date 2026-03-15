if [ "${DEVHAVEN_WRAPPER_PATH_BOOTSTRAPPED:-0}" != "1" ]; then
  export DEVHAVEN_WRAPPER_PATH_BOOTSTRAPPED=1
fi

if [ -n "${DEVHAVEN_SHELL_INTEGRATION_DIR:-}" ] && [ -r "${DEVHAVEN_SHELL_INTEGRATION_DIR}/devhaven-wrapper-path.sh" ]; then
  . "${DEVHAVEN_SHELL_INTEGRATION_DIR}/devhaven-wrapper-path.sh"
fi

# Keep user shell defaults authoritative: if legacy startup injected
# DevHaven shell-state history path, normalize it back to ~/.bash_history.
if [ -n "${HOME:-}" ] && [ -n "${HISTFILE:-}" ]; then
  _devhaven_default_histfile="${HOME}/.bash_history"
  if [ -n "${DEVHAVEN_SHELL_STATE_DIR:-}" ] && [ "${HISTFILE}" = "${DEVHAVEN_SHELL_STATE_DIR}/.bash_history" ]; then
    export HISTFILE="${_devhaven_default_histfile}"
  elif [ "${HISTFILE}" = "${HOME}/.devhaven/shell-state/bash/.bash_history" ]; then
    export HISTFILE="${_devhaven_default_histfile}"
  fi
  unset _devhaven_default_histfile
fi

if [ -n "${DEVHAVEN_USER_PROMPT_COMMAND:-}" ]; then
  eval "${DEVHAVEN_USER_PROMPT_COMMAND}"
fi
