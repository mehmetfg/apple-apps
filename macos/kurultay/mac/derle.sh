#!/bin/zsh
# Builds Kurultay (Mac, arm64 + Intel) without Xcode: ~/Applications/Kurultay.app
#   zsh "_araçlar/kurultay/mac/derle.sh"
set -e
UPDATER="${0:A:h:h:h:h}/shared/AppUpdater"
cd "${0:A:h}"
SDK=$(xcrun --show-sdk-path --sdk macosx 2>/dev/null || echo /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
for ARCH in arm64 x86_64; do
  swiftc -O -swift-version 5 -parse-as-library -target $ARCH-apple-macos14.0 -sdk "$SDK" Sources/*.swift "$UPDATER/AppUpdater.swift" -o "$TMP/Kurultay-$ARCH"
done
APP="${KURULTAY_APP:-$HOME/Applications/Kurultay.app}"
if [ -z "$KURULTAY_APP" ] && pgrep -xq Kurultay; then pkill -x Kurultay || true; sleep 1; fi
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create "$TMP/Kurultay-arm64" "$TMP/Kurultay-x86_64" -output "$APP/Contents/MacOS/Kurultay"
cp Info.plist "$APP/Contents/Info.plist"
cp Resources/adapters.json "$APP/Contents/Resources/"
[ -f Resources/Kurultay.icns ] && cp Resources/Kurultay.icns "$APP/Contents/Resources/"
ID=$(security find-identity -v -p codesigning 2>/dev/null | awk '/Apple Development/{print $2; exit}')
codesign --force --deep --sign "${ID:--}" "$APP"
[ -z "$KURULTAY_APP" ] && zsh "$UPDATER/publish.sh" "$APP" Kurultay
echo "Kurultay.app ready: $APP (signature: ${ID:-ad-hoc})"
