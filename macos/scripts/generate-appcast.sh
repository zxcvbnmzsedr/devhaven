#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MACOS_DIR="$(dirname "$SCRIPT_DIR")"
ARCHIVES_DIR=""
DOWNLOAD_URL_PREFIX=""
OUTPUT_PATH=""
CHANNEL=""
MAXIMUM_VERSIONS="3"
MAXIMUM_DELTAS="0"
LINK_URL=""
FULL_RELEASE_NOTES_URL=""
RELEASE_NOTES_URL_PREFIX=""
EMBED_RELEASE_NOTES=0
PRIVATE_KEY_ENV_NAME="DEVHAVEN_SPARKLE_PRIVATE_KEY"
PRIVATE_KEY_FILE=""

usage() {
  cat <<'USAGE'
用法：generate-appcast.sh --archives-dir <path> --download-url-prefix <url> [选项]

作用：
  统一封装 Sparkle generate_appcast，为 DevHaven stable/nightly 发布生成 appcast。

选项：
  --archives-dir <path>               存放更新归档（zip 等）的目录
  --download-url-prefix <url>         appcast enclosure 使用的下载前缀
  --output <path>                     指定输出 appcast 路径；默认 <archives-dir>/appcast.xml
  --channel <name>                    为新生成条目写入 Sparkle channel（如 nightly）
  --maximum-versions <num>            每个分支点最多保留多少个版本（默认：3）
  --maximum-deltas <num>              为最新版本最多生成多少个 delta（默认：0）
  --link <url>                        产品主页链接
  --full-release-notes-url <url>      完整发布说明链接
  --release-notes-url-prefix <url>    release notes URL 前缀
  --embed-release-notes               强制把 release notes 嵌入 appcast
  --private-key-env <name>            私钥环境变量名（默认：DEVHAVEN_SPARKLE_PRIVATE_KEY）
  --private-key-file <path>           私钥文件路径；若未提供则尝试从环境变量读取
  --help                              显示帮助
USAGE
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
    --archives-dir)
      [[ $# -ge 2 ]] || fail "--archives-dir 需要参数"
      ARCHIVES_DIR="$2"
      shift 2
      ;;
    --download-url-prefix)
      [[ $# -ge 2 ]] || fail "--download-url-prefix 需要参数"
      DOWNLOAD_URL_PREFIX="$2"
      shift 2
      ;;
    --output)
      [[ $# -ge 2 ]] || fail "--output 需要参数"
      OUTPUT_PATH="$2"
      shift 2
      ;;
    --channel)
      [[ $# -ge 2 ]] || fail "--channel 需要参数"
      CHANNEL="$2"
      shift 2
      ;;
    --maximum-versions)
      [[ $# -ge 2 ]] || fail "--maximum-versions 需要参数"
      MAXIMUM_VERSIONS="$2"
      shift 2
      ;;
    --maximum-deltas)
      [[ $# -ge 2 ]] || fail "--maximum-deltas 需要参数"
      MAXIMUM_DELTAS="$2"
      shift 2
      ;;
    --link)
      [[ $# -ge 2 ]] || fail "--link 需要参数"
      LINK_URL="$2"
      shift 2
      ;;
    --full-release-notes-url)
      [[ $# -ge 2 ]] || fail "--full-release-notes-url 需要参数"
      FULL_RELEASE_NOTES_URL="$2"
      shift 2
      ;;
    --release-notes-url-prefix)
      [[ $# -ge 2 ]] || fail "--release-notes-url-prefix 需要参数"
      RELEASE_NOTES_URL_PREFIX="$2"
      shift 2
      ;;
    --embed-release-notes)
      EMBED_RELEASE_NOTES=1
      shift
      ;;
    --private-key-env)
      [[ $# -ge 2 ]] || fail "--private-key-env 需要参数"
      PRIVATE_KEY_ENV_NAME="$2"
      shift 2
      ;;
    --private-key-file)
      [[ $# -ge 2 ]] || fail "--private-key-file 需要参数"
      PRIVATE_KEY_FILE="$2"
      shift 2
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

[[ -n "$ARCHIVES_DIR" ]] || fail "必须提供 --archives-dir"
[[ -n "$DOWNLOAD_URL_PREFIX" ]] || fail "必须提供 --download-url-prefix"
[[ "$MAXIMUM_VERSIONS" =~ ^[0-9]+$ ]] || fail "--maximum-versions 必须是非负整数"
[[ "$MAXIMUM_DELTAS" =~ ^[0-9]+$ ]] || fail "--maximum-deltas 必须是非负整数"

ARCHIVES_DIR="$(resolve_path "$ARCHIVES_DIR")"
OUTPUT_PATH="${OUTPUT_PATH:-$ARCHIVES_DIR/appcast.xml}"
OUTPUT_PATH="$(resolve_path "$OUTPUT_PATH")"
if [[ -n "$PRIVATE_KEY_FILE" ]]; then
  PRIVATE_KEY_FILE="$(resolve_path "$PRIVATE_KEY_FILE")"
fi

[[ -d "$ARCHIVES_DIR" ]] || fail "archives 目录不存在：$ARCHIVES_DIR"

bash "$SCRIPT_DIR/setup-sparkle-framework.sh" --ensure-worktree-vendor >/dev/null

TOOL_PATH="$MACOS_DIR/Vendor/SparkleTools/bin/generate_appcast"
[[ -x "$TOOL_PATH" ]] || fail "未找到 generate_appcast：$TOOL_PATH"

cmd=(
  "$TOOL_PATH"
  --download-url-prefix "$DOWNLOAD_URL_PREFIX"
  --maximum-versions "$MAXIMUM_VERSIONS"
  --maximum-deltas "$MAXIMUM_DELTAS"
  -o "$OUTPUT_PATH"
)

if [[ -n "$CHANNEL" ]]; then
  cmd+=(--channel "$CHANNEL")
fi
if [[ -n "$LINK_URL" ]]; then
  cmd+=(--link "$LINK_URL")
fi
if [[ -n "$FULL_RELEASE_NOTES_URL" ]]; then
  cmd+=(--full-release-notes-url "$FULL_RELEASE_NOTES_URL")
fi
if [[ -n "$RELEASE_NOTES_URL_PREFIX" ]]; then
  cmd+=(--release-notes-url-prefix "$RELEASE_NOTES_URL_PREFIX")
fi
if (( EMBED_RELEASE_NOTES )); then
  cmd+=(--embed-release-notes)
fi

private_key=""
if [[ -n "$PRIVATE_KEY_FILE" ]]; then
  [[ -f "$PRIVATE_KEY_FILE" ]] || fail "私钥文件不存在：$PRIVATE_KEY_FILE"
  cmd+=(--ed-key-file "$PRIVATE_KEY_FILE")
elif [[ -n "${!PRIVATE_KEY_ENV_NAME:-}" ]]; then
  private_key="${!PRIVATE_KEY_ENV_NAME}"
  cmd+=(--ed-key-file -)
else
  fail "未提供 Sparkle 私钥。请设置 $PRIVATE_KEY_ENV_NAME 或 --private-key-file"
fi

cmd+=("$ARCHIVES_DIR")

if [[ -n "$private_key" ]]; then
  printf '%s' "$private_key" | "${cmd[@]}"
else
  "${cmd[@]}"
fi

[[ -f "$OUTPUT_PATH" ]] || fail "未生成 appcast：$OUTPUT_PATH"
command -v python3 >/dev/null 2>&1 || fail "未检测到 python3，无法校验 appcast XML"
python3 - "$OUTPUT_PATH" <<'PY2'
import sys
import xml.etree.ElementTree as ET
ET.parse(sys.argv[1])
PY2

printf 'APPCAST_PATH=%s\n' "$OUTPUT_PATH"
