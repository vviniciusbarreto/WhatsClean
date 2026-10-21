#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${1:?Usage: ./scripts/release.sh VERSION BUILD_NUMBER}"
BUILD_NUMBER="${2:?Usage: ./scripts/release.sh VERSION BUILD_NUMBER}"
ARCHIVE_NAME="WhatsClean-${VERSION}-arm64.zip"
NOTES_NAME="WhatsClean-${VERSION}-arm64.md"
RELEASE_DIR="$ROOT/Releases/$VERSION"
PUBLIC_DIR="$ROOT/ReleaseAssets/$VERSION"

VERSION="$VERSION" BUILD_NUMBER="$BUILD_NUMBER" "$ROOT/build.sh"

mkdir -p "$RELEASE_DIR"
ditto "$ROOT/WhatsClean-macOS.zip" "$RELEASE_DIR/$ARCHIVE_NAME"

if [[ ! -f "$RELEASE_DIR/$NOTES_NAME" ]]; then
    printf '%s\n' \
        "# WhatsClean $VERSION" \
        "" \
        "- Native Apple Silicon application." \
        "- Automatic updates powered by Sparkle." \
        > "$RELEASE_DIR/$NOTES_NAME"
fi

"$ROOT/Vendor/Sparkle/bin/generate_appcast" \
    --download-url-prefix "https://github.com/vviniciusbarreto/WhatsClean/releases/download/v${VERSION}/" \
    --link "https://github.com/vviniciusbarreto/WhatsClean" \
    --embed-release-notes \
    --maximum-versions 0 \
    -o "$ROOT/appcast.xml" \
    "$RELEASE_DIR"

mkdir -p "$PUBLIC_DIR"
ditto "$RELEASE_DIR/$ARCHIVE_NAME" "$PUBLIC_DIR/$ARCHIVE_NAME"
ditto "$ROOT/WhatsClean.dmg" "$PUBLIC_DIR/WhatsClean-${VERSION}-arm64.dmg"

echo "Release prepared:"
echo "  $PUBLIC_DIR/$ARCHIVE_NAME"
echo "  $PUBLIC_DIR/WhatsClean-${VERSION}-arm64.dmg"
echo "  $ROOT/appcast.xml"
echo "SHA-256: $(shasum -a 256 "$RELEASE_DIR/$ARCHIVE_NAME" | awk '{print $1}')"

"$ROOT/scripts/update-cask.sh" "$VERSION"
