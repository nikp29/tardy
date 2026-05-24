// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Tardy",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/google/GoogleSignIn-iOS.git", from: "8.0.0")
    ],
    targets: [
        .executableTarget(
            name: "Tardy",
            dependencies: [
                .product(name: "GoogleSignIn", package: "GoogleSignIn-iOS")
            ],
            path: "Sources/Tardy",
            exclude: ["Resources/Tardy.entitlements"],
            resources: [
                .copy("Resources/CalendarUsage.plist"),
                .copy("Resources/Fonts"),
                .copy("Resources/Sounds"),
            ]
        ),
        .testTarget(
            name: "TardyTests",
            dependencies: ["Tardy"],
            path: "Tests/TardyTests"
        ),
    ]
)
