if [[ -z "${DEVHAVEN_AGENT_BIN_DIR:-}" && -n "${DEVHAVEN_AGENT_RESOURCES_DIR:-}" ]]; then
  export DEVHAVEN_AGENT_BIN_DIR="${DEVHAVEN_AGENT_RESOURCES_DIR}/bin"
fi

if [[ -n "${DEVHAVEN_AGENT_BIN_DIR:-}" && -d "${DEVHAVEN_AGENT_BIN_DIR}" ]]; then
  IFS=':' read -r -a __devhaven_agent_path_entries <<< "${PATH:-}"
  __devhaven_agent_normalized_path=""
  for __devhaven_agent_path_entry in "${__devhaven_agent_path_entries[@]}"; do
    if [[ "$__devhaven_agent_path_entry" == "$DEVHAVEN_AGENT_BIN_DIR" ]]; then
      continue
    fi
    if [[ -n "$__devhaven_agent_normalized_path" ]]; then
      __devhaven_agent_normalized_path="${__devhaven_agent_normalized_path}:$__devhaven_agent_path_entry"
    else
      __devhaven_agent_normalized_path="$__devhaven_agent_path_entry"
    fi
  done

  if [[ -n "$__devhaven_agent_normalized_path" ]]; then
    export PATH="${DEVHAVEN_AGENT_BIN_DIR}:${__devhaven_agent_normalized_path}"
  else
    export PATH="${DEVHAVEN_AGENT_BIN_DIR}"
  fi

  builtin unset __devhaven_agent_normalized_path
  builtin unset __devhaven_agent_path_entries
  builtin unset __devhaven_agent_path_entry
fi
