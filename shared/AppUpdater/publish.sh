#!/bin/zsh
# Stamps a build number into a freshly built Mac app, re-signs it with the same identity
# and publishes it to the shared iCloud folder, where AppUpdater.swift on the other Mac finds it.
#   zsh publish.sh <path/to/App.app> <ZipName>        e.g. publish.sh ~/Applications/Teoria.app Teoria
set -e
APP="$1"; NAME="$2"
DIST_DIR="${APP_UPDATER_DIR:-$HOME/Library/Mobile Documents/iCloud~md~obsidian/Documents/Personel Data Management/_araçlar/dagitim}"
[ -d "$APP" ] && [ -n "$NAME" ] || { echo "publish: usage: publish.sh <App.app> <ZipName>"; exit 1; }
[ -d "$DIST_DIR" ] || { echo "publish: shared folder missing, skipped: $DIST_DIR"; exit 0; }
BUILD=$(date +%Y%m%d%H%M%S)
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" "$APP/Contents/Info.plist"
ID=$(codesign -dvv "$APP" 2>&1 | sed -n 's/^Authority=//p' | head -1)
# by name first; if the name does not resolve (e.g. non-ASCII in it), use the certificate hash
if ! codesign --force --deep --sign "${ID:--}" "$APP" >/dev/null 2>&1; then
  HASH=$(security find-identity -v -p codesigning 2>/dev/null | awk '/Apple Development/{print $2; exit}')
  codesign --force --deep --sign "${HASH:--}" "$APP" >/dev/null 2>&1
fi
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
ditto -c -k --keepParent "$APP" "$TMP/$NAME.zip"
python3 "${0:A:h}/manifest.py" "$DIST_DIR" "$TMP/$NAME.zip" "$APP" "$NAME" "$BUILD"
