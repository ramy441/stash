// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Stash",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(
            name: "Stash",
            path: "Sources/Stash",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
