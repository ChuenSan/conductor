import XCTest
@testable import CmuxCore

final class SkillCatalogTests: XCTestCase {
    private func makeTempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cmux-skills-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testScanParsesFrontmatterAndDisabledState() throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }

        let skillA = root.appendingPathComponent("electron")
        try FileManager.default.createDirectory(at: skillA, withIntermediateDirectories: true)
        try """
        ---
        name: electron
        description: Build cross-platform desktop apps.
        metadata:
          author: hairy
          version: "2026.1.30"
        ---
        body here
        """.write(to: skillA.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        // 被禁用的 skill（SKILL.md.disabled）
        let skillB = root.appendingPathComponent("playwright")
        try FileManager.default.createDirectory(at: skillB, withIntermediateDirectories: true)
        try """
        ---
        name: playwright
        description: Browser automation.
        ---
        """.write(to: skillB.appendingPathComponent("SKILL.md.disabled"), atomically: true, encoding: .utf8)

        let catalog = SkillCatalog(roots: [.init(url: root, source: .codex)])
        let entries = catalog.scan()
        XCTAssertEqual(entries.count, 2)

        let electron = entries.first { $0.name == "electron" }
        XCTAssertNotNil(electron)
        XCTAssertEqual(electron?.description, "Build cross-platform desktop apps.")
        XCTAssertEqual(electron?.version, "2026.1.30")
        XCTAssertEqual(electron?.author, "hairy")
        XCTAssertEqual(electron?.enabled, true)
        XCTAssertEqual(electron?.source, .codex)

        let playwright = entries.first { $0.name == "playwright" }
        XCTAssertEqual(playwright?.enabled, false)
    }

    func testEnableDisableRenamesFile() throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let dir = root.appendingPathComponent("foo")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let md = dir.appendingPathComponent("SKILL.md")
        try "---\nname: foo\ndescription: d\n---\n".write(to: md, atomically: true, encoding: .utf8)

        let catalog = SkillCatalog(roots: [.init(url: root, source: .other)])
        let entry = catalog.scan().first!
        XCTAssertTrue(entry.enabled)

        let disabledPath = try SkillCatalog.setEnabled(entry, false)
        XCTAssertTrue(disabledPath.hasSuffix("SKILL.md.disabled"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: md.path))

        // 重新扫描应为禁用
        let reEntry = catalog.scan().first!
        XCTAssertFalse(reEntry.enabled)

        let enabledPath = try SkillCatalog.setEnabled(reEntry, true)
        XCTAssertTrue(enabledPath.hasSuffix("SKILL.md"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: md.path))
    }
}
