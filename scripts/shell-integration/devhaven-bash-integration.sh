if [ -n "${DEVHAVEN_SHELL_INTEGRATION_DIR:-}" ] && [ -r "${DEVHAVEN_SHELL_INTEGRATION_DIR}/bash/devhaven-bash-bootstrap.sh" ]; then
  . "${DEVHAVEN_SHELL_INTEGRATION_DIR}/bash/devhaven-bash-bootstrap.sh"
elif [ -n "${DEVHAVEN_SHELL_INTEGRATION_DIR:-}" ] && [ -r "${DEVHAVEN_SHELL_INTEGRATION_DIR}/devhaven-wrapper-path.sh" ]; then
  . "${DEVHAVEN_SHELL_INTEGRATION_DIR}/devhaven-wrapper-path.sh"
fi
