#!/bin/zsh
# Uygulamalarım menü çubuğu uygulamasını derler: ~/Applications/Uygulamalarım.app (arm64 + Intel), Xcode gerekmez.
# Liste derlemeye gömülmez: uygulama her açılışta ../uygulamalar.json'u okur (içine yalnız yedek kopya konur).
#   zsh "_araçlar/cekmece/mac/derle.sh"
set -e
cd "${0:A:h}"
SDK=$(xcrun --show-sdk-path --sdk macosx 2>/dev/null || echo /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk)
GECICI=$(mktemp -d)
trap 'rm -rf "$GECICI"' EXIT
python3 -c "import json,sys; json.load(open('../uygulamalar.json'))" || { echo "uygulamalar.json bozuk"; exit 1; }
if [ ! -f Cekmece.icns ]; then
  swift ikon.swift "$GECICI/ikon.png"
  mkdir "$GECICI/Cekmece.iconset"
  for s in 16 32 128 256 512; do
    sips -z $s $s "$GECICI/ikon.png" --out "$GECICI/Cekmece.iconset/icon_${s}x${s}.png" >/dev/null
    sips -z $((s*2)) $((s*2)) "$GECICI/ikon.png" --out "$GECICI/Cekmece.iconset/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$GECICI/Cekmece.iconset" -o Cekmece.icns
fi
for MIMARI in arm64 x86_64; do
  swiftc -O -swift-version 5 -target $MIMARI-apple-macos14.0 -sdk "$SDK" main.swift -o "$GECICI/Cekmece-$MIMARI"
done
APP="$HOME/Applications/Uygulamalarım.app"
ACIKTI=0
if pgrep -xq Cekmece; then ACIKTI=1; pkill -x Cekmece || true; sleep 1; fi
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create "$GECICI/Cekmece-arm64" "$GECICI/Cekmece-x86_64" -output "$APP/Contents/MacOS/Cekmece"
cp Info.plist "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string Cekmece" "$APP/Contents/Info.plist"
cp Cekmece.icns ../uygulamalar.json "$APP/Contents/Resources/"
KIMLIK=$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Apple Development/{print $2; exit}')
codesign --force --deep --sign "${KIMLIK:--}" "$APP"
echo "Uygulamalarım.app hazır: $APP (imza: ${KIMLIK:-geçici})"
open "$APP"
