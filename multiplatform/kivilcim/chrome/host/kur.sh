#!/bin/zsh
# Registers the Kıvılcım helper with Chrome (and Brave/Edge/Arc/Chromium if present). Run once per Mac:
#   zsh ~/Documents/projects/apple-apps/multiplatform/kivilcim/chrome/host/kur.sh
# Then in Chrome: chrome://extensions › Developer mode › Load unpacked › …/kivilcim/chrome
set -e
DIR="${0:A:h}"
# Chrome'un başlattığı programlar ~/Documents'ı okuyamaz (macOS gizlilik kuralı): yardımcı korumasız bir yere kopyalanır.
# Yardımcı değişince bu betik yeniden çalıştırılır.
KUR="$HOME/Library/Application Support/Kivilcim/chrome-host"
mkdir -p "$KUR"
cp "$DIR/kivilcim_host.py" "$KUR/kivilcim_host.py"
HOST="$KUR/kivilcim_host.py"
chmod +x "$HOST"
EXT_ID=$(cat "$DIR/../.extid")
ICERIK=$(cat <<EOF
{
  "name": "com.fatihgocgun.kivilcim",
  "description": "Kıvılcım · Dikkat yardımcısı",
  "path": "$HOST",
  "type": "stdio",
  "allowed_origins": ["chrome-extension://$EXT_ID/"]
}
EOF
)
for d in "Google/Chrome" "Google/Chrome Beta" "Chromium" "BraveSoftware/Brave-Browser" "Microsoft Edge" "Arc/User Data"; do
  base="$HOME/Library/Application Support/$d"
  [ -d "$base" ] || continue
  mkdir -p "$base/NativeMessagingHosts"
  print -r -- "$ICERIK" > "$base/NativeMessagingHosts/com.fatihgocgun.kivilcim.json"
  echo "kuruldu: $d"
done
echo "eklenti kimliği: $EXT_ID"
