#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MACOS_DIR="$(dirname "$SCRIPT_DIR")"
APP_PATH="${1:?Usage: test-cmux-localization.sh /absolute/path/to/DevHaven.app}"
TEST_DIR="$(mktemp -d "$MACOS_DIR/.build/localization-smoke.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
SMOKE_APP="$TEST_DIR/LocalizationSmoke.app"
mkdir -p "$SMOKE_APP/Contents/MacOS" "$TEST_DIR/dev"
cp "$APP_PATH/Contents/Info.plist" "$SMOKE_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleExecutable LocalizationSmoke' "$SMOKE_APP/Contents/Info.plist"
ln -s "$APP_PATH/Contents/Resources" "$SMOKE_APP/Contents/Resources"
export CMUX_TEST_FRAMEWORK="$APP_PATH/Contents/Frameworks/CmuxEmbedded.framework"
swiftc "$MACOS_DIR/Tests/CmuxEmbeddedIntegration/LocalizationSmoke.swift" -o "$SMOKE_APP/Contents/MacOS/LocalizationSmoke"
for language in zh-Hans en ja; do
  "$SMOKE_APP/Contents/MacOS/LocalizationSmoke" -AppleLanguages "($language)"
done
# swift run has no .app Info.plist; Bundle.main must still find its Chinese resources.
cp "$SMOKE_APP/Contents/MacOS/LocalizationSmoke" "$TEST_DIR/dev/LocalizationSmoke"
python3 "$SCRIPT_DIR/prepare-cmux-localization.py" install \
  --framework "$CMUX_TEST_FRAMEWORK" --destination "$TEST_DIR/dev"
for language in zh-Hans en ja; do
  "$TEST_DIR/dev/LocalizationSmoke" -AppleLanguages "($language)"
done
