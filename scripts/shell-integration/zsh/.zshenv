if [[ -n "${ZDOTDIR:-}" ]]; then
  export DEVHAVEN_SHELL_INTEGRATION_HOME="$ZDOTDIR"
fi

function _devhaven_user_zdotdir() {
  if [[ -n "${DEVHAVEN_RESOLVED_USER_ZDOTDIR:-}" ]]; then
    print -r -- "${DEVHAVEN_RESOLVED_USER_ZDOTDIR}"
    return
  fi
  if [[ -n "${DEVHAVEN_USER_ZDOTDIR:-}" ]]; then
    print -r -- "${DEVHAVEN_USER_ZDOTDIR}"
    return
  fi
  if [[ -n "${HOME:-}" ]]; then
    print -r -- "${HOME}"
  fi
}

function _devhaven_source_user_zsh_file() {
  local _file_name="$1"
  local _user_zdotdir="$(_devhaven_user_zdotdir)"
  [[ -n "${_user_zdotdir:-}" ]] || return 0

  local _target_file="${_user_zdotdir}/${_file_name}"
  [[ -r "${_target_file}" ]] || return 0

  local _restore_target="${DEVHAVEN_SHELL_INTEGRATION_HOME:-}"
  if [[ -z "${_restore_target}" ]]; then
    _restore_target="${ZDOTDIR:-}"
  fi

  export ZDOTDIR="${_user_zdotdir}"
  source "${_target_file}"
  if [[ -n "${ZDOTDIR:-}" && -n "${DEVHAVEN_SHELL_INTEGRATION_HOME:-}" && "${ZDOTDIR}" != "${DEVHAVEN_SHELL_INTEGRATION_HOME}" ]]; then
    export DEVHAVEN_RESOLVED_USER_ZDOTDIR="${ZDOTDIR}"
  fi

  if [[ -n "${_restore_target:-}" ]]; then
    export ZDOTDIR="${_restore_target}"
  else
    unset ZDOTDIR
  fi
}

function _devhaven_finalize_user_shell_state() {
  local _user_zdotdir="$(_devhaven_user_zdotdir)"
  [[ -n "${_user_zdotdir:-}" ]] || return 0

  export ZDOTDIR="${_user_zdotdir}"

  if [[ -z "${HISTFILE:-}" ]]; then
    export HISTFILE="${_user_zdotdir}/.zsh_history"
    return 0
  fi

  if [[ -n "${DEVHAVEN_SHELL_INTEGRATION_HOME:-}" && "${HISTFILE}" == "${DEVHAVEN_SHELL_INTEGRATION_HOME}"/* ]]; then
    export HISTFILE="${_user_zdotdir}/.zsh_history"
  fi
}

_devhaven_source_user_zsh_file ".zshenv"

if [[ -n "${ZDOTDIR:-}" && -n "${DEVHAVEN_SHELL_INTEGRATION_HOME:-}" && "${ZDOTDIR}" != "${DEVHAVEN_SHELL_INTEGRATION_HOME}" ]]; then
  export DEVHAVEN_RESOLVED_USER_ZDOTDIR="${ZDOTDIR}"
fi

if [[ -z "${DEVHAVEN_RESOLVED_USER_ZDOTDIR:-}" ]]; then
  DEVHAVEN_RESOLVED_USER_ZDOTDIR="$(_devhaven_user_zdotdir)"
  export DEVHAVEN_RESOLVED_USER_ZDOTDIR
fi

if [[ -n "${DEVHAVEN_SHELL_INTEGRATION_HOME:-}" ]]; then
  export ZDOTDIR="${DEVHAVEN_SHELL_INTEGRATION_HOME}"
fi

unset _devhaven_user_zdotdir
