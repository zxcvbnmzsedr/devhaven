#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MACOS_DIR="$(dirname "$SCRIPT_DIR")"
APP_METADATA_PATH="$MACOS_DIR/Resources/AppMetadata.json"

CONFIGURATION="release"
OUTPUT_DIR=""
OPEN_OUTPUT_DIR=1

read_metadata_field() {
  local field="$1"
  if [[ ! -f "$APP_METADATA_PATH" ]]; then
    return 0
  fi
  plutil -extract "$field" raw -o - "$APP_METADATA_PATH" 2>/dev/null || true
}

DEFAULT_APP_NAME="$(read_metadata_field productName)"
DEFAULT_APP_NAME="${DEFAULT_APP_NAME:-DevHaven}"
DEFAULT_VERSION="$(read_metadata_field version)"
DEFAULT_VERSION="${DEFAULT_VERSION:-0.1.0}"
DEFAULT_IDENTIFIER="$(read_metadata_field bundleIdentifier)"
DEFAULT_IDENTIFIER="${DEFAULT_IDENTIFIER:-com.devhaven}"

APP_NAME="${DEVHAVEN_NATIVE_APP_NAME:-$DEFAULT_APP_NAME}"
BUNDLE_IDENTIFIER="${DEVHAVEN_NATIVE_BUNDLE_ID:-$DEFAULT_IDENTIFIER}"
BUNDLE_VERSION="${DEVHAVEN_NATIVE_VERSION:-$DEFAULT_VERSION}"
ICON_SOURCE="$MACOS_DIR/Resources/DevHaven.icns"

usage() {
  cat <<USAGE
用法：$(basename "$0") [选项]

作用：
  构建 Swift 原生版 DevHaven `.app`，输出到稳定目录，
  默认完成本地 ad-hoc 签名后打开产物目录。

选项：
  --debug                 构建 debug 版
  --release               构建 release 版（默认）
  --output-dir <path>     指定产物目录；默认：macos/.build/native-app/<configuration>
  --app-name <name>       自定义 `.app` 名称（默认：$DEFAULT_APP_NAME）
  --bundle-id <id>        自定义 bundle identifier（默认：$DEFAULT_IDENTIFIER）
  --version <version>     自定义 CFBundleShortVersionString（默认：$DEFAULT_VERSION）
  --no-open               构建完成后不执行 open
  --help                  显示帮助

典型用法：
  bash macos/scripts/build-native-app.sh
  bash macos/scripts/build-native-app.sh --debug --no-open
  bash macos/scripts/build-native-app.sh --output-dir ./tmp/native-app
USAGE
}

log() {
  printf '==> %s\n' "$*"
}

fail() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

resolve_path() {
  local input="$1"
  if [[ "$input" = /* ]]; then
    printf '%s\n' "$input"
    return
  fi
  printf '%s/%s\n' "$(pwd)" "$input"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --debug)
      CONFIGURATION="debug"
      shift
      ;;
    --release)
      CONFIGURATION="release"
      shift
      ;;
    --output-dir)
      [[ $# -ge 2 ]] || fail "--output-dir 需要路径参数"
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --app-name)
      [[ $# -ge 2 ]] || fail "--app-name 需要名称参数"
      APP_NAME="$2"
      shift 2
      ;;
    --bundle-id)
      [[ $# -ge 2 ]] || fail "--bundle-id 需要参数"
      BUNDLE_IDENTIFIER="$2"
      shift 2
      ;;
    --version)
      [[ $# -ge 2 ]] || fail "--version 需要参数"
      BUNDLE_VERSION="$2"
      shift 2
      ;;
    --no-open)
      OPEN_OUTPUT_DIR=0
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      fail "未知参数：$1"
      ;;
  esac
done

if [[ -z "$OUTPUT_DIR" ]]; then
  OUTPUT_DIR="$MACOS_DIR/.build/native-app/$CONFIGURATION"
fi
OUTPUT_DIR="$(resolve_path "$OUTPUT_DIR")"

APP_BUNDLE_NAME="$APP_NAME.app"
APP_OUTPUT_PATH="$OUTPUT_DIR/$APP_BUNDLE_NAME"
STAGE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/devhaven-native-app.XXXXXX")"
APP_STAGE_PATH="$STAGE_DIR/$APP_BUNDLE_NAME"
INFO_PLIST_PATH="$APP_STAGE_PATH/Contents/Info.plist"

cleanup() {
  rm -rf "$STAGE_DIR"
}
trap cleanup EXIT

command -v swift >/dev/null 2>&1 || fail "未检测到 swift，请先安装 Xcode Command Line Tools 或 Xcode"
command -v plutil >/dev/null 2>&1 || fail "未检测到 plutil"
command -v codesign >/dev/null 2>&1 || fail "未检测到 codesign"
command -v ditto >/dev/null 2>&1 || fail "未检测到 ditto"

log "验证 Ghostty vendor 完整性"
bash "$SCRIPT_DIR/setup-ghostty-framework.sh" --verify-only

log "开始构建 Swift 原生版（configuration=${CONFIGURATION}）"
swift build -c "$CONFIGURATION" --package-path "$MACOS_DIR"

BIN_DIR="$(swift build -c "$CONFIGURATION" --package-path "$MACOS_DIR" --show-bin-path)"
EXECUTABLE_PATH="$BIN_DIR/DevHavenApp"
RESOURCE_BUNDLE_PATH="$BIN_DIR/DevHavenNative_DevHavenApp.bundle"

[[ -f "$EXECUTABLE_PATH" ]] || fail "未找到原生可执行文件：$EXECUTABLE_PATH"
[[ -d "$RESOURCE_BUNDLE_PATH" ]] || fail "未找到 SwiftPM 资源 bundle：$RESOURCE_BUNDLE_PATH"

log "组装本地 .app bundle"
mkdir -p "$APP_STAGE_PATH/Contents/MacOS" "$APP_STAGE_PATH/Contents/Resources"
cp "$EXECUTABLE_PATH" "$APP_STAGE_PATH/Contents/MacOS/DevHavenApp"
ditto "$RESOURCE_BUNDLE_PATH" "$APP_STAGE_PATH/Contents/Resources/$(basename "$RESOURCE_BUNDLE_PATH")"

HAS_ICON=0
if [[ -f "$ICON_SOURCE" ]]; then
  cp "$ICON_SOURCE" "$APP_STAGE_PATH/Contents/Resources/DevHaven.icns"
  HAS_ICON=1
else
  log "未找到图标文件，继续构建无自定义图标版本：${ICON_SOURCE}"
fi

cat > "$INFO_PLIST_PATH" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>zh_CN</string>
  <key>CFBundleExecutable</key>
  <string>DevHavenApp</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_IDENTIFIER</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$BUNDLE_VERSION</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
PLIST

if (( HAS_ICON )); then
  cat >> "$INFO_PLIST_PATH" <<'PLIST'
  <key>CFBundleIconFile</key>
  <string>DevHaven.icns</string>
PLIST
fi

cat >> "$INFO_PLIST_PATH" <<'PLIST'
</dict>
</plist>
PLIST

chmod +x "$APP_STAGE_PATH/Contents/MacOS/DevHavenApp"
plutil -lint "$INFO_PLIST_PATH" >/dev/null

mkdir -p "$OUTPUT_DIR"
if [[ -e "$APP_OUTPUT_PATH" ]]; then
  log "清理旧产物：${APP_OUTPUT_PATH}"
  rm -rf "$APP_OUTPUT_PATH"
fi
ditto "$APP_STAGE_PATH" "$APP_OUTPUT_PATH"

log "执行本地 ad-hoc 签名"
codesign --force --deep --sign - "$APP_OUTPUT_PATH" >/dev/null
codesign --verify --deep --strict "$APP_OUTPUT_PATH"

log "原生 App 已生成：${APP_OUTPUT_PATH}"
log "产物目录：${OUTPUT_DIR}"
printf 'APP_PATH=%s\n' "$APP_OUTPUT_PATH"
printf 'OUTPUT_DIR=%s\n' "$OUTPUT_DIR"

if (( OPEN_OUTPUT_DIR )); then
  command -v open >/dev/null 2>&1 || fail "未检测到 open"
  log "打开产物目录"
  open "$OUTPUT_DIR"
fi
