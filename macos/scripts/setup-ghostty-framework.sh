#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MACOS_DIR="$(dirname "$SCRIPT_DIR")"
REPO_DIR="$(dirname "$MACOS_DIR")"

SOURCE_DIR="${GHOSTTY_SOURCE_DIR:-}"
VENDOR_DIR="$MACOS_DIR/Vendor"
SKIP_BUILD=0
VERIFY_ONLY=0

usage() {
  cat <<USAGE
用法：$(basename "$0") [选项]

作用：
  从 Ghostty 源码目录构建或复制 GhosttyKit.xcframework / 资源文件，
  并写入当前仓库的 macos/Vendor（或自定义 vendor 目录）。

选项：
  --source <path>      Ghostty 源码目录；也可用环境变量 GHOSTTY_SOURCE_DIR
  --vendor-dir <path>  输出目录，默认：$VENDOR_DIR
  --skip-build         不执行 zig build，直接复用 source 下现有产物
  --verify-only        只验证 vendor 目录是否完整，不做复制
  --help               显示帮助

典型用法：
  bash macos/scripts/setup-ghostty-framework.sh --source /path/to/ghostty
  bash macos/scripts/setup-ghostty-framework.sh --source /path/to/ghostty --skip-build
  bash macos/scripts/setup-ghostty-framework.sh --verify-only
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
  local parent
  parent="$(cd "$(dirname "$input")" && pwd)"
  printf '%s/%s\n' "$parent" "$(basename "$input")"
}

copy_tree() {
  local src="$1"
  local dst="$2"
  [[ -d "$src" ]] || fail "目录不存在：$src"
  mkdir -p "$dst"
  rsync -a --delete "$src/" "$dst/"
}

verify_vendor() {
  local vendor_dir="$1"
  local framework_dir="$vendor_dir/GhosttyKit.xcframework"
  local resources_root="$vendor_dir/GhosttyResources"
  local ghostty_dir="$resources_root/ghostty"
  local terminfo_dir="$resources_root/terminfo"
  local issues=()

  if [[ ! -d "$framework_dir" ]]; then
    issues+=("缺少 GhosttyKit.xcframework：$framework_dir")
  fi
  if [[ ! -f "$framework_dir/Info.plist" ]]; then
    issues+=("GhosttyKit.xcframework 缺少 Info.plist：$framework_dir/Info.plist")
  fi

  local framework_payload=""
  if [[ -d "$framework_dir" ]]; then
    framework_payload="$(find "$framework_dir" -mindepth 2 -maxdepth 2 \( -type f -o -type d \) ! -name 'Info.plist' ! -path '*/Headers*' ! -path '*/Modules*' -print -quit 2>/dev/null || true)"
    if [[ -z "$framework_payload" ]]; then
      issues+=("GhosttyKit.xcframework 未检测到任何 framework/library payload（当前通常意味着只有 Headers）")
    fi
  fi

  if [[ ! -d "$ghostty_dir/themes" ]]; then
    issues+=("GhosttyResources 缺少 themes 目录：$ghostty_dir/themes")
  fi

  local terminfo_payload=""
  if [[ -d "$terminfo_dir" ]]; then
    terminfo_payload="$(find "$terminfo_dir" -type f -print -quit 2>/dev/null || true)"
  fi
  if [[ -z "$terminfo_payload" ]]; then
    issues+=("GhosttyResources 缺少 terminfo 内容：$terminfo_dir")
  fi

  if ((${#issues[@]} > 0)); then
    printf 'Ghostty vendor 验证失败：%s\n' "$vendor_dir" >&2
    for issue in "${issues[@]}"; do
      printf '  - %s\n' "$issue" >&2
    done
    return 1
  fi

  log "Ghostty vendor 验证通过：$vendor_dir"
  if [[ -n "$framework_payload" ]]; then
    printf '    framework payload: %s\n' "$framework_payload"
  fi
  if [[ -n "$terminfo_payload" ]]; then
    printf '    terminfo payload: %s\n' "$terminfo_payload"
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source)
      [[ $# -ge 2 ]] || fail "--source 需要路径参数"
      SOURCE_DIR="$2"
      shift 2
      ;;
    --vendor-dir)
      [[ $# -ge 2 ]] || fail "--vendor-dir 需要路径参数"
      VENDOR_DIR="$2"
      shift 2
      ;;
    --skip-build)
      SKIP_BUILD=1
      shift
      ;;
    --verify-only)
      VERIFY_ONLY=1
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

VENDOR_DIR="$(resolve_path "$VENDOR_DIR")"

if (( VERIFY_ONLY )); then
  verify_vendor "$VENDOR_DIR"
  exit 0
fi

[[ -n "$SOURCE_DIR" ]] || fail "请通过 --source 或 GHOSTTY_SOURCE_DIR 指定 Ghostty 源码目录"
SOURCE_DIR="$(resolve_path "$SOURCE_DIR")"
[[ -d "$SOURCE_DIR" ]] || fail "Ghostty 源码目录不存在：$SOURCE_DIR"
[[ -f "$SOURCE_DIR/build.zig" ]] || fail "Ghostty 源码目录缺少 build.zig：$SOURCE_DIR"

if (( ! SKIP_BUILD )); then
  command -v zig >/dev/null 2>&1 || fail "未检测到 zig，请先安装 zig"
  log "开始构建 GhosttyKit.xcframework"
  (
    cd "$SOURCE_DIR"
    zig build -Doptimize=ReleaseFast -Demit-xcframework=true -Dsentry=false
  )
else
  log "跳过 zig build，直接复用现有 Ghostty 构建产物"
fi

FRAMEWORK_SRC="$SOURCE_DIR/macos/GhosttyKit.xcframework"
GHOSTTY_RESOURCE_SRC="$SOURCE_DIR/zig-out/share/ghostty"
TERMINFO_SRC="$SOURCE_DIR/zig-out/share/terminfo"
MAN_SRC="$SOURCE_DIR/zig-out/share/man"

[[ -d "$FRAMEWORK_SRC" ]] || fail "未找到 GhosttyKit.xcframework：$FRAMEWORK_SRC"
[[ -d "$GHOSTTY_RESOURCE_SRC" ]] || fail "未找到 ghostty 资源目录：$GHOSTTY_RESOURCE_SRC"
[[ -d "$TERMINFO_SRC" ]] || fail "未找到 terminfo 目录：$TERMINFO_SRC"

log "同步 Ghostty framework 到 $VENDOR_DIR"
copy_tree "$FRAMEWORK_SRC" "$VENDOR_DIR/GhosttyKit.xcframework"

log "同步 GhosttyResources/ghostty 到 $VENDOR_DIR/GhosttyResources/ghostty"
copy_tree "$GHOSTTY_RESOURCE_SRC" "$VENDOR_DIR/GhosttyResources/ghostty"

log "同步 GhosttyResources/terminfo 到 $VENDOR_DIR/GhosttyResources/terminfo"
copy_tree "$TERMINFO_SRC" "$VENDOR_DIR/GhosttyResources/terminfo"

if [[ -d "$MAN_SRC" ]]; then
  log "同步 GhosttyResources/man 到 $VENDOR_DIR/GhosttyResources/man"
  copy_tree "$MAN_SRC" "$VENDOR_DIR/GhosttyResources/man"
fi

verify_vendor "$VENDOR_DIR"
log "Ghostty vendor 已准备完成。后续可重新运行 swift test --package-path macos 验证。"
