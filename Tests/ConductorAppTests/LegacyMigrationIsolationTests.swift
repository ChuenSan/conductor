@testable import ConductorApp
import ConductorCore
import XCTest

final class LegacyMigrationIsolationTests: XCTestCase {
    func testMigrationIsDisabledWhenStateDirectoryIsOverridden() {
        let env = [ConductorPaths.stateDirEnvKey: "/tmp/conductor-isolated-\(UUID().uuidString)"]

        XCTAssertFalse(LegacyMigration.shouldRun(environment: env))
    }
}
