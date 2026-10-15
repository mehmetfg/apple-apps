#!/bin/zsh
# Cümle Mac uygulamasını derler: ~/Applications/Cümle.app (arm64 + Intel), Xcode gerekmez.
# Öteki Mac için: vault › _araçlar/dagitim/Cumle.zip (aç, Uygulamalar'a sürükle; ilk açılışta sağ tık › Aç).
set -e
cd "${0:A:h}"
SDK=$(xcrun --show-sdk-path --sdk macosx 2>/dev/null || echo /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk)
GECICI=$(mktemp -d)
KAYNAK=(Kaynak/*.swift)
for MIMARI in arm64 x86_64; do
  swiftc -O -swift-version 5 -parse-as-library -target $MIMARI-apple-macos14.0 -sdk "$SDK" $KAYNAK -o "$GECICI/Cumle-$MIMARI"
done
APP="$HOME/Applications/Cümle.app"
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create "$GECICI/Cumle-arm64" "$GECICI/Cumle-x86_64" -output "$APP/Contents/MacOS/Cumle"
cp Info.plist "$APP/Contents/Info.plist"
[ -f Cumle.icns ] && cp Cumle.icns "$APP/Contents/Resources/"
codesign --force --deep --sign - "$APP"
mkdir -p dagitim
rm -f dagitim/Cumle.zip
ditto -c -k --keepParent "$APP" dagitim/Cumle.zip
DIST_DIR="$HOME/Library/Mobile Documents/iCloud~md~obsidian/Documents/Personel Data Management/_araçlar/dagitim"   # iCloud copy for the other Mac
[ -d "$DIST_DIR" ] && cp dagitim/Cumle.zip "$DIST_DIR/"
rm -rf "$GECICI"
echo "Cümle.app hazır: $APP"
