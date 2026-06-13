import XCTest
@testable import ConductorGit

final class ParsingTests: XCTestCase {
    // MARK: - status / 变更

    func testStatusSplitCodeAndPath() {
        XCTAssertEqual(QueryLocalChanges.splitCodeAndPath(" M src/a.swift")?.code, " M")
        XCTAssertEqual(QueryLocalChanges.splitCodeAndPath(" M src/a.swift")?.path, "src/a.swift")
        // "M " 暂存修改：尾随空格去掉 → "M"
        XCTAssertEqual(QueryLocalChanges.splitCodeAndPath("M  src/a.swift")?.code, "M")
        XCTAssertEqual(QueryLocalChanges.splitCodeAndPath("MM src/a.swift")?.code, "MM")
        XCTAssertEqual(QueryLocalChanges.splitCodeAndPath("?? new.txt")?.code, "??")
    }

    func testStatusParseMixed() {
        let out = """
        M  staged.swift
         M dirty.swift
        MM both.swift
        ?? untracked.txt
        D  removed.swift
        """
        let changes = QueryLocalChanges.parse(out)
        XCTAssertEqual(changes.count, 5)

        let staged = changes.first { $0.path == "staged.swift" }
        XCTAssertEqual(staged?.index, .modified)
        XCTAssertEqual(staged?.workTree, .none)
        XCTAssertTrue(staged?.isStaged ?? false)

        let dirty = changes.first { $0.path == "dirty.swift" }
        XCTAssertEqual(dirty?.index, .none)
        XCTAssertEqual(dirty?.workTree, .modified)

        let both = changes.first { $0.path == "both.swift" }
        XCTAssertEqual(both?.index, .modified)
        XCTAssertEqual(both?.workTree, .modified)

        let untracked = changes.first { $0.path == "untracked.txt" }
        XCTAssertEqual(untracked?.workTree, .untracked)
    }

    func testStatusParseRename() {
        let changes = QueryLocalChanges.parse("R  old/name.swift -> new/name.swift")
        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(changes[0].index, .renamed)
        XCTAssertEqual(changes[0].originalPath, "old/name.swift")
        XCTAssertEqual(changes[0].path, "new/name.swift")
    }

    func testStatusParseConflict() {
        let changes = QueryLocalChanges.parse("UU conflicted.swift")
        XCTAssertEqual(changes[0].workTree, .conflicted)
        XCTAssertEqual(changes[0].conflictReason, .bothModified)
        XCTAssertTrue(changes[0].isConflicted)
    }

    // MARK: - 提交历史

    func testUserParse() {
        let u = GitUser.parse("Jane Doe±jane@example.com")
        XCTAssertEqual(u.name, "Jane Doe")
        XCTAssertEqual(u.email, "jane@example.com")
        XCTAssertEqual(GitUser.parse("NoEmail").name, "NoEmail")
    }

    func testCommitParse() {
        let line = [
            "abc123", "p1 p2", "HEAD -> refs/heads/main, tag: refs/tags/v1",
            "Jane±jane@x.com", "1700000000", "Bob±bob@x.com", "1700000100", "Fix the thing",
        ].joined(separator: "\u{0}")
        let commits = QueryCommits.parse(line)
        XCTAssertEqual(commits.count, 1)
        let c = commits[0]
        XCTAssertEqual(c.sha, "abc123")
        XCTAssertEqual(c.parents, ["p1", "p2"])
        XCTAssertEqual(c.author.name, "Jane")
        XCTAssertEqual(c.committerTime, 1_700_000_100)
        XCTAssertEqual(c.subject, "Fix the thing")
        XCTAssertTrue(c.isMerged)
        XCTAssertTrue(c.isCurrentHead)
        XCTAssertTrue(c.decorators.contains { $0.kind == .currentBranchHead && $0.name == "main" })
        XCTAssertTrue(c.decorators.contains { $0.kind == .tag && $0.name == "v1" })
    }

    func testCommitParseSkipsMalformed() {
        XCTAssertEqual(QueryCommits.parse("not enough fields").count, 0)
    }

    // MARK: - 分支

    func testBranchParseLocalCurrent() {
        let line = ["refs/heads/main", "1700000000", "deadbeef", "*", "refs/remotes/origin/main", "=", ""]
            .joined(separator: "\u{0}")
        let b = QueryBranches.parseLine(line)
        XCTAssertEqual(b?.name, "main")
        XCTAssertTrue(b?.isLocal ?? false)
        XCTAssertTrue(b?.isCurrent ?? false)
        XCTAssertEqual(b?.upstream, "refs/remotes/origin/main")
    }

    func testBranchParseRemote() {
        let line = ["refs/remotes/origin/feature", "1700000000", "cafe", "", "", "", ""]
            .joined(separator: "\u{0}")
        let b = QueryBranches.parseLine(line)
        XCTAssertEqual(b?.remote, "origin")
        XCTAssertEqual(b?.name, "feature")
        XCTAssertFalse(b?.isLocal ?? true)
        XCTAssertEqual(b?.friendlyName, "origin/feature")
    }

    func testBranchSkipsHEADPointer() {
        let line = ["refs/remotes/origin/HEAD", "0", "x", "", "", "", ""].joined(separator: "\u{0}")
        XCTAssertNil(QueryBranches.parseLine(line))
    }

    // MARK: - 远程 / stash / 追踪

    func testRemotesParseDedup() {
        let out = """
        origin\thttps://github.com/x/y.git (fetch)
        origin\thttps://github.com/x/y.git (push)
        upstream\thttps://github.com/a/b.git (fetch)
        upstream\thttps://github.com/a/b.git (push)
        """
        let remotes = QueryRemotes.parse(out)
        XCTAssertEqual(remotes.map(\.name), ["origin", "upstream"])
        XCTAssertEqual(remotes[0].url, "https://github.com/x/y.git")
    }

    func testStashParse() {
        let out = "stash@{0}\u{0}abc\u{0}1700000000\u{0}WIP on main: fix"
        let stashes = QueryStashes.parse(out)
        XCTAssertEqual(stashes.count, 1)
        XCTAssertEqual(stashes[0].name, "stash@{0}")
        XCTAssertEqual(stashes[0].message, "WIP on main: fix")
    }

    func testParseLeftRight() {
        XCTAssertEqual(QueryHead.parseLeftRight("2\t3").left, 2)
        XCTAssertEqual(QueryHead.parseLeftRight("2\t3").right, 3)
        XCTAssertEqual(QueryHead.parseLeftRight("garbage").left, 0)
    }

    // MARK: - diff

    func testDiffParseBasic() {
        let raw = """
        diff --git a/file.txt b/file.txt
        index 111..222 100644
        --- a/file.txt
        +++ b/file.txt
        @@ -1,3 +1,4 @@
         context line
        -removed line
        +added line one
        +added line two
         trailing context
        """
        let diff = TextDiff.parse(raw)
        XCTAssertFalse(diff.isBinary)
        XCTAssertEqual(diff.oldPath, "file.txt")
        XCTAssertEqual(diff.newPath, "file.txt")
        XCTAssertEqual(diff.hunks.count, 1)
        XCTAssertEqual(diff.addedCount, 2)
        XCTAssertEqual(diff.deletedCount, 1)

        let lines = diff.hunks[0].lines
        XCTAssertEqual(lines[0].kind, .context)
        XCTAssertEqual(lines[0].oldLine, 1)
        XCTAssertEqual(lines[0].newLine, 1)
        XCTAssertEqual(lines[1].kind, .deleted)
        XCTAssertEqual(lines[1].oldLine, 2)
        XCTAssertNil(lines[1].newLine)
        XCTAssertEqual(lines[2].kind, .added)
        XCTAssertEqual(lines[2].newLine, 2)
    }

    func testDiffParseBinary() {
        let raw = """
        diff --git a/img.png b/img.png
        Binary files a/img.png and b/img.png differ
        """
        XCTAssertTrue(TextDiff.parse(raw).isBinary)
    }

    func testHunkHeaderParse() {
        XCTAssertEqual(TextDiff.parseHunkHeader("@@ -12,7 +15,9 @@ func foo()").oldStart, 12)
        XCTAssertEqual(TextDiff.parseHunkHeader("@@ -12,7 +15,9 @@ func foo()").newStart, 15)
        XCTAssertEqual(TextDiff.parseHunkHeader("@@ -1 +1 @@").oldStart, 1)
    }

    func testStripDiffPath() {
        XCTAssertEqual(TextDiff.stripDiffPath("a/src/x.swift"), "src/x.swift")
        XCTAssertEqual(TextDiff.stripDiffPath("/dev/null"), "")
    }
}
