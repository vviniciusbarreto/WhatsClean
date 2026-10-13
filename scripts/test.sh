#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SPARKLE_ROOT="$ROOT/Vendor/Sparkle"
BUILD_DIR="$ROOT/.build/tests"
[[ -d "$SPARKLE_ROOT/Sparkle.framework" ]] || { echo "Run ./scripts/install-sparkle.sh first." >&2; exit 1; }
mkdir -p "$BUILD_DIR"
xcrun swiftc -parse-as-library -D UI_TEST_RENDER -D QA_TESTING \
  -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
  -target arm64-apple-macos12.0 \
  -module-cache-path "$BUILD_DIR/module-cache" \
  -F "$SPARKLE_ROOT" -framework Sparkle \
  -Xlinker -rpath -Xlinker "$SPARKLE_ROOT" \
  "$ROOT/Sources/WhatsClean.swift" "$ROOT/Tests/CleanupTests.swift" \
  -o "$BUILD_DIR/cleanup-tests"
"$BUILD_DIR/cleanup-tests"
