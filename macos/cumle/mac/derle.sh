#!/bin/zsh
# Cümle Mac uygulamasını derler: ~/Applications/Cümle.app (arm64 + Intel), Xcode gerekmez.
# Öteki Mac: vault › _araçlar/dagitim/Cumle.zip; ilk kurulumdan sonra uygulama kendini günceller (shared/AppUpdater).
set -e
UPDATER="${0:A:h:h:h:h}/shared/AppUpdater"   # resolved before cd: $0 may be relative
cd "${0:A:h}"
SDK=$(xcrun --show-sdk-path --sdk macosx 2>/dev/null || echo /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk)
GECICI=$(mktemp -d)
KAYNAK=(Kaynak/*.swift "$UPDATER/AppUpdater.swift")
for MIMARI in arm64 x86_64; do
  swiftc -O -swift-version 5 -parse-as-library -target $MIMARI-apple-macos14.0 -sdk "$SDK" $KAYNAK -o "$GECICI/Cumle-$MIMARI"
done
APP="$HOME/Applications/Cümle.app"
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create "$GECICI/Cumle-arm64" "$GECICI/Cumle-x86_64" -output "$APP/Contents/MacOS/Cumle"
cp Info.plist "$APP/Contents/Info.plist"
[ -f Cumle.icns ] && cp Cumle.icns "$APP/Contents/Resources/"
codesign --force --deep --sign - "$APP"
zsh "$UPDATER/publish.sh" "$APP" Cumle   # iCloud update for the other Mac
mkdir -p dagitim
rm -f dagitim/Cumle.zip
ditto -c -k --keepParent "$APP" dagitim/Cumle.zip
rm -rf "$GECICI"
echo "Cümle.app hazır: $APP"
