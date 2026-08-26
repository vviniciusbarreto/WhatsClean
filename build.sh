#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$ROOT/.build/release"
APP="$ROOT/WhatsClean.app"
DMG="$ROOT/WhatsClean.dmg"
ZIP="$ROOT/WhatsClean-macOS.zip"
SPARKLE_ROOT="$ROOT/Vendor/Sparkle"
SPARKLE_FRAMEWORK="$SPARKLE_ROOT/Sparkle.framework"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
MIN_MACOS="${MIN_MACOS:-12.0}"
ARCH="${ARCH:-arm64}"
VERSION="${VERSION:-1.0.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
SIGNING_IDENTITY="${APP_SIGNING_IDENTITY:--}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

if [[ "$SIGNING_IDENTITY" != "-" ]] && \
   ! security find-identity -v -p codesigning | grep -Fq "$SIGNING_IDENTITY"; then
    echo "Code-signing identity not found: $SIGNING_IDENTITY" >&2
    echo "Install a Developer ID Application certificate or omit APP_SIGNING_IDENTITY for a local build." >&2
    exit 1
fi

if [[ "$ARCH" != "arm64" ]]; then
    echo "Unsupported build architecture: $ARCH" >&2
    exit 1
fi

if [[ ! -d "$SPARKLE_FRAMEWORK" ]]; then
    echo "Sparkle.framework was not found at $SPARKLE_FRAMEWORK" >&2
    exit 1
fi

echo "Building WhatsClean for Apple Silicon..."
mkdir -p "$BUILD_DIR"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
ditto "$SPARKLE_FRAMEWORK" "$APP/Contents/Frameworks/Sparkle.framework"

xcrun swiftc -parse-as-library -O -sdk "$SDK" \
    -target "arm64-apple-macos${MIN_MACOS}" \
    -F "$SPARKLE_ROOT" -framework Sparkle \
    -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
    "$ROOT/Sources/WhatsClean.swift" \
    -o "$APP/Contents/MacOS/WhatsClean"
chmod 755 "$APP/Contents/MacOS/WhatsClean"

cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleGetInfoString WhatsClean $VERSION, created by Vinicius Barreto (@vviniciusbarreto)." "$APP/Contents/Info.plist"

# Keep a validated legacy ICNS fallback for macOS 12–15. Regenerating it with
# iconutil can fail intermittently on newer macOS releases despite valid PNGs.
ditto "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

# Compile a modern asset catalog for macOS Tahoe while retaining AppIcon.icns
# as the fallback for macOS 12–15.
ASSET_CATALOG="$BUILD_DIR/Assets.xcassets"
rm -rf "$ASSET_CATALOG"
ditto "$ROOT/Resources/Assets.xcassets" "$ASSET_CATALOG"
MODERN_ICONSET="$ASSET_CATALOG/AppIcon.appiconset"
for SPEC in "16 icon_16x16" "32 icon_16x16@2x" "32 icon_32x32" \
            "64 icon_32x32@2x" "128 icon_128x128" "256 icon_128x128@2x" \
            "256 icon_256x256" "512 icon_256x256@2x" "512 icon_512x512" \
            "1024 icon_512x512@2x"; do
    SIZE="${SPEC%% *}"
    NAME="${SPEC#* }"
    sips -z "$SIZE" "$SIZE" "$ROOT/Resources/AppIconModern.png" \
        --out "$MODERN_ICONSET/$NAME.png" >/dev/null
done
xcrun actool "$ASSET_CATALOG" \
    --compile "$APP/Contents/Resources" \
    --platform macosx \
    --minimum-deployment-target "$MIN_MACOS" \
    --target-device mac \
    --app-icon AppIcon \
    --output-partial-info-plist "$BUILD_DIR/AppIcon-Info.plist" \
    >/dev/null

sign_bundle() {
    local target="$1"
    if [[ "$SIGNING_IDENTITY" != "-" ]]; then
        codesign --force --sign "$SIGNING_IDENTITY" --options runtime --timestamp "$target"
    else
        codesign --force --sign - "$target"
    fi
}

# Sign nested code from the inside out.
sign_bundle "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Downloader.xpc"
sign_bundle "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Installer.xpc"
sign_bundle "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/Updater.app"
sign_bundle "$APP/Contents/Frameworks/Sparkle.framework"

if [[ "$SIGNING_IDENTITY" != "-" ]]; then
    codesign --force --sign "$SIGNING_IDENTITY" --options runtime --timestamp \
        --entitlements "$ROOT/Resources/WhatsClean.entitlements" "$APP"
else
    echo "Warning: this local ad-hoc build requires manual Gatekeeper approval on first launch."
    codesign --force --sign - --entitlements "$ROOT/Resources/WhatsClean.entitlements" "$APP"
fi

codesign --verify --deep --strict --verbose=2 "$APP"

STAGE="$BUILD_DIR/dmg"
rm -rf "$STAGE" "$DMG" "$ZIP"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/WhatsClean.app"
ln -s /Applications "$STAGE/Applications"
cp "$ROOT/Resources/INSTALL.txt" "$STAGE/README - INSTALLATION.txt"
hdiutil create -volname "WhatsClean" -srcfolder "$STAGE" -ov -format UDZO "$DMG"

if [[ "$SIGNING_IDENTITY" != "-" ]]; then
    codesign --force --sign "$SIGNING_IDENTITY" --timestamp "$DMG"
    if [[ -n "$NOTARY_PROFILE" ]]; then
        echo "Submitting DMG for Apple notarization..."
        xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
        xcrun stapler staple "$DMG"
        xcrun stapler validate "$DMG"
    else
        echo "Warning: NOTARY_PROFILE is not set; the DMG is signed but not notarized."
    fi
fi

ditto -c -k --norsrc --keepParent "$APP" "$ZIP"

echo "Generated artifacts:"
echo "  $APP"
echo "  $DMG"
echo "  $ZIP"
echo "Architecture: $(lipo -archs "$APP/Contents/MacOS/WhatsClean")"
