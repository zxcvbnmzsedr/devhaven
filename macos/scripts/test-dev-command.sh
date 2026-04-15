#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DEV_CMD="$REPO_ROOT/dev"

HELP_OUTPUT="$($DEV_CMD --help)"
[[ "$HELP_OUTPUT" == *"用法："* ]]
[[ "$HELP_OUTPUT" == *"--dry-run"* ]]
[[ "$HELP_OUTPUT" == *"--logs all|app|ghostty"* ]]

DRY_RUN_OUTPUT="$($DEV_CMD --dry-run)"
[[ "$DRY_RUN_OUTPUT" == *"bash macos/scripts/setup-ghostty-framework.sh --ensure-worktree-vendor"* ]]
[[ "$DRY_RUN_OUTPUT" == *"bash macos/scripts/setup-sparkle-framework.sh --ensure-worktree-vendor"* ]]
[[ "$DRY_RUN_OUTPUT" == *"log stream --style compact --level debug --predicate"* ]]
[[ "$DRY_RUN_OUTPUT" == *'subsystem == "DevHavenNative"'* ]]
[[ "$DRY_RUN_OUTPUT" == *'subsystem == "com.mitchellh.ghostty"'* ]]
[[ "$DRY_RUN_OUTPUT" == *"swift run --package-path macos DevHavenApp"* ]]

APP_ONLY_OUTPUT="$($DEV_CMD --dry-run --logs app)"
[[ "$APP_ONLY_OUTPUT" == *'subsystem == "DevHavenNative"'* ]]
[[ "$APP_ONLY_OUTPUT" != *'subsystem == "com.mitchellh.ghostty"'* ]]

NO_LOG_OUTPUT="$($DEV_CMD --dry-run --no-log)"
[[ "$NO_LOG_OUTPUT" != *"log stream --style compact --level debug --predicate"* ]]

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/devhaven-dev-worktree-test.XXXXXX")"
cleanup() {
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

TEST_REPO="$TMP_ROOT/repo"
TEST_WORKTREE="$TMP_ROOT/worktree"
MOCK_BIN="$TMP_ROOT/mock-bin"
SWIFT_LOG="$TMP_ROOT/swift.log"
mkdir -p "$TEST_REPO/macos/scripts" "$MOCK_BIN"

cp "$DEV_CMD" "$TEST_REPO/dev"
cp "$REPO_ROOT/macos/scripts/setup-ghostty-framework.sh" "$TEST_REPO/macos/scripts/setup-ghostty-framework.sh"
cat > "$TEST_REPO/macos/scripts/setup-sparkle-framework.sh" <<'EOF_SPARKLE'
#!/usr/bin/env bash
set -euo pipefail
printf '==> Sparkle mock ok\n'
EOF_SPARKLE
chmod +x \
  "$TEST_REPO/dev" \
  "$TEST_REPO/macos/scripts/setup-ghostty-framework.sh" \
  "$TEST_REPO/macos/scripts/setup-sparkle-framework.sh"

(
  cd "$TEST_REPO"
  git init -b main >/dev/null
  git config user.name test >/dev/null
  git config user.email test@example.com >/dev/null
  git add dev macos/scripts/setup-ghostty-framework.sh
  git commit -m init >/dev/null
  git worktree add -b feature/demo "$TEST_WORKTREE" >/dev/null
)

mkdir -p "$TEST_WORKTREE/macos/scripts"
cp "$TEST_REPO/macos/scripts/setup-sparkle-framework.sh" "$TEST_WORKTREE/macos/scripts/setup-sparkle-framework.sh"
chmod +x "$TEST_WORKTREE/macos/scripts/setup-sparkle-framework.sh"

mkdir -p \
  "$TEST_REPO/macos/Vendor/GhosttyKit.xcframework/macos-arm64/GhosttyKit.framework" \
  "$TEST_REPO/macos/Vendor/GhosttyResources/ghostty/themes" \
  "$TEST_REPO/macos/Vendor/GhosttyResources/terminfo/78"
cat > "$TEST_REPO/macos/Vendor/GhosttyKit.xcframework/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundlePackageType</key>
  <string>XFWK</string>
</dict>
</plist>
PLIST
touch \
  "$TEST_REPO/macos/Vendor/GhosttyKit.xcframework/macos-arm64/GhosttyKit.framework/GhosttyKit" \
  "$TEST_REPO/macos/Vendor/GhosttyResources/ghostty/themes/default.conf" \
  "$TEST_REPO/macos/Vendor/GhosttyResources/terminfo/78/xterm-ghostty"

cat > "$MOCK_BIN/swift" <<'EOF_SWIFT'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" > "${DEVHAVEN_TEST_SWIFT_LOG:?}"
EOF_SWIFT
chmod +x "$MOCK_BIN/swift"

WORKTREE_OUTPUT="$(
  cd "$TEST_WORKTREE"
  DEVHAVEN_TEST_SWIFT_LOG="$SWIFT_LOG" PATH="$MOCK_BIN:$PATH" ./dev --no-log
)"

[[ "$WORKTREE_OUTPUT" == *"复用"* || "$WORKTREE_OUTPUT" == *"同步"* ]]
[[ "$WORKTREE_OUTPUT" == *"Sparkle mock ok"* ]]
[[ -f "$TEST_WORKTREE/macos/Vendor/GhosttyKit.xcframework/Info.plist" ]]
[[ -f "$TEST_WORKTREE/macos/Vendor/GhosttyResources/terminfo/78/xterm-ghostty" ]]
[[ "$(cat "$SWIFT_LOG")" == "run --package-path macos DevHavenApp" ]]

echo "dev command smoke ok"
