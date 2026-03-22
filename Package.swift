// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "PhotoSeek",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "PhotoSeek",
            path: "Sources/PhotoSeek",
            exclude: ["Resources/Info.plist", "Resources/PhotoSeek.entitlements", "Resources/AppIcon.icns"],
            resources: [
                .copy("Resources/MenuBarIcon.png"),
                .copy("Resources/MenuBarIcon@2x.png"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
