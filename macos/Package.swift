// swift-tools-version: 6.0
import PackageDescription
import Foundation

let cmuxBuildProductsPath = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("Vendor/CmuxBuildProducts")
    .path

let package = Package(
    name: "DevHavenNative",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "DevHavenCore", targets: ["DevHavenCore"]),
        .executable(name: "DevHavenApp", targets: ["DevHavenApp"]),
        .executable(name: "DevHavenCLI", targets: ["DevHavenCLI"]),
    ],
    dependencies: [],
    targets: [
        .binaryTarget(
            name: "GhosttyKit",
            path: "Vendor/GhosttyKit.xcframework"
        ),
        .binaryTarget(
            name: "Sparkle",
            path: "Vendor/Sparkle.xcframework"
        ),
        .binaryTarget(
            name: "CmuxEmbedded",
            path: "Vendor/CmuxEmbedded.xcframework"
        ),
        .target(
            name: "DevHavenCore"
        ),
        .executableTarget(
            name: "DevHavenCLI",
            dependencies: ["DevHavenCore"]
        ),
        .executableTarget(
            name: "DevHavenApp",
            dependencies: [
                "DevHavenCore",
                "GhosttyKit",
                "Sparkle",
                "CmuxEmbedded",
            ],
            resources: [
                .copy("GhosttyResources"),
                .copy("AgentResources"),
                .copy("MarkdownResources"),
                .copy("MonacoDiffResources"),
                .copy("MonacoEditorResources"),
                .copy("WorkspaceRunConfigurationResources"),
            ],
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedLibrary("c++"),
                .linkedFramework("Sentry", .when(platforms: [.macOS])),
                .linkedFramework("Iroh", .when(platforms: [.macOS])),
                .unsafeFlags([
                    "-F", cmuxBuildProductsPath,
                ]),
            ]
        ),
        .testTarget(
            name: "DevHavenAppTests",
            dependencies: [
                "DevHavenApp",
                "DevHavenCore",
            ]
        ),
        .testTarget(
            name: "DevHavenCoreTests",
            dependencies: ["DevHavenCore"]
        ),
    ]
)
