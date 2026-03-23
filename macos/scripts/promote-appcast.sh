#!/usr/bin/env bash
set -euo pipefail

REPO=""
RELEASE_TAG=""
APPCAST_PATH=""
ASSET_NAME="appcast.xml"
RELEASE_TITLE=""
PRERELEASE=0

usage() {
  cat <<'USAGE'
用法：promote-appcast.sh --repo <owner/repo> --release-tag <tag> --appcast <path> [选项]

作用：
  把 staged appcast 提升到稳定别名 release（如 stable-appcast / nightly），让客户端始终命中固定 feed URL。

选项：
  --repo <owner/repo>         目标 GitHub 仓库，例如 zxcvbnmzsedr/devhaven
  --release-tag <tag>         appcast alias release tag，例如 stable-appcast 或 nightly
  --appcast <path>            待上传的 appcast 文件路径
  --asset-name <name>         release asset 名称（默认：appcast.xml）
  --title <title>             release 标题；默认与 tag 相同
  --prerelease                若 release 不存在，则按 prerelease 创建
  --help                      显示帮助
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
    --repo)
      [[ $# -ge 2 ]] || fail "--repo 需要参数"
      REPO="$2"
      shift 2
      ;;
    --release-tag)
      [[ $# -ge 2 ]] || fail "--release-tag 需要参数"
      RELEASE_TAG="$2"
      shift 2
      ;;
    --appcast)
      [[ $# -ge 2 ]] || fail "--appcast 需要参数"
      APPCAST_PATH="$2"
      shift 2
      ;;
    --asset-name)
      [[ $# -ge 2 ]] || fail "--asset-name 需要参数"
      ASSET_NAME="$2"
      shift 2
      ;;
    --title)
      [[ $# -ge 2 ]] || fail "--title 需要参数"
      RELEASE_TITLE="$2"
      shift 2
      ;;
    --prerelease)
      PRERELEASE=1
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

[[ -n "$REPO" ]] || fail "必须提供 --repo"
[[ -n "$RELEASE_TAG" ]] || fail "必须提供 --release-tag"
[[ -n "$APPCAST_PATH" ]] || fail "必须提供 --appcast"
command -v gh >/dev/null 2>&1 || fail "未检测到 gh CLI"

APPCAST_PATH="$(resolve_path "$APPCAST_PATH")"
[[ -f "$APPCAST_PATH" ]] || fail "appcast 文件不存在：$APPCAST_PATH"
[[ -n "${GH_TOKEN:-}" ]] || fail "必须提供 GH_TOKEN，供 gh release 上传"

RELEASE_TITLE="${RELEASE_TITLE:-$RELEASE_TAG}"

if gh release view "$RELEASE_TAG" -R "$REPO" >/dev/null 2>&1; then
  gh release edit "$RELEASE_TAG" -R "$REPO" --title "$RELEASE_TITLE" >/dev/null
else
  create_args=(release create "$RELEASE_TAG" -R "$REPO" --title "$RELEASE_TITLE" --notes "")
  if (( PRERELEASE )); then
    create_args+=(--prerelease)
  fi
  gh "${create_args[@]}" >/dev/null
fi

gh release upload "$RELEASE_TAG" "$APPCAST_PATH#$ASSET_NAME" -R "$REPO" --clobber >/dev/null
printf 'PROMOTED_RELEASE=%s\n' "$RELEASE_TAG"
printf 'PROMOTED_ASSET=%s\n' "$ASSET_NAME"
