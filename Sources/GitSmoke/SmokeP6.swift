import ConductorGit
import Foundation

enum SmokeP6 {
    static func run(
        check: (Bool, String) -> Void,
        makeRepo: () -> URL,
        write: (URL, String, String) -> Void,
        sh: ([String], URL) -> String) async
    {
        print("\n== P6: hunk staging / commit graph ==")
        let dir = makeRepo()
        defer { try? FileManager.default.removeItem(at: dir) }
        guard let repo = await GitRepository.discover(at: dir.path) else {
            check(false, "discover repo for P6"); return
        }

        // 多行文件，改顶部和底部两处 → 两个 hunk。
        write(dir, "f.txt", (1...20).map { "line \($0)" }.joined(separator: "\n") + "\n")
        _ = sh(["add", "-A"], dir); _ = sh(["commit", "-m", "base"], dir)
        var lines = (1...20).map { "line \($0)" }
        lines[0] = "LINE 1 CHANGED"
        lines[19] = "LINE 20 CHANGED"
        write(dir, "f.txt", lines.joined(separator: "\n") + "\n")

        let diff = (try? await Diff.file(repo, path: "f.txt", source: .workTree)) ?? TextDiff()
        check(diff.hunks.count == 2, "diff: two hunks (\(diff.hunks.count))")
        check(!diff.fileHeader.isEmpty, "diff: file header captured")

        // 只暂存第一个 hunk。
        if let first = diff.hunks.first {
            let patch = (diff.fileHeader + [first.patchText]).joined(separator: "\n")
            try? await ApplyPatch.stage(repo, patch: patch)
        }
        let changes = (try? await QueryLocalChanges.run(repo)) ?? []
        let f = changes.first { $0.path == "f.txt" }
        check(f?.isStaged ?? false, "hunk stage: file now has staged part")
        check(f?.hasWorkTreeChange ?? false, "hunk stage: file still has unstaged part")
        // 暂存区的 diff 应只含第一处改动。
        let staged = (try? await Diff.file(repo, path: "f.txt", source: .staged)) ?? TextDiff()
        let stagedText = staged.hunks.flatMap(\.lines).map(\.content).joined(separator: "\n")
        check(stagedText.contains("LINE 1 CHANGED") && !stagedText.contains("LINE 20 CHANGED"),
              "hunk stage: only first hunk staged")

        // 提交图布局：造一条分叉再合并的历史。
        _ = sh(["checkout", "-b", "br"], dir)
        write(dir, "g.txt", "x\n"); _ = sh(["add", "-A"], dir); _ = sh(["commit", "-m", "on br"], dir)
        _ = sh(["checkout", "main"], dir)
        write(dir, "h.txt", "y\n"); _ = sh(["add", "-A"], dir); _ = sh(["commit", "-m", "on main"], dir)
        _ = sh(["merge", "--no-ff", "br", "-m", "merge br"], dir)
        let commits = (try? await QueryCommits.run(repo, maxCount: 50)) ?? []
        let layout = CommitGraphLayout.compute(commits)
        check(layout.columns.count == commits.count, "graph: a column per commit")
        check(layout.maxColumn >= 1, "graph: branching produced >1 lane (maxCol=\(layout.maxColumn))")
        // 合并提交应有两个父。
        check(commits.contains { $0.parents.count == 2 }, "graph: merge commit has two parents")
    }
}
