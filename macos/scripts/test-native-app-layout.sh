#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/devhaven-native-layout-test.XXXXXX")"
APP_PATH="$OUTPUT_DIR/DevHaven.app"
RESOURCE_BUNDLE_NAME="DevHavenNative_DevHavenApp.bundle"
EXPECTED_BUNDLE_PATH="$APP_PATH/Contents/Resources/$RESOURCE_BUNDLE_NAME"
INVALID_ROOT_BUNDLE_PATH="$APP_PATH/$RESOURCE_BUNDLE_NAME"

cleanup() {
  rm -rf "$OUTPUT_DIR"
}
trap cleanup EXIT

bash "$SCRIPT_DIR/build-native-app.sh" --release --no-open --output-dir "$OUTPUT_DIR" >/dev/null

if [[ ! -d "$EXPECTED_BUNDLE_PATH" ]]; then
  echo "Error: 资源 bundle 未放到 SwiftPM 可执行目标期望的位置：$EXPECTED_BUNDLE_PATH" >&2
  exit 1
fi

if [[ ! -d "$EXPECTED_BUNDLE_PATH/GhosttyResources" ]]; then
  echo "Error: 资源 bundle 内缺少 GhosttyResources：$EXPECTED_BUNDLE_PATH/GhosttyResources" >&2
  exit 1
fi

if [[ -e "$INVALID_ROOT_BUNDLE_PATH" ]]; then
  echo "Error: app 根目录不应再存在资源 bundle：$INVALID_ROOT_BUNDLE_PATH" >&2
  exit 1
fi

echo "native app layout ok: $EXPECTED_BUNDLE_PATH"
