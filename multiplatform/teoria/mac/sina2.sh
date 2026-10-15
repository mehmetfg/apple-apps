#!/bin/zsh
# Depo + eşitleme sınaması (geçici vault ve kapsayıcı; gerçek kayda dokunmaz): zsh mac/sina2.sh
cd "${0:A:h}/.."
export DEVELOPER_DIR=/Library/Developer/CommandLineTools
SDK=/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk
G=$(mktemp -d)
mkdir -p $G/vault/veri && cp veri/kartlar.json veri/akis.json $G/vault/veri/
swiftc -swift-version 5 -parse-as-library -target arm64-apple-macos15.0 -sdk $SDK ios/Ortak/*.swift ios/Ekranlar/*.swift mac/sina2/main.swift -o $G/sina2 2>&1 | grep error -A3
TEORIA_VAULT=$G/vault TEORIA_KAPSAYICI=$G/kap $G/sina2
K=$?; rm -rf $G; exit $K
