#!/bin/zsh
# Compila y empaqueta Opus Lite.app (sin Xcode project).
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release --arch arm64
BIN=$(swift build -c release --arch arm64 --show-bin-path)/OpusLite

APP=build/"Opus Lite.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/es.lproj"
cp "$BIN" "$APP/Contents/MacOS/OpusLite"
strip -x "$APP/Contents/MacOS/OpusLite"
cp Resources/Info.plist "$APP/Contents/Info.plist"
[[ -f Resources/AppIcon.icns ]] && cp Resources/AppIcon.icns "$APP/Contents/Resources/" || true
codesign --force --sign - "$APP"

echo "✔ $APP ($(du -sh "$APP" | cut -f1))"
