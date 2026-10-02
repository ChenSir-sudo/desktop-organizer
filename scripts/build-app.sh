#!/bin/bash
# 编译并打包成可双击运行的「桌面整理.app」
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CONFIG="${1:-release}"
APP="$ROOT/dist/桌面整理.app"
BINARY_NAME="DesktopOrganizer"

# 把编译缓存全部留在工程目录内，避免在受限环境里写不了 /var/folders 与 ~/Library
export CLANG_MODULE_CACHE_PATH="$ROOT/.cache/clang"
export SWIFTPM_MODULECACHE_OVERRIDE="$ROOT/.cache/swift"
export TMPDIR="$ROOT/.cache/tmp"
mkdir -p "$CLANG_MODULE_CACHE_PATH" "$SWIFTPM_MODULECACHE_OVERRIDE" "$TMPDIR"

SWIFT_FLAGS=(
  --disable-sandbox
  --cache-path "$ROOT/.cache/spm"
  --scratch-path "$ROOT/.build"
  -Xswiftc -module-cache-path
  -Xswiftc "$ROOT/.cache/swift"
)

echo "==> swift build -c $CONFIG"
swift build -c "$CONFIG" "${SWIFT_FLAGS[@]}"

BIN_PATH="$(swift build -c "$CONFIG" "${SWIFT_FLAGS[@]}" --show-bin-path)/$BINARY_NAME"
if [ ! -f "$BIN_PATH" ]; then
  echo "编译产物不存在: $BIN_PATH" >&2
  exit 1
fi

echo "==> 组装 app bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_PATH" "$APP/Contents/MacOS/$BINARY_NAME"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> ad-hoc 签名"
if codesign --force --sign - --timestamp=none "$APP" >/dev/null 2>&1; then
  echo "    签名完成"
else
  echo "    签名跳过（不影响本机运行）"
fi

echo ""
echo "构建完成: $APP"
echo "启动:    open \"$APP\""
