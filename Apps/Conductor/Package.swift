// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Conductor",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Conductor", targets: ["Conductor"]),
        .executable(name: "ConductorModelCheck", targets: ["ConductorModelCheck"]),
        .library(name: "ConductorCore", targets: ["ConductorCore"])
    ],
    dependencies: [
        .package(path: "Packages/CodeEditSourceEditor"),
        .package(
            url: "https://github.com/CodeEditApp/CodeEditLanguages.git",
            exact: "0.1.20"
        )
    ],
    targets: [
        .binaryTarget(
            name: "GhosttyKit",
            path: "Vendor/GhosttyKit.xcframework"
        ),
        .target(
            name: "ConductorCore"
        ),
        .executableTarget(
            name: "Conductor",
            dependencies: [
                "ConductorCore",
                "GhosttyKit",
                "CodeEditSourceEditor",
                "CodeEditLanguages"
            ],
            linkerSettings: [
                .linkedLibrary("c++"),
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("IOSurface"),
                .linkedFramework("Metal"),
                .linkedFramework("QuartzCore"),
                .linkedFramework("UniformTypeIdentifiers")
            ]
        ),
        .executableTarget(
            name: "ConductorModelCheck",
            dependencies: ["ConductorCore"]
        )
    ]
)
