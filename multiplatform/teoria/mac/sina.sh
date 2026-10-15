#!/bin/zsh
# Motor sınaması: zsh mac/sina.sh
cd "${0:A:h}/.."
export DEVELOPER_DIR=/Library/Developer/CommandLineTools
SDK=/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk
[ -d $SDK ] || SDK=$(xcrun --show-sdk-path)
G=$(mktemp -d)
swiftc -swift-version 5 -target arm64-apple-macos15.0 -sdk $SDK ios/Ortak/Model.swift ios/Ortak/ConceptQuestion.swift ios/Ortak/FSRS.swift ios/Ortak/Dil.swift ios/Ortak/Motor.swift ios/Ortak/Gunluk.swift ios/Ortak/XPaylas.swift mac/sina/main.swift -o $G/sina && $G/sina "$PWD/veri"
