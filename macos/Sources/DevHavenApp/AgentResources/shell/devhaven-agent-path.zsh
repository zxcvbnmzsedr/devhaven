if [[ -z "${DEVHAVEN_AGENT_BIN_DIR:-}" && -n "${DEVHAVEN_AGENT_RESOURCES_DIR:-}" ]]; then
  export DEVHAVEN_AGENT_BIN_DIR="${DEVHAVEN_AGENT_RESOURCES_DIR}/bin"
fi

if [[ -n "${DEVHAVEN_AGENT_BIN_DIR:-}" && -d "${DEVHAVEN_AGENT_BIN_DIR}" ]]; then
  path=(${path:#$DEVHAVEN_AGENT_BIN_DIR})
  path=("$DEVHAVEN_AGENT_BIN_DIR" $path)
  export PATH
fi
