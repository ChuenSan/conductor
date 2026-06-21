@testable import ConductorApp
import ConductorCore
import XCTest

final class UsageCredentialsIsolationTests: XCTestCase {
    override func tearDown() {
        UsageCredentials.apply(.default)
        unsetenv("OPENAI_ADMIN_KEY")
        unsetenv("OPENAI_API_KEY")
        super.tearDown()
    }

    func testManagedCredentialsAreRestoredWhileSpawningTerminalChildren() throws {
        unsetenv("OPENAI_ADMIN_KEY")
        unsetenv("OPENAI_API_KEY")

        var config = AppConfig.default
        config.usage.providers["openai"] = UsageProviderConfig(enabled: true, apiKey: "app-secret")

        UsageCredentials.apply(config)
        XCTAssertEqual(String(cString: getenv("OPENAI_ADMIN_KEY")), "app-secret")

        var observed: [String: String] = [:]
        UsageCredentials.withManagedProcessEnvironmentRestored {
            observed = ProcessInfo.processInfo.environment
            XCTAssertNil(getenv("OPENAI_ADMIN_KEY"))
            XCTAssertNil(getenv("OPENAI_API_KEY"))
        }

        XCTAssertNil(observed["OPENAI_ADMIN_KEY"])
        XCTAssertNil(observed["OPENAI_API_KEY"])
        XCTAssertEqual(String(cString: getenv("OPENAI_ADMIN_KEY")), "app-secret")
        XCTAssertEqual(String(cString: getenv("OPENAI_API_KEY")), "app-secret")
    }

    func testTerminalScrubPairsBlankActiveManagedCredentialNames() {
        var config = AppConfig.default
        config.usage.providers["openai"] = UsageProviderConfig(enabled: true, apiKey: "app-secret")

        UsageCredentials.apply(config)

        let scrub = Dictionary(uniqueKeysWithValues: UsageCredentials.terminalEnvironmentScrubPairs())

        XCTAssertEqual(scrub["OPENAI_ADMIN_KEY"], "")
        XCTAssertEqual(scrub["OPENAI_API_KEY"], "")
    }
}
