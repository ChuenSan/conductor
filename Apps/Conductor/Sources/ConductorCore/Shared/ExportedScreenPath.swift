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
    ///
    /// Uses `resolvingSymlinksInPath` (not `standardizedFileURL`) so the macOS
    /// `/var` → `/private/var` symlink is reconciled: libghostty may report the
    /// canonical `/private/var/...` form while `FileManager.temporaryDirectory`
    /// returns the `/var/...` form, and without resolving them the guard would
    /// never match and the temp export would leak on every capture.
    public static func isUnderTemporaryDirectory(
        _ fileURL: URL,
        temporaryDirectory: URL = FileManager.default.temporaryDirectory
    ) -> Bool {
        let file = fileURL.resolvingSymlinksInPath().path
        let temp = temporaryDirectory.resolvingSymlinksInPath().path
        return file.hasPrefix(temp + "/")
    }
}
