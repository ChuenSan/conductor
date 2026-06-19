import Foundation
#if canImport(SQLite3)
import SQLite3
#endif
import XCTest
@testable import ConductorCore

final class OpenCodeGoUsageTests: XCTestCase {
    #if canImport(SQLite3)
    func testLocalUsageReaderBuildsCodexBarWindows() throws {
        let env = try Self.makeEnvironment()
        defer { try? FileManager.default.removeItem(at: env.root) }

        try Self.writeAuth(to: env.authURL)
        try Self.createDatabase(at: env.databaseURL)
        try Self.insertMessage(
            databaseURL: env.databaseURL,
            createdMs: Self.ms("2026-03-06T11:00:00.000Z"),
            cost: 3.0)
        try Self.insertMessage(
            databaseURL: env.databaseURL,
            createdMs: Self.ms("2026-03-05T12:00:00.000Z"),
            cost: 6.0)
        try Self.insertMessage(
            databaseURL: env.databaseURL,
            createdMs: Self.ms("2026-02-25T07:53:16.000Z"),
            cost: 2.0)

        let reader = OpenCodeGoLocalUsageReader(authURL: env.authURL, databaseURL: env.databaseURL)
        let now = Date(timeIntervalSince1970: 1_772_798_400)
        let snapshot = try reader.fetch(now: now)

        XCTAssertEqual(snapshot.primary?.usedPercent, 25)
        XCTAssertEqual(snapshot.secondary?.usedPercent, 30)
        XCTAssertEqual(snapshot.tertiary?.usedPercent, 18.3)
        XCTAssertEqual(Int(snapshot.primary?.resetsAt?.timeIntervalSince(now) ?? -1), 14_400)
        XCTAssertEqual(Int(snapshot.secondary?.resetsAt?.timeIntervalSince(now) ?? -1), 216_000)
        XCTAssertEqual(Int(snapshot.tertiary?.resetsAt?.timeIntervalSince(now) ?? -1), 1_626_796)
    }

    func testLocalUsageReaderUsesStepFinishPartsWithoutDoubleCountingMessageCost() throws {
        let env = try Self.makeEnvironment()
        defer { try? FileManager.default.removeItem(at: env.root) }

        try Self.writeAuth(to: env.authURL)
        try Self.createDatabase(at: env.databaseURL)
        let firstMessage = try Self.insertMessage(
            databaseURL: env.databaseURL,
            createdMs: Self.ms("2026-03-06T11:00:00.000Z"),
            cost: nil)
        try Self.insertStepFinishPart(
            databaseURL: env.databaseURL,
            messageID: firstMessage,
            createdMs: Self.ms("2026-03-06T11:00:00.000Z"),
            cost: 3.0)
        let secondMessage = try Self.insertMessage(
            databaseURL: env.databaseURL,
            createdMs: Self.ms("2026-03-06T11:30:00.000Z"),
            cost: 3.0)
        try Self.insertStepFinishPart(
            databaseURL: env.databaseURL,
            messageID: secondMessage,
            createdMs: Self.ms("2026-03-06T11:30:00.000Z"),
            cost: 3.0)

        let reader = OpenCodeGoLocalUsageReader(authURL: env.authURL, databaseURL: env.databaseURL)
        let snapshot = try reader.fetch(now: Date(timeIntervalSince1970: 1_772_798_400))

        XCTAssertEqual(snapshot.primary?.usedPercent, 50)
        XCTAssertEqual(snapshot.secondary?.usedPercent, 20)
        XCTAssertEqual(snapshot.tertiary?.usedPercent, 10)
    }

    func testLocalUsageReaderReportsMissingHistoryAfterAuth() throws {
        let env = try Self.makeEnvironment()
        defer { try? FileManager.default.removeItem(at: env.root) }
        try Self.writeAuth(to: env.authURL)

        let reader = OpenCodeGoLocalUsageReader(authURL: env.authURL, databaseURL: env.databaseURL)

        XCTAssertThrowsError(try reader.fetch(now: Date(timeIntervalSince1970: 1_772_798_400))) { error in
            XCTAssertEqual(error as? OpenCodeGoLocalUsageError, .historyUnavailable("database not found"))
        }
    }

    private static func makeEnvironment() throws -> (root: URL, authURL: URL, databaseURL: URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenCodeGoUsageTests-\(UUID().uuidString)", isDirectory: true)
        let directory = root
            .appendingPathComponent(".local", isDirectory: true)
            .appendingPathComponent("share", isDirectory: true)
            .appendingPathComponent("opencode", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (
            root,
            directory.appendingPathComponent("auth.json", isDirectory: false),
            directory.appendingPathComponent("opencode.db", isDirectory: false))
    }

    private static func writeAuth(to url: URL) throws {
        try Data(#"{"opencode-go":{"type":"api-key","key":"go-key"}}"#.utf8).write(to: url)
    }

    private static func createDatabase(at url: URL) throws {
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }
        try exec(
            db: db,
            sql: """
                CREATE TABLE message (
                  id TEXT PRIMARY KEY,
                  session_id TEXT NOT NULL,
                  data TEXT NOT NULL,
                  time_created INTEGER,
                  time_updated INTEGER
                );
                CREATE TABLE part (
                  id TEXT PRIMARY KEY,
                  message_id TEXT NOT NULL,
                  session_id TEXT NOT NULL,
                  data TEXT NOT NULL,
                  time_created INTEGER,
                  time_updated INTEGER
                );
            """)
    }

    @discardableResult
    private static func insertMessage(databaseURL: URL, createdMs: Int64, cost: Double?) throws -> String {
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(databaseURL.path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }

        let messageID = UUID().uuidString
        var payload: [String: Any] = [
            "providerID": "opencode-go",
            "role": "assistant",
            "time": ["created": createdMs],
        ]
        if let cost {
            payload["cost"] = cost
        }
        let data = try JSONSerialization.data(withJSONObject: payload)
        let json = String(data: data, encoding: .utf8) ?? "{}"

        var stmt: OpaquePointer?
        XCTAssertEqual(
            sqlite3_prepare_v2(
                db,
                "INSERT INTO message (id, session_id, data, time_created, time_updated) VALUES (?, ?, ?, ?, ?)",
                -1,
                &stmt,
                nil),
            SQLITE_OK)
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, messageID, -1, sqliteTransient)
        sqlite3_bind_text(stmt, 2, "session-1", -1, sqliteTransient)
        sqlite3_bind_text(stmt, 3, json, -1, sqliteTransient)
        sqlite3_bind_int64(stmt, 4, createdMs)
        sqlite3_bind_int64(stmt, 5, createdMs)
        XCTAssertEqual(sqlite3_step(stmt), SQLITE_DONE)
        return messageID
    }

    private static func insertStepFinishPart(
        databaseURL: URL,
        messageID: String,
        createdMs: Int64,
        cost: Double
    ) throws {
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(databaseURL.path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }

        let payload: [String: Any] = [
            "type": "step-finish",
            "cost": cost,
            "tokens": ["input": 1, "output": 1, "total": 2],
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let json = String(data: data, encoding: .utf8) ?? "{}"

        var stmt: OpaquePointer?
        XCTAssertEqual(
            sqlite3_prepare_v2(
                db,
                "INSERT INTO part (id, message_id, session_id, data, time_created, time_updated) VALUES (?, ?, ?, ?, ?, ?)",
                -1,
                &stmt,
                nil),
            SQLITE_OK)
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, UUID().uuidString, -1, sqliteTransient)
        sqlite3_bind_text(stmt, 2, messageID, -1, sqliteTransient)
        sqlite3_bind_text(stmt, 3, "session-1", -1, sqliteTransient)
        sqlite3_bind_text(stmt, 4, json, -1, sqliteTransient)
        sqlite3_bind_int64(stmt, 5, createdMs)
        sqlite3_bind_int64(stmt, 6, createdMs)
        XCTAssertEqual(sqlite3_step(stmt), SQLITE_DONE)
    }

    private static func exec(db: OpaquePointer?, sql: String) throws {
        var message: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(db, sql, nil, nil, &message) == SQLITE_OK else {
            sqlite3_free(message)
            XCTFail("sqlite exec failed")
            return
        }
    }

    private static func ms(_ iso: String) -> Int64 {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return Int64((formatter.date(from: iso)?.timeIntervalSince1970 ?? 0) * 1000)
    }

    private static let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    #endif
}
