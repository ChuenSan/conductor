import XCTest
@testable import ConductorGit

final class CommitGraphLayoutTests: XCTestCase {
    private func commit(_ sha: String, parents: [String]) -> GitCommit {
        var c = GitCommit()
        c.sha = sha
        c.parents = parents
        return c
    }

    func testLinearHistoryAllColumnZero() {
        let commits = [
            commit("c", parents: ["b"]),
            commit("b", parents: ["a"]),
            commit("a", parents: []),
        ]
        let layout = CommitGraphLayout.compute(commits)
        XCTAssertEqual(layout.columns, [0, 0, 0])
        XCTAssertEqual(layout.maxColumn, 0)
    }

    func testBranchAndMergeUsesMultipleLanes() {
        // m 合并 main(d) 与 br(b)；分叉产生第二条泳道。
        let commits = [
            commit("m", parents: ["d", "b"]),
            commit("d", parents: ["a"]),
            commit("b", parents: ["a"]),
            commit("a", parents: []),
        ]
        let layout = CommitGraphLayout.compute(commits)
        XCTAssertEqual(layout.columns.count, 4)
        XCTAssertGreaterThanOrEqual(layout.maxColumn, 1, "分叉应产生 >1 列")
        XCTAssertEqual(layout.columns[0], 0, "合并提交在主列")
    }

    func testEmpty() {
        let layout = CommitGraphLayout.compute([])
        XCTAssertEqual(layout.columns, [])
        XCTAssertEqual(layout.maxColumn, 0)
    }
}

final class DiffPatchTests: XCTestCase {
    func testParseRetainsFileHeaderAndHunkPatch() {
        let raw = """
        diff --git a/f.txt b/f.txt
        index 111..222 100644
        --- a/f.txt
        +++ b/f.txt
        @@ -1,2 +1,2 @@
        -old
        +new
         tail
        """
        let diff = TextDiff.parse(raw)
        XCTAssertTrue(diff.fileHeader.contains("diff --git a/f.txt b/f.txt"))
        XCTAssertTrue(diff.fileHeader.contains("--- a/f.txt"))
        XCTAssertEqual(diff.hunks.count, 1)
        let patch = diff.hunks[0].patchText
        XCTAssertTrue(patch.hasPrefix("@@ -1,2 +1,2 @@"))
        XCTAssertTrue(patch.contains("-old"))
        XCTAssertTrue(patch.contains("+new"))
        // 重建的完整补丁应可被 git apply 接受的形状：头 + hunk。
        let full = (diff.fileHeader + [patch]).joined(separator: "\n")
        XCTAssertTrue(full.contains("diff --git") && full.contains("@@"))
    }
}
