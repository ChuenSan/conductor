import Foundation

/// Pure helpers for handling the temp-file path that libghostty's
/// `write_screen_file:copy,…` action places on the pasteboard.
public enum ExportedScreenPath {
    /// Normalizes a pasteboard string to a filesystem path: accepts a `file://`
    /// URL or an absolute path, rejects anything else.
    public static func normalized(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let url = URL(string: trimmed), url.isFileURL, !url.path.isEmpty {
            return url.path
        }
        return trimmed.hasPrefix("/") ? trimmed : nil
    }

    /// True only when `fileURL` lives under the system temporary directory, so the
    /// caller can safely delete the export without ever touching a user file.
    public static func isUnderTemporaryDirectory(
        _ fileURL: URL,
        temporaryDirectory: URL = FileManager.default.temporaryDirectory
    ) -> Bool {
        let file = fileURL.standardizedFileURL
        let temp = temporaryDirectory.standardizedFileURL
        return file.path.hasPrefix(temp.path + "/")
    }
}
