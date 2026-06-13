// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Conductor",
    defaultLocalization: "zh-Hans",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ConductorCore", targets: ["ConductorCore"]),
        .library(name: "ConductorGit", targets: ["ConductorGit"]),
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

        // Git 内核：纯 Swift，shell 调 git CLI 再解析输出（移植自 SourceGit 的 Commands/Models）。
        // 无 UI、无引擎依赖，可独立测试。复用 ConductorCore 的 PathBuilder 解析 git/PATH。
        .target(
            name: "ConductorGit",
            dependencies: ["ConductorCore"]
        ),
        .testTarget(name: "ConductorGitTests", dependencies: ["ConductorGit"]),

        // 临时冒烟可执行：沙盒里无 Xcode/XCTest，用它对真实临时仓库跑运行时验证。开发结束后删除。
        .executableTarget(
            name: "GitSmoke",
            dependencies: ["ConductorGit"],
            swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "ConductorAppTests", dependencies: ["ConductorApp", "GhosttyKit"]),

        // 预编译的 libghostty（来自 manaflow-ai/ghostty release，与 Conductor 同款）。
        .binaryTarget(
            name: "GhosttyKit",
            path: "Vendor/GhosttyKit.xcframework"
        ),
        // conductor 主应用：工作区 / Tab / 自由分屏 + 真 libghostty 终端。
        .executableTarget(
            name: "ConductorApp",
            dependencies: ["ConductorCore", "ConductorGit", "GhosttyKit", .product(name: "Yams", package: "Yams")],
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
