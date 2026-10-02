#!/bin/bash
# 打出「双击 -> 拖进应用程序」样式的安装盘。
#
# 做法是标准的 macOS 流程：先建可读写镜像，挂载后把窗口布局、图标位置、
# 背景图写进 .DS_Store，卸载后再压成只读的 UDZO。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="桌面整理"
VOL_NAME="桌面整理"
APP="$ROOT/dist/$APP_NAME.app"
OUT="$ROOT/dist/$APP_NAME.dmg"
STAGE="$ROOT/.cache/dmgstage"
RW="$ROOT/.cache/tmp/rw.dmg"
MOUNT="/Volumes/$VOL_NAME"

export TMPDIR="$ROOT/.cache/tmp"
mkdir -p "$ROOT/.cache/tmp"

if [ ! -d "$APP" ]; then
  echo "找不到 $APP，先跑 scripts/build-app.sh" >&2
  exit 1
fi

echo "==> 准备暂存目录"
rm -rf "$STAGE"
mkdir -p "$STAGE/.background"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/应用程序"
cp "$ROOT/Resources/dmg-background.png" "$STAGE/.background/背景.png"
cp "$ROOT/Resources/AppIcon.icns" "$STAGE/.VolumeIcon.icns"

echo "==> 建可读写镜像"
rm -f "$RW" "$OUT"
if [ -d "$MOUNT" ]; then hdiutil detach "$MOUNT" >/dev/null 2>&1 || true; fi
hdiutil create -volname "$VOL_NAME" -srcfolder "$STAGE" -ov -format UDRW -quiet "$RW"

echo "==> 挂载"
hdiutil attach "$RW" -nobrowse -quiet
sleep 2

echo "==> 写入窗口布局"
osascript <<APPLESCRIPT || echo "    (Finder 布局设置失败，退化为普通安装盘)"
tell application "Finder"
  tell disk "$VOL_NAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {400, 200, 1040, 600}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 128
    set text size of opts to 13
    set background picture of opts to file ".background:背景.png"
    set position of item "$APP_NAME.app" of container window to {160, 185}
    set position of item "应用程序" of container window to {480, 185}
    update without registering applications
    delay 2
    close
  end tell
end tell
APPLESCRIPT

# 卷图标（需要 SetFile 打上自定义图标标志，没装 Xcode 就跳过）
if command -v SetFile >/dev/null 2>&1; then
  SetFile -a C "$MOUNT" 2>/dev/null || true
  echo "    (卷图标已设置)"
else
  echo "    (没有 SetFile，卷图标可能不显示)"
fi

sync
sleep 1

echo "==> 卸载并压缩"
hdiutil detach "$MOUNT" -quiet 2>/dev/null || hdiutil detach "$MOUNT" -force -quiet 2>/dev/null || true
sleep 1
hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -o "$OUT" -quiet
rm -f "$RW"
rm -rf "$STAGE"

echo ""
echo "构建完成: $OUT ($(du -h "$OUT" | cut -f1))"
