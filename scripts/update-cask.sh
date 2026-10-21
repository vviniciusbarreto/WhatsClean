#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${1:?Usage: ./scripts/update-cask.sh VERSION [TAP_DIR]}"
TAP_DIR="${2:-}"
ZIP="$ROOT/ReleaseAssets/$VERSION/WhatsClean-${VERSION}-arm64.zip"
CASK="$ROOT/Packaging/Homebrew/Casks/whatsclean.rb"

if [[ ! -f "$ZIP" ]]; then
    echo "Release archive not found: $ZIP" >&2
    echo "Run ./scripts/release.sh $VERSION BUILD_NUMBER first." >&2
    exit 1
fi

SHA256="$(shasum -a 256 "$ZIP" | awk '{print $1}')"
VERSION="$VERSION" SHA256="$SHA256" perl -pi -e '
    s/^(\s*version\s+)"[^"]*"/$1"$ENV{VERSION}"/;
    s/^(\s*sha256\s+)"[^"]*"/$1"$ENV{SHA256}"/;
' "$CASK"

grep -q "version \"$VERSION\"" "$CASK" && grep -q "sha256 \"$SHA256\"" "$CASK" || {
    echo "Could not update $CASK" >&2
    exit 1
}
echo "Updated $CASK: version $VERSION, sha256 $SHA256"

if [[ -n "$TAP_DIR" ]]; then
    if [[ ! -d "$TAP_DIR/Casks" ]]; then
        echo "Homebrew tap not found at $TAP_DIR (expected a Casks folder)." >&2
        exit 1
    fi
    cp "$CASK" "$TAP_DIR/Casks/whatsclean.rb"
    echo "Copied to $TAP_DIR/Casks/whatsclean.rb"
else
    echo "Copy it to the tap with: ./scripts/update-cask.sh $VERSION /path/to/homebrew-tap"
fi
