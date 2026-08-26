#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
LOCAL_APP="$DIR/WhatsClean.app"

if [ -w "/Applications" ]; then
    INSTALL_APP="/Applications/WhatsClean.app"
else
    mkdir -p "$HOME/Applications"
    INSTALL_APP="$HOME/Applications/WhatsClean.app"
fi

echo "🔨 Compilando WhatsClean (Swift Nativo)..."

for TARGET in "$INSTALL_APP" "$LOCAL_APP"; do
    mkdir -p "$TARGET/Contents/MacOS" "$TARGET/Contents/Resources"
    cp "$DIR/Resources/Info.plist" "$TARGET/Contents/Info.plist"
done

swiftc -parse-as-library -O "$DIR/Sources/WhatsClean.swift" -o "$INSTALL_APP/Contents/MacOS/WhatsClean"
cp "$INSTALL_APP/Contents/MacOS/WhatsClean" "$LOCAL_APP/Contents/MacOS/WhatsClean"
chmod +x "$INSTALL_APP/Contents/MacOS/WhatsClean" "$LOCAL_APP/Contents/MacOS/WhatsClean"

echo "🎨 Gerando e aplicando ícone customizado..."
swiftc "$DIR/Resources/generate_icon.swift" -o /tmp/gen_icon_bin
/tmp/gen_icon_bin
rm -f /tmp/gen_icon_bin

codesign -s - --force --deep "$INSTALL_APP" 2>/dev/null || true
codesign -s - --force --deep "$LOCAL_APP" 2>/dev/null || true

echo "📦 Gerando pacote de compartilhamento (WhatsClean-macOS.zip)..."
(cd "$DIR" && zip -r -q "WhatsClean-macOS.zip" "WhatsClean.app")

echo "✅ WhatsClean instalado com sucesso em: $INSTALL_APP"
open "$INSTALL_APP"
