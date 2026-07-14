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
        // NOTE: The iOS app is built exclusively by the xcodegen-generated
        // DejaVi.xcodeproj app target (sources in Sources/DejaViiOS, linking the
        // DejaViCore library). It is deliberately NOT an SPM target — an
        // executableTarget named "DejaViiOS" collides with the app scheme and
        // makes `xcodebuild archive` build a command-line tool (SKIP_INSTALL=YES)
        // instead of the app, producing an empty archive.
    ]
)
