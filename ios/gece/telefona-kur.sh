#!/bin/zsh
# Gece'yi (akşam 3–5 dakikalık bel, boyun, diz rutini) kablolu iPhone'a derleyip kurar ve açar. Geliştirici hesabıyla (ekip EK4WY8PSFE) imza bir yıl geçerli; süre dolunca ya da telefon değişince:
# telefonu bağla, kilidini aç, bu betiği yeniden çalıştır (ilerleme silinmez).
#   zsh ~/Documents/projects/apple-apps/ios/gece/telefona-kur.sh   (vault: zsh "_araçlar/gece/telefona-kur.sh")
# Başka iPhone'a kurmak için:  GECE_CIHAZ=<udid> zsh …/telefona-kur.sh
set -e
setopt pipefail
cd "${0:A:h}"
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
if xcodebuild -showsdks 2>&1 | grep -q "license"; then
  echo "Xcode lisansı onaylanmamış. Önce Terminal'de: sudo xcodebuild -license accept"; exit 1
fi
if ! xcrun simctl list runtimes 2>/dev/null | grep -q "iOS"; then
  echo "iOS platformu henüz kurulu değil. İndirme sürüyorsa bitmesini bekle; yoksa: xcodebuild -downloadPlatform iOS"; exit 1
fi
CIHAZ_JSON=$(mktemp)
xcrun devicectl list devices --json-output "$CIHAZ_JSON" >/dev/null 2>&1 || true
read UDID DCID <<<$(python3 - "$CIHAZ_JSON" <<'P'
import json, sys
try:
    d = json.load(open(sys.argv[1]))["result"]["devices"]
except Exception:
    d = []
import os
tercih = os.environ.get("GECE_CIHAZ", "00008110-001E384C0C30401E")   # Aşina ve Teoria'nın kurulu olduğu iPhone 13 Pro Max
adaylar = [x for x in d if x.get("hardwareProperties", {}).get("platform") == "iOS"
           and x.get("connectionProperties", {}).get("pairingState") == "paired"]
adaylar.sort(key=lambda x: x.get("hardwareProperties", {}).get("udid") != tercih)
for x in adaylar[:1]:
    print(x["hardwareProperties"].get("udid", ""), x.get("identifier", ""))
P
)
if [ -z "$UDID" ]; then echo "Bağlı, eşleşmiş iPhone bulunamadı. Kabloyla bağla, kilidini aç, 'Bu bilgisayara güven' de."; exit 1; fi
echo "iPhone: $UDID"
KAYIT=/tmp/gece-derleme.log
if ! xcodebuild -project ios/Gece.xcodeproj -scheme Gece -configuration Release \
  -destination "platform=iOS,id=$UDID" -derivedDataPath /tmp/gece-dev -allowProvisioningUpdates build > "$KAYIT" 2>&1; then
  echo "Derleme başarısız. Hatalar:"
  grep -E "error:" "$KAYIT" | sed 's/.*error: /  • /' | sort -u
  if grep -qi "maximum number of apps" "$KAYIT"; then
    echo "→ Bu iPhone'da ücretsiz imzanın 3 uygulama sınırı dolu. Birini sil (veriler o uygulamada kalır, tekrar kurulabilir) ya da GECE_CIHAZ ile öteki iPhone'u seç."
  fi
  if grep -q "No Accounts" "$KAYIT"; then
    echo "→ Xcode › Settings › Accounts › + › Apple Account ile giriş yap, sonra bu betiği yeniden çalıştır."
  fi
  exit 1
fi
echo "Derleme tamam."
xcrun devicectl device install app --device "$DCID" /tmp/gece-dev/Build/Products/Release-iphoneos/Gece.app
xcrun devicectl device process launch --device "$DCID" com.fatihgocgun.gece || true
echo "Gece kuruldu. İlk açılışta bildirim ve Apple Sağlık izinlerini ver; Ayarlar › PDM Ağı › Vault klasörünü seç."
