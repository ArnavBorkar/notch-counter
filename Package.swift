// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NotchCounter",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/vapor/postgres-nio.git", from: "1.21.0"),
    ],
    targets: [
        .executableTarget(
            name: "NotchCounter",
            dependencies: [.product(name: "PostgresNIO", package: "postgres-nio")],
            path: "Sources/NotchCounter"
        )
    ]
)
