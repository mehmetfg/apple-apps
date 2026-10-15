#!/bin/zsh
# Ekran önizlemesi (sahte geçmişle, geçici klasörde): zsh mac/ekran.sh → onizleme/e-*.png
cd "${0:A:h}/.."
export DEVELOPER_DIR=/Library/Developer/CommandLineTools
SDK=/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk
G=$(mktemp -d)
swiftc -swift-version 5 -parse-as-library -target arm64-apple-macos15.0 -sdk $SDK ios/Ortak/*.swift ios/Ekranlar/*.swift mac/Atolye.swift mac/ekran/main.swift -o $G/ekran 2>&1 | grep error -A3
TEORIA_KAPAK="$PWD/ios/Teoria/Kaynaklar" TEORIA_KAPSAYICI=$G/kap $G/ekran "$PWD/onizleme" "$PWD/veri"
# widget'ları da aynı sahte geçmişin anlık görüntüsüyle çiz
swiftc -O -swift-version 5 -target arm64-apple-macos15.0 -sdk $SDK ios/Ortak/*.swift mac/onizle/main.swift -o $G/onizle 2>&1 | grep error -A3
$G/onizle "$PWD/onizleme" "$G/kap/widget.json"
rm -rf $G
