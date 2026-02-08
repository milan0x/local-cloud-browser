// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "LocalStackNavigator",
    platforms: [
        .macOS(.v14)
    ],
    // TODO: Add dependencies as needed:
    // .package(url: "https://github.com/soto-project/soto.git", from: "7.0.0"),
    dependencies: [],
    targets: [
        .executableTarget(
            name: "LocalStackNavigator",
            path: "Sources/LocalStackNavigator"
        )
    ]
)
