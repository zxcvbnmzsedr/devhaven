#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MACOS_DIR="$(dirname "$SCRIPT_DIR")"
APP_METADATA_PATH="$MACOS_DIR/Resources/AppMetadata.json"

CONFIGURATION="release"
OUTPUT_DIR=""
OPEN_OUTPUT_DIR=1
SWIFT_TRIPLE="${DEVHAVEN_NATIVE_TRIPLE:-}"

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
DEFAULT_BUILD_NUMBER="$(read_metadata_field buildNumber)"
DEFAULT_BUILD_NUMBER="${DEFAULT_BUILD_NUMBER:-1}"
DEFAULT_IDENTIFIER="$(read_metadata_field bundleIdentifier)"
DEFAULT_IDENTIFIER="${DEFAULT_IDENTIFIER:-com.devhaven}"
DEFAULT_STABLE_FEED_URL="$(read_metadata_field stableFeedURL)"
DEFAULT_NIGHTLY_FEED_URL="$(read_metadata_field nightlyFeedURL)"
DEFAULT_UPDATE_DELIVERY_MODE="$(read_metadata_field updateDeliveryMode)"
DEFAULT_UPDATE_DELIVERY_MODE="${DEFAULT_UPDATE_DELIVERY_MODE:-manualDownload}"
DEFAULT_STABLE_DOWNLOADS_PAGE_URL="$(read_metadata_field stableDownloadsPageURL)"
DEFAULT_NIGHTLY_DOWNLOADS_PAGE_URL="$(read_metadata_field nightlyDownloadsPageURL)"

APP_NAME="${DEVHAVEN_NATIVE_APP_NAME:-$DEFAULT_APP_NAME}"
BUNDLE_IDENTIFIER="${DEVHAVEN_NATIVE_BUNDLE_ID:-$DEFAULT_IDENTIFIER}"
BUNDLE_VERSION="${DEVHAVEN_NATIVE_VERSION:-$DEFAULT_VERSION}"
BUNDLE_BUILD_NUMBER="${DEVHAVEN_NATIVE_BUILD_NUMBER:-$DEFAULT_BUILD_NUMBER}"
UPDATE_CHANNEL="${DEVHAVEN_UPDATE_CHANNEL:-stable}"
UPDATE_DELIVERY_MODE="${DEVHAVEN_UPDATE_DELIVERY_MODE:-$DEFAULT_UPDATE_DELIVERY_MODE}"
SPARKLE_PUBLIC_KEY="${DEVHAVEN_SPARKLE_PUBLIC_KEY:-}"
STABLE_FEED_URL="${DEVHAVEN_STABLE_FEED_URL:-$DEFAULT_STABLE_FEED_URL}"
NIGHTLY_FEED_URL="${DEVHAVEN_NIGHTLY_FEED_URL:-$DEFAULT_NIGHTLY_FEED_URL}"
STABLE_DOWNLOADS_PAGE_URL="${DEVHAVEN_STABLE_DOWNLOADS_PAGE_URL:-$DEFAULT_STABLE_DOWNLOADS_PAGE_URL}"
NIGHTLY_DOWNLOADS_PAGE_URL="${DEVHAVEN_NIGHTLY_DOWNLOADS_PAGE_URL:-$DEFAULT_NIGHTLY_DOWNLOADS_PAGE_URL}"
ICON_SOURCE="$MACOS_DIR/Resources/DevHaven.icns"
SKIP_SIGN=0

usage() {
  cat <<USAGE
用法：$(basename "$0") [选项]

作用：
  构建 Swift 原生版 DevHaven .app，输出到稳定目录，
  默认完成本地 ad-hoc 签名后打开产物目录。

选项：
  --debug                 构建 debug 版
  --release               构建 release 版（默认）
  --output-dir <path>     指定产物目录；默认：macos/.build/native-app/<configuration>
  --app-name <name>       自定义 .app 名称（默认：${DEFAULT_APP_NAME}）
  --bundle-id <id>        自定义 bundle identifier（默认：${DEFAULT_IDENTIFIER}）
  --version <version>     自定义 CFBundleShortVersionString（默认：${DEFAULT_VERSION}）
  --build-number <num>    自定义 CFBundleVersion（默认：${DEFAULT_BUILD_NUMBER}）
  --update-channel <name> 设置默认更新通道 stable/nightly（默认：stable）
  --update-delivery-mode <m> 设置升级交付模式 automatic/manualDownload（默认：从 AppMetadata 读取）
  --sparkle-public-key <k> 写入 Sparkle SUPublicEDKey；也可用 DEVHAVEN_SPARKLE_PUBLIC_KEY
  --triple <triple>       指定 Swift 构建 triple（默认：跟随当前运行环境；也可用环境变量 DEVHAVEN_NATIVE_TRIPLE）
  --skip-sign             跳过本地 ad-hoc 签名，供 CI 后续显式签名
  --no-open               构建完成后不执行 open
  --help                  显示帮助

典型用法：
  bash macos/scripts/build-native-app.sh
  bash macos/scripts/build-native-app.sh --debug --no-open
  bash macos/scripts/build-native-app.sh --release --triple x86_64-apple-macosx14.0 --no-open
  bash macos/scripts/build-native-app.sh --build-number 3000001 --sparkle-public-key <pubkey> --no-open
  bash macos/scripts/build-native-app.sh --update-delivery-mode manualDownload --no-open
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

list_rpaths() {
  local binary_path="$1"
  otool -l "$binary_path" | awk '
    $1 == "cmd" && $2 == "LC_RPATH" { capture=1; next }
    capture && $1 == "path" { print $2; capture=0 }
  '
}

ensure_binary_rpath() {
  local binary_path="$1"
  local required_rpath="$2"
  if list_rpaths "$binary_path" | grep -Fxq "$required_rpath"; then
    log "主可执行文件已包含 rpath：${required_rpath}"
    return
  fi
  log "为主可执行文件注入 rpath：${required_rpath}"
  install_name_tool -add_rpath "$required_rpath" "$binary_path"
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
    --build-number)
      [[ $# -ge 2 ]] || fail "--build-number 需要参数"
      BUNDLE_BUILD_NUMBER="$2"
      shift 2
      ;;
    --update-channel)
      [[ $# -ge 2 ]] || fail "--update-channel 需要参数"
      UPDATE_CHANNEL="$2"
      shift 2
      ;;
    --update-delivery-mode)
      [[ $# -ge 2 ]] || fail "--update-delivery-mode 需要参数"
      UPDATE_DELIVERY_MODE="$2"
      shift 2
      ;;
    --sparkle-public-key)
      [[ $# -ge 2 ]] || fail "--sparkle-public-key 需要参数"
      SPARKLE_PUBLIC_KEY="$2"
      shift 2
      ;;
    --triple)
      [[ $# -ge 2 ]] || fail "--triple 需要参数"
      SWIFT_TRIPLE="$2"
      shift 2
      ;;
    --skip-sign)
      SKIP_SIGN=1
      shift
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

[[ "$UPDATE_CHANNEL" == "stable" || "$UPDATE_CHANNEL" == "nightly" ]] || fail "--update-channel 仅支持 stable 或 nightly"
[[ "$UPDATE_DELIVERY_MODE" == "automatic" || "$UPDATE_DELIVERY_MODE" == "manualDownload" ]] || fail "--update-delivery-mode 仅支持 automatic 或 manualDownload"
[[ "$BUNDLE_BUILD_NUMBER" =~ ^[0-9]+$ ]] || fail "--build-number 必须是非负整数"

if [[ -z "$OUTPUT_DIR" ]]; then
  OUTPUT_DIR="$MACOS_DIR/.build/native-app/$CONFIGURATION"
fi
OUTPUT_DIR="$(resolve_path "$OUTPUT_DIR")"

APP_BUNDLE_NAME="$APP_NAME.app"
APP_OUTPUT_PATH="$OUTPUT_DIR/$APP_BUNDLE_NAME"
STAGE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/devhaven-native-app.XXXXXX")"
APP_STAGE_PATH="$STAGE_DIR/$APP_BUNDLE_NAME"
INFO_PLIST_PATH="$APP_STAGE_PATH/Contents/Info.plist"
FRAMEWORKS_PATH="$APP_STAGE_PATH/Contents/Frameworks"
SPARKLE_FRAMEWORK_SRC="$MACOS_DIR/Vendor/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"

cleanup() {
  rm -rf "$STAGE_DIR"
}
trap cleanup EXIT

command -v swift >/dev/null 2>&1 || fail "未检测到 swift，请先安装 Xcode Command Line Tools 或 Xcode"
command -v plutil >/dev/null 2>&1 || fail "未检测到 plutil"
command -v codesign >/dev/null 2>&1 || fail "未检测到 codesign"
command -v ditto >/dev/null 2>&1 || fail "未检测到 ditto"
command -v otool >/dev/null 2>&1 || fail "未检测到 otool"
command -v install_name_tool >/dev/null 2>&1 || fail "未检测到 install_name_tool"

SWIFT_BUILD_ARGS=(-c "$CONFIGURATION" --package-path "$MACOS_DIR")
if [[ -n "$SWIFT_TRIPLE" ]]; then
  SWIFT_BUILD_ARGS+=(--triple "$SWIFT_TRIPLE")
fi

log "确保 Ghostty vendor 可用"
bash "$SCRIPT_DIR/setup-ghostty-framework.sh" --ensure-worktree-vendor

log "确保 Sparkle vendor 可用"
bash "$SCRIPT_DIR/setup-sparkle-framework.sh" --ensure-worktree-vendor

log "开始构建 Swift 原生版（configuration=${CONFIGURATION}${SWIFT_TRIPLE:+, triple=$SWIFT_TRIPLE}）"
swift build "${SWIFT_BUILD_ARGS[@]}"
swift build "${SWIFT_BUILD_ARGS[@]}" --product DevHavenCLI

BIN_DIR="$(swift build "${SWIFT_BUILD_ARGS[@]}" --show-bin-path)"
EXECUTABLE_PATH="$BIN_DIR/DevHavenApp"
CLI_HELPER_PATH="$BIN_DIR/DevHavenCLI"
RESOURCE_BUNDLE_PATH="$BIN_DIR/DevHavenNative_DevHavenApp.bundle"

[[ -f "$EXECUTABLE_PATH" ]] || fail "未找到原生可执行文件：$EXECUTABLE_PATH"
[[ -f "$CLI_HELPER_PATH" ]] || fail "未找到 CLI helper：$CLI_HELPER_PATH"
[[ -d "$RESOURCE_BUNDLE_PATH" ]] || fail "未找到 SwiftPM 资源 bundle：$RESOURCE_BUNDLE_PATH"
[[ -d "$SPARKLE_FRAMEWORK_SRC" ]] || fail "未找到 Sparkle.framework：$SPARKLE_FRAMEWORK_SRC"

DEFAULT_FEED_URL="$STABLE_FEED_URL"
if [[ "$UPDATE_CHANNEL" == "nightly" ]]; then
  DEFAULT_FEED_URL="$NIGHTLY_FEED_URL"
fi
[[ -n "$DEFAULT_FEED_URL" ]] || fail "默认更新 feed 不能为空，请配置 AppMetadata 或环境变量"

log "组装本地 .app bundle"
mkdir -p "$APP_STAGE_PATH/Contents/MacOS" "$APP_STAGE_PATH/Contents/Resources" "$FRAMEWORKS_PATH"
cp "$EXECUTABLE_PATH" "$APP_STAGE_PATH/Contents/MacOS/DevHavenApp"
cp "$CLI_HELPER_PATH" "$APP_STAGE_PATH/Contents/MacOS/DevHavenCLI"
ditto "$RESOURCE_BUNDLE_PATH" "$APP_STAGE_PATH/Contents/Resources/$(basename "$RESOURCE_BUNDLE_PATH")"
ditto "$SPARKLE_FRAMEWORK_SRC" "$FRAMEWORKS_PATH/Sparkle.framework"
ensure_binary_rpath "$APP_STAGE_PATH/Contents/MacOS/DevHavenApp" "@executable_path/../Frameworks"

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
  <string>$BUNDLE_BUILD_NUMBER</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>SUEnableAutomaticChecks</key>
  <true/>
  <key>SUAutomaticallyUpdate</key>
  <false/>
  <key>SUFeedURL</key>
  <string>$DEFAULT_FEED_URL</string>
  <key>DevHavenStableFeedURL</key>
  <string>$STABLE_FEED_URL</string>
  <key>DevHavenNightlyFeedURL</key>
  <string>$NIGHTLY_FEED_URL</string>
  <key>DevHavenDefaultUpdateChannel</key>
  <string>$UPDATE_CHANNEL</string>
  <key>DevHavenUpdateDeliveryMode</key>
  <string>$UPDATE_DELIVERY_MODE</string>
  <key>DevHavenStableDownloadsPageURL</key>
  <string>$STABLE_DOWNLOADS_PAGE_URL</string>
  <key>DevHavenNightlyDownloadsPageURL</key>
  <string>$NIGHTLY_DOWNLOADS_PAGE_URL</string>
PLIST

if (( HAS_ICON )); then
  cat >> "$INFO_PLIST_PATH" <<'PLIST'
  <key>CFBundleIconFile</key>
  <string>DevHaven.icns</string>
PLIST
fi

if [[ -n "$SPARKLE_PUBLIC_KEY" ]]; then
  cat >> "$INFO_PLIST_PATH" <<PLIST
  <key>SUPublicEDKey</key>
  <string>$SPARKLE_PUBLIC_KEY</string>
PLIST
fi

cat >> "$INFO_PLIST_PATH" <<'PLIST'
</dict>
</plist>
PLIST

chmod +x "$APP_STAGE_PATH/Contents/MacOS/DevHavenApp"
chmod +x "$APP_STAGE_PATH/Contents/MacOS/DevHavenCLI"
plutil -lint "$INFO_PLIST_PATH" >/dev/null

mkdir -p "$OUTPUT_DIR"
if [[ -e "$APP_OUTPUT_PATH" ]]; then
  log "清理旧产物：${APP_OUTPUT_PATH}"
  rm -rf "$APP_OUTPUT_PATH"
fi
ditto "$APP_STAGE_PATH" "$APP_OUTPUT_PATH"

if (( ! SKIP_SIGN )); then
  log "执行本地 ad-hoc 签名"
  codesign --force --deep --sign - "$APP_OUTPUT_PATH" >/dev/null
  codesign --verify --deep --strict "$APP_OUTPUT_PATH"
else
  log "跳过签名，等待外部流程显式签名"
fi

log "原生 App 已生成：${APP_OUTPUT_PATH}"
log "产物目录：${OUTPUT_DIR}"
printf 'APP_PATH=%s\n' "$APP_OUTPUT_PATH"
printf 'OUTPUT_DIR=%s\n' "$OUTPUT_DIR"

if (( OPEN_OUTPUT_DIR )); then
  command -v open >/dev/null 2>&1 || fail "未检测到 open"
  log "打开产物目录"
  open "$OUTPUT_DIR"
fi
