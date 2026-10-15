#!/bin/zsh
# Builds the Atrium Mac app into ~/Applications/Atrium.app (arm64 + Intel). No Xcode project needed.
#   zsh "_araçlar/atrium/mac/build.sh"
set -e
cd "${0:A:h}/.."
SDK=$(xcrun --show-sdk-path --sdk macosx 2>/dev/null || echo /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk)
TMP=$(mktemp -d)
SOURCES=(ios/Core/*.swift ios/Screens/*.swift mac/AtriumMac.swift)
ARCHS=(arm64 x86_64)
[ "$1" = "--fast" ] && ARCHS=(arm64)
for ARCH in $ARCHS; do
  swiftc -O -swift-version 5 -parse-as-library -target $ARCH-apple-macos14.0 -sdk "$SDK" $SOURCES -o "$TMP/Atrium-$ARCH"
done
APP="$HOME/Applications/Atrium.app"
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create $TMP/Atrium-* -output "$APP/Contents/MacOS/Atrium"
cp mac/Info.plist "$APP/Contents/Info.plist"
[ -f mac/Atrium.icns ] && cp mac/Atrium.icns "$APP/Contents/Resources/"
codesign --force --deep --sign - "$APP"
rm -rf "$TMP"
echo "Atrium.app ready: $APP"
