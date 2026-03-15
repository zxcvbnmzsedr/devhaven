function _devhaven_run_zsh_bootstrap() {
  if [[ -n "${DEVHAVEN_SHELL_INTEGRATION_DIR:-}" && -r "${DEVHAVEN_SHELL_INTEGRATION_DIR}/../devhaven-wrapper-path.sh" ]]; then
    source "${DEVHAVEN_SHELL_INTEGRATION_DIR}/../devhaven-wrapper-path.sh"
  fi

  if typeset -f _devhaven_finalize_user_shell_state >/dev/null 2>&1; then
    if [[ "${1:-}" == "login" || ! -o login ]]; then
      _devhaven_finalize_user_shell_state
    fi
  fi
}
