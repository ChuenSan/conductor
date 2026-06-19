import XCTest
@testable import ConductorCore

final class UsagePersonalInfoRedactorTests: XCTestCase {
    func testRedactEmailMatchesCodexBarPlaceholder() {
        XCTAssertEqual(
            UsagePersonalInfoRedactor.redactEmail("dev@example.com", isEnabled: true),
            "Hidden")
    }

    func testRedactEmailsReplacesEveryEmailInText() {
        let text = "dev@example.com · team@example.org"
        XCTAssertEqual(
            UsagePersonalInfoRedactor.redactEmails(in: text, isEnabled: true),
            "Hidden · Hidden")
    }

    func testRedactEmailsLeavesTextWhenDisabled() {
        let text = "dev@example.com"
        XCTAssertEqual(
            UsagePersonalInfoRedactor.redactEmails(in: text, isEnabled: false),
            text)
    }
}
