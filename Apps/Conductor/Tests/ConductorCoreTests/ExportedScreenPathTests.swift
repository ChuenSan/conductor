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
