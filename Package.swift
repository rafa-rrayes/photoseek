// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "PhotoSeek",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "PhotoSeek",
            path: "Sources/PhotoSeek",
            exclude: ["Resources"],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
