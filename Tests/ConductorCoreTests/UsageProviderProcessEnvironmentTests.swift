import XCTest
@testable import ConductorCore

final class UsageProviderProcessEnvironmentTests: XCTestCase {
    func testScrubbedChildEnvironmentRemovesKnownProviderSecretsByDefault() {
        let environment = UsageProviderProcessEnvironment.scrubbedChildEnvironment(from: [
            "PATH": "/usr/bin",
            "OPENAI_ADMIN_KEY": "openai-secret",
            "ANTHROPIC_ADMIN_KEY": "claude-secret",
            "DEEPGRAM_API_URL": "https://api.deepgram.com/v1",
            "UNRELATED": "keep",
        ])

        XCTAssertEqual(environment["PATH"], "/usr/bin")
        XCTAssertEqual(environment["UNRELATED"], "keep")
        XCTAssertNil(environment["OPENAI_ADMIN_KEY"])
        XCTAssertNil(environment["ANTHROPIC_ADMIN_KEY"])
        XCTAssertNil(environment["DEEPGRAM_API_URL"])
    }

    func testScrubbedChildEnvironmentCanAllowProviderSpecificNames() {
        let environment = UsageProviderProcessEnvironment.scrubbedChildEnvironment(
            from: [
                "OPENAI_ADMIN_KEY": "openai-secret",
                "ANTHROPIC_ADMIN_KEY": "claude-secret",
                "CONDUCTOR_USAGE_CLAUDE_COOKIE": "sessionKey=abc",
            ],
            preservingProviderID: "claude")

        XCTAssertNil(environment["OPENAI_ADMIN_KEY"])
        XCTAssertEqual(environment["ANTHROPIC_ADMIN_KEY"], "claude-secret")
        XCTAssertEqual(environment["CONDUCTOR_USAGE_CLAUDE_COOKIE"], "sessionKey=abc")
    }
}
