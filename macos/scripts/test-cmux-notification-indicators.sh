#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MACOS_DIR="$(dirname "$SCRIPT_DIR")"
APP_PATH="${1:?Usage: test-cmux-notification-indicators.sh /absolute/path/to/DevHaven.app}"
[[ -d "$APP_PATH/Contents/Frameworks/CmuxEmbedded.framework" ]] || { echo "Missing packaged cmux framework" >&2; exit 1; }
TEST_DIR="$(mktemp -d "$MACOS_DIR/.build/notification-indicators-smoke.XXXXXX")"
SMOKE_APP="$TEST_DIR/NotificationIndicatorSmoke.app"
mkdir -p "$SMOKE_APP/Contents/MacOS"
ln -s "$APP_PATH/Contents/Frameworks" "$SMOKE_APP/Contents/Frameworks"
ln -s "$APP_PATH/Contents/Resources" "$SMOKE_APP/Contents/Resources"
cat > "$SMOKE_APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>com.devhaven.notification-indicators-smoke</string><key>CFBundleExecutable</key><string>NotificationIndicatorSmoke</string><key>CFBundleName</key><string>NotificationIndicatorSmoke</string><key>CFBundlePackageType</key><string>APPL</string></dict></plist>
PLIST
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.devhaven.$(basename "$TEST_DIR")" "$SMOKE_APP/Contents/Info.plist"
# Override only this disposable bundle's config so the BEL regression does not
# depend on the user's bell preferences or interactive shell startup files.
SMOKE_CONFIG_DIR="$HOME/Library/Application Support/com.devhaven.$(basename "$TEST_DIR")"
mkdir "$SMOKE_CONFIG_DIR"
trap 'rm -rf "$SMOKE_CONFIG_DIR"' EXIT
cat > "$SMOKE_CONFIG_DIR/config.ghostty" <<'CONFIG'
bell-features = visual
command = /bin/bash --noprofile --norc
CONFIG
swiftc -parse-as-library \
  "$MACOS_DIR/Tests/CmuxEmbeddedIntegration/NotificationIndicatorSmoke.swift" \
  "$MACOS_DIR/Sources/DevHavenApp/CmuxEmbeddedHostView.swift" \
  "$MACOS_DIR/Sources/DevHavenApp/CmuxEmbeddedWorkspaceCommands.swift" \
  -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
  -o "$SMOKE_APP/Contents/MacOS/NotificationIndicatorSmoke"
SMOKE_LOG="$TEST_DIR/smoke.log"
open -n -W --stdout "$SMOKE_LOG" --stderr "$SMOKE_LOG" "$SMOKE_APP"
cat "$SMOKE_LOG"
rg -q '^PASS: notification indicator regression complete$' "$SMOKE_LOG"
