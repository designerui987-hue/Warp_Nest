// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WarpNest",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "WarpCore", targets: ["WarpCore"]),
        .executable(name: "warpnest", targets: ["WarpCLI"])
    ],
    targets: [
        .target(
            name: "WarpCore",
            dependencies: []
        ),
        .executableTarget(
            name: "WarpCLI",
            dependencies: ["WarpCore"]
        ),
        .testTarget(
            name: "WarpCoreTests",
            dependencies: ["WarpCore"]
        )
    ]
)
