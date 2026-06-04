import Foundation

public struct ConductorDiagnosticsBundleFile: Equatable, Sendable {
    public var relativePath: String
    public var byteCount: Int

    public init(relativePath: String, byteCount: Int) {
        self.relativePath = relativePath
        self.byteCount = byteCount
    }
}

public struct ConductorDiagnosticsBundleExport: Equatable, Sendable {
    public var directoryURL: URL
    public var createdAt: Date
    public var files: [ConductorDiagnosticsBundleFile]
    public var missingFiles: [String]

    public init(
        directoryURL: URL,
        createdAt: Date,
        files: [ConductorDiagnosticsBundleFile],
        missingFiles: [String]
    ) {
        self.directoryURL = directoryURL
        self.createdAt = createdAt
        self.files = files
        self.missingFiles = missingFiles
    }
}

public enum ConductorDiagnosticsBundleExportError: LocalizedError, Equatable {
    case outputPathIsFile(String)
    case cannotEncodeSummary
    case cannotWriteBundle(String)

    public var errorDescription: String? {
        switch self {
        case .outputPathIsFile(let path):
            "Diagnostics export path is a file, not a directory: \(path)"
        case .cannotEncodeSummary:
            "Could not encode diagnostics summary."
        case .cannotWriteBundle(let message):
            "Could not write diagnostics bundle: \(message)"
        }
    }
}

public enum ConductorDiagnosticsBundleExporter {
    public static func export(
        summary: ConductorControlJSON,
        logURLs: [URL],
        outputPath: String?,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        now: Date = Date(),
        fileManager: FileManager = .default
    ) throws -> ConductorDiagnosticsBundleExport {
        do {
            let directoryURL = try resolveBundleDirectory(
                outputPath: outputPath,
                homeDirectory: homeDirectory,
                now: now,
                fileManager: fileManager
            )
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

            var missingFiles: [String] = []
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]

            let summaryData = try encoder.encode(summary)
            guard let summaryText = String(data: summaryData, encoding: .utf8) else {
                throw ConductorDiagnosticsBundleExportError.cannotEncodeSummary
            }
            try writeText(
                redacted(summaryText, homeDirectory: homeDirectory),
                to: directoryURL.appendingPathComponent("summary.redacted.json")
            )

            let logDirectoryURL = directoryURL.appendingPathComponent("logs", isDirectory: true)
            try fileManager.createDirectory(at: logDirectoryURL, withIntermediateDirectories: true)
            for logURL in logURLs {
                guard fileManager.fileExists(atPath: logURL.path) else {
                    missingFiles.append(logURL.lastPathComponent)
                    continue
                }
                let text = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
                try writeText(
                    redacted(text, homeDirectory: homeDirectory),
                    to: logDirectoryURL.appendingPathComponent(logURL.lastPathComponent)
                )
            }

            try writeText(readmeText(createdAt: now), to: directoryURL.appendingPathComponent("README.txt"))

            var files = try listedFiles(in: directoryURL, fileManager: fileManager)
            let manifest = ConductorControlJSON.object([
                "formatVersion": .int(1),
                "createdAt": .string(iso8601String(now)),
                "privacy": .object([
                    "redacted": .bool(true),
                    "rules": .array([
                        .string("home-directory"),
                        .string("users-path"),
                        .string("email-like-values")
                    ])
                ]),
                "missingFiles": .array(missingFiles.map { .string($0) }),
                "files": .array(files.map { file in
                    .object([
                        "path": .string(file.relativePath),
                        "bytes": .int(file.byteCount)
                    ])
                })
            ])
            try writeJSON(manifest, to: directoryURL.appendingPathComponent("manifest.json"), encoder: encoder)
            files = try listedFiles(in: directoryURL, fileManager: fileManager)

            return ConductorDiagnosticsBundleExport(
                directoryURL: directoryURL,
                createdAt: now,
                files: files,
                missingFiles: missingFiles
            )
        } catch let error as ConductorDiagnosticsBundleExportError {
            throw error
        } catch {
            throw ConductorDiagnosticsBundleExportError.cannotWriteBundle(error.localizedDescription)
        }
    }

    private static func resolveBundleDirectory(
        outputPath: String?,
        homeDirectory: URL,
        now: Date,
        fileManager: FileManager
    ) throws -> URL {
        let name = "conductor-diagnostics-\(filenameTimestamp(now))"
        guard let outputPath, !outputPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return uniqueDirectoryURL(
                homeDirectory
                    .appendingPathComponent("Library", isDirectory: true)
                    .appendingPathComponent("Application Support", isDirectory: true)
                    .appendingPathComponent("Conductor", isDirectory: true)
                    .appendingPathComponent("Diagnostics", isDirectory: true)
                    .appendingPathComponent(name, isDirectory: true),
                fileManager: fileManager
            )
        }

        let expandedPath = NSString(string: outputPath).expandingTildeInPath
        let url = URL(fileURLWithPath: expandedPath)
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else {
                throw ConductorDiagnosticsBundleExportError.outputPathIsFile(url.path)
            }
            return uniqueDirectoryURL(url.appendingPathComponent(name, isDirectory: true), fileManager: fileManager)
        }
        return uniqueDirectoryURL(url, fileManager: fileManager)
    }

    private static func uniqueDirectoryURL(_ url: URL, fileManager: FileManager) -> URL {
        guard fileManager.fileExists(atPath: url.path) else { return url }
        let base = url.deletingLastPathComponent()
        let stem = url.lastPathComponent
        for index in 2..<1000 {
            let candidate = base.appendingPathComponent("\(stem)-\(index)", isDirectory: true)
            if !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return base.appendingPathComponent("\(stem)-\(UUID().uuidString)", isDirectory: true)
    }

    private static func writeJSON(
        _ value: ConductorControlJSON,
        to url: URL,
        encoder: JSONEncoder
    ) throws {
        let data = try encoder.encode(value)
        try data.write(to: url, options: .atomic)
    }

    private static func writeText(_ text: String, to url: URL) throws {
        try Data(text.utf8).write(to: url, options: .atomic)
    }

    private static func listedFiles(
        in directoryURL: URL,
        fileManager: FileManager
    ) throws -> [ConductorDiagnosticsBundleFile] {
        guard let enumerator = fileManager.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var files: [ConductorDiagnosticsBundleFile] = []
        for case let fileURL as URL in enumerator {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: fileURL.path, isDirectory: &isDirectory),
                  !isDirectory.boolValue else {
                continue
            }
            let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
            let byteCount = (attributes[.size] as? NSNumber)?.intValue ?? 0
            let relativePath = relativePath(from: directoryURL, to: fileURL)
            files.append(ConductorDiagnosticsBundleFile(
                relativePath: relativePath,
                byteCount: byteCount
            ))
        }
        return files.sorted { $0.relativePath < $1.relativePath }
    }

    private static func relativePath(from directoryURL: URL, to fileURL: URL) -> String {
        let baseComponents = directoryURL.standardizedFileURL.pathComponents
        let fileComponents = fileURL.standardizedFileURL.pathComponents
        guard fileComponents.count > baseComponents.count else {
            return fileURL.lastPathComponent
        }
        return fileComponents.dropFirst(baseComponents.count).joined(separator: "/")
    }

    private static func readmeText(createdAt: Date) -> String {
        """
        Conductor Diagnostics Bundle
        Created: \(iso8601String(createdAt))

        Contents:
        - summary.redacted.json: app, session, notification, update, and control summaries.
        - logs/: redacted Conductor diagnostic logs when available.
        - manifest.json: bundle file list and redaction metadata.

        Review this directory before sharing it. Home paths, /Users/<name> paths,
        and email-like values are redacted, but project names or command text can
        still appear in diagnostic events.
        """
    }

    private static func redacted(_ text: String, homeDirectory: URL) -> String {
        var value = text.replacingOccurrences(of: homeDirectory.path, with: "~")
        value = replacingMatches(#"/Users/[^/"\s]+"#, in: value, with: "/Users/[user]")
        value = replacingMatches(#"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#, in: value, with: "[email]")
        return value
    }

    private static func replacingMatches(_ pattern: String, in text: String, with replacement: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return text
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: replacement)
    }

    private static func iso8601String(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private static func filenameTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }
}
