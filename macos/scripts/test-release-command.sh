#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RELEASE_CMD="$REPO_ROOT/release"
FAKE_BIN_DIR="$(mktemp -d "${TMPDIR:-/tmp}/devhaven-release-test-bin.XXXXXX")"
RECORDED_ARGS_PATH="$FAKE_BIN_DIR/recorded-args.txt"

cleanup() {
  rm -rf "$FAKE_BIN_DIR"
}
trap cleanup EXIT

cat > "$FAKE_BIN_DIR/bash" <<'BASH'
#!/bin/bash
set -euo pipefail
printf '%s\n' "$@" > "${DEVHAVEN_RELEASE_TEST_OUTPUT:?}"
BASH
chmod +x "$FAKE_BIN_DIR/bash"

PATH="$FAKE_BIN_DIR:$PATH" DEVHAVEN_RELEASE_TEST_OUTPUT="$RECORDED_ARGS_PATH" /bin/bash "$RELEASE_CMD" --no-open --output-dir /tmp/devhaven-release-test-output >/dev/null

recorded_args=()
while IFS= read -r line; do
  recorded_args+=("$line")
done < "$RECORDED_ARGS_PATH"
[[ "${recorded_args[0]}" == "macos/scripts/build-native-app.sh" ]]
[[ "${recorded_args[1]}" == "--release" ]]
[[ "${recorded_args[2]}" == "--no-open" ]]
[[ "${recorded_args[3]}" == "--output-dir" ]]
[[ "${recorded_args[4]}" == "/tmp/devhaven-release-test-output" ]]

rm -f "$RECORDED_ARGS_PATH"
set +e
DEBUG_OUTPUT="$(PATH="$FAKE_BIN_DIR:$PATH" DEVHAVEN_RELEASE_TEST_OUTPUT="$RECORDED_ARGS_PATH" /bin/bash "$RELEASE_CMD" --debug 2>&1)"
DEBUG_EXIT=$?
set -e
[[ $DEBUG_EXIT -ne 0 ]]
[[ "$DEBUG_OUTPUT" == *"不支持 --debug"* ]]
[[ ! -f "$RECORDED_ARGS_PATH" ]]

HELP_OUTPUT="$(/bin/bash "$RELEASE_CMD" --help)"
[[ "$HELP_OUTPUT" == *"构建 Swift 原生版 DevHaven"* ]]
[[ "$HELP_OUTPUT" == *"--release"* ]]

echo "release command smoke ok"
