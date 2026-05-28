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
        .package(path: "../../ThirdParty/CodexBar")
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
                .product(name: "CodexBarFeature", package: "CodexBar")
            ],
            resources: [
                .process("Resources")
            ],
            linkerSettings: [
                .linkedLibrary("c++"),
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("IOSurface"),
                .linkedFramework("Metal"),
                .linkedFramework("Quartz"),
                .linkedFramework("QuartzCore"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("UniformTypeIdentifiers"),
                .linkedFramework("WebKit")
            ]
        ),
        .executableTarget(
            name: "ConductorModelCheck",
            dependencies: ["ConductorCore"]
        )
    ]
)
