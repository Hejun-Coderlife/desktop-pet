#!/bin/zsh
# Mac 安装包：Intel + Apple 芯片通用版 Pip.app → dist/Pip.dmg（拖进「应用程序」即可）
set -e
cd "${0:a:h}/.."
./package.sh >/dev/null                                   # 先出 dist/Pip.app（arm64）并装到本机
swift build -c release --triple x86_64-apple-macosx13.0 --scratch-path .build-x86 >/dev/null
BIN=dist/Pip.app/Contents/MacOS/Pip
lipo -create .build/release/Pip .build-x86/release/Pip -output /tmp/Pip-universal
cp /tmp/Pip-universal "$BIN"
codesign --force --deep --sign - dist/Pip.app
lipo -info "$BIN"
STAGE=$(mktemp -d)
cp -R dist/Pip.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f dist/Pip.dmg
hdiutil create -volname "Pip" -srcfolder "$STAGE" -ov -format UDZO dist/Pip.dmg >/dev/null
rm -rf "$STAGE"
ls -lh dist/Pip.dmg
