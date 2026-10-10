#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MACOS_DIR="$(dirname "$SCRIPT_DIR")"
APP_PATH="${1:?用法：test-cmux-terminal-file-drop.sh <DevHaven.app 绝对路径>}"
[[ -d "$APP_PATH/Contents/Frameworks/CmuxEmbedded.framework" ]] || { echo "App 中缺少 CmuxEmbedded.framework" >&2; exit 1; }
TEST_DIR="$(mktemp -d "$MACOS_DIR/.build/terminal-file-drop-smoke.XXXXXX")"
SMOKE_APP="$TEST_DIR/TerminalFileDropSmoke.app"
mkdir -p "$SMOKE_APP/Contents/MacOS"
ln -s "$APP_PATH/Contents/Frameworks" "$SMOKE_APP/Contents/Frameworks"
ln -s "$APP_PATH/Contents/Resources" "$SMOKE_APP/Contents/Resources"
cat > "$SMOKE_APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>com.devhaven.terminal-file-drop-smoke</string><key>CFBundleExecutable</key><string>TerminalFileDropSmoke</string><key>CFBundleName</key><string>TerminalFileDropSmoke</string><key>CFBundlePackageType</key><string>APPL</string></dict></plist>
PLIST
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.devhaven.$(basename "$TEST_DIR")" "$SMOKE_APP/Contents/Info.plist"
swiftc -parse-as-library \
  "$MACOS_DIR/Tests/CmuxEmbeddedIntegration/TerminalFileDropSmoke.swift" \
  "$MACOS_DIR/Sources/DevHavenApp/CmuxEmbeddedHostView.swift" \
  "$MACOS_DIR/Sources/DevHavenApp/CmuxEmbeddedWorkspaceCommands.swift" \
  -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
  -o "$SMOKE_APP/Contents/MacOS/TerminalFileDropSmoke"
SMOKE_LOG="$TEST_DIR/smoke.log"
open -n -W --stdout "$SMOKE_LOG" --stderr "$SMOKE_LOG" "$SMOKE_APP"
cat "$SMOKE_LOG"
rg -q '^PASS: terminal file drop regression complete$' "$SMOKE_LOG"
