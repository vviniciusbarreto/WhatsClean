#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="2.9.6"
EXPECTED_SHA256="52bf9e88cdd972fc0c81501377a880e90d47031bd8ca5462488f843e2609e192"
URL="https://github.com/sparkle-project/Sparkle/releases/download/$VERSION/Sparkle-$VERSION.tar.xz"
DEST="$ROOT/Vendor/Sparkle"
ARCHIVE="$DEST/Sparkle-$VERSION.tar.xz"

mkdir -p "$DEST"
curl -fL "$URL" -o "$ARCHIVE"

ACTUAL_SHA256="$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')"
if [[ "$ACTUAL_SHA256" != "$EXPECTED_SHA256" ]]; then
    echo "Invalid checksum for Sparkle $VERSION." >&2
    exit 1
fi

tar -xJf "$ARCHIVE" -C "$DEST" \
    ./Sparkle.framework \
    ./bin/generate_keys \
    ./bin/generate_appcast \
    ./bin/sign_update \
    ./LICENSE

echo "Sparkle $VERSION installed and verified at $DEST"
