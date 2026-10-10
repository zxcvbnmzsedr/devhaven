#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/devhaven-universal-test.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT

# 使用两个架构的真实 Mach-O 和已签名嵌套框架，覆盖 lipo 导致签名失效的场景。
cat > "$TEST_DIR/framework.c" <<'C'
int fixture_value(void) { return 0; }
C
cat > "$TEST_DIR/main.c" <<'C'
extern int fixture_value(void);
int main(void) { return fixture_value(); }
C

for arch in arm64 x86_64; do
  app="$TEST_DIR/$arch/DevHaven.app"
  framework="$app/Contents/Frameworks/CmuxEmbedded.framework"
  mkdir -p "$app/Contents/MacOS" "$framework/Versions/A/Resources"
  cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.devhaven.universal-test</string>
<key>CFBundleExecutable</key><string>DevHavenApp</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0.0</string>
<key>CFBundleVersion</key><string>1</string>
</dict></plist>
PLIST
  cat > "$framework/Versions/A/Resources/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.devhaven.universal-test.cmux</string>
<key>CFBundleExecutable</key><string>CmuxEmbedded</string>
<key>CFBundlePackageType</key><string>FMWK</string>
</dict></plist>
PLIST
  ln -s A "$framework/Versions/Current"
  ln -s Versions/Current/CmuxEmbedded "$framework/CmuxEmbedded"
  ln -s Versions/Current/Resources "$framework/Resources"
  xcrun clang -target "$arch-apple-macos14.0" -dynamiclib "$TEST_DIR/framework.c" \
    -install_name '@rpath/CmuxEmbedded.framework/Versions/A/CmuxEmbedded' \
    -o "$framework/Versions/A/CmuxEmbedded"
  xcrun clang -target "$arch-apple-macos14.0" "$TEST_DIR/main.c" \
    -F "$app/Contents/Frameworks" -framework CmuxEmbedded \
    -Wl,-rpath,@executable_path/../Frameworks -o "$app/Contents/MacOS/DevHavenApp"
  codesign --force --deep --sign - "$app"
  codesign --verify --deep --strict "$app"
done

output="$TEST_DIR/Universal/DevHaven.app"
bash "$SCRIPT_DIR/create-universal-app.sh" \
  --arm64-app "$TEST_DIR/arm64/DevHaven.app" \
  --x86-app "$TEST_DIR/x86_64/DevHaven.app" --output "$output"
for arch in arm64 x86_64; do
  lipo "$output/Contents/MacOS/DevHavenApp" -verify_arch "$arch"
  lipo "$output/Contents/Frameworks/CmuxEmbedded.framework/CmuxEmbedded" -verify_arch "$arch"
done
codesign --verify --deep --strict "$output"
"$output/Contents/MacOS/DevHavenApp"

# 两个架构的元数据不一致时必须拒绝合成，并保留上一次有效的产物。
/usr/libexec/PlistBuddy -c 'Set :CFBundleVersion 2' "$TEST_DIR/x86_64/DevHaven.app/Contents/Info.plist"
if bash "$SCRIPT_DIR/create-universal-app.sh" \
  --arm64-app "$TEST_DIR/arm64/DevHaven.app" \
  --x86-app "$TEST_DIR/x86_64/DevHaven.app" --output "$output" > "$TEST_DIR/error.log" 2>&1; then
  echo "错误：接受了版本不一致的安装包" >&2
  exit 1
fi
grep -q 'CFBundleVersion 不一致' "$TEST_DIR/error.log"
codesign --verify --deep --strict "$output"
echo "universal app signing smoke ok (arm64 + x86_64)"
