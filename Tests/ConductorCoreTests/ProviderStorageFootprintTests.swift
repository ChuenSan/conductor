import XCTest
@testable import ConductorCore

final class ProviderStorageFootprintTests: XCTestCase {
    func testScannerTotalsFilesByTopLevelComponent() throws {
        let root = try makeTemporaryDirectory()
        let sessions = root.appendingPathComponent("sessions", isDirectory: true)
        let cache = root.appendingPathComponent("cache", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 11).write(to: sessions.appendingPathComponent("a.jsonl"))
        try Data(repeating: 2, count: 7).write(to: sessions.appendingPathComponent("b.jsonl"))
        try Data(repeating: 3, count: 5).write(to: cache.appendingPathComponent("c.bin"))

        let footprint = ProviderStorageScanner().scan(
            providerID: "codex",
            candidatePaths: [root.path],
            now: Date(timeIntervalSince1970: 1))

        XCTAssertEqual(footprint.providerID, "codex")
        XCTAssertEqual(footprint.totalBytes, 23)
        XCTAssertEqual(footprint.paths, [root.path])
        XCTAssertTrue(footprint.missingPaths.isEmpty)
        XCTAssertEqual(footprint.components.map(\.name), ["sessions", "cache"])
        XCTAssertEqual(footprint.components.map(\.totalBytes), [18, 5])
    }

    func testCandidatePathsIncludeCodexHomeAndManagedHomes() throws {
        let root = try makeTemporaryDirectory()
        let codexHome = root.appendingPathComponent("live-codex", isDirectory: true)
        let managedHome = root.appendingPathComponent("managed-codex", isDirectory: true)
        let storeURL = root.appendingPathComponent("managed-codex-accounts.json")
        try FileManager.default.createDirectory(at: codexHome, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: managedHome, withIntermediateDirectories: true)
        try FileCodexManagedAccountStore(fileURL: storeURL).storeAccounts(CodexManagedAccountSet(
            version: 1,
            accounts: [
                CodexManagedAccount(
                    id: UUID(uuidString: "11111111-1111-4111-8111-111111111111")!,
                    email: "user@example.com",
                    managedHomePath: managedHome.path,
                    createdAt: 1,
                    updatedAt: 1),
            ]))

        let paths = ProviderStoragePathCatalog.candidatePaths(
            for: "codex",
            environment: [
                "HOME": root.path,
                "CODEX_HOME": codexHome.path,
                CodexManagedAccountDiscovery.storePathEnvironmentName: storeURL.path,
            ])

        XCTAssertEqual(paths, [codexHome.path, managedHome.path])
    }

    func testCandidatePathsDeduplicateAdditionalCodexHomes() throws {
        let root = try makeTemporaryDirectory()
        let codexHome = root.appendingPathComponent("codex", isDirectory: true)
        let otherHome = root.appendingPathComponent("codex-other", isDirectory: true)

        let paths = ProviderStoragePathCatalog.candidatePaths(
            for: "codex",
            environment: [
                "HOME": root.path,
                "CODEX_HOME": codexHome.path,
                CodexManagedAccountDiscovery.storePathEnvironmentName:
                    root.appendingPathComponent("missing-store.json").path,
            ],
            additionalCodexHomePaths: [codexHome.path, otherHome.path, " "])

        XCTAssertEqual(paths, [codexHome.path, otherHome.path])
    }

    func testCodexCleanupRecommendationsAreScopedAndSorted() throws {
        let root = try makeTemporaryDirectory()
        let external = try makeTemporaryDirectory()
        let footprint = ProviderStorageFootprint(
            providerID: "codex",
            totalBytes: 170,
            paths: [root.path],
            missingPaths: [],
            unreadablePaths: [],
            components: [
                .init(path: root.appendingPathComponent("cache").path, totalBytes: 30),
                .init(path: root.appendingPathComponent("sessions").path, totalBytes: 20),
                .init(path: root.appendingPathComponent("logs_2026.sqlite").path, totalBytes: 100),
                .init(path: external.appendingPathComponent("sessions").path, totalBytes: 999),
                .init(path: root.appendingPathComponent("unknown").path, totalBytes: 20),
            ],
            updatedAt: Date())

        let recommendations = footprint.cleanupRecommendations

        XCTAssertEqual(recommendations.map(\.title), [
            "手动清理：会话",
            "手动清理：缓存",
            "手动清理：日志",
        ])
        XCTAssertEqual(recommendations.map(\.exportTitle), [
            "Manual cleanup: sessions",
            "Manual cleanup: cache",
            "Manual cleanup: logs",
        ])
        XCTAssertEqual(recommendations.map(\.bytes), [20, 30, 100])
        XCTAssertTrue(recommendations.allSatisfy { $0.providerID == "codex" })
        XCTAssertTrue(recommendations.allSatisfy { $0.riskLevel == .manualCleanup })
    }

    func testClaudeCleanupRecommendationsUseKnownComponentNames() throws {
        let root = try makeTemporaryDirectory()
        let footprint = ProviderStorageFootprint(
            providerID: "claude",
            totalBytes: 150,
            paths: [root.path],
            missingPaths: [],
            unreadablePaths: [],
            components: [
                .init(path: root.appendingPathComponent("image-cache").path, totalBytes: 90),
                .init(path: root.appendingPathComponent("projects").path, totalBytes: 20),
                .init(path: root.appendingPathComponent("plans").path, totalBytes: 40),
            ],
            updatedAt: Date())

        XCTAssertEqual(footprint.cleanupRecommendations.map(\.title), [
            "手动清理：历史会话",
            "手动清理：已保存计划",
            "手动清理：附件缓存",
        ])
        XCTAssertEqual(footprint.cleanupRecommendations.map(\.exportTitle), [
            "Manual cleanup: past sessions",
            "Manual cleanup: saved plans",
            "Manual cleanup: attachment cache",
        ])
    }

    func testApplyingScanResultsReusesExistingFootprintWhenOnlyTimestampChanges() throws {
        let root = try makeTemporaryDirectory()
        let existing = ProviderStorageFootprint(
            providerID: "codex",
            totalBytes: 12,
            paths: [root.path],
            missingPaths: [],
            unreadablePaths: [],
            components: [.init(path: root.appendingPathComponent("sessions").path, totalBytes: 12)],
            updatedAt: Date(timeIntervalSince1970: 1))
        let incoming = ProviderStorageFootprint(
            providerID: "codex",
            totalBytes: 12,
            paths: [root.path],
            missingPaths: [],
            unreadablePaths: [],
            components: [.init(path: root.appendingPathComponent("sessions").path, totalBytes: 12)],
            updatedAt: Date(timeIntervalSince1970: 99))
        let unrelated = ProviderStorageFootprint(
            providerID: "claude",
            totalBytes: 3,
            paths: [root.appendingPathComponent("claude").path],
            missingPaths: [],
            unreadablePaths: [],
            updatedAt: Date(timeIntervalSince1970: 5))

        let updated = ProviderStorageFootprint.applyingScanResults(
            ["codex": incoming],
            to: ["codex": existing, "claude": unrelated],
            providerIDs: ["codex"])

        XCTAssertEqual(updated["codex"], existing)
        XCTAssertEqual(updated["codex"]?.updatedAt, Date(timeIntervalSince1970: 1))
        XCTAssertEqual(updated["claude"], unrelated)
    }

    func testApplyingScanResultsReplacesChangedFootprints() throws {
        let root = try makeTemporaryDirectory()
        let existing = ProviderStorageFootprint(
            providerID: "codex",
            totalBytes: 12,
            paths: [root.path],
            missingPaths: [],
            unreadablePaths: [],
            updatedAt: Date(timeIntervalSince1970: 1))
        let incoming = ProviderStorageFootprint(
            providerID: "codex",
            totalBytes: 24,
            paths: [root.path],
            missingPaths: [],
            unreadablePaths: [],
            updatedAt: Date(timeIntervalSince1970: 99))

        let updated = ProviderStorageFootprint.applyingScanResults(
            ["codex": incoming],
            to: ["codex": existing],
            providerIDs: ["codex"])

        XCTAssertEqual(updated["codex"], incoming)
    }

    func testApplyingScanResultsRemovesProviderWithoutFreshFootprint() throws {
        let root = try makeTemporaryDirectory()
        let existing = ProviderStorageFootprint(
            providerID: "codex",
            totalBytes: 12,
            paths: [root.path],
            missingPaths: [],
            unreadablePaths: [],
            updatedAt: Date(timeIntervalSince1970: 1))
        let unrelated = ProviderStorageFootprint(
            providerID: "claude",
            totalBytes: 3,
            paths: [root.appendingPathComponent("claude").path],
            missingPaths: [],
            unreadablePaths: [],
            updatedAt: Date(timeIntervalSince1970: 5))

        let updated = ProviderStorageFootprint.applyingScanResults(
            [:],
            to: ["codex": existing, "claude": unrelated],
            providerIDs: ["codex"])

        XCTAssertNil(updated["codex"])
        XCTAssertEqual(updated["claude"], unrelated)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("conductor-storage-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }
}
