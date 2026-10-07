#!/bin/zsh
# Builds and packages Opus Lite.app (no Xcode project needed).
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release --arch arm64
BIN=$(swift build -c release --arch arm64 --show-bin-path)/OpusLite

APP=build/"Opus Lite.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/OpusLite"
strip -x "$APP/Contents/MacOS/OpusLite"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp -R Resources/*.lproj "$APP/Contents/Resources/"
cp CHANGELOG.md "$APP/Contents/Resources/"
[[ -f Resources/AppIcon.icns ]] && cp Resources/AppIcon.icns "$APP/Contents/Resources/" || true
codesign --force --sign - "$APP"

echo "✔ $APP ($(du -sh "$APP" | cut -f1))"
