// swift-tools-version: 5.4

import PackageDescription

let package = Package(
    name: "unfaird",
    platforms: [
        .macOS(.v10_15),
    ],
    products: [
        .executable(name: "UnfairDaemon", targets: ["UnfairDaemon"]),
    ],
    dependencies: [
        .package(name: "unfair-swift", url: "https://github.com/Lakr233/unfair.git", .exact("0.1.4")),
        .package(url: "https://github.com/apple/swift-argument-parser.git", .upToNextMinor(from: "1.0.0")),
        .package(url: "https://github.com/vapor/vapor.git", .exact("4.60.0")),
    ],
    targets: [
        .executableTarget(
            name: "UnfairDaemon",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "UnfairKit", package: "unfair-swift"),
                .product(name: "Vapor", package: "vapor"),
            ]
        ),
    ]
)
