#!/bin/zsh
# Teoria Mac uygulamasını derler: ~/Applications/Teoria.app (arm64 + Intel), Xcode gerekmez.
# Ev Mac'i: vault › _araçlar/dagitim/Teoria.zip; ilk kurulumdan sonra uygulama kendini günceller (shared/AppUpdater).
set -e
UPDATER="${0:A:h:h:h:h}/shared/AppUpdater"   # resolved before cd: $0 may be relative
cd "${0:A:h}/.."
KOK=$PWD
SDK=$(xcrun --show-sdk-path --sdk macosx 2>/dev/null || echo /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk)
[ -d /Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk ] && SDK=/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk
python3 veri/kapak.py >/dev/null            # kitap kapakları (akis.json'a göre)
GECICI=$(mktemp -d)
KAYNAK=(ios/Ortak/*.swift ios/Ekranlar/*.swift mac/TeoriaMac.swift mac/Atolye.swift mac/KutuphaneAg.swift mac/BookStudio.swift mac/Defter.swift "$UPDATER/AppUpdater.swift")
for MIMARI in arm64 x86_64; do
  swiftc -O -swift-version 5 -parse-as-library -target $MIMARI-apple-macos14.0 -sdk "$SDK" $KAYNAK -o "$GECICI/Teoria-$MIMARI"
done
APP="$HOME/Applications/Teoria.app"
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create "$GECICI/Teoria-arm64" "$GECICI/Teoria-x86_64" -output "$APP/Contents/MacOS/Teoria"
cp mac/Info.plist "$APP/Contents/Info.plist"
cp veri/kartlar.json veri/akis.json veri/mufredat.json "$APP/Contents/Resources/"
cp ios/Teoria/Kaynaklar/kapak-*.jpg "$APP/Contents/Resources/" 2>/dev/null || true
[ -f mac/Teoria.icns ] && cp mac/Teoria.icns "$APP/Contents/Resources/"
codesign --force --deep --sign - "$APP"
zsh "$UPDATER/publish.sh" "$APP" Teoria   # iCloud update for the other Mac
mkdir -p mac/dagitim
rm -f mac/dagitim/Teoria.zip
ditto -c -k --keepParent "$APP" mac/dagitim/Teoria.zip
rm -rf "$GECICI"
echo "Teoria.app hazır: $APP"
