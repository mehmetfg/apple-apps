#!/bin/zsh
# Kıvılcım Mac uygulamasını derler: ~/Applications/Kıvılcım.app (arm64 + Intel), Xcode gerekmez.
# Ortak çekirdek ios/Ortak/ altındadır (telefonla aynı veri modeli, arama, kural sınıflayıcı).
#   zsh "_araçlar/kivilcim/mac/derle.sh"
set -e
cd "${0:A:h}"
SDK=$(xcrun --show-sdk-path --sdk macosx 2>/dev/null || echo /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk)
GECICI=$(mktemp -d)
KAYNAK=(Kaynak/*.swift ../ios/Ortak/Veri.swift ../ios/Ortak/Renk.swift)
for MIMARI in arm64 x86_64; do
  swiftc -O -swift-version 5 -parse-as-library -target $MIMARI-apple-macos14.0 -sdk "$SDK" $KAYNAK -o "$GECICI/Kivilcim-$MIMARI"
done
APP="$HOME/Applications/Kıvılcım.app"
ACIKTI=0
if pgrep -xq Kivilcim; then ACIKTI=1; osascript -e 'quit app id "com.fatihgocgun.kivilcim.mac"' 2>/dev/null || pkill -x Kivilcim || true; sleep 1; fi
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create "$GECICI/Kivilcim-arm64" "$GECICI/Kivilcim-x86_64" -output "$APP/Contents/MacOS/Kivilcim"
cp Info.plist "$APP/Contents/Info.plist"
cp Kivilcim.icns "$APP/Contents/Resources/"
# Geliştirici kimliğiyle imzala: mikrofon izni her derlemede yeniden sorulmasın. Kimlik yoksa geçici imza.
KIMLIK=$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Apple Development/{print $2; exit}')
codesign --force --deep --sign "${KIMLIK:--}" "$APP"
rm -rf "$GECICI"
echo "Kıvılcım.app hazır: $APP (imza: ${KIMLIK:-geçici})"
[ "$ACIKTI" = 1 ] && open "$APP" || true
