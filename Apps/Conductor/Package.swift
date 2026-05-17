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
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", from: "2.4.1")
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
                .product(name: "MarkdownUI", package: "swift-markdown-ui")
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
