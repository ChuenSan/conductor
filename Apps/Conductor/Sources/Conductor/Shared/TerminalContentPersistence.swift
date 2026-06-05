import ConductorCore
import Foundation
import Yams

final class TerminalContentPersistence {
    static let fileName = "terminal-content-snapshots.yaml"

    private let fileManager: FileManager
    private let fileURL: URL
    private let isEnabled: Bool

    init(fileManager: FileManager = .default, isEnabled: Bool = WorkspacePersistence.isEnabledByDefault) {
        self.fileManager = fileManager
        self.isEnabled = isEnabled
        self.fileURL = Self.defaultFileURL(fileManager: fileManager)
    }

    func load(validTerminalIDs: Set<TerminalID>) -> PersistedTerminalContentSnapshotFile? {
        guard isEnabled else { return nil }
        if ProcessInfo.processInfo.environment["CONDUCTOR_RESET_STATE"] == "1" {
            reset()
            return nil
        }
        guard fileManager.fileExists(atPath: fileURL.path),
              let data = fileManager.contents(atPath: fileURL.path),
              let text = String(data: data, encoding: .utf8),
              let decoded = try? YAMLDecoder().decode(PersistedTerminalContentSnapshotFile.self, from: text) else {
            return nil
        }
        let filtered = decoded.filtered(validTerminalIDs: validTerminalIDs)
        return filtered.snapshots.isEmpty ? nil : filtered
    }

    func save(_ snapshotFile: PersistedTerminalContentSnapshotFile) {
        guard isEnabled else { return }
        let encoder = YAMLEncoder()
        encoder.options.allowUnicode = true
        guard let text = try? encoder.encode(snapshotFile),
              let data = text.data(using: .utf8) else {
            return
        }
        try? fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: [.atomic])
    }

    func reset() {
        try? fileManager.removeItem(at: fileURL)
    }

    static func defaultFileURL(fileManager: FileManager = .default) -> URL {
        if let overridePath = ProcessInfo.processInfo.environment["CONDUCTOR_STATE_PATH"],
           !overridePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return URL(fileURLWithPath: overridePath)
                .deletingLastPathComponent()
                .appendingPathComponent(fileName)
        }
        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return baseURL
            .appendingPathComponent("Conductor", isDirectory: true)
            .appendingPathComponent(fileName)
    }
}
