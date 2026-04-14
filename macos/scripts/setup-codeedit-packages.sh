#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MACOS_DIR="$(dirname "$SCRIPT_DIR")"
REPO_DIR="$(dirname "$MACOS_DIR")"
VENDOR_DIR="$MACOS_DIR/Vendor/CodeEditPackages"
VERIFY_ONLY=0
ENSURE_WORKTREE_VENDOR=0

CODEEDIT_SOURCE_EDITOR_URL="${DEVHAVEN_CODEEDIT_SOURCE_EDITOR_URL:-https://github.com/CodeEditApp/CodeEditSourceEditor.git}"
CODEEDIT_SOURCE_EDITOR_REF="${DEVHAVEN_CODEEDIT_SOURCE_EDITOR_REF:-main}"
CODEEDIT_TEXT_VIEW_URL="${DEVHAVEN_CODEEDIT_TEXT_VIEW_URL:-https://github.com/CodeEditApp/CodeEditTextView.git}"
CODEEDIT_TEXT_VIEW_REF="${DEVHAVEN_CODEEDIT_TEXT_VIEW_REF:-0.12.1}"
CODEEDIT_LANGUAGES_URL="${DEVHAVEN_CODEEDIT_LANGUAGES_URL:-https://github.com/CodeEditApp/CodeEditLanguages.git}"
CODEEDIT_LANGUAGES_REF="${DEVHAVEN_CODEEDIT_LANGUAGES_REF:-0.1.20}"
CODEEDIT_SYMBOLS_URL="${DEVHAVEN_CODEEDIT_SYMBOLS_URL:-https://github.com/CodeEditApp/CodeEditSymbols.git}"
CODEEDIT_SYMBOLS_REF="${DEVHAVEN_CODEEDIT_SYMBOLS_REF:-main}"

usage() {
  cat <<USAGE
用法：$(basename "$0") [选项]

作用：
  准备 DevHaven 所需的 CodeEdit 本地 package vendor，
  默认写入 macos/Vendor/CodeEditPackages。

选项：
  --vendor-dir <path>          输出目录，默认：$VENDOR_DIR
  --verify-only                只校验 vendor，不下载
  --ensure-worktree-vendor     若当前 worktree 缺失，则优先复用同仓库其他 worktree 已准备好的 CodeEditPackages vendor；若都没有则自动下载
  --help                       显示帮助

默认版本：
  CodeEditSourceEditor: $CODEEDIT_SOURCE_EDITOR_REF
  CodeEditTextView:     $CODEEDIT_TEXT_VIEW_REF
  CodeEditLanguages:    $CODEEDIT_LANGUAGES_REF
  CodeEditSymbols:      $CODEEDIT_SYMBOLS_REF
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
  rsync -a --delete --exclude '.git/' "$src/" "$dst/"
}

expected_refs_manifest() {
  cat <<EOF
CodeEditSourceEditor=${CODEEDIT_SOURCE_EDITOR_REF}
CodeEditTextView=${CODEEDIT_TEXT_VIEW_REF}
CodeEditLanguages=${CODEEDIT_LANGUAGES_REF}
CodeEditSymbols=${CODEEDIT_SYMBOLS_REF}
EOF
}

verify_vendor() {
  local vendor_dir="$1"
  local issues=()
  local refs_file="$vendor_dir/.devhaven-codeedit-refs"
  local source_editor_package="$vendor_dir/CodeEditSourceEditor/Package.swift"

  if [[ ! -d "$vendor_dir/CodeEditSourceEditor" ]]; then
    issues+=("缺少 CodeEditSourceEditor：$vendor_dir/CodeEditSourceEditor")
  fi
  if [[ ! -f "$vendor_dir/CodeEditSourceEditor/Package.swift" ]]; then
    issues+=("CodeEditSourceEditor 缺少 Package.swift：$vendor_dir/CodeEditSourceEditor/Package.swift")
  fi
  if [[ ! -d "$vendor_dir/CodeEditSourceEditor/Sources" ]]; then
    issues+=("CodeEditSourceEditor 缺少 Sources：$vendor_dir/CodeEditSourceEditor/Sources")
  fi

  if [[ ! -d "$vendor_dir/CodeEditTextView" ]]; then
    issues+=("缺少 CodeEditTextView：$vendor_dir/CodeEditTextView")
  fi
  if [[ ! -f "$vendor_dir/CodeEditTextView/Package.swift" ]]; then
    issues+=("CodeEditTextView 缺少 Package.swift：$vendor_dir/CodeEditTextView/Package.swift")
  fi
  if [[ ! -d "$vendor_dir/CodeEditTextView/Sources" ]]; then
    issues+=("CodeEditTextView 缺少 Sources：$vendor_dir/CodeEditTextView/Sources")
  fi

  if [[ ! -d "$vendor_dir/CodeEditLanguages" ]]; then
    issues+=("缺少 CodeEditLanguages：$vendor_dir/CodeEditLanguages")
  fi
  if [[ ! -f "$vendor_dir/CodeEditLanguages/Package.swift" ]]; then
    issues+=("CodeEditLanguages 缺少 Package.swift：$vendor_dir/CodeEditLanguages/Package.swift")
  fi
  if [[ ! -f "$vendor_dir/CodeEditLanguages/CodeLanguagesContainer.xcframework.zip" ]]; then
    issues+=("CodeEditLanguages 缺少 CodeLanguagesContainer.xcframework.zip：$vendor_dir/CodeEditLanguages/CodeLanguagesContainer.xcframework.zip")
  fi
  if [[ ! -d "$vendor_dir/CodeEditLanguages/Sources" ]]; then
    issues+=("CodeEditLanguages 缺少 Sources：$vendor_dir/CodeEditLanguages/Sources")
  fi

  if [[ ! -d "$vendor_dir/CodeEditSymbols" ]]; then
    issues+=("缺少 CodeEditSymbols：$vendor_dir/CodeEditSymbols")
  fi
  if [[ ! -f "$vendor_dir/CodeEditSymbols/Package.swift" ]]; then
    issues+=("CodeEditSymbols 缺少 Package.swift：$vendor_dir/CodeEditSymbols/Package.swift")
  fi
  if [[ ! -d "$vendor_dir/CodeEditSymbols/Sources/CodeEditSymbols/Symbols.xcassets" ]]; then
    issues+=("CodeEditSymbols 缺少 Symbols.xcassets：$vendor_dir/CodeEditSymbols/Sources/CodeEditSymbols/Symbols.xcassets")
  fi

  if [[ ! -f "$refs_file" ]]; then
    issues+=("缺少 refs 清单：$refs_file")
  elif [[ "$(cat "$refs_file")" != "$(expected_refs_manifest)" ]]; then
    issues+=("refs 清单与当前期望版本不一致：$refs_file")
  fi

  if [[ -f "$source_editor_package" ]]; then
    grep -Fq '.package(path: "../CodeEditTextView")' "$source_editor_package" \
      || issues+=("CodeEditSourceEditor 尚未改写为本地 CodeEditTextView path 依赖：$source_editor_package")
    grep -Fq '.package(path: "../CodeEditLanguages")' "$source_editor_package" \
      || issues+=("CodeEditSourceEditor 尚未改写为本地 CodeEditLanguages path 依赖：$source_editor_package")
    grep -Fq '.package(path: "../CodeEditSymbols")' "$source_editor_package" \
      || issues+=("CodeEditSourceEditor 尚未改写为本地 CodeEditSymbols path 依赖：$source_editor_package")
  fi

  if ((${#issues[@]} > 0)); then
    printf 'CodeEditPackages vendor 验证失败：%s\n' "$vendor_dir" >&2
    for issue in "${issues[@]}"; do
      printf '  - %s\n' "$issue" >&2
    done
    return 1
  fi

  log "CodeEditPackages vendor 验证通过：$vendor_dir"
  printf '    refs: CodeEditSourceEditor=%s, CodeEditTextView=%s, CodeEditLanguages=%s\n' \
    "$CODEEDIT_SOURCE_EDITOR_REF" "$CODEEDIT_TEXT_VIEW_REF" "$CODEEDIT_LANGUAGES_REF"
  printf '          CodeEditSymbols=%s\n' "$CODEEDIT_SYMBOLS_REF"
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

    candidate_vendor="$worktree_path/macos/Vendor/CodeEditPackages"
    if vendor_is_valid "$candidate_vendor"; then
      printf '%s\n' "$candidate_vendor"
      return 0
    fi
  done < <(git -C "$REPO_DIR" worktree list --porcelain 2>/dev/null || true)

  return 1
}

clone_repo_snapshot() {
  local url="$1"
  local ref="$2"
  local dst="$3"

  log "下载 $(basename "$dst") (ref=${ref})"
  git clone --depth 1 --branch "$ref" "$url" "$dst" >/dev/null 2>&1 \
    || fail "下载失败：${url} @ ${ref}"
}

rewrite_source_editor_local_dependencies() {
  local package_file="$1"
  [[ -f "$package_file" ]] || fail "未找到 CodeEditSourceEditor Package.swift：$package_file"

  perl -0pi -e 's/\.package\(\s*url: "https:\/\/github\.com\/CodeEditApp\/CodeEditTextView\.git",\s*from: "[^"]+"\s*\)/.package(path: "..\/CodeEditTextView")/g' "$package_file"
  perl -0pi -e 's/\.package\(\s*url: "https:\/\/github\.com\/CodeEditApp\/CodeEditLanguages\.git",\s*exact: "[^"]+"\s*\)/.package(path: "..\/CodeEditLanguages")/g' "$package_file"
  perl -0pi -e 's/\.package\(\s*url: "https:\/\/github\.com\/CodeEditApp\/CodeEditSymbols\.git",\s*exact: "[^"]+"\s*\)/.package(path: "..\/CodeEditSymbols")/g' "$package_file"
}

rewrite_symbols_package_resources() {
  local package_file="$1"
  [[ -f "$package_file" ]] || fail "未找到 CodeEditSymbols Package.swift：$package_file"

  perl -0pi -e 's/\.target\(\s*name: "CodeEditSymbols",\s*dependencies: \[\]\s*\)/.target(\n            name: "CodeEditSymbols",\n            dependencies: [],\n            resources: [\n                .process("Symbols.xcassets")\n            ]\n        )/g' "$package_file"
}

write_refs_manifest() {
  local vendor_dir="$1"
  expected_refs_manifest > "$vendor_dir/.devhaven-codeedit-refs"
}

download_vendor() {
  local vendor_dir="$1"
  local tmp_dir
  tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/devhaven-codeedit.XXXXXX")"

  command -v git >/dev/null 2>&1 || fail "未检测到 git"

  clone_repo_snapshot "$CODEEDIT_SOURCE_EDITOR_URL" "$CODEEDIT_SOURCE_EDITOR_REF" "$tmp_dir/CodeEditSourceEditor"
  clone_repo_snapshot "$CODEEDIT_TEXT_VIEW_URL" "$CODEEDIT_TEXT_VIEW_REF" "$tmp_dir/CodeEditTextView"
  clone_repo_snapshot "$CODEEDIT_LANGUAGES_URL" "$CODEEDIT_LANGUAGES_REF" "$tmp_dir/CodeEditLanguages"
  clone_repo_snapshot "$CODEEDIT_SYMBOLS_URL" "$CODEEDIT_SYMBOLS_REF" "$tmp_dir/CodeEditSymbols"

  log "同步 CodeEditSourceEditor 到 $vendor_dir/CodeEditSourceEditor"
  copy_tree "$tmp_dir/CodeEditSourceEditor" "$vendor_dir/CodeEditSourceEditor"

  log "同步 CodeEditTextView 到 $vendor_dir/CodeEditTextView"
  copy_tree "$tmp_dir/CodeEditTextView" "$vendor_dir/CodeEditTextView"

  log "同步 CodeEditLanguages 到 $vendor_dir/CodeEditLanguages"
  copy_tree "$tmp_dir/CodeEditLanguages" "$vendor_dir/CodeEditLanguages"

  log "同步 CodeEditSymbols 到 $vendor_dir/CodeEditSymbols"
  copy_tree "$tmp_dir/CodeEditSymbols" "$vendor_dir/CodeEditSymbols"

  rewrite_source_editor_local_dependencies "$vendor_dir/CodeEditSourceEditor/Package.swift"
  rewrite_symbols_package_resources "$vendor_dir/CodeEditSymbols/Package.swift"
  write_refs_manifest "$vendor_dir"

  rm -rf "$tmp_dir"
}

ensure_worktree_vendor() {
  if vendor_is_valid "$VENDOR_DIR"; then
    log "当前 worktree 的 CodeEditPackages vendor 已可用：$VENDOR_DIR"
    verify_vendor "$VENDOR_DIR"
    return 0
  fi

  local reusable_vendor=""
  reusable_vendor="$(find_reusable_worktree_vendor || true)"
  if [[ -n "$reusable_vendor" ]]; then
    log "复用同仓库其他 worktree 的 CodeEditPackages vendor：$reusable_vendor"
    copy_tree "$reusable_vendor" "$VENDOR_DIR"
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
