#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DEV_CMD="$REPO_ROOT/dev"

HELP_OUTPUT="$("$DEV_CMD" --help)"
[[ "$HELP_OUTPUT" == *"用法："* ]]
[[ "$HELP_OUTPUT" == *"--dry-run"* ]]
[[ "$HELP_OUTPUT" == *"--logs all|app|ghostty"* ]]

DRY_RUN_OUTPUT="$("$DEV_CMD" --dry-run)"
[[ "$DRY_RUN_OUTPUT" == *"bash macos/scripts/setup-ghostty-framework.sh --verify-only"* ]]
[[ "$DRY_RUN_OUTPUT" == *"log stream --style compact --level debug --predicate"* ]]
[[ "$DRY_RUN_OUTPUT" == *'subsystem == "DevHavenNative"'* ]]
[[ "$DRY_RUN_OUTPUT" == *'subsystem == "com.mitchellh.ghostty"'* ]]
[[ "$DRY_RUN_OUTPUT" == *"swift run --package-path macos DevHavenApp"* ]]

APP_ONLY_OUTPUT="$("$DEV_CMD" --dry-run --logs app)"
[[ "$APP_ONLY_OUTPUT" == *'subsystem == "DevHavenNative"'* ]]
[[ "$APP_ONLY_OUTPUT" != *'subsystem == "com.mitchellh.ghostty"'* ]]

NO_LOG_OUTPUT="$("$DEV_CMD" --dry-run --no-log)"
[[ "$NO_LOG_OUTPUT" != *"log stream --style compact --level debug --predicate"* ]]

echo "dev command smoke ok"
