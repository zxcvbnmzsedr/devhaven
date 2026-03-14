if [ -n "${DEVHAVEN_SHELL_INTEGRATION_DIR:-}" ] && [ -r "${DEVHAVEN_SHELL_INTEGRATION_DIR}/devhaven-wrapper-path.sh" ]; then
  . "${DEVHAVEN_SHELL_INTEGRATION_DIR}/devhaven-wrapper-path.sh"
fi
