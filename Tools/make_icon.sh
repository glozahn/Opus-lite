#!/bin/zsh
# Regenerates Resources/AppIcon.icns from Tools/make_icon.swift.
set -euo pipefail
cd "$(dirname "$0")/.."
swift Tools/make_icon.swift
SET=$(mktemp -d)/AppIcon.iconset
mkdir -p "$SET"
for s in 16 32 128 256 512; do
  sips -z $s $s Resources/AppIcon.png --out "$SET/icon_${s}x${s}.png" >/dev/null
  [[ $s -lt 512 ]] && sips -z $((s*2)) $((s*2)) Resources/AppIcon.png --out "$SET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$SET" -o Resources/AppIcon.icns
echo "✔ Resources/AppIcon.icns"
