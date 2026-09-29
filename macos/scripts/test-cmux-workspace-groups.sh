#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MACOS_DIR="$(dirname "$SCRIPT_DIR")"
APP_PATH="${1:?Usage: test-cmux-workspace-groups.sh /absolute/path/to/DevHaven.app}"
[[ -d "$APP_PATH/Contents/Frameworks/CmuxEmbedded.framework" ]] || { echo "Missing packaged cmux framework" >&2; exit 1; }
TEST_DIR="$(mktemp -d "$MACOS_DIR/.build/workspace-group-smoke.XXXXXX")"
SMOKE_APP="$TEST_DIR/WorkspaceGroupSmoke.app"
mkdir -p "$SMOKE_APP/Contents/MacOS"
ln -s "$APP_PATH/Contents/Frameworks" "$SMOKE_APP/Contents/Frameworks"
ln -s "$APP_PATH/Contents/Resources" "$SMOKE_APP/Contents/Resources"
cat > "$SMOKE_APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>com.devhaven.workspace-group-smoke</string><key>CFBundleExecutable</key><string>WorkspaceGroupSmoke</string><key>CFBundleName</key><string>WorkspaceGroupSmoke</string><key>CFBundlePackageType</key><string>APPL</string></dict></plist>
PLIST
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.devhaven.$(basename "$TEST_DIR")" "$SMOKE_APP/Contents/Info.plist"
# Use the pinned build's public drop-plan type to drive the same callback
# the native sidebar invokes after accepting a drag (no separate model stub).
CMUX_PRODUCTS="$MACOS_DIR/ThirdParty/cmux/build/embedded-derived-data/Build/Products/Debug"
swiftc -parse-as-library \
  -I "$CMUX_PRODUCTS" \
  -Xcc "-fmodule-map-file=$MACOS_DIR/ThirdParty/cmux/build/embedded-derived-data/Build/Intermediates.noindex/GeneratedModuleMaps/CmuxFoundationAtomicsC.modulemap" \
  -F "$APP_PATH/Contents/Frameworks" -framework CmuxEmbedded \
  "$MACOS_DIR/Tests/CmuxEmbeddedIntegration/WorkspaceGroupSmoke.swift" \
  "$MACOS_DIR/Sources/DevHavenApp/CmuxEmbeddedHostView.swift" \
  "$MACOS_DIR/Sources/DevHavenApp/CmuxEmbeddedWorkspaceCommands.swift" \
  -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
  -o "$SMOKE_APP/Contents/MacOS/WorkspaceGroupSmoke"
SMOKE_LOG="$TEST_DIR/smoke.log"
if [[ "${2:-}" == "--restore" ]]; then
  for stage in write read deleted; do
    STAGE_LOG="$TEST_DIR/restore-$stage.log"
    open -n -W --stdout "$STAGE_LOG" --stderr "$STAGE_LOG" "$SMOKE_APP" --args "--restore-$stage"
    cat "$STAGE_LOG"
    rg -q "^PASS: group restore $stage complete$" "$STAGE_LOG"
  done
else
  open -n -W --stdout "$SMOKE_LOG" --stderr "$SMOKE_LOG" "$SMOKE_APP"
  cat "$SMOKE_LOG"
  rg -q '^PASS: workspace group regression complete$' "$SMOKE_LOG"
fi
