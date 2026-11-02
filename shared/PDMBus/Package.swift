// swift-tools-version:5.9
// PDMBus — the shared Swift package of the PDM bus (vault `_bus/`).
// Event writing (`_bus/events/<app>/<device>.jsonl`), state reading (`_bus/state/*.json`),
// vault folder access, and the shared App Group `group.com.fatihgocgun.pdm`.
import PackageDescription

let package = Package(
    name: "PDMBus",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "PDMBus", targets: ["PDMBus"])],
    targets: [
        .target(name: "PDMBus"),
        .testTarget(name: "PDMBusTests", dependencies: ["PDMBus"]),
    ],
    swiftLanguageVersions: [.v5]
)
