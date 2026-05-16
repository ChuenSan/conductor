// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "GhosttySurfaceValidation",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "GhosttySurfaceValidation",
            targets: ["GhosttySurfaceValidation"]
        )
    ],
    targets: [
        .binaryTarget(
            name: "GhosttyKit",
            path: "Vendor/GhosttyKit.xcframework"
        ),
        .executableTarget(
            name: "GhosttySurfaceValidation",
            dependencies: ["GhosttyKit"],
            linkerSettings: [
                .linkedLibrary("c++"),
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("IOSurface"),
                .linkedFramework("Metal"),
                .linkedFramework("QuartzCore"),
                .linkedFramework("UniformTypeIdentifiers")
            ]
        )
    ]
)
