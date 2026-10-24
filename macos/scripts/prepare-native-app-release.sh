#!/usr/bin/env bash
set -euo pipefail

APP_PATH="${1:?用法：prepare-native-app-release.sh <已组装的 App 路径>}"
CMUX_FRAMEWORK="$APP_PATH/Contents/Frameworks/CmuxEmbedded.framework"
BINARIES=(
  "$APP_PATH/Contents/MacOS/DevHavenApp"
  "$APP_PATH/Contents/MacOS/DevHavenCLI"
  "$CMUX_FRAMEWORK/Versions/A/CmuxEmbedded"
)

# 只处理 staging App，保留 SwiftPM / Xcode 的原始构建产物供链接与调试。
for binary in "${BINARIES[@]}"; do
  [[ -f "$binary" ]] || { echo "缺少待精简的发布二进制：$binary" >&2; exit 1; }
done

for binary in "${BINARIES[@]}"; do
  before="$(stat -f %z "$binary")"
  # 保留全局符号，确保 cmux 的 dlopen / dlsym C ABI 入口继续可用。
  # 此操作使旧签名失效；调用者必须在全部精简操作后重新签名。
  xcrun strip -S -x "$binary"
  after="$(stat -f %z "$binary")"
  printf '发布符号精简：%s，%s -> %s bytes\n' "$(basename "$binary")" "$before" "$after"
done

# Swift 编译模块与源码索引仅用于编译，不参与 App 运行。
# 同时删除版本目录和顶层链接，避免保留指向不存在目录的符号链接。
rm -rf "$CMUX_FRAMEWORK/Versions/A/Modules" "$CMUX_FRAMEWORK/Modules"
