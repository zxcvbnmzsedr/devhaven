if [ -n "${DEVHAVEN_WRAPPER_BIN_PATH:-}" ]; then
  _devhaven_wrapper_path="${DEVHAVEN_WRAPPER_BIN_PATH%/}"
  _devhaven_compacted_path=""
  _devhaven_old_ifs="${IFS:- }"
  IFS=':'
  for _devhaven_path_entry in ${PATH:-}; do
    if [ -z "${_devhaven_path_entry}" ] || [ "${_devhaven_path_entry}" = "${_devhaven_wrapper_path}" ]; then
      continue
    fi
    if [ -z "${_devhaven_compacted_path}" ]; then
      _devhaven_compacted_path="${_devhaven_path_entry}"
    else
      _devhaven_compacted_path="${_devhaven_compacted_path}:${_devhaven_path_entry}"
    fi
  done
  IFS="${_devhaven_old_ifs}"

  if [ -n "${_devhaven_compacted_path}" ]; then
    export PATH="${_devhaven_wrapper_path}:${_devhaven_compacted_path}"
  else
    export PATH="${_devhaven_wrapper_path}"
  fi
  hash -r 2>/dev/null || true
  unset _devhaven_wrapper_path _devhaven_compacted_path _devhaven_path_entry _devhaven_old_ifs
fi
