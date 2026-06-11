import XCTest
@testable import ConductorApp

final class FileBrowserListerTests: XCTestCase {
    private func entry(_ name: String, dir: Bool = false, hidden: Bool = false) -> FileBrowserEntry {
        FileBrowserEntry(name: name, path: "/t/\(name)", isDirectory: dir,
                         isHidden: hidden, size: dir ? nil : 1, modifiedAt: nil)
    }

    func testSortedPutsDirectoriesFirstThenByName() {
        let sorted = FileBrowserLister.sorted([
            entry("b.txt"), entry("zeta", dir: true), entry("a.txt"), entry("alpha", dir: true),
        ])
        XCTAssertEqual(sorted.map(\.name), ["alpha", "zeta", "a.txt", "b.txt"])
    }

    func testSortedIsNumericAware() {
        let sorted = FileBrowserLister.sorted([entry("file10"), entry("file2"), entry("File1")])
        XCTAssertEqual(sorted.map(\.name), ["File1", "file2", "file10"])
    }

    func testListFiltersHiddenAndSorts() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("fb-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("sub"), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: root.appendingPathComponent("a.txt"))
        try Data().write(to: root.appendingPathComponent(".hidden"))

        let visible = FileBrowserLister.list(directory: root.path, showHidden: false)
        XCTAssertEqual(visible.map(\.name), ["sub", "a.txt"])
        XCTAssertTrue(visible[0].isDirectory)
        XCTAssertEqual(visible[1].size, 1)

        let all = FileBrowserLister.list(directory: root.path, showHidden: true)
        XCTAssertEqual(all.map(\.name), ["sub", ".hidden", "a.txt"])
    }

    func testListNonexistentDirectoryReturnsEmpty() {
        XCTAssertEqual(FileBrowserLister.list(directory: "/nonexistent-\(UUID())", showHidden: true), [])
    }

    func testBreadcrumbSplitsAbsolutePath() {
        let crumbs = FileBrowserLister.breadcrumb(for: "/Users/dev/proj")
        XCTAssertEqual(crumbs.map(\.name), ["/", "Users", "dev", "proj"])
        XCTAssertEqual(crumbs.map(\.path), ["/", "/Users", "/Users/dev", "/Users/dev/proj"])
    }

    func testBreadcrumbRootOnly() {
        let crumbs = FileBrowserLister.breadcrumb(for: "/")
        XCTAssertEqual(crumbs.map(\.path), ["/"])
    }
}
