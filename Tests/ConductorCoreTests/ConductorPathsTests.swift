import XCTest
@testable import ConductorCore

final class ConductorPathsTests: XCTestCase {
    func testStateDirectoryOverrideControlsAppSupportDirectoryAndSocket() {
        let root = URL(fileURLWithPath: "/tmp/conductor-state-\(UUID().uuidString)", isDirectory: true)
        let env = [ConductorPaths.stateDirEnvKey: root.path]

        XCTAssertEqual(ConductorPaths.appSupportDirectory(environment: env), root)
        XCTAssertEqual(
            ConductorPaths.agentHomeDirectory(environment: env),
            root.appendingPathComponent("home", isDirectory: true))
        XCTAssertEqual(
            ConductorPaths.automationSocketURL(environment: env),
            root.appendingPathComponent("automation.sock", isDirectory: false))
    }

    func testStateDirectoryOverrideControlsDefaultConfigURL() {
        let root = URL(fileURLWithPath: "/tmp/conductor-state-\(UUID().uuidString)", isDirectory: true)
        let env = [ConductorPaths.stateDirEnvKey: root.path]

        XCTAssertEqual(
            ConductorPaths.configURL(environment: env),
            root.appendingPathComponent("config.yaml", isDirectory: false))
    }

    func testExplicitConfigPathWinsOverStateDirectory() {
        let root = URL(fileURLWithPath: "/tmp/conductor-state-\(UUID().uuidString)", isDirectory: true)
        let explicit = URL(fileURLWithPath: "/tmp/conductor-config-\(UUID().uuidString).yaml")
        let env = [
            ConductorPaths.stateDirEnvKey: root.path,
            ConductorPaths.configPathEnvKey: explicit.path,
        ]

        XCTAssertEqual(ConductorPaths.configURL(environment: env), explicit)
    }
}
