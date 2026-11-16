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
        // NOTE: The iOS app is built exclusively by the xcodegen-generated
        // PhotoSeek.xcodeproj app target (sources in Sources/PhotoSeekiOS, linking the
        // PhotoSeekCore library). It is deliberately NOT an SPM target — an
        // executableTarget named "PhotoSeekiOS" collides with the app scheme and
        // makes `xcodebuild archive` build a command-line tool (SKIP_INSTALL=YES)
        // instead of the app, producing an empty archive.
    ]
)
