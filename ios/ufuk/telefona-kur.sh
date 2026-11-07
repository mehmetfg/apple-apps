#!/bin/zsh
# Ufuk'u (bisiklet yolu, hava, güneş) kablolu iPhone'a derleyip kurar ve açar. Geliştirici hesabıyla (ekip EK4WY8PSFE) imza bir yıl geçerli; süre dolunca ya da telefon değişince:
# telefonu bağla, kilidini aç, bu betiği yeniden çalıştır (ilerleme silinmez).
#   zsh ~/Documents/projects/apple-apps/ios/ufuk/telefona-kur.sh   (vault: zsh "_araçlar/ufuk/telefona-kur.sh")
# Başka iPhone'a kurmak için:  UFUK_CIHAZ=<udid> zsh …/telefona-kur.sh
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
tercih = os.environ.get("UFUK_CIHAZ", "00008110-001E384C0C30401E")   # Aşina ve Teoria'nın kurulu olduğu iPhone 13 Pro Max
adaylar = [x for x in d if x.get("hardwareProperties", {}).get("platform") == "iOS"
           and x.get("connectionProperties", {}).get("pairingState") == "paired"]
adaylar.sort(key=lambda x: x.get("hardwareProperties", {}).get("udid") != tercih)
for x in adaylar[:1]:
    print(x["hardwareProperties"].get("udid", ""), x.get("identifier", ""))
P
)
if [ -z "$UDID" ]; then echo "Bağlı, eşleşmiş iPhone bulunamadı. Kabloyla bağla, kilidini aç, 'Bu bilgisayara güven' de."; exit 1; fi
echo "iPhone: $UDID"
KAYIT=/tmp/ufuk-derleme.log
if ! xcodebuild -project ios/Ufuk.xcodeproj -scheme Ufuk -configuration Release \
  -destination "platform=iOS,id=$UDID" -derivedDataPath /tmp/ufuk-dev -allowProvisioningUpdates build > "$KAYIT" 2>&1; then
  echo "Derleme başarısız. Hatalar:"
  grep -E "error:" "$KAYIT" | sed 's/.*error: /  • /' | sort -u
  if grep -qi "maximum number of apps" "$KAYIT"; then
    echo "→ Bu iPhone'da ücretsiz imzanın 3 uygulama sınırı dolu. Birini sil (veriler o uygulamada kalır, tekrar kurulabilir) ya da UFUK_CIHAZ ile öteki iPhone'u seç."
  fi
  if grep -qi "weatherkit" "$KAYIT"; then
    echo "→ WeatherKit yetkisi alınamadı. developer.apple.com › Identifiers › com.fatihgocgun.ufuk › WeatherKit (Capabilities ve App Services) açılıp yeniden denenmeli."
  fi
  if grep -q "No Accounts" "$KAYIT"; then
    echo "→ Xcode › Settings › Accounts › + › Apple Account ile giriş yap, sonra bu betiği yeniden çalıştır."
  fi
  exit 1
fi
echo "Derleme tamam."
xcrun devicectl device install app --device "$DCID" /tmp/ufuk-dev/Build/Products/Release-iphoneos/Ufuk.app
xcrun devicectl device process launch --device "$DCID" com.fatihgocgun.ufuk || true
echo "Ufuk kuruldu. İlk açılışta bildirim, konum ve Apple Sağlık izinlerini ver; Ayarlar › Yerler’de ev ve işi işaretle; Ayarlar › PDM Ağı › Vault klasörünü seç."
