import XCTest
@testable import ConductorCore

final class CodexActiveAccountResolverTests: XCTestCase {
    func testDefaultsToLiveSystemWhenNoConfiguredAccountExists() {
        let live = account(
            id: UUID(uuidString: "11111111-1111-4111-8111-111111111111")!,
            label: "live@example.com",
            token: "/live",
            externalIdentifier: "live-system")

        let resolution = CodexActiveAccountResolver.resolveDefaultAccount(
            configured: nil,
            discoveredAccounts: [live])

        XCTAssertEqual(resolution.resolvedAccount, live)
        XCTAssertFalse(resolution.requiresPersistenceCorrection)
        XCTAssertEqual(resolution.reason, .liveSystemDefault)
    }

    func testRefreshesConfiguredManagedAccountFromDiscovery() {
        let id = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
        let configured = account(
            id: id,
            label: "old@example.com",
            token: "/old-managed",
            externalIdentifier: "managed:\(id.uuidString.lowercased())")
        let discovered = account(
            id: id,
            label: "new@example.com",
            token: "/new-managed",
            externalIdentifier: "managed:\(id.uuidString.lowercased())")

        let resolution = CodexActiveAccountResolver.resolveDefaultAccount(
            configured: UsageProviderTokenAccountData(accounts: [configured], activeIndex: 0),
            discoveredAccounts: [discovered])

        XCTAssertEqual(resolution.persistedAccount, configured)
        XCTAssertEqual(resolution.resolvedAccount, discovered)
        XCTAssertTrue(resolution.requiresPersistenceCorrection)
        XCTAssertEqual(resolution.reason, .refreshedDiscoveredAccount)
    }

    func testManagedAccountConvergesToLiveSystemWhenPromotionReusesStoredIdentity() {
        let id = UUID(uuidString: "33333333-3333-4333-8333-333333333333")!
        let configured = account(
            id: id,
            label: "managed@example.com",
            token: "/managed",
            externalIdentifier: "managed:\(id.uuidString.lowercased())")
        let live = account(
            id: id,
            label: "managed@example.com",
            token: "/live",
            externalIdentifier: "live-system")

        let resolution = CodexActiveAccountResolver.resolveDefaultAccount(
            configured: UsageProviderTokenAccountData(accounts: [configured], activeIndex: 0),
            discoveredAccounts: [live])

        XCTAssertEqual(resolution.resolvedAccount, live)
        XCTAssertTrue(resolution.requiresPersistenceCorrection)
        XCTAssertEqual(resolution.reason, .managedAccountConvergedToLiveSystem)
    }

    func testMissingManagedAccountFallsBackToLiveSystem() {
        let configured = account(
            id: UUID(uuidString: "44444444-4444-4444-8444-444444444444")!,
            label: "missing@example.com",
            token: "/missing-managed",
            externalIdentifier: "managed:44444444-4444-4444-8444-444444444444")
        let live = account(
            id: UUID(uuidString: "55555555-5555-4555-8555-555555555555")!,
            label: "live@example.com",
            token: "/live",
            externalIdentifier: "live-system")

        let resolution = CodexActiveAccountResolver.resolveDefaultAccount(
            configured: UsageProviderTokenAccountData(accounts: [configured], activeIndex: 0),
            discoveredAccounts: [live])

        XCTAssertEqual(resolution.resolvedAccount, live)
        XCTAssertTrue(resolution.requiresPersistenceCorrection)
        XCTAssertEqual(resolution.reason, .managedAccountMissingFellBackToLiveSystem)
    }

    func testMergedAccountsReplacesConfiguredAccountsWithFreshDiscoveryAndAppendsNewAccounts() {
        let managedID = UUID(uuidString: "66666666-6666-4666-8666-666666666666")!
        let configuredManaged = account(
            id: managedID,
            label: "old@example.com",
            token: "/old",
            externalIdentifier: "managed:\(managedID.uuidString.lowercased())")
        let discoveredManaged = account(
            id: managedID,
            label: "new@example.com",
            token: "/new",
            externalIdentifier: "managed:\(managedID.uuidString.lowercased())")
        let live = account(
            id: UUID(uuidString: "77777777-7777-4777-8777-777777777777")!,
            label: "live@example.com",
            token: "/live",
            externalIdentifier: "live-system")

        let merged = CodexActiveAccountResolver.mergedAccounts(
            configured: [configuredManaged],
            discovered: [discoveredManaged, live])

        XCTAssertEqual(merged, [discoveredManaged, live])
    }

    func testCorrectedTokenAccountDataClampsActiveIndex() {
        let account = account(
            id: UUID(uuidString: "88888888-8888-4888-8888-888888888888")!,
            label: "configured@example.com",
            token: "/configured",
            externalIdentifier: "managed:88888888-8888-4888-8888-888888888888")

        let corrected = CodexActiveAccountResolver.correctedTokenAccountData(
            configured: UsageProviderTokenAccountData(accounts: [account], activeIndex: 99),
            discoveredAccounts: [])

        XCTAssertEqual(corrected, Optional(UsageProviderTokenAccountData(accounts: [account], activeIndex: 0)))
    }

    func testCorrectedTokenAccountDataPersistsManagedPromotionToLive() {
        let id = UUID(uuidString: "99999999-9999-4999-8999-999999999999")!
        let configured = account(
            id: id,
            label: "managed@example.com",
            token: "/managed",
            externalIdentifier: "managed:\(id.uuidString.lowercased())")
        let live = account(
            id: id,
            label: "managed@example.com",
            token: "/live",
            externalIdentifier: "live-system")

        let corrected = CodexActiveAccountResolver.correctedTokenAccountData(
            configured: UsageProviderTokenAccountData(accounts: [configured], activeIndex: 0),
            discoveredAccounts: [live])

        XCTAssertEqual(corrected, Optional(UsageProviderTokenAccountData(accounts: [live], activeIndex: 0)))
    }

    func testCorrectedTokenAccountDataPersistsMissingManagedFallbackToLive() {
        let configured = account(
            id: UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!,
            label: "missing@example.com",
            token: "/missing-managed",
            externalIdentifier: "managed:aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")
        let live = account(
            id: UUID(uuidString: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb")!,
            label: "live@example.com",
            token: "/live",
            externalIdentifier: "live-system")

        let corrected = CodexActiveAccountResolver.correctedTokenAccountData(
            configured: UsageProviderTokenAccountData(accounts: [configured], activeIndex: 0),
            discoveredAccounts: [live])

        XCTAssertEqual(corrected, Optional(UsageProviderTokenAccountData(accounts: [configured, live], activeIndex: 1)))
    }

    private func account(
        id: UUID,
        label: String,
        token: String,
        externalIdentifier: String)
        -> UsageProviderTokenAccount
    {
        UsageProviderTokenAccount(
            id: id,
            label: label,
            token: token,
            externalIdentifier: externalIdentifier)
    }
}
