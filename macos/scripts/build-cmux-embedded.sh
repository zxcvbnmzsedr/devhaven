#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MACOS_DIR="$(dirname "$SCRIPT_DIR")"
CMUX_DIR="$MACOS_DIR/ThirdParty/cmux"
INTEGRATION_DIR="$MACOS_DIR/CmuxEmbeddedIntegration"
OUTPUT_DIR="$MACOS_DIR/Vendor/CmuxEmbedded.xcframework"
DERIVED_DATA_DIR="$CMUX_DIR/build/embedded-derived-data"
BUILD_ARCH="${CMUX_EMBEDDED_ARCH:-$(uname -m)}"
BUILD_CONFIGURATION="${CMUX_EMBEDDED_CONFIGURATION:-Debug}"
CMUX_COMMIT="2ae26d1c7dff6a91104d23258b395f3b1b6940e9"

case "$BUILD_ARCH" in
  arm64|x86_64) ;;
  *) echo "Unsupported cmux build architecture: $BUILD_ARCH" >&2; exit 1 ;;
esac
case "$BUILD_CONFIGURATION" in
  Debug|Release) ;;
  *) echo "Unsupported cmux build configuration: $BUILD_CONFIGURATION" >&2; exit 1 ;;
esac

if [[ ! -e "$CMUX_DIR/.git" ]]; then
  git clone --filter=blob:none https://github.com/manaflow-ai/cmux.git "$CMUX_DIR"
  git -C "$CMUX_DIR" checkout --detach "$CMUX_COMMIT"
  git -C "$CMUX_DIR" submodule update --init --recursive
fi

[[ "$(git -C "$CMUX_DIR" rev-parse HEAD)" == "$CMUX_COMMIT" ]] || {
  echo "cmux source must be at $CMUX_COMMIT" >&2
  exit 1
}

if [[ ! -f "$CMUX_DIR/cmux.xcodeproj/xcshareddata/xcschemes/CmuxEmbedded.xcscheme" ]]; then
  project_file="$CMUX_DIR/cmux.xcodeproj/project.pbxproj"
  normalized_project="$(mktemp "${TMPDIR:-/tmp}/devhaven-cmux-project.XXXXXX")"
  plutil -convert xml1 -o "$normalized_project" "$project_file"
  mv "$normalized_project" "$project_file"
  patch -s -d "$CMUX_DIR" -p0 < "$INTEGRATION_DIR/cmux-project.patch"
  mkdir -p "$CMUX_DIR/cmux.xcodeproj/xcshareddata/xcschemes"
fi
cmp -s "$INTEGRATION_DIR/CmuxEmbedded.xcscheme" "$CMUX_DIR/cmux.xcodeproj/xcshareddata/xcschemes/CmuxEmbedded.xcscheme" ||
  cp "$INTEGRATION_DIR/CmuxEmbedded.xcscheme" "$CMUX_DIR/cmux.xcodeproj/xcshareddata/xcschemes/"
cmp -s "$INTEGRATION_DIR/CmuxEmbeddedRootView.swift" "$CMUX_DIR/Sources/CmuxEmbeddedRootView.swift" ||
  cp "$INTEGRATION_DIR/CmuxEmbeddedRootView.swift" "$CMUX_DIR/Sources/"

if git -C "$CMUX_DIR" apply --check "$INTEGRATION_DIR/cmux-lifecycle.patch" 2>/dev/null; then
  git -C "$CMUX_DIR" apply "$INTEGRATION_DIR/cmux-lifecycle.patch"
elif ! git -C "$CMUX_DIR" apply --reverse --check "$INTEGRATION_DIR/cmux-lifecycle.patch" 2>/dev/null; then
  echo "cmux lifecycle patch does not match the pinned source" >&2
  exit 1
fi

if git -C "$CMUX_DIR" apply --check "$INTEGRATION_DIR/cmux-embedded-sidebar.patch" 2>/dev/null; then
  git -C "$CMUX_DIR" apply "$INTEGRATION_DIR/cmux-embedded-sidebar.patch"
elif git -C "$CMUX_DIR" apply --reverse --check "$INTEGRATION_DIR/cmux-embedded-workspace-list.patch" 2>/dev/null; then
  : # The workspace-list patch extends the already-applied sidebar hunk.
elif ! git -C "$CMUX_DIR" apply --reverse --check "$INTEGRATION_DIR/cmux-embedded-sidebar.patch" 2>/dev/null; then
  echo "cmux embedded sidebar patch does not match the pinned source" >&2
  exit 1
fi

if git -C "$CMUX_DIR" apply --check "$INTEGRATION_DIR/cmux-embedded-drag.patch" 2>/dev/null; then
  git -C "$CMUX_DIR" apply "$INTEGRATION_DIR/cmux-embedded-drag.patch"
elif ! git -C "$CMUX_DIR" apply --reverse --check "$INTEGRATION_DIR/cmux-embedded-drag.patch" 2>/dev/null; then
  echo "cmux embedded drag patch does not match the pinned source" >&2
  exit 1
fi

if git -C "$CMUX_DIR" apply --check "$INTEGRATION_DIR/cmux-embedded-titlebar.patch" 2>/dev/null; then
  git -C "$CMUX_DIR" apply "$INTEGRATION_DIR/cmux-embedded-titlebar.patch"
elif ! git -C "$CMUX_DIR" apply --reverse --check "$INTEGRATION_DIR/cmux-embedded-titlebar.patch" 2>/dev/null; then
  echo "cmux embedded titlebar patch does not match the pinned source" >&2
  exit 1
fi

if git -C "$CMUX_DIR" apply --check "$INTEGRATION_DIR/cmux-embedded-workspace-list.patch" 2>/dev/null; then
  git -C "$CMUX_DIR" apply "$INTEGRATION_DIR/cmux-embedded-workspace-list.patch"
elif ! git -C "$CMUX_DIR" apply --reverse --check "$INTEGRATION_DIR/cmux-embedded-workspace-list.patch" 2>/dev/null; then
  echo "cmux embedded workspace-list patch does not match the pinned source" >&2
  exit 1
fi

if [[ ! -d "$CMUX_DIR/GhosttyKit.xcframework" ]]; then
  (cd "$CMUX_DIR" && ./scripts/download-prebuilt-ghosttykit.sh)
fi

xcodebuild \
  -quiet \
  -project "$CMUX_DIR/cmux.xcodeproj" \
  -scheme CmuxEmbedded \
  -configuration "$BUILD_CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA_DIR" \
  ONLY_ACTIVE_ARCH=YES \
  ARCHS="$BUILD_ARCH" \
  COMPILER_INDEX_STORE_ENABLE=NO \
  -jobs "${CMUX_EMBEDDED_JOBS:-8}" \
  build

FRAMEWORK_PATH="$DERIVED_DATA_DIR/Build/Products/$BUILD_CONFIGURATION/CmuxEmbedded.framework"
[[ -d "$FRAMEWORK_PATH" ]] || {
  echo "Missing cmux embedded framework at $FRAMEWORK_PATH" >&2
  exit 1
}

install_name_tool -id \
  "@rpath/CmuxEmbedded.framework/Versions/A/CmuxEmbedded" \
  "$FRAMEWORK_PATH/Versions/A/CmuxEmbedded"

rm -rf "$OUTPUT_DIR"
xcodebuild -create-xcframework \
  -allow-internal-distribution \
  -framework "$FRAMEWORK_PATH" \
  -output "$OUTPUT_DIR"

echo "Built $OUTPUT_DIR"
