#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/devhaven-release-test.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
APP_PATH="$TEST_DIR/Release Fixture.app"
FRAMEWORK="$APP_PATH/Contents/Frameworks/CmuxEmbedded.framework"
mkdir -p "$APP_PATH/Contents/MacOS" "$FRAMEWORK/Versions/A/Modules" "$FRAMEWORK/Versions/A/Resources"
ln -s A "$FRAMEWORK/Versions/Current"
ln -s Versions/Current/Modules "$FRAMEWORK/Modules"
ln -s Versions/Current/CmuxEmbedded "$FRAMEWORK/CmuxEmbedded"
printf '编译模块\n' > "$FRAMEWORK/Modules/fixture.swiftmodule"
printf '运行资源\n' > "$FRAMEWORK/Versions/A/Resources/fixture.txt"

cat > "$TEST_DIR/library.c" <<'C'
static __attribute__((noinline)) int private_value(void) { return 42; }
int cmux_embedded_fixture(void) { return private_value(); }
C
cat > "$TEST_DIR/main.c" <<'C'
#include <dlfcn.h>
int main(int argc, char **argv) {
    if (argc != 2) return 2;
    void *handle = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
    if (!handle) return 3;
    int (*entry)(void) = (int (*)(void))dlsym(handle, "cmux_embedded_fixture");
    int result = entry && entry() == 42 ? 0 : 4;
    dlclose(handle);
    return result;
}
C
for arch in arm64 x86_64; do
  xcrun clang -target "$arch-apple-macos14.0" -g -O0 -dynamiclib "$TEST_DIR/library.c" -o "$TEST_DIR/library-$arch"
  xcrun clang -target "$arch-apple-macos14.0" -g -O0 "$TEST_DIR/main.c" -o "$TEST_DIR/main-$arch"
done
xcrun lipo -create "$TEST_DIR/library-arm64" "$TEST_DIR/library-x86_64" -output "$FRAMEWORK/Versions/A/CmuxEmbedded"
xcrun lipo -create "$TEST_DIR/main-arm64" "$TEST_DIR/main-x86_64" -output "$APP_PATH/Contents/MacOS/DevHavenApp"
cp "$APP_PATH/Contents/MacOS/DevHavenApp" "$APP_PATH/Contents/MacOS/DevHavenCLI"
cp "$FRAMEWORK/Versions/A/CmuxEmbedded" "$TEST_DIR/original-library"
xcrun nm -gU "$FRAMEWORK/Versions/A/CmuxEmbedded" > "$TEST_DIR/exports-before"
"$APP_PATH/Contents/MacOS/DevHavenApp" "$FRAMEWORK/Versions/A/CmuxEmbedded"

bash "$SCRIPT_DIR/prepare-native-app-release.sh" "$APP_PATH"
xcrun nm -gU "$FRAMEWORK/Versions/A/CmuxEmbedded" > "$TEST_DIR/exports-after"
cmp "$TEST_DIR/exports-before" "$TEST_DIR/exports-after"
[[ "$(stat -f %z "$FRAMEWORK/Versions/A/CmuxEmbedded")" -lt "$(stat -f %z "$TEST_DIR/original-library")" ]]
[[ ! -e "$FRAMEWORK/Modules" && ! -L "$FRAMEWORK/Modules" && ! -e "$FRAMEWORK/Versions/A/Modules" ]]
[[ "$(cat "$FRAMEWORK/Versions/A/Resources/fixture.txt")" == "运行资源" ]]
for binary in "$APP_PATH/Contents/MacOS/DevHavenApp" "$APP_PATH/Contents/MacOS/DevHavenCLI" "$FRAMEWORK/Versions/A/CmuxEmbedded"; do
  for arch in arm64 x86_64; do
    xcrun lipo "$binary" -verify_arch "$arch"
  done
  codesign --force --sign - "$binary"
  codesign --verify --strict "$binary"
done
"$APP_PATH/Contents/MacOS/DevHavenApp" "$FRAMEWORK/Versions/A/CmuxEmbedded"
"$APP_PATH/Contents/MacOS/DevHavenCLI" "$FRAMEWORK/Versions/A/CmuxEmbedded"

# 缺少输入时必须在修改其它二进制前失败。
cp "$APP_PATH/Contents/MacOS/DevHavenApp" "$TEST_DIR/unchanged-app"
rm "$APP_PATH/Contents/MacOS/DevHavenCLI"
if bash "$SCRIPT_DIR/prepare-native-app-release.sh" "$APP_PATH" > "$TEST_DIR/error.log" 2>&1; then
  echo "不完整的 App 不应通过发布精简" >&2; exit 1
fi
cmp "$TEST_DIR/unchanged-app" "$APP_PATH/Contents/MacOS/DevHavenApp"
echo "PASS: 发布精简保留双架构、全局符号、动态入口与运行资源，重新签名后可执行"
