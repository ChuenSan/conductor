import Foundation

enum ConductorDiagnostics {
    static let logURL: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("Conductor", isDirectory: true)
            .appendingPathComponent("diagnostics.log")
    }()

    static var logURLs: [URL] {
        [
            logURL,
            logURL.deletingPathExtension().appendingPathExtension("previous.log")
        ]
    }

    private static let maxLogBytes: UInt64 = 2_000_000
    private static let queue = DispatchQueue(label: "app.conductor.diagnostics")

    static func record(_ event: String, fields: [String: CustomStringConvertible] = [:]) {
        let line = formatLine(event: event, fields: fields)
        queue.async {
            appendLineOnQueue(line)
        }
        ConductorLog.diagnostics.debug("\(event, privacy: .public)")
    }

    static func recordSync(_ event: String, fields: [String: CustomStringConvertible] = [:]) {
        let line = formatLine(event: event, fields: fields)
        queue.sync {
            appendLineOnQueue(line)
        }
        ConductorLog.diagnostics.debug("\(event, privacy: .public)")
    }

    private static func formatLine(
        event: String,
        fields: [String: CustomStringConvertible]
    ) -> String {
        let timestamp = String(format: "%.3f", Date().timeIntervalSince1970)
        var parts = ["ts=\(timestamp)", "event=\(sanitize(event))"]
        for key in fields.keys.sorted() {
            guard let value = fields[key] else { continue }
            parts.append("\(sanitize(key))=\(sanitize(value.description))")
        }
        return parts.joined(separator: " ") + "\n"
    }

    private static func sanitize(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._:-"))
        let scalars = value.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "_"
        }
        return String(scalars).prefix(160).description
    }

    private static func appendLineOnQueue(_ line: String) {
        let directory = logURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            rotateIfNeeded()
            if !FileManager.default.fileExists(atPath: logURL.path) {
                FileManager.default.createFile(atPath: logURL.path, contents: nil)
            }
            let handle = try FileHandle(forWritingTo: logURL)
            defer {
                try? handle.close()
            }
            try handle.seekToEnd()
            if let data = line.data(using: .utf8) {
                handle.write(data)
            }
        } catch {
            ConductorLog.diagnostics.error("Diagnostic log write failed: \(error.localizedDescription)")
        }
    }

    private static func rotateIfNeeded() {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: logURL.path),
              let size = attributes[.size] as? UInt64,
              size > maxLogBytes else {
            return
        }
        let rotatedURL = logURL.deletingPathExtension().appendingPathExtension("previous.log")
        try? FileManager.default.removeItem(at: rotatedURL)
        try? FileManager.default.moveItem(at: logURL, to: rotatedURL)
    }
}
