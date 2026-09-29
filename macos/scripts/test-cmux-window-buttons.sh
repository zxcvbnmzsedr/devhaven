#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MACOS_DIR="$(dirname "$SCRIPT_DIR")"
APP_PATH="${1:?Usage: test-cmux-window-buttons.sh /absolute/path/to/DevHaven.app}"
[[ -d "$APP_PATH/Contents/Frameworks/CmuxEmbedded.framework" ]] || { echo "Missing packaged cmux framework" >&2; exit 1; }
TEST_DIR="$(mktemp -d "$MACOS_DIR/.build/window-buttons-smoke.XXXXXX")"
SMOKE_APP="$TEST_DIR/WindowButtonsSmoke.app"
mkdir -p "$SMOKE_APP/Contents/MacOS"
ln -s "$APP_PATH/Contents/Frameworks" "$SMOKE_APP/Contents/Frameworks"
ln -s "$APP_PATH/Contents/Resources" "$SMOKE_APP/Contents/Resources"
cat > "$SMOKE_APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>com.devhaven.window-buttons-smoke</string><key>CFBundleExecutable</key><string>WindowButtonsSmoke</string><key>CFBundleName</key><string>WindowButtonsSmoke</string><key>CFBundlePackageType</key><string>APPL</string></dict></plist>
PLIST
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.devhaven.$(basename "$TEST_DIR")" "$SMOKE_APP/Contents/Info.plist"
swiftc -parse-as-library \
  "$MACOS_DIR/Tests/CmuxEmbeddedIntegration/WindowButtonsSmoke.swift" \
  "$MACOS_DIR/Sources/DevHavenApp/CmuxEmbeddedHostView.swift" \
  "$MACOS_DIR/Sources/DevHavenApp/CmuxEmbeddedWorkspaceCommands.swift" \
  -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
  -o "$SMOKE_APP/Contents/MacOS/WindowButtonsSmoke"
SMOKE_LOG="$TEST_DIR/smoke.log"
open -n -W --stdout "$SMOKE_LOG" --stderr "$SMOKE_LOG" "$SMOKE_APP"
cat "$SMOKE_LOG"
rg -q '^PASS: window buttons regression complete$' "$SMOKE_LOG"
