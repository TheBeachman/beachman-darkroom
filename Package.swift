// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "BeachmanDarkroom",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "BeachmanDarkroom",
            path: "Sources/BeachmanDarkroom",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
