#!/bin/zsh
# Tezgâh.app'i derler ve kurar. Gerekli: Xcode Command Line Tools (xcode-select --install).
#   zsh Artifacts/_ortak/app/derle.sh              → ~/Applications/Tezgâh.app
#   zsh Artifacts/_ortak/app/derle.sh /Applications
# Çıkan uygulama hem Apple Silicon hem Intel Mac'te çalışır (ikinci Mac için).
set -e
cd "$(dirname "$0")"
HEDEF="${1:-$HOME/Applications}"
APP="$HEDEF/Tezgâh.app"
GECICI="$(mktemp -d)"
trap 'rm -rf "$GECICI"' EXIT

echo "→ derleniyor (arm64 + x86_64)…"
for MIMARI in arm64 x86_64; do
  swiftc -O -swift-version 5 -target "$MIMARI-apple-macos13.0" main.swift araclar.swift \
    -o "$GECICI/Tezgah-$MIMARI" -framework Cocoa -framework WebKit -framework ServiceManagement -framework Carbon
done
lipo -create "$GECICI/Tezgah-arm64" "$GECICI/Tezgah-x86_64" -output "$GECICI/Tezgah"

if [ ! -f Tezgah.icns ]; then
  echo "→ ikon çiziliyor…"
  python3 ikon.py "$GECICI/ikon.png" >/dev/null
  SET="$GECICI/Tezgah.iconset"; mkdir -p "$SET"
  for B in 16 32 128 256 512; do
    sips -z $B $B "$GECICI/ikon.png" --out "$SET/icon_${B}x${B}.png" >/dev/null
    sips -z $((B*2)) $((B*2)) "$GECICI/ikon.png" --out "$SET/icon_${B}x${B}@2x.png" >/dev/null
  done
  iconutil -c icns "$SET" -o Tezgah.icns
fi

echo "→ kuruluyor: $APP"
mkdir -p "$HEDEF"
if pgrep -x Tezgah >/dev/null; then osascript -e 'quit app id "com.mfg.tezgah"' || true; sleep 1; fi
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$GECICI/Tezgah" "$APP/Contents/MacOS/Tezgah"
cp Info.plist "$APP/Contents/Info.plist"
cp Tezgah.icns "$APP/Contents/Resources/Tezgah.icns"
codesign --force --deep --sign - "$APP" >/dev/null
touch "$APP"
# ikinci Mac için hazır kopya (kur.command önce bunu kullanır)
mkdir -p dagitim
rm -f dagitim/Tezgah.zip
ditto -c -k --keepParent "$APP" dagitim/Tezgah.zip
DIST_DIR="$HOME/Library/Mobile Documents/iCloud~md~obsidian/Documents/Personel Data Management/_araçlar/dagitim"   # iCloud copy for the other Mac
[ -d "$DIST_DIR" ] && cp dagitim/Tezgah.zip "$DIST_DIR/"
echo "✓ hazır: $APP  (+ dagitim/Tezgah.zip)"
