// swift-tools-version: 6.2
import CompilerPluginSupport
import Foundation
import PackageDescription

let sweetCookieKitPath = "../SweetCookieKit"
let useLocalSweetCookieKit =
    ProcessInfo.processInfo.environment["CODEXBAR_USE_LOCAL_SWEETCOOKIEKIT"] == "1"
let sweetCookieKitDependency: Package.Dependency =
    useLocalSweetCookieKit && FileManager.default.fileExists(atPath: sweetCookieKitPath)
    ? .package(path: sweetCookieKitPath)
    : .package(url: "https://github.com/steipete/SweetCookieKit", from: "0.4.1")

let cliOnly = ProcessInfo.processInfo.environment["CODEXBAR_CLI_ONLY"] == "1"
let dependencies: [Package.Dependency] = {
    var dependencies: [Package.Dependency] = [
        .package(url: "https://github.com/steipete/Commander", from: "0.2.1"),
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0"),
        .package(url: "https://github.com/apple/swift-log", from: "1.12.0"),
        .package(url: "https://github.com/apple/swift-syntax", from: "600.0.1"),
        sweetCookieKitDependency,
    ]
    guard !cliOnly else { return dependencies }
    dependencies.append(contentsOf: [
        .package(url: "https://github.com/zats/Vortex", revision: "ef5392088d4aeb255c4eee83157dbdafcd31bf07"),
    ])
    return dependencies
}()

let package = Package(
    name: "CodexBar",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "CodexBarFeature", targets: ["CodexBar"]),
    ],
    dependencies: dependencies,
    targets: {
        var targets: [Target] = [
            .target(
                name: "CodexBarCore",
                dependencies: [
                    "CodexBarMacroSupport",
                    .product(name: "Crypto", package: "swift-crypto"),
                    .product(name: "Logging", package: "swift-log"),
                    .product(name: "SweetCookieKit", package: "SweetCookieKit"),
                ],
                swiftSettings: [
                    .enableUpcomingFeature("StrictConcurrency"),
                ]),
            .macro(
                name: "CodexBarMacros",
                dependencies: [
                    .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
                    .product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
                    .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                ]),
            .target(
                name: "CodexBarMacroSupport",
                dependencies: [
                    "CodexBarMacros",
                ]),
            .executableTarget(
                name: "CodexBarCLI",
                dependencies: [
                    "CodexBarCore",
                    .product(name: "Commander", package: "Commander"),
                ],
                path: "Sources/CodexBarCLI",
                swiftSettings: [
                    .enableUpcomingFeature("StrictConcurrency"),
                ]),
            .testTarget(
                name: "CodexBarLinuxTests",
                dependencies: ["CodexBarCore", "CodexBarCLI"],
                path: "TestsLinux",
                swiftSettings: [
                    .enableUpcomingFeature("StrictConcurrency"),
                    .enableExperimentalFeature("SwiftTesting"),
                ]),
        ]

        #if os(macOS)
        if !cliOnly {
            targets.append(contentsOf: [
                .executableTarget(
                    name: "CodexBarClaudeWatchdog",
                    dependencies: [],
                    path: "Sources/CodexBarClaudeWatchdog",
                    swiftSettings: [
                        .enableUpcomingFeature("StrictConcurrency"),
                    ]),
                .target(
                    name: "CodexBar",
                    dependencies: [
                        .product(name: "Vortex", package: "Vortex"),
                        "CodexBarMacroSupport",
                        "CodexBarCore",
                    ],
                    path: "Sources/CodexBar",
                    resources: [
                        .process("Resources"),
                    ],
                    swiftSettings: [
                        // Opt into Swift 6 strict concurrency (approachable migration path).
                        .enableUpcomingFeature("StrictConcurrency"),
                        .define("CONDUCTOR_EMBEDDED"),
                    ]),
                .executableTarget(
                    name: "CodexBarWidget",
                    dependencies: ["CodexBarCore"],
                    path: "Sources/CodexBarWidget",
                    swiftSettings: [
                        .enableUpcomingFeature("StrictConcurrency"),
                    ]),
                .executableTarget(
                    name: "CodexBarClaudeWebProbe",
                    dependencies: ["CodexBarCore"],
                    path: "Sources/CodexBarClaudeWebProbe",
                    swiftSettings: [
                        .enableUpcomingFeature("StrictConcurrency"),
                    ]),
            ])

            targets.append(.testTarget(
                name: "CodexBarTests",
                dependencies: ["CodexBar", "CodexBarCore", "CodexBarCLI", "CodexBarWidget"],
                path: "Tests",
                resources: [
                    .copy("CodexBarTests/Fixtures"),
                ],
                swiftSettings: [
                    .enableUpcomingFeature("StrictConcurrency"),
                    .enableExperimentalFeature("SwiftTesting"),
                ]))
        }
        #endif

        return targets
    }())
