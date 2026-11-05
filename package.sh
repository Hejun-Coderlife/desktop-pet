#!/bin/bash
# 打包 Pip.app 并安装到 /Applications
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Pip"
DIST="dist"

echo "▶ swift build -c release"
swift build -c release

BIN=".build/release/$APP_NAME"
if [ ! -f "$BIN" ]; then
  echo "✗ 找不到 $BIN"
  exit 1
fi

echo "▶ 组装 $DIST/$APP_NAME.app"
rm -rf "$DIST/$APP_NAME.app"
mkdir -p "$DIST/$APP_NAME.app/Contents/MacOS"
mkdir -p "$DIST/$APP_NAME.app/Contents/Resources"
cp "$BIN" "$DIST/$APP_NAME.app/Contents/MacOS/$APP_NAME"
cp "Resources/Info.plist" "$DIST/$APP_NAME.app/Contents/Info.plist"
cp "Resources/AppIcon.icns" "$DIST/$APP_NAME.app/Contents/Resources/AppIcon.icns"
chmod +x "$DIST/$APP_NAME.app/Contents/MacOS/$APP_NAME"

# Info.plist 校验：LSUIElement 必须为 true（不显示程序坞图标）
if ! /usr/libexec/PlistBuddy -c "Print :LSUIElement" "$DIST/$APP_NAME.app/Contents/Info.plist" | grep -q true; then
  echo "✗ Info.plist 里 LSUIElement 不是 true"
  exit 1
fi

echo "▶ ad-hoc 签名"
if ! codesign --force --sign - "$DIST/$APP_NAME.app" 2>/dev/null; then
  echo "  签名失败（不影响本地运行，继续）"
fi

echo "▶ 安装到 /Applications/$APP_NAME.app"
if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
  echo "  先退出正在运行的 $APP_NAME"
  osascript -e "tell application \"$APP_NAME\" to quit" >/dev/null 2>&1 || true
  sleep 1
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
fi
rm -rf "/Applications/$APP_NAME.app"
cp -R "$DIST/$APP_NAME.app" "/Applications/$APP_NAME.app"

echo ""
echo "✔ 完成：/Applications/$APP_NAME.app"
echo "  打开：open /Applications/$APP_NAME.app"
echo "  菜单栏会多出一个爪印图标；没有程序坞图标。"
