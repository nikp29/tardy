// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Tardy",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Tardy",
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
