#!/bin/zsh
# Compila em release e empacota DiskNotch.app (assinatura ad hoc, só para uso local).
set -euo pipefail
cd "${0:A:h}"

swift build -c release --product DiskNotch
BIN="$(swift build -c release --show-bin-path)/DiskNotch"
APP="build/DiskNotch.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/DiskNotch"
cp Support/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"

echo "Pronto: $PWD/$APP"
