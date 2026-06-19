import XCTest
@testable import ConductorCore

final class UsageSnapshotHydrationStoreTests: XCTestCase {
    func testStoresAndLoadsScopedSnapshot() throws {
        let root = temporaryRoot()
        let now = Date(timeIntervalSince1970: 1_000)
        let snapshot = UsageSnapshot(
            primary: RateWindow(title: "Session", usedPercent: 42),
            planName: "Pro",
            accountLabel: "team@example.com",
            updatedAt: now)

        UsageSnapshotHydrationStore.save(
            providerID: "codex",
            accountKey: "codex-email:abc",
            snapshot: snapshot,
            recordedAt: now,
            source: "test",
            applicationSupportRoot: root)

        let loaded = try XCTUnwrap(UsageSnapshotHydrationStore.loadRecord(
            providerID: "codex",
            accountKey: "codex-email:abc",
            maxAge: nil,
            applicationSupportRoot: root))

        XCTAssertEqual(loaded.providerID, "codex")
        XCTAssertEqual(loaded.accountKey, "codex-email:abc")
        XCTAssertEqual(loaded.snapshot, snapshot)
        XCTAssertEqual(loaded.source, "test")
    }

    func testFallsBackToUnscopedSnapshotWhenScopedRecordIsMissing() throws {
        let root = temporaryRoot()
        let snapshot = UsageSnapshot(
            primary: RateWindow(title: "Budget", usedPercent: 12),
            updatedAt: Date(timeIntervalSince1970: 2_000))

        UsageSnapshotHydrationStore.save(
            providerID: "claude",
            accountKey: nil,
            snapshot: snapshot,
            recordedAt: snapshot.updatedAt,
            applicationSupportRoot: root)

        let loaded = UsageSnapshotHydrationStore.loadSnapshot(
            providerID: "claude",
            accountKey: "external:claude:team-a",
            maxAge: nil,
            applicationSupportRoot: root)

        XCTAssertEqual(loaded, snapshot)
    }

    func testMaxAgeRejectsStaleSnapshots() {
        let root = temporaryRoot()
        let old = Date(timeIntervalSinceNow: -10_000)
        UsageSnapshotHydrationStore.save(
            providerID: "codex",
            accountKey: nil,
            snapshot: UsageSnapshot(
                primary: RateWindow(title: "Session", usedPercent: 10),
                updatedAt: old),
            recordedAt: old,
            applicationSupportRoot: root)

        XCTAssertNil(UsageSnapshotHydrationStore.loadSnapshot(
            providerID: "codex",
            accountKey: nil,
            maxAge: 1,
            applicationSupportRoot: root))
    }

    func testClearRemovesHydrationFile() {
        let root = temporaryRoot()
        UsageSnapshotHydrationStore.save(
            providerID: "codex",
            accountKey: nil,
            snapshot: UsageSnapshot(primary: RateWindow(title: "Session", usedPercent: 10)),
            applicationSupportRoot: root)

        let removed = UsageSnapshotHydrationStore.clear(applicationSupportRoot: root)

        XCTAssertEqual(removed, [UsageSnapshotHydrationStore.fileURL(applicationSupportRoot: root)])
        XCTAssertNil(UsageSnapshotHydrationStore.loadSnapshot(
            providerID: "codex",
            accountKey: nil,
            maxAge: nil,
            applicationSupportRoot: root))
    }

    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
}
