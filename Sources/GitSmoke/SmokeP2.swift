import ConductorGit
import Foundation

enum SmokeP2 {
    static func run(
        check: (Bool, String) -> Void,
        makeRepo: () -> URL,
        write: (URL, String, String) -> Void,
        sh: ([String], URL) -> String) async
    {
        print("\n== P2: write commands ==")
        let dir = makeRepo()
        defer { try? FileManager.default.removeItem(at: dir) }
        guard let repo = await GitRepository.discover(at: dir.path) else {
            check(false, "discover repo for P2")
            return
        }

        // 1) 暂存（初始提交前）。
        write(dir, "a.txt", "alpha\n")
        try? await Stage.paths(repo, ["a.txt"])
        var changes = (try? await QueryLocalChanges.run(repo)) ?? []
        check(changes.contains { $0.path == "a.txt" && $0.isStaged }, "stage: file staged")

        // 2) 取消暂存（初始提交前 → 回到未跟踪）。
        try? await Unstage.paths(repo, ["a.txt"])
        changes = (try? await QueryLocalChanges.run(repo)) ?? []
        check(changes.contains { $0.path == "a.txt" && $0.workTree == .untracked }, "unstage: back to untracked (pre-commit)")

        // 3) 提交。
        try? await Stage.paths(repo, ["a.txt"])
        try? await Commit.run(repo, message: "first commit\n\nbody line")
        var commits = (try? await QueryCommits.run(repo)) ?? []
        check(commits.count == 1 && commits[0].subject == "first commit", "commit: created with subject")

        // 4) 改动 + 暂存 + 取消暂存（有 HEAD → restore --staged）。
        write(dir, "a.txt", "alpha changed\n")
        try? await Stage.paths(repo, ["a.txt"])
        check((try? await QueryLocalChanges.run(repo))?.contains { $0.path == "a.txt" && $0.isStaged } ?? false,
              "stage: modified staged")
        try? await Unstage.paths(repo, ["a.txt"])
        changes = (try? await QueryLocalChanges.run(repo)) ?? []
        check(changes.contains { $0.path == "a.txt" && $0.workTree == .modified && !$0.isStaged },
              "unstage: back to unstaged modified (post-commit)")

        // 5) 丢弃工作区改动（已跟踪还原，未跟踪删除）。
        write(dir, "junk.txt", "delete me\n")
        let toDiscard = (try? await QueryLocalChanges.run(repo)) ?? []
        try? await Discard.changes(repo, toDiscard)
        changes = (try? await QueryLocalChanges.run(repo)) ?? []
        check(changes.isEmpty, "discard: worktree clean after discard")
        check(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("junk.txt").path),
              "discard: untracked file removed")

        // 6) 新建并切换分支。
        try? await Branch.create(repo, name: "feature")
        try? await Checkout.branch(repo, "feature")
        let head = (try? await QueryHead.run(repo)) ?? GitHeadInfo()
        check(head.branch == "feature", "branch: switched to feature (\(head.branch))")
        let branches = (try? await QueryBranches.run(repo)) ?? []
        check(branches.contains { $0.name == "main" } && branches.contains { $0.name == "feature" },
              "branch: both main and feature listed")

        // 7) stash push / pop。
        write(dir, "a.txt", "stash me\n")
        try? await Stash.push(repo, message: "wip")
        check(((try? await QueryLocalChanges.run(repo)) ?? []).isEmpty, "stash: worktree clean after push")
        let stashes = (try? await QueryStashes.run(repo)) ?? []
        check(stashes.count == 1, "stash: one entry listed")
        try? await Stash.pop(repo)
        check(((try? await QueryLocalChanges.run(repo)) ?? []).contains { $0.path == "a.txt" },
              "stash: change restored after pop")

        // 8) amend 提交。
        try? await Stage.all(repo)
        try? await Commit.run(repo, message: "feature commit")
        try? await Commit.run(repo, message: "feature commit amended", amend: true)
        commits = (try? await QueryCommits.run(repo)) ?? []
        check(commits.first?.subject == "feature commit amended", "commit: amend rewrote subject")
    }
}
