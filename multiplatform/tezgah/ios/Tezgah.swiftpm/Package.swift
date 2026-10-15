// swift-tools-version: 5.9
// Tezgâh — iPhone okuyucusu. Xcode'da bu klasörü (Tezgah.swiftpm) aç → hedef iPhone → ▶︎.
// Ayrıntı: ../README.md

import PackageDescription
import AppleProductTypes

let package = Package(
    name: "Tezgah",
    platforms: [
        .iOS("17.0")
    ],
    products: [
        .iOSApplication(
            name: "Tezgâh",
            targets: ["AppModule"],
            bundleIdentifier: "com.fatihgocgun.tezgah",
            teamIdentifier: "",
            displayVersion: "1.0",
            bundleVersion: "1",
            appIcon: .asset("AppIcon"),
            accentColor: .presetColor(.brown),
            supportedDeviceFamilies: [
                .phone
            ],
            supportedInterfaceOrientations: [
                .portrait
            ],
            appCategory: .productivity
        )
    ],
    targets: [
        .executableTarget(
            name: "AppModule",
            path: "."
        )
    ]
)
