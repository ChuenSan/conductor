// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Conductor",
    defaultLocalization: "zh-Hans",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ConductorCore", targets: ["ConductorCore"]),
        .executable(name: "ConductorApp", targets: ["ConductorApp"]),
    ],
    dependencies: [
        // YAML 解析（用户配置 config.yaml）。Swift 事实标准，支持 Codable。仅 App 层用。
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.1.0"),
    ],
    targets: [
        .target(
            name: "ConductorCore",
            resources: [
                .process("Resources/en.lproj"),
                .process("Resources/zh-Hans.lproj"),
            ]
        ),
        .testTarget(name: "ConductorCoreTests", dependencies: ["ConductorCore"]),
        .testTarget(name: "ConductorAppTests", dependencies: ["ConductorApp"]),

        // 预编译的 libghostty（来自 manaflow-ai/ghostty release，与 Conductor 同款）。
        .binaryTarget(
            name: "GhosttyKit",
            path: "Vendor/GhosttyKit.xcframework"
        ),
        // conductor 主应用：工作区 / Tab / 自由分屏 + 真 libghostty 终端。
        .executableTarget(
            name: "ConductorApp",
            dependencies: ["ConductorCore", "GhosttyKit", .product(name: "Yams", package: "Yams")],
            resources: [
                .copy("Resources/Logos"),
                .process("Resources/en.lproj"),
                .process("Resources/zh-Hans.lproj"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ],
            linkerSettings: [
                .linkedLibrary("c++"),
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("IOSurface"),
                .linkedFramework("Metal"),
                .linkedFramework("QuartzCore"),
            ]
        ),
    ]
)
