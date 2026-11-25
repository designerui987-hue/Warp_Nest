// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WarpNest",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "WarpCore", targets: ["WarpCore"]),
        .executable(name: "warpctl", targets: ["WarpCTL"]),
        .executable(name: "warpnest", targets: ["WarpCLI"]),
        .executable(name: "WarpNestApp", targets: ["WarpNestApp"])
    ],
    targets: [
        .target(
            name: "WarpCore",
            dependencies: []
        ),
        .executableTarget(
            name: "WarpCTL",
            dependencies: ["WarpCore"]
        ),
        .executableTarget(
            name: "WarpCLI",
            dependencies: ["WarpCore"]
        ),
        .executableTarget(
            name: "WarpNestApp",
            dependencies: ["WarpCore"],
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .testTarget(
            name: "WarpCoreTests",
            dependencies: ["WarpCore"]
        )
    ]
)
