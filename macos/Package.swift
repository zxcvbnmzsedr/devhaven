// swift-tools-version: 6.0
import PackageDescription

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
    dependencies: [
        .package(path: "Vendor/CodeEditPackages/CodeEditSourceEditor"),
        .package(path: "Vendor/CodeEditPackages/CodeEditTextView"),
        .package(path: "Vendor/CodeEditPackages/CodeEditLanguages"),
    ],
    targets: [
        .binaryTarget(
            name: "GhosttyKit",
            path: "Vendor/GhosttyKit.xcframework"
        ),
        .binaryTarget(
            name: "Sparkle",
            path: "Vendor/Sparkle.xcframework"
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
                .product(name: "CodeEditLanguages", package: "CodeEditLanguages"),
                .product(name: "CodeEditSourceEditor", package: "CodeEditSourceEditor"),
                .product(name: "CodeEditTextView", package: "CodeEditTextView"),
            ],
            resources: [
                .copy("GhosttyResources"),
                .copy("AgentResources"),
            ],
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedLibrary("c++"),
            ]
        ),
        .testTarget(
            name: "DevHavenAppTests",
            dependencies: ["DevHavenApp", "DevHavenCore"]
        ),
        .testTarget(
            name: "DevHavenCoreTests",
            dependencies: ["DevHavenCore"]
        ),
    ]
)
