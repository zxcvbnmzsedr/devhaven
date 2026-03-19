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
    ],
    targets: [
        .target(
            name: "DevHavenCore"
        ),
        .executableTarget(
            name: "DevHavenApp",
            dependencies: ["DevHavenCore"]
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
