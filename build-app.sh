#!/bin/zsh
# Compila em release e empacota DiskNotch.app com a extensão de widgets
# (assinatura ad hoc, só para uso local).
set -euo pipefail
cd "${0:A:h}"

swift build -c release --product DiskNotch
swift build -c release --product DiskNotchWidget
BIN_DIR="$(swift build -c release --show-bin-path)"
APP="build/DiskNotch.app"
APPEX="$APP/Contents/PlugIns/DiskNotchWidget.appex"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APPEX/Contents/MacOS"
cp "$BIN_DIR/DiskNotch" "$APP/Contents/MacOS/DiskNotch"
cp Support/Info.plist "$APP/Contents/Info.plist"
cp "$BIN_DIR/DiskNotchWidget" "$APPEX/Contents/MacOS/DiskNotchWidget"
cp Support/Widget-Info.plist "$APPEX/Contents/Info.plist"

# Chaves que o Xcode grava em todo bundle. O serviço de widgets (chronod) ignora
# extensões sem a plataforma e o SDK declarados.
SDK_VERSION="$(xcrun --show-sdk-version)"
SDK_BUILD="$(xcrun --show-sdk-build-version)"
for PLIST in "$APP/Contents/Info.plist" "$APPEX/Contents/Info.plist"; do
    plutil -replace CFBundleInfoDictionaryVersion -string "6.0" "$PLIST"
    plutil -replace CFBundleSupportedPlatforms -json '["MacOSX"]' "$PLIST"
    plutil -replace DTPlatformName -string "macosx" "$PLIST"
    plutil -replace DTPlatformVersion -string "$SDK_VERSION" "$PLIST"
    plutil -replace DTPlatformBuild -string "$SDK_BUILD" "$PLIST"
    plutil -replace DTSDKName -string "macosx$SDK_VERSION" "$PLIST"
    plutil -replace DTSDKBuild -string "$SDK_BUILD" "$PLIST"
done

# A extensão é assinada antes do app, com a sandbox exigida pelo WidgetKit.
codesign --force --sign - --entitlements Support/Widget.entitlements "$APPEX"
codesign --force --sign - "$APP"

# Registra o app e a extensão no sistema, para o widget aparecer na galeria.
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
"$LSREGISTER" -f "$APP" >/dev/null 2>&1 || true
pluginkit -a "$APPEX" >/dev/null 2>&1 || true

echo "Pronto: $PWD/$APP"
