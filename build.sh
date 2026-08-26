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
    echo "Identidade de assinatura não encontrada: $SIGNING_IDENTITY" >&2
    echo "Instale um certificado Developer ID Application ou rode sem APP_SIGNING_IDENTITY para um build local." >&2
    exit 1
fi

if [[ "$ARCH" != "arm64" ]]; then
    echo "Arquitetura não suportada por este build: $ARCH" >&2
    exit 1
fi

if [[ ! -d "$SPARKLE_FRAMEWORK" ]]; then
    echo "Sparkle.framework não encontrado em $SPARKLE_FRAMEWORK" >&2
    exit 1
fi

echo "Compilando WhatsClean para Apple Silicon..."
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

ICONSET="$BUILD_DIR/AppIcon.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
for SPEC in "16 icon_16x16" "32 icon_16x16@2x" "32 icon_32x32" \
            "64 icon_32x32@2x" "128 icon_128x128" "256 icon_128x128@2x" \
            "256 icon_256x256" "512 icon_256x256@2x" "512 icon_512x512" \
            "1024 icon_512x512@2x"; do
    SIZE="${SPEC%% *}"
    NAME="${SPEC#* }"
    sips -z "$SIZE" "$SIZE" "$ROOT/Resources/AppIcon.png" \
        --out "$ICONSET/$NAME.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

sign_bundle() {
    local target="$1"
    if [[ "$SIGNING_IDENTITY" != "-" ]]; then
        codesign --force --sign "$SIGNING_IDENTITY" --options runtime --timestamp "$target"
    else
        codesign --force --sign - "$target"
    fi
}

# Assinatura de dentro para fora, como exigido por bundles com código aninhado.
sign_bundle "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Downloader.xpc"
sign_bundle "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Installer.xpc"
sign_bundle "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/Updater.app"
sign_bundle "$APP/Contents/Frameworks/Sparkle.framework"

if [[ "$SIGNING_IDENTITY" != "-" ]]; then
    codesign --force --sign "$SIGNING_IDENTITY" --options runtime --timestamp \
        --entitlements "$ROOT/Resources/WhatsClean.entitlements" "$APP"
else
    echo "Aviso: build local com assinatura ad-hoc; ele exige autorização manual do Gatekeeper na primeira abertura."
    codesign --force --sign - --entitlements "$ROOT/Resources/WhatsClean.entitlements" "$APP"
fi

codesign --verify --deep --strict --verbose=2 "$APP"

STAGE="$BUILD_DIR/dmg"
rm -rf "$STAGE" "$DMG" "$ZIP"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/WhatsClean.app"
ln -s /Applications "$STAGE/Applications"
cp "$ROOT/Resources/COMO_ABRIR.txt" "$STAGE/LEIA PRIMEIRO - INSTALAÇÃO.txt"
hdiutil create -volname "WhatsClean" -srcfolder "$STAGE" -ov -format UDZO "$DMG"

if [[ "$SIGNING_IDENTITY" != "-" ]]; then
    codesign --force --sign "$SIGNING_IDENTITY" --timestamp "$DMG"
    if [[ -n "$NOTARY_PROFILE" ]]; then
        echo "Enviando DMG para notarização da Apple..."
        xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
        xcrun stapler staple "$DMG"
        xcrun stapler validate "$DMG"
    else
        echo "Aviso: NOTARY_PROFILE não definido; o DMG foi assinado, mas não notarizado."
    fi
fi

ditto -c -k --norsrc --keepParent "$APP" "$ZIP"

echo "Artefatos gerados:"
echo "  $APP"
echo "  $DMG"
echo "  $ZIP"
echo "Arquitetura: $(lipo -archs "$APP/Contents/MacOS/WhatsClean")"
