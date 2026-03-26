// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "PhotoSeek",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "PhotoSeekCore", targets: ["PhotoSeekCore"]),
    ],
    targets: [
        .target(
            name: "PhotoSeekCore",
            path: "Sources/PhotoSeekCore",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .executableTarget(
            name: "PhotoSeekMac",
            dependencies: ["PhotoSeekCore"],
            path: "Sources/PhotoSeekMac",
            exclude: ["Resources/Info.plist", "Resources/PhotoSeek.entitlements", "Resources/AppIcon.icns"],
            resources: [
                .copy("Resources/MenuBarIcon.png"),
                .copy("Resources/MenuBarIcon@2x.png"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .executableTarget(
            name: "PhotoSeekiOS",
            dependencies: ["PhotoSeekCore"],
            path: "Sources/PhotoSeekiOS",
            exclude: ["Resources/Info.plist"],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
    ]
)
