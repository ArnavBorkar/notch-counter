// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NotchCounter",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "NotchCounter", path: "Sources/NotchCounter")
    ]
)
