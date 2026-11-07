#!/bin/zsh
# Builds Perde and installs it on the connected iPhone. Lists, ratings and keys are kept.
# The developer account (team EK4WY8PSFE) signs for one year. When it expires, connect the
# phone, unlock it and run this again.
#   zsh install-on-iphone.sh
# For another iPhone:  PERDE_DEVICE=<udid> zsh install-on-iphone.sh
set -e
setopt pipefail
cd "${0:A:h}/ios"
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

DEVICES_JSON=$(mktemp)
xcrun devicectl list devices --json-output "$DEVICES_JSON" >/dev/null 2>&1 || true
read UDID CORE_DEVICE_ID <<<$(python3 - "$DEVICES_JSON" <<'PY'
import json, os, sys
try:
    devices = json.load(open(sys.argv[1]))["result"]["devices"]
except Exception:
    devices = []
preferred = os.environ.get("PERDE_DEVICE", "00008110-001E384C0C30401E")  # iPhone 13 Pro Max
paired = [d for d in devices if d.get("hardwareProperties", {}).get("platform") == "iOS"
          and d.get("connectionProperties", {}).get("pairingState") == "paired"]
paired.sort(key=lambda d: d.get("hardwareProperties", {}).get("udid") != preferred)
for device in paired[:1]:
    print(device["hardwareProperties"].get("udid", ""), device.get("identifier", ""))
PY
)
if [ -z "$UDID" ]; then
  echo "Bağlı, eşleşmiş iPhone bulunamadı. Kabloyla bağla, kilidini aç, 'Bu bilgisayara güven' de."
  exit 1
fi
echo "iPhone: $UDID"

[ -d Perde.xcodeproj ] || xcodegen generate
BUILD_DIR="$HOME/Library/Developer/Xcode/DerivedData/Perde-device"
LOG=$(mktemp -t perde-build)
if ! xcodebuild -project Perde.xcodeproj -scheme Perde -configuration Release \
    -destination "id=$UDID" -derivedDataPath "$BUILD_DIR" -allowProvisioningUpdates build > "$LOG" 2>&1; then
  grep -E 'error:|requires a provisioning|No Accounts' "$LOG" | sort -u | head -20
  echo "Derleme başarısız. Ayrıntı: $LOG"
  exit 1
fi

APP="$BUILD_DIR/Build/Products/Release-iphoneos/Perde.app"
xcrun devicectl device install app --device "$CORE_DEVICE_ID" "$APP"
xcrun devicectl device process launch --device "$CORE_DEVICE_ID" com.fatihgocgun.perde \
  || echo "Kuruldu, ama açılamadı. Telefon kilitli olabilir; ana ekrandan aç."
