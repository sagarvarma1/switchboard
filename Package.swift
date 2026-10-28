// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GhostCursor",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "GhostCursor",
            path: "Sources/GhostCursor",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("Carbon"),
            ]
        )
    ],
    swiftLanguageModes: [.v5]
)
