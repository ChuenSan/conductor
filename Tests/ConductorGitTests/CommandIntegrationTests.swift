import XCTest
@testable import ConductorGit

/// 命令层对真实临时仓库的集成测试。需要环境中存在 git。
final class CommandIntegrationTests: XCTestCase {
    private func makeRepo() throws -> (TempGitRepo, GitRepository) {
        let tmp = try TempGitRepo()
        let repo = GitRepository(path: tmp.path)
        return (tmp, repo)
    }

    func testStageCommitRoundTrip() async throws {
        let (tmp, repo) = try makeRepo()
        try tmp.write("a.txt", "alpha\n")

        try await Stage.paths(repo, ["a.txt"])
        var changes = try await QueryLocalChanges.run(repo)
        XCTAssertTrue(changes.contains { $0.path == "a.txt" && $0.isStaged })

        try await Commit.run(repo, message: "init")
        let commits = try await QueryCommits.run(repo)
        XCTAssertEqual(commits.count, 1)
        XCTAssertEqual(commits[0].subject, "init")

        changes = try await QueryLocalChanges.run(repo)
        XCTAssertTrue(changes.isEmpty)
    }

    func testUnstagePostCommit() async throws {
        let (tmp, repo) = try makeRepo()
        try tmp.write("a.txt", "alpha\n")
        try tmp.commitAll("init")

        try tmp.write("a.txt", "changed\n")
        try await Stage.paths(repo, ["a.txt"])
        try await Unstage.paths(repo, ["a.txt"])

        let changes = try await QueryLocalChanges.run(repo)
        let a = changes.first { $0.path == "a.txt" }
        XCTAssertEqual(a?.workTree, .modified)
        XCTAssertFalse(a?.isStaged ?? true)
    }

    func testDiscardRevertsTrackedAndRemovesUntracked() async throws {
        let (tmp, repo) = try makeRepo()
        try tmp.write("tracked.txt", "v1\n")
        try tmp.commitAll("init")

        try tmp.write("tracked.txt", "v2\n")
        try tmp.write("untracked.txt", "junk\n")

        let changes = try await QueryLocalChanges.run(repo)
        try await Discard.changes(repo, changes)

        let after = try await QueryLocalChanges.run(repo)
        XCTAssertTrue(after.isEmpty)
        let tracked = try String(contentsOf: tmp.url.appendingPathComponent("tracked.txt"), encoding: .utf8)
        XCTAssertEqual(tracked, "v1\n")
        XCTAssertFalse(FileManager.default.fileExists(atPath: tmp.url.appendingPathComponent("untracked.txt").path))
    }

    func testBranchCreateAndCheckout() async throws {
        let (tmp, repo) = try makeRepo()
        try tmp.write("a.txt", "alpha\n")
        try tmp.commitAll("init")

        try await Branch.create(repo, name: "feature")
        try await Checkout.branch(repo, "feature")

        let head = try await QueryHead.run(repo)
        XCTAssertEqual(head.branch, "feature")

        let branches = try await QueryBranches.run(repo)
        XCTAssertTrue(branches.contains { $0.name == "feature" })
        XCTAssertTrue(branches.contains { $0.name == "main" })
    }

    func testStashPushPop() async throws {
        let (tmp, repo) = try makeRepo()
        try tmp.write("a.txt", "alpha\n")
        try tmp.commitAll("init")

        try tmp.write("a.txt", "stash me\n")
        try await Stash.push(repo, message: "wip")
        XCTAssertTrue(try await QueryLocalChanges.run(repo).isEmpty)
        XCTAssertEqual(try await QueryStashes.run(repo).count, 1)

        try await Stash.pop(repo)
        XCTAssertTrue(try await QueryLocalChanges.run(repo).contains { $0.path == "a.txt" })
    }

    func testWorktreeDiff() async throws {
        let (tmp, repo) = try makeRepo()
        try tmp.write("a.txt", "line1\nline2\n")
        try tmp.commitAll("init")
        try tmp.write("a.txt", "line1\nline2 changed\nline3\n")

        let diff = try await Diff.file(repo, path: "a.txt", source: .workTree)
        XCTAssertFalse(diff.isEmpty)
        XCTAssertGreaterThanOrEqual(diff.addedCount, 1)
        XCTAssertEqual(diff.hunks.count, 1)
    }
}
