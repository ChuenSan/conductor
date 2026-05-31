import Foundation
import Testing
@testable import ConductorCore

@Test func normalizesFileURLToPath() {
    #expect(ExportedScreenPath.normalized("file:///tmp/screen.vt") == "/tmp/screen.vt")
}

@Test func passesThroughAbsolutePath() {
    #expect(ExportedScreenPath.normalized("/var/folders/x/screen.vt") == "/var/folders/x/screen.vt")
}

@Test func trimsWhitespace() {
    #expect(ExportedScreenPath.normalized("  /tmp/a.vt \n") == "/tmp/a.vt")
}

@Test func rejectsNonAbsoluteOrEmpty() {
    #expect(ExportedScreenPath.normalized("not-a-path") == nil)
    #expect(ExportedScreenPath.normalized("   ") == nil)
    #expect(ExportedScreenPath.normalized(nil) == nil)
}

@Test func temporaryDirectoryGuard() {
    let temp = URL(fileURLWithPath: "/var/folders/tmp", isDirectory: true)
    #expect(ExportedScreenPath.isUnderTemporaryDirectory(
        URL(fileURLWithPath: "/var/folders/tmp/screen.vt"), temporaryDirectory: temp))
    #expect(!ExportedScreenPath.isUnderTemporaryDirectory(
        URL(fileURLWithPath: "/Users/me/screen.vt"), temporaryDirectory: temp))
}

@Test func temporaryDirectoryGuardReconcilesVarSymlink() throws {
    // Use a real file under the real temp dir so symlinks actually resolve
    // (resolvingSymlinksInPath only resolves components that exist on disk).
    let temp = FileManager.default.temporaryDirectory
    let file = temp.appendingPathComponent("conductor-export-guard-test.vt")
    try Data("x".utf8).write(to: file)
    defer { try? FileManager.default.removeItem(at: file) }

    // The file under the real temp dir is recognized.
    #expect(ExportedScreenPath.isUnderTemporaryDirectory(file, temporaryDirectory: temp))

    // ghostty may report the canonical (symlink-resolved) /private/var form while
    // FileManager's temporaryDirectory is the /var symlink form. The canonical file
    // must still be recognized — the case the old standardizedFileURL impl missed.
    let canonical = file.resolvingSymlinksInPath()
    #expect(ExportedScreenPath.isUnderTemporaryDirectory(canonical, temporaryDirectory: temp))

    // A non-temp user path is never matched.
    #expect(!ExportedScreenPath.isUnderTemporaryDirectory(
        URL(fileURLWithPath: "/Users/someone/notes.vt"), temporaryDirectory: temp))
}
