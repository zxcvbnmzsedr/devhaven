#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MACOS_DIR="$(dirname "$SCRIPT_DIR")"
REPO_DIR="$(dirname "$MACOS_DIR")"
VENDOR_DIR="$MACOS_DIR/Vendor"
SPARKLE_VERSION="${DEVHAVEN_SPARKLE_VERSION:-2.8.1}"
SPARKLE_URL="${DEVHAVEN_SPARKLE_URL:-https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-for-Swift-Package-Manager.zip}"
VERIFY_ONLY=0
ENSURE_WORKTREE_VENDOR=0

usage() {
  cat <<USAGE
用法：$(basename "$0") [选项]

作用：
  准备 DevHaven 所需的 Sparkle.xcframework 与 generate_appcast/sign_update 工具，
  默认写入 macos/Vendor。

选项：
  --vendor-dir <path>          输出目录，默认：$VENDOR_DIR
  --verify-only                只校验 vendor，不下载
  --ensure-worktree-vendor     若当前 worktree 缺失，则优先复用同仓库其他 worktree 已准备好的 Sparkle vendor；若都没有则自动下载
  --help                       显示帮助
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
  local framework_dir="$vendor_dir/Sparkle.xcframework"
  local framework_payload="$framework_dir/macos-arm64_x86_64/Sparkle.framework"
  local tool_dir="$vendor_dir/SparkleTools/bin"
  local issues=()

  [[ -d "$framework_dir" ]] || issues+=("缺少 Sparkle.xcframework：$framework_dir")
  [[ -f "$framework_dir/Info.plist" ]] || issues+=("Sparkle.xcframework 缺少 Info.plist：$framework_dir/Info.plist")
  [[ -d "$framework_payload" ]] || issues+=("缺少 Sparkle.framework payload：$framework_payload")
  [[ -x "$tool_dir/generate_appcast" ]] || issues+=("缺少 generate_appcast：$tool_dir/generate_appcast")
  [[ -x "$tool_dir/sign_update" ]] || issues+=("缺少 sign_update：$tool_dir/sign_update")

  if ((${#issues[@]} > 0)); then
    printf 'Sparkle vendor 验证失败：%s\n' "$vendor_dir" >&2
    for issue in "${issues[@]}"; do
      printf '  - %s\n' "$issue" >&2
    done
    return 1
  fi

  log "Sparkle vendor 验证通过：$vendor_dir"
}

vendor_is_valid() {
  local vendor_dir="$1"
  verify_vendor "$vendor_dir" >/dev/null 2>&1
}

find_reusable_worktree_vendor() {
  command -v git >/dev/null 2>&1 || return 1

  local line=""
  local worktree_path=""
  local candidate_vendor=""
  while IFS= read -r line; do
    [[ "$line" == worktree\ * ]] || continue
    worktree_path="${line#worktree }"
    [[ "$worktree_path" == "$REPO_DIR" ]] && continue

    candidate_vendor="$worktree_path/macos/Vendor"
    if vendor_is_valid "$candidate_vendor"; then
      printf '%s\n' "$candidate_vendor"
      return 0
    fi
  done < <(git -C "$REPO_DIR" worktree list --porcelain 2>/dev/null || true)

  return 1
}

download_vendor() {
  local vendor_dir="$1"
  local tmp_dir
  tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/devhaven-sparkle.XXXXXX")"

  command -v curl >/dev/null 2>&1 || fail "未检测到 curl"
  command -v unzip >/dev/null 2>&1 || fail "未检测到 unzip"

  log "下载 Sparkle ${SPARKLE_VERSION}"
  curl -L "$SPARKLE_URL" -o "$tmp_dir/sparkle.zip"
  unzip -q "$tmp_dir/sparkle.zip" -d "$tmp_dir/extracted"

  [[ -d "$tmp_dir/extracted/Sparkle.xcframework" ]] || fail "Sparkle 压缩包缺少 Sparkle.xcframework"
  [[ -d "$tmp_dir/extracted/bin" ]] || fail "Sparkle 压缩包缺少 bin 目录"

  log "同步 Sparkle.xcframework 到 $vendor_dir/Sparkle.xcframework"
  copy_tree "$tmp_dir/extracted/Sparkle.xcframework" "$vendor_dir/Sparkle.xcframework"

  log "同步 SparkleTools/bin 到 $vendor_dir/SparkleTools/bin"
  copy_tree "$tmp_dir/extracted/bin" "$vendor_dir/SparkleTools/bin"

  rm -rf "$tmp_dir"
}

ensure_worktree_vendor() {
  if vendor_is_valid "$VENDOR_DIR"; then
    log "当前 worktree 的 Sparkle vendor 已可用：$VENDOR_DIR"
    verify_vendor "$VENDOR_DIR"
    return 0
  fi

  local reusable_vendor=""
  reusable_vendor="$(find_reusable_worktree_vendor || true)"
  if [[ -n "$reusable_vendor" ]]; then
    log "复用同仓库其他 worktree 的 Sparkle vendor：$reusable_vendor"
    copy_tree "$reusable_vendor/Sparkle.xcframework" "$VENDOR_DIR/Sparkle.xcframework"
    copy_tree "$reusable_vendor/SparkleTools" "$VENDOR_DIR/SparkleTools"
    verify_vendor "$VENDOR_DIR"
    return 0
  fi

  download_vendor "$VENDOR_DIR"
  verify_vendor "$VENDOR_DIR"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --vendor-dir)
      [[ $# -ge 2 ]] || fail "--vendor-dir 需要路径参数"
      VENDOR_DIR="$2"
      shift 2
      ;;
    --verify-only)
      VERIFY_ONLY=1
      shift
      ;;
    --ensure-worktree-vendor)
      ENSURE_WORKTREE_VENDOR=1
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

if (( VERIFY_ONLY && ENSURE_WORKTREE_VENDOR )); then
  fail "--verify-only 与 --ensure-worktree-vendor 不能同时使用"
fi

if (( VERIFY_ONLY )); then
  verify_vendor "$VENDOR_DIR"
  exit 0
fi

if (( ENSURE_WORKTREE_VENDOR )); then
  ensure_worktree_vendor
  exit 0
fi

download_vendor "$VENDOR_DIR"
verify_vendor "$VENDOR_DIR"
