import XCTest
@testable import ConductorCore

final class UsageAccountCacheKeyTests: XCTestCase {
    func testCodexTokenAccountUsesWorkspaceAccountIDBeforeTokenUUID() {
        let account = UsageProviderTokenAccount(
            id: UUID(uuidString: "11111111-1111-4111-8111-111111111111")!,
            label: "user@example.com",
            token: "/codex",
            externalIdentifier: "live-system",
            organizationID: "acct_123")

        let key = UsageAccountCacheKey.tokenAccountKey(providerID: "codex", account: account)

        XCTAssertTrue(key.hasPrefix("codex-account:"))
        XCTAssertFalse(key.contains(account.id.uuidString.lowercased()))
        XCTAssertFalse(key.contains("acct_123"))
    }

    func testCodexTokenAccountFallsBackToHashedEmailWhenLiveSystemHasNoWorkspaceID() {
        let account = UsageProviderTokenAccount(
            id: UUID(uuidString: "22222222-2222-4222-8222-222222222222")!,
            label: "User@Example.com",
            token: "/codex",
            externalIdentifier: "live-system")

        let key = UsageAccountCacheKey.tokenAccountKey(providerID: "codex", account: account)

        XCTAssertTrue(key.hasPrefix("codex-email:"))
        XCTAssertFalse(key.localizedCaseInsensitiveContains("user@example.com"))
        XCTAssertFalse(key.contains(account.id.uuidString.lowercased()))
    }

    func testManagedCodexUUIDOnlyAccountUsesHashedManagedIdentifier() {
        let id = UUID(uuidString: "33333333-3333-4333-8333-333333333333")!
        let account = UsageProviderTokenAccount(
            id: id,
            label: "Codex",
            token: "/managed",
            externalIdentifier: "managed:\(id.uuidString.lowercased())")

        let key = UsageAccountCacheKey.tokenAccountKey(providerID: "codex", account: account)

        XCTAssertEqual(key, "external:codex:\(sha256Prefix("managed:\(id.uuidString.lowercased())"))")
    }

    func testGenericTokenAccountUsesHashedExternalIdentifier() {
        let account = UsageProviderTokenAccount(
            id: UUID(uuidString: "44444444-4444-4444-8444-444444444444")!,
            label: "Team A",
            token: "secret",
            externalIdentifier: "team-a")

        let key = UsageAccountCacheKey.tokenAccountKey(providerID: "litellm", account: account)

        XCTAssertTrue(key.hasPrefix("external:litellm:"))
        XCTAssertFalse(key.contains("team-a"))
    }

    func testStorageIDSeparatesScopedAndUnscopedHistory() {
        XCTAssertEqual(
            UsageAccountCacheKey.storageID(providerID: "codex", accountKey: nil),
            "codex")
        XCTAssertEqual(
            UsageAccountCacheKey.storageID(providerID: "codex", accountKey: "codex-email:abc"),
            "codex|account:codex-email:abc")
    }

    private func sha256Prefix(_ raw: String) -> String {
        UsageAccountCacheKey.tokenAccountKey(
            providerID: "dummy",
            account: UsageProviderTokenAccount(
                label: "x",
                token: "x",
                externalIdentifier: raw))
            .replacingOccurrences(of: "external:dummy:", with: "")
    }
}
