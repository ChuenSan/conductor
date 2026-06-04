import Foundation
import Testing
@testable import ConductorCore

@Test func diagnosticsBundleExporterWritesRedactedSummaryAndLogs() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("conductor-diagnostics-bundle-test-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

    let home = root.appendingPathComponent("home", isDirectory: true)
    let logURL = root.appendingPathComponent("diagnostics.log")
    try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    try "path=\(home.path)/project email=person@example.com other=/Users/realname/project\n"
        .write(to: logURL, atomically: true, encoding: .utf8)

    let summary = ConductorControlJSON.object([
        "path": .string(home.appendingPathComponent("workspace").path),
        "email": .string("person@example.com"),
        "state": .string("ok")
    ])

    let export = try ConductorDiagnosticsBundleExporter.export(
        summary: summary,
        logURLs: [logURL, root.appendingPathComponent("missing.log")],
        outputPath: root.appendingPathComponent("out").path,
        homeDirectory: home,
        now: Date(timeIntervalSince1970: 1_717_000_000)
    )

    let relativePaths = export.files.map(\.relativePath)
    #expect(FileManager.default.fileExists(atPath: export.directoryURL.path))
    #expect(relativePaths.contains("manifest.json"))
    #expect(relativePaths.contains("summary.redacted.json"))
    #expect(relativePaths.contains("logs/diagnostics.log"))
    #expect(export.missingFiles == ["missing.log"])

    let summaryText = try String(
        contentsOf: export.directoryURL.appendingPathComponent("summary.redacted.json"),
        encoding: .utf8
    )
    #expect(summaryText.contains("~/workspace"))
    #expect(!summaryText.contains(home.path))
    #expect(!summaryText.contains("person@example.com"))

    let logText = try String(
        contentsOf: export.directoryURL.appendingPathComponent("logs/diagnostics.log"),
        encoding: .utf8
    )
    #expect(logText.contains("~/project"))
    #expect(logText.contains("/Users/[user]/project"))
    #expect(!logText.contains("person@example.com"))
}
