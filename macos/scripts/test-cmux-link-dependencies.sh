#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREPARE_SCRIPT="$SCRIPT_DIR/prepare-cmux-link-dependencies.sh"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/devhaven-cmux-link-test.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
products="$TEST_DIR/Build Products"
destination="$TEST_DIR/Clean Vendor/CmuxBuildProducts"

# 本机部分 lipo 版本允许旧参数顺序，CI 的 Xcode lipo 会拒绝。
# 只收紧参数解析；架构检查、静态库合并和链接仍使用真实工具。
export DEVHAVEN_TEST_REAL_LIPO="$(command -v lipo)"
mkdir -p "$TEST_DIR/tools"
cat > "$TEST_DIR/tools/lipo" <<'LIPO'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "-verify_arch" ]]; then
  echo "lipo: -verify_arch requires the input file before the option" >&2
  exit 1
fi
exec "$DEVHAVEN_TEST_REAL_LIPO" "$@"
LIPO
chmod +x "$TEST_DIR/tools/lipo"
export PATH="$TEST_DIR/tools:$PATH"

# Real versioned static frameworks exercise symlinks, architecture validation,
# and the same -F / -framework lookup used by SwiftPM on a clean CI runner.
for framework in Sentry Iroh; do
  root="$products/$framework.framework"
  mkdir -p "$root/Versions/A/Resources"
  printf 'int fixture_%s(void) { return 0; }\n' "$framework" > "$TEST_DIR/$framework.c"
  for arch in arm64 x86_64; do
    xcrun clang -target "$arch-apple-macos14.0" -c "$TEST_DIR/$framework.c" -o "$TEST_DIR/$framework-$arch.o"
    xcrun ar rcs "$TEST_DIR/$framework-$arch.a" "$TEST_DIR/$framework-$arch.o"
  done
  lipo -create "$TEST_DIR/$framework-arm64.a" "$TEST_DIR/$framework-x86_64.a" -output "$root/Versions/A/$framework"
  ln -s A "$root/Versions/Current"
  ln -s "Versions/Current/$framework" "$root/$framework"
  ln -s Versions/Current/Resources "$root/Resources"
done
cat > "$TEST_DIR/main.c" <<'C'
extern int fixture_Sentry(void);
extern int fixture_Iroh(void);
int main(void) { return fixture_Sentry() + fixture_Iroh(); }
C

# A fresh destination must resolve both frameworks for either CI architecture.
for arch in arm64 x86_64; do
  bash "$PREPARE_SCRIPT" "$products" "$destination" "$arch"
  [[ -L "$destination/Sentry.framework/Sentry" ]]
  xcrun clang -target "$arch-apple-macos14.0" "$TEST_DIR/main.c" \
    -F "$destination" -framework Sentry -framework Iroh -o "$TEST_DIR/probe-$arch"
  lipo "$TEST_DIR/probe-$arch" -verify_arch "$arch"
done
"$TEST_DIR/probe-$(uname -m)"

# Rebuilding / switching configuration must replace rather than merge stale files.
touch "$destination/Sentry.framework/Resources/stale-resource"
bash "$PREPARE_SCRIPT" "$products" "$destination" arm64
[[ ! -e "$destination/Sentry.framework/Resources/stale-resource" ]]

# Missing or incompatible inputs must fail without replacing the good copy.
mv "$products/Iroh.framework" "$products/Iroh.saved"
if bash "$PREPARE_SCRIPT" "$products" "$destination" arm64 > "$TEST_DIR/error.log" 2>&1; then
  echo "Missing Iroh unexpectedly accepted" >&2; exit 1
fi
grep -q 'Missing cmux link dependency' "$TEST_DIR/error.log"
cmp "$products/Iroh.saved/Iroh" "$destination/Iroh.framework/Iroh"
mv "$products/Iroh.saved" "$products/Iroh.framework"
lipo -thin arm64 "$products/Iroh.framework/Iroh" -output "$TEST_DIR/Iroh-arm64"
cp "$TEST_DIR/Iroh-arm64" "$products/Iroh.framework/Versions/A/Iroh"
if bash "$PREPARE_SCRIPT" "$products" "$destination" x86_64 > "$TEST_DIR/error.log" 2>&1; then
  echo "Wrong architecture unexpectedly accepted" >&2; exit 1
fi
grep -q 'does not support x86_64' "$TEST_DIR/error.log"
lipo "$destination/Iroh.framework/Iroh" -verify_arch x86_64

echo "cmux link dependencies smoke ok (arm64 + x86_64)"
