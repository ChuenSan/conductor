import ConductorGit
import Foundation

enum SmokeP1 {
    static func run(
        repoDir: URL,
        check: (Bool, String) -> Void,
        write: (URL, String, String) -> Void) async
    {
        print("\n== P1: read models / queries ==")
        guard let repo = await GitRepository.discover(at: repoDir.path) else {
            check(false, "discover repo for P1")
            return
        }

        // 初始空仓库：建一个文件并首提交。
        write(repoDir, "README.md", "# hello\nline2\n")
        write(repoDir, "src/main.swift", "print(\"hi\")\n")
        _ = try? await stage(repo, ["README.md", "src/main.swift"])
        _ = try? await commit(repo, "init commit")

        // 改一个已跟踪文件 + 新增一个未跟踪文件。
        write(repoDir, "README.md", "# hello\nline2 changed\nline3\n")
        write(repoDir, "untracked.txt", "brand new\n")

        let changes = (try? await QueryLocalChanges.run(repo)) ?? []
        check(changes.contains { $0.path == "README.md" && $0.workTree == .modified }, "status: modified file")
        check(changes.contains { $0.path == "untracked.txt" && $0.workTree == .untracked }, "status: untracked file")

        let head = (try? await QueryHead.run(repo)) ?? GitHeadInfo()
        check(head.branch == "main", "head: current branch is main (\(head.branch))")

        let commits = (try? await QueryCommits.run(repo)) ?? []
        check(commits.count == 1 && commits[0].subject == "init commit", "log: one commit with subject")
        check(commits.first?.isCurrentHead ?? false, "log: HEAD decorator on tip")

        let branches = (try? await QueryBranches.run(repo)) ?? []
        check(branches.contains { $0.name == "main" && $0.isCurrent }, "branches: main current")

        // 工作区 diff（README 改动）。
        let diff = (try? await Diff.file(repo, path: "README.md", source: .workTree)) ?? TextDiff()
        check(diff.addedCount >= 1 && diff.hunks.count >= 1, "diff: worktree shows additions")

        // 未跟踪文件 diff（整文件新增）。
        let untrackedDiff = (try? await Diff.file(repo, path: "untracked.txt", source: .untracked)) ?? TextDiff()
        check(untrackedDiff.addedCount == 1, "diff: untracked shows whole file added")

        let remotes = (try? await QueryRemotes.run(repo)) ?? []
        check(remotes.isEmpty, "remotes: none in fresh repo")
    }

    // 小工具：复用 GitProcess 直接跑写命令（P2 会有正式封装）。
    static func stage(_ repo: GitRepository, _ paths: [String]) async throws {
        _ = try await repo.git(["add"] + paths).run()
    }

    static func commit(_ repo: GitRepository, _ message: String) async throws {
        _ = try await repo.git(["commit", "-m", message]).run()
    }
}
