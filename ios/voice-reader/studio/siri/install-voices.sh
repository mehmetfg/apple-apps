#!/bin/zsh
# Copies this Mac's Turkish Siri voices (Elif, Kaan) and their shared resource into the app's Models folder, where
# Wise Path's SiriEngine finds them (Speech/Neural/Models/SiriVoices.bundle; Models/ is not in the public repo).
# The voices are on the Mac when Siri's language is Turkish; pick each voice once in System Settings › Siri to
# download it. Run again after a macOS update to take newer voices.
#   zsh studio/siri/install-voices.sh [target folder]
set -e
setopt pipefail null_glob
here="${0:A:h}"
target="${1:-$here/../../ios/VoiceReader/Speech/Neural/Models/SiriVoices.bundle}"
assets=/System/Library/AssetsV2/com_apple_MobileAsset_Trial_Siri_SiriTextToSpeech/purpose_auto

# newest asset whose name matches: "<version> <path>"
newest() {
  local best="" best_version=-1 name version
  for plist in $assets/*.asset/Info.plist; do
    name=$(/usr/libexec/PlistBuddy -c "Print :CFBundleName" "$plist" 2>/dev/null) || continue
    [[ "$name" == $~1 ]] || continue
    version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$plist" 2>/dev/null || echo 0)
    version=${version%%.*}
    if (( version > best_version )); then best_version=$version; best="${plist:h}/AssetData"; fi
  done
  [[ -n "$best" ]] && echo "$best_version $best"
}

mkdir -p "$target"
missing=0
for item in "elif:com.apple.siri.tts.voice.tr_TR.elif.neural.*" "kaan:com.apple.siri.tts.voice.tr_TR.kaan.neural.*" "resource:com.apple.siri.tts.resource.tr_TR-*"; do
  folder="${item%%:*}"; pattern="${item#*:}"
  found=$(newest "$pattern") || true
  if [[ -z "$found" ]]; then
    echo "✗ $folder: bu Mac'te yok (Sistem Ayarları › Siri › Dil: Türkçe; sesi bir kez seç ki insin)."
    missing=1; continue
  fi
  version="${found%% *}"; source="${found#* }"
  rm -rf "$target/$folder"
  cp -R "$source" "$target/$folder"
  chmod -R u+w "$target/$folder"
  echo "✓ $folder: sürüm $version, $(du -sh "$target/$folder" | cut -f1)"
done
(( missing )) && { echo "Eksik ses var; uygulamada o ses soluk görünür."; exit 1; }
echo "Hazır: $target"
