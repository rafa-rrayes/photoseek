// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "DejaVi",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "DejaViCore", targets: ["DejaViCore"]),
    ],
    targets: [
        .target(
            name: "DejaViCore",
            path: "Sources/DejaViCore",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .executableTarget(
            name: "DejaViMac",
            dependencies: ["DejaViCore"],
            path: "Sources/DejaViMac",
            exclude: ["Resources/Info.plist", "Resources/DejaVi.entitlements", "Resources/AppIcon.icns"],
            resources: [
                .copy("Resources/MenuBarIcon.png"),
                .copy("Resources/MenuBarIcon@2x.png"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .executableTarget(
            name: "DejaViiOS",
            dependencies: ["DejaViCore"],
            path: "Sources/DejaViiOS",
            exclude: ["Resources/Info.plist"],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
    ]
)
