if [[ -n "${ZDOTDIR:-}" ]]; then
  export DEVHAVEN_SHELL_INTEGRATION_HOME="$ZDOTDIR"
fi

function _devhaven_restore_zdotdir() {
  if [[ -n "${ZDOTDIR:-}" && -n "${DEVHAVEN_SHELL_INTEGRATION_HOME:-}" && "$ZDOTDIR" != "$DEVHAVEN_SHELL_INTEGRATION_HOME" ]]; then
    export DEVHAVEN_RESOLVED_USER_ZDOTDIR="$ZDOTDIR"
  fi
  if [[ -n "${DEVHAVEN_SHELL_INTEGRATION_HOME:-}" ]]; then
    export ZDOTDIR="$DEVHAVEN_SHELL_INTEGRATION_HOME"
  fi
}

if [[ -n "${DEVHAVEN_USER_ZDOTDIR:-}" && -r "${DEVHAVEN_USER_ZDOTDIR}/.zshenv" ]]; then
  source "${DEVHAVEN_USER_ZDOTDIR}/.zshenv"
fi

_devhaven_restore_zdotdir
