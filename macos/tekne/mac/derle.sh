#!/bin/zsh
# Builds Tekne (Mac, arm64 + Intel) without Xcode: ~/Applications/Tekne.app
#   zsh "_araçlar/tekne/mac/derle.sh"
set -e
UPDATER="${0:A:h:h:h:h}/shared/AppUpdater"   # resolved before cd: $0 may be relative
cd "${0:A:h}"
SDK=$(xcrun --show-sdk-path --sdk macosx 2>/dev/null || echo /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
for ARCH in arm64 x86_64; do
  swiftc -O -swift-version 5 -parse-as-library -target $ARCH-apple-macos14.0 -sdk "$SDK" Sources/*.swift "$UPDATER/AppUpdater.swift" "${UPDATER:h}/TimeBox/TimeBox.swift" -o "$TMP/Tekne-$ARCH"
done
APP="${TEKNE_APP:-$HOME/Applications/Tekne.app}"
if [ -z "$TEKNE_APP" ] && pgrep -xq Tekne; then pkill -x Tekne || true; sleep 1; fi
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create "$TMP/Tekne-arm64" "$TMP/Tekne-x86_64" -output "$APP/Contents/MacOS/Tekne"
cp Info.plist "$APP/Contents/Info.plist"
# sign by certificate hash: the name has non-ASCII letters and does not always resolve
ID=$(security find-identity -v -p codesigning 2>/dev/null | awk '/Apple Development/{print $2; exit}')
codesign --force --deep --sign "${ID:--}" "$APP"
[ -z "$TEKNE_APP" ] && zsh "$UPDATER/publish.sh" "$APP" Tekne   # iCloud update for the other Mac
echo "Tekne.app ready: $APP (signature: ${ID:-ad-hoc})"
