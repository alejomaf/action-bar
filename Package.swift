// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ActionBar",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(
            name: "ActionBar",
            targets: ["ActionBar"]
        ),
    ],
    targets: [
        .executableTarget(
            name: "ActionBar",
            path: "Sources/ActionBar",
            resources: [
                .process("Resources"),
            ]
        ),
        .testTarget(
            name: "ActionBarTests",
            dependencies: ["ActionBar"],
            path: "Tests/ActionBarTests"
        ),
    ]
)
