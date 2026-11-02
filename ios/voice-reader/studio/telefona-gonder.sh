#!/bin/zsh
# Sends a studio pack (<name>.vrstudio, made by studio.py) to Voice Reader on the iPhone: it is copied into the app's
# Documents folder, and the app adds it to the library the next time it comes to the front (same book again = its
# audio is replaced). The phone must be paired (cable or the same network).
#   zsh telefona-gonder.sh ~/Documents/"Voice Reader Studio"/leibniz.vrstudio
set -e
PACK="${1:?usage: telefona-gonder.sh <pack.vrstudio>}"
PACK="${PACK%/}"
NAME="${PACK:t}"
TMP=$(mktemp -d)
cp -R "$PACK" "$TMP/$NAME"
# packs made before book.json carried an id: give it the same id studio.py now writes (from the title)
python3 - "$TMP/$NAME/book.json" <<'P'
import json, sys, uuid
p = sys.argv[1]; b = json.load(open(p))
b.setdefault("id", str(uuid.uuid5(uuid.NAMESPACE_URL, "voice-reader-studio:" + b["title"])).upper())
json.dump(b, open(p, "w"), ensure_ascii=False)
print(f"{b['title']}: {len(b['segments'])} parça, {sum(s.get('duration', 0) for s in b['segments']) / 60:.1f} dk ses")
P
DEV=$(xcrun devicectl list devices 2>/dev/null | awk '/iPhone/ && /available/ {print $3; exit}')
[ -z "$DEV" ] && { echo "Eşleşmiş, erişilebilir iPhone yok."; exit 1; }
xcrun devicectl device copy to --device "$DEV" --domain-type appDataContainer --domain-identifier com.fatihgocgun.okur \
  --source "$TMP/$NAME" --destination "Documents/$NAME" >/dev/null
rm -rf "$TMP"
echo "Gönderildi. Voice Reader'ı aç: kitap kütüphaneye girer (Felsefe/Bilimler/Mühendislik ile başlıyorsa o klasöre)."
