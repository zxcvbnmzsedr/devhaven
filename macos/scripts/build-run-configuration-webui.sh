#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MACOS_DIR="$(dirname "$SCRIPT_DIR")"
WEBUI_DIR="$MACOS_DIR/WebUI/WorkspaceRunConfiguration"

log() {
  printf '==> %s\n' "$*"
}

fail() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

command -v node >/dev/null 2>&1 || fail "未检测到 Node.js，请先安装 Node 22+"
command -v npm >/dev/null 2>&1 || fail "未检测到 npm，请先安装 Node.js 自带 npm"
[[ -f "$WEBUI_DIR/package.json" ]] || fail "未找到 WebUI package.json：$WEBUI_DIR/package.json"

cd "$WEBUI_DIR"

if [[ -f package-lock.json ]]; then
  log "安装 WorkspaceRunConfiguration WebUI 依赖"
  npm ci --no-fund --no-audit
else
  log "首次安装 WorkspaceRunConfiguration WebUI 依赖"
  npm install --no-fund --no-audit
fi

log "构建 WorkspaceRunConfiguration WebUI"
npm run build
