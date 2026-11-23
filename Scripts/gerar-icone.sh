#!/bin/zsh
# Gera Support/AppIcon.icns a partir do desenho do ícone (o mesmo anel do banner do README).
#
#   Scripts/gerar-icone.sh
#
# Usa o app já compilado para desenhar o ícone em 1024 px (docs/design/app-icon.png),
# reduz para todos os tamanhos que o macOS pede e monta o .icns com o iconutil.
set -euo pipefail
cd "${0:A:h}/.."

APP_BIN="build/DiskNotch.app/Contents/MacOS/DiskNotch"
[[ -x "$APP_BIN" ]] || ./build-app.sh
"$APP_BIN" --render-readme-images "$PWD/docs/design" >/dev/null

MASTER="docs/design/app-icon.png"
SET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$SET"
for size in 16 32 128 256 512; do
    sips -z $size $size "$MASTER" --out "$SET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z $double $double "$MASTER" --out "$SET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$SET" -o Support/AppIcon.icns
rm -rf "${SET:h}"
echo "Pronto: Support/AppIcon.icns"
