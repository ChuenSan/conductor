import ConductorGit
import Foundation

enum SmokeP4 {
    static func run(
        check: (Bool, String) -> Void,
        makeRepo: () -> URL,
        write: (URL, String, String) -> Void,
        sh: ([String], URL) -> String) async
    {
        print("\n== P4: full operation surface ==")
        let dir = makeRepo()
        defer { try? FileManager.default.removeItem(at: dir) }
        guard let repo = await GitRepository.discover(at: dir.path) else {
            check(false, "discover repo for P4"); return
        }

        // 三个提交打底。
        write(dir, "f.txt", "v1\n"); _ = sh(["add", "-A"], dir); _ = sh(["commit", "-m", "c1"], dir)
        write(dir, "f.txt", "v2\n"); _ = sh(["add", "-A"], dir); _ = sh(["commit", "-m", "c2"], dir)
        write(dir, "f.txt", "v3\n"); _ = sh(["add", "-A"], dir); _ = sh(["commit", "-m", "c3"], dir)
        let head = sh(["rev-parse", "HEAD"], dir).trimmingCharacters(in: .whitespacesAndNewlines)

        // Tag：轻量 + 附注 + 查询 + 删除。
        try? await Tag.createLightweight(repo, name: "v1.0", basedOn: "HEAD")
        try? await Tag.createAnnotated(repo, name: "v1.1", basedOn: "HEAD", message: "release 1.1")
        var tags = (try? await QueryTags.run(repo)) ?? []
        check(tags.contains { $0.name == "v1.0" } && tags.contains { $0.name == "v1.1" }, "tag: create + query")
        check(tags.first { $0.name == "v1.1" }?.sha == head, "tag: annotated deref to commit")
        try? await Tag.delete(repo, name: "v1.0")
        tags = (try? await QueryTags.run(repo)) ?? []
        check(!tags.contains { $0.name == "v1.0" }, "tag: delete")

        // Reset --soft HEAD^：上个提交的改动回到暂存区。
        try? await Reset.toCommit(repo, revision: "HEAD~1", mode: .soft)
        var changes = (try? await QueryLocalChanges.run(repo)) ?? []
        check(changes.contains { $0.path == "f.txt" && $0.isStaged }, "reset --soft: change re-staged")
        // 复位回去继续测。
        _ = sh(["reset", "--hard", head], dir)

        // Revert HEAD：生成一个反向提交。
        try? await Revert.commit(repo, "HEAD", autoCommit: true)
        let log = sh(["log", "--oneline"], dir)
        check(log.lowercased().contains("revert"), "revert: created revert commit")
        _ = sh(["reset", "--hard", head], dir)

        // CherryPick：在分叉分支造一个提交，挑回 main。
        _ = sh(["checkout", "-b", "feature"], dir)
        write(dir, "feat.txt", "feature\n"); _ = sh(["add", "-A"], dir); _ = sh(["commit", "-m", "feat"], dir)
        let featSHA = sh(["rev-parse", "HEAD"], dir).trimmingCharacters(in: .whitespacesAndNewlines)
        _ = sh(["checkout", "main"], dir)
        try? await CherryPick.run(repo, commits: [featSHA])
        check(FileManager.default.fileExists(atPath: dir.appendingPathComponent("feat.txt").path),
              "cherry-pick: file applied onto main")

        // Merge：另造分支再合并。
        _ = sh(["checkout", "-b", "topic"], dir)
        write(dir, "topic.txt", "topic\n"); _ = sh(["add", "-A"], dir); _ = sh(["commit", "-m", "topic"], dir)
        _ = sh(["checkout", "main"], dir)
        try? await Merge.run(repo, source: "topic")
        check(FileManager.default.fileExists(atPath: dir.appendingPathComponent("topic.txt").path),
              "merge: branch merged")

        // Blame。
        let blame = (try? await Blame.run(repo, path: "f.txt")) ?? GitBlame()
        check(!blame.lines.isEmpty && blame.lines.allSatisfy { !$0.sha.isEmpty },
              "blame: lines carry sha")
        check(blame.lines.first?.author.contains("Smoke") ?? false, "blame: author captured")

        // 单文件历史。
        let fh = (try? await FileHistory.run(repo, path: "f.txt")) ?? []
        check(fh.count >= 3, "file history: >=3 commits touched f.txt (\(fh.count))")

        // AssumeUnchanged。
        try? await AssumeUnchanged.set(repo, path: "f.txt", assume: true)
        let lsf = sh(["ls-files", "-v", "f.txt"], dir)
        check(lsf.hasPrefix("h") || lsf.contains("\nh"), "assume-unchanged: flagged (\(lsf.prefix(2)))")
        try? await AssumeUnchanged.set(repo, path: "f.txt", assume: false)

        // SaveAsPatch（提交）。
        let patch = dir.appendingPathComponent("out.patch").path
        try? await Patch.saveCommit(repo, sha: featSHA, to: patch)
        let patchText = (try? String(contentsOfFile: patch, encoding: .utf8)) ?? ""
        check(patchText.contains("feat.txt") && patchText.contains("diff --git"), "save-as-patch: commit patch written")

        // .gitignore 追加。
        try? GitIgnore.append(repo, pattern: "*.log")
        let gi = (try? String(contentsOf: dir.appendingPathComponent(".gitignore"), encoding: .utf8)) ?? ""
        check(gi.contains("*.log"), "gitignore: pattern appended")

        // 设置上游（无远程时应失败，但不崩）。
        try? await Branch.setUpstream(repo, name: "main", upstream: "origin/main")
        check(true, "set-upstream: no crash without remote")
    }
}
