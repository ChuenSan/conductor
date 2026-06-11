import XCTest
@testable import ConductorApp

final class FolderTreeFlattenerTests: XCTestCase {
    private func dir(_ name: String, _ path: String) -> FileBrowserEntry {
        FileBrowserEntry(name: name, path: path, isDirectory: true,
                         isHidden: false, size: nil, modifiedAt: nil)
    }

    func testCollapsedRootYieldsSingleRow() {
        let rows = FolderTreeFlattener.rows(root: "/home", rootName: "~", expanded: [], children: [:])
        XCTAssertEqual(rows.map(\.path), ["/home"])
        XCTAssertFalse(rows[0].isExpanded)
        XCTAssertEqual(rows[0].depth, 0)
        XCTAssertEqual(rows[0].name, "~")
    }

    func testExpandedNodesFlattenDepthFirstWithDepths() {
        let children: [String: [FileBrowserEntry]] = [
            "/home": [dir("a", "/home/a"), dir("b", "/home/b")],
            "/home/a": [dir("x", "/home/a/x")],
        ]
        let rows = FolderTreeFlattener.rows(
            root: "/home", rootName: "~",
            expanded: ["/home", "/home/a"], children: children)
        XCTAssertEqual(rows.map(\.path), ["/home", "/home/a", "/home/a/x", "/home/b"])
        XCTAssertEqual(rows.map(\.depth), [0, 1, 2, 1])
        XCTAssertTrue(rows[1].isExpanded)
        XCTAssertFalse(rows[3].isExpanded)
    }

    func testCollapsedSubtreeHidesDescendants() {
        let children: [String: [FileBrowserEntry]] = [
            "/home": [dir("a", "/home/a")],
            "/home/a": [dir("x", "/home/a/x")],
        ]
        // a 未展开 → 其缓存的子目录不出现在行里
        let rows = FolderTreeFlattener.rows(
            root: "/home", rootName: "~", expanded: ["/home"], children: children)
        XCTAssertEqual(rows.map(\.path), ["/home", "/home/a"])
    }

    func testExpandedWithoutLoadedChildrenYieldsNoChildRows() {
        let rows = FolderTreeFlattener.rows(
            root: "/home", rootName: "~", expanded: ["/home"], children: [:])
        XCTAssertEqual(rows.map(\.path), ["/home"])
        XCTAssertTrue(rows[0].isExpanded)
    }
}
