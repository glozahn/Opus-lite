#!/bin/bash
# Builds, signs with Developer ID, notarizes and staples Opus Lite, then packages a DMG.
# Secrets come from scripts/notarize.env (git-ignored); see scripts/notarize.env.example.
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="Opus Lite"
DMG_PREFIX="Opus-Lite"
APP="build/${APP_NAME}.app"
ENTITLEMENTS="Resources/OpusLite.entitlements"

[ -f scripts/notarize.env ] && source scripts/notarize.env
: "${SIGNING_IDENTITY:?Set SIGNING_IDENTITY (Developer ID Application certificate)}"
: "${ASC_KEY_ID:?Set ASC_KEY_ID}"
: "${ASC_ISSUER_ID:?Set ASC_ISSUER_ID}"
KEY_PATH="${ASC_API_KEY_PATH:-$HOME/.app-store-connect/AuthKey_${ASC_KEY_ID}.p8}"
[ -f "$KEY_PATH" ] || { echo "App Store Connect key not found: $KEY_PATH" >&2; exit 1; }

[ "${SKIP_BUILD:-0}" = 1 ] || ./build.sh

VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
mkdir -p dist
DMG="dist/${DMG_PREFIX}-${VERSION}-$(uname -m).dmg"

package_dmg() {
    local staging; staging=$(mktemp -d)
    ditto "$APP" "$staging/${APP_NAME}.app"
    ln -s /Applications "$staging/Applications"
    [ -f LICENSE ] && cp LICENSE "$staging/LICENSE.txt"
    codesign --verify --deep --strict "$staging/${APP_NAME}.app"
    hdiutil create -volname "$APP_NAME" -srcfolder "$staging" -format UDZO -ov "$DMG" >/dev/null
    hdiutil verify "$DMG" >/dev/null
    rm -rf "$staging"
    (cd dist && shasum -a 256 "$(basename "$DMG")" > "$(basename "$DMG").sha256")
}

echo "Signing…"
rm -rf "$APP/Contents/_CodeSignature"
codesign --force --options runtime --timestamp --entitlements "$ENTITLEMENTS" \
    --sign "$SIGNING_IDENTITY" "$APP"

# codesign can fail softly and leave the bundle ad-hoc: confirm the signature took.
INFO=$(codesign -dv --verbose=4 "$APP" 2>&1)
grep -q "TeamIdentifier=" <<<"$INFO" && grep -q "Timestamp=" <<<"$INFO" && ! grep -q "Signature=adhoc" <<<"$INFO" || {
    echo "Signature not applied (is timestamp.apple.com blocked by a VPN?)" >&2; exit 1; }
codesign --verify --deep --strict --verbose=2 "$APP"

echo "Packaging and notarizing…"
package_dmg
xcrun notarytool submit "$DMG" --key "$KEY_PATH" --key-id "$ASC_KEY_ID" \
    --issuer "$ASC_ISSUER_ID" --wait

echo "Stapling…"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
package_dmg   # the final DMG carries the stapled app
xcrun stapler staple "$DMG"
spctl --assess --type exec -vv "$APP"
echo "Done: $DMG"
