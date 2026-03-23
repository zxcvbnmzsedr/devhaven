#!/usr/bin/env bash
set -euo pipefail

ARM64_APP=""
X86_APP=""
OUTPUT_APP=""

usage() {
  cat <<'USAGE'
用法：create-universal-app.sh --arm64-app <path> --x86-app <path> --output <path>

作用：
  以 arm64 产物为基础复制一份 .app，并用 lipo 合成通用二进制，生成可给 Sparkle 更新 feed 使用的 universal App。
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

find_executable() {
  local app_path="$1"
  find "$app_path/Contents/MacOS" -mindepth 1 -maxdepth 1 -type f -print -quit
}

plist_value() {
  local plist_path="$1"
  local key="$2"
  /usr/libexec/PlistBuddy -c "Print :$key" "$plist_path" 2>/dev/null || true
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --arm64-app)
      [[ $# -ge 2 ]] || fail "--arm64-app 需要参数"
      ARM64_APP="$2"
      shift 2
      ;;
    --x86-app)
      [[ $# -ge 2 ]] || fail "--x86-app 需要参数"
      X86_APP="$2"
      shift 2
      ;;
    --output)
      [[ $# -ge 2 ]] || fail "--output 需要参数"
      OUTPUT_APP="$2"
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

[[ -n "$ARM64_APP" ]] || fail "必须提供 --arm64-app"
[[ -n "$X86_APP" ]] || fail "必须提供 --x86-app"
[[ -n "$OUTPUT_APP" ]] || fail "必须提供 --output"

command -v ditto >/dev/null 2>&1 || fail "未检测到 ditto"
command -v lipo >/dev/null 2>&1 || fail "未检测到 lipo"
command -v /usr/libexec/PlistBuddy >/dev/null 2>&1 || fail "未检测到 PlistBuddy"

ARM64_APP="$(resolve_path "$ARM64_APP")"
X86_APP="$(resolve_path "$X86_APP")"
OUTPUT_APP="$(resolve_path "$OUTPUT_APP")"

[[ -d "$ARM64_APP" ]] || fail "arm64 .app 不存在：$ARM64_APP"
[[ -d "$X86_APP" ]] || fail "x86_64 .app 不存在：$X86_APP"

arm64_plist="$ARM64_APP/Contents/Info.plist"
x86_plist="$X86_APP/Contents/Info.plist"
[[ -f "$arm64_plist" ]] || fail "arm64 Info.plist 不存在：$arm64_plist"
[[ -f "$x86_plist" ]] || fail "x86_64 Info.plist 不存在：$x86_plist"

arm64_exec="$(find_executable "$ARM64_APP")"
x86_exec="$(find_executable "$X86_APP")"
[[ -n "$arm64_exec" ]] || fail "arm64 .app 缺少可执行文件"
[[ -n "$x86_exec" ]] || fail "x86_64 .app 缺少可执行文件"

arm64_exec_name="$(basename "$arm64_exec")"
x86_exec_name="$(basename "$x86_exec")"
[[ "$arm64_exec_name" == "$x86_exec_name" ]] || fail "两个 .app 的主可执行文件名称不一致：$arm64_exec_name / $x86_exec_name"

arm64_version="$(plist_value "$arm64_plist" CFBundleShortVersionString)"
x86_version="$(plist_value "$x86_plist" CFBundleShortVersionString)"
arm64_build="$(plist_value "$arm64_plist" CFBundleVersion)"
x86_build="$(plist_value "$x86_plist" CFBundleVersion)"
[[ "$arm64_version" == "$x86_version" ]] || fail "两个 .app 的 CFBundleShortVersionString 不一致：$arm64_version / $x86_version"
[[ "$arm64_build" == "$x86_build" ]] || fail "两个 .app 的 CFBundleVersion 不一致：$arm64_build / $x86_build"

mkdir -p "$(dirname "$OUTPUT_APP")"
rm -rf "$OUTPUT_APP"
ditto "$ARM64_APP" "$OUTPUT_APP"

output_exec="$OUTPUT_APP/Contents/MacOS/$arm64_exec_name"
lipo -create "$arm64_exec" "$x86_exec" -output "$output_exec"
chmod +x "$output_exec"

printf 'UNIVERSAL_APP=%s\n' "$OUTPUT_APP"
file "$output_exec"
