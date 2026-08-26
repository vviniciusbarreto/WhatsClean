#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DESTINATION="${1:-}"

if [[ -z "$DESTINATION" ]]; then
    echo "Usage: ./scripts/backup-sparkle-key.sh /path/to/encrypted-backup-folder" >&2
    exit 1
fi

mkdir -p "$DESTINATION"
DESTINATION="$(cd "$DESTINATION" && pwd)"
BACKUP_FILE="$DESTINATION/WhatsClean-Sparkle-private-key.txt"

if [[ -e "$BACKUP_FILE" ]]; then
    echo "Refusing to overwrite existing backup: $BACKUP_FILE" >&2
    exit 1
fi

case "$DESTINATION" in
    "$ROOT"|"$ROOT"/*)
        echo "Refusing to save the private key inside the Git repository." >&2
        exit 1
        ;;
esac

umask 077
"$ROOT/Vendor/Sparkle/bin/generate_keys" -x "$BACKUP_FILE"
chmod 600 "$BACKUP_FILE"

echo "Sparkle private key exported successfully."
echo "Backup: $BACKUP_FILE"
echo "Keep this file in encrypted storage and never commit or share it."
echo "Restore on another Mac with:"
echo "  Vendor/Sparkle/bin/generate_keys -f <private-key-file>"
