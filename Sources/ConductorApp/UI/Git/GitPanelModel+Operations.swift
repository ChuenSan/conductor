import AppKit
import ConductorGit
import Foundation

/// 需要弹窗的操作（输入框 / 模式选择 / 危险确认）。
enum GitPrompt: Equatable, Identifiable {
    case createBranch(basedOn: String, baseLabel: String)
    case createTag(basedOn: String, baseLabel: String)
    case renameBranch(GitBranch)
    case setUpstream(GitBranch)
    case resetMode(GitCommit)
    case stashToBranch(GitStash)
    case confirmDeleteBranch(GitBranch)
    case confirmDeleteTag(GitTag)
    case confirmDropStash(GitStash)

    var id: String {
        switch self {
        case let .createBranch(b, _): "createBranch:\(b)"
        case let .createTag(b, _): "createTag:\(b)"
        case let .renameBranch(br): "rename:\(br.id)"
        case let .setUpstream(br): "upstream:\(br.id)"
        case let .resetMode(c): "reset:\(c.sha)"
        case let .stashToBranch(s): "stashBranch:\(s.id)"
        case let .confirmDeleteBranch(br): "delBranch:\(br.id)"
        case let .confirmDeleteTag(t): "delTag:\(t.id)"
        case let .confirmDropStash(s): "dropStash:\(s.id)"
        }
    }
}

/// 子视图检视器。
enum GitInspector: Equatable, Identifiable {
    case blame(path: String)
    case fileHistory(path: String)

    var id: String {
        switch self {
        case let .blame(p): "blame:\(p)"
        case let .fileHistory(p): "history:\(p)"
        }
    }

    var path: String {
        switch self {
        case let .blame(p), let .fileHistory(p): p
        }
    }
}

enum GitOpError: LocalizedError {
    case noUpstream
    case noRemote
    var errorDescription: String? {
        switch self {
        case .noUpstream: L("当前分支没有设置上游")
        case .noRemote: L("没有可用的远程仓库")
        }
    }
}

// MARK: - 操作

extension GitPanelModel {
    static func splitUpstream(_ raw: String) -> (remote: String, branch: String)? {
        var u = raw
        if u.hasPrefix("refs/remotes/") { u = String(u.dropFirst("refs/remotes/".count)) }
        let parts = u.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        return (parts[0], parts[1])
    }

    private var primaryRemote: String { "origin" }

    // MARK: 提交操作

    func checkoutCommit(_ c: GitCommit) {
        runOperation { try await Checkout.commit($0, c.sha) }
    }

    func promptCreateBranch(basedOn: String, baseLabel: String) {
        self.prompt = .createBranch(basedOn: basedOn, baseLabel: baseLabel)
    }

    func promptCreateTag(basedOn: String, baseLabel: String) {
        self.prompt = .createTag(basedOn: basedOn, baseLabel: baseLabel)
    }

    func promptResetTo(_ c: GitCommit) { self.prompt = .resetMode(c) }

    func resetTo(_ c: GitCommit, mode: GitResetMode) {
        self.prompt = nil
        runOperation { try await Reset.toCommit($0, revision: c.sha, mode: mode) }
    }

    func revertCommit(_ c: GitCommit) {
        runOperation { try await Revert.commit($0, c.sha) }
    }

    func cherryPick(_ c: GitCommit) {
        runOperation { try await CherryPick.run($0, commits: [c.sha]) }
    }

    func rebaseOnto(_ c: GitCommit) {
        runOperation { try await Rebase.onto($0, basedOn: c.sha) }
    }

    func saveCommitAsPatch(_ c: GitCommit) {
        guard let dest = Self.savePanel(suggested: "\(c.shortSHA).patch") else { return }
        runOperation(fullReload: false, successToast: L("已存为补丁")) {
            try await Patch.saveCommit($0, sha: c.sha, to: dest)
        }
    }

    /// 复制提交完整信息。
    func copyCommitMessage(_ c: GitCommit) {
        guard let repo = self.repository else { return }
        Task {
            let r = try? await repo.git(["log", "-1", "--format=%B", c.sha]).run(allowFailure: true)
            self.copyText(r?.stdout.trimmingCharacters(in: .whitespacesAndNewlines) ?? c.subject)
        }
    }

    // MARK: 分支操作

    func mergeBranch(_ b: GitBranch) {
        runOperation { try await Merge.run($0, source: b.friendlyName) }
    }

    func rebaseOntoBranch(_ b: GitBranch) {
        runOperation { try await Rebase.onto($0, basedOn: b.friendlyName) }
    }

    func promptRenameBranch(_ b: GitBranch) { self.prompt = .renameBranch(b) }
    func promptSetUpstream(_ b: GitBranch) { self.prompt = .setUpstream(b) }
    func promptDeleteBranch(_ b: GitBranch) { self.prompt = .confirmDeleteBranch(b) }

    func deleteBranch(_ b: GitBranch, force: Bool) {
        self.prompt = nil
        if b.isLocal {
            runOperation { try await Branch.delete($0, name: b.name, force: force) }
        } else {
            runOperation { try await Push.delete($0, remote: b.remote, refname: b.name) }
        }
    }

    func pushBranch(_ b: GitBranch) {
        let remote = self.primaryRemote
        runOperation(successToast: L("已推送")) { repo in
            if !b.upstream.isEmpty, let (r, rb) = Self.splitUpstream(b.upstream) {
                try await Push.branch(repo, localBranch: b.name, remote: r, remoteBranch: rb)
            } else {
                try await Push.branch(
                    repo, localBranch: b.name, remote: remote, remoteBranch: b.name, setUpstream: true)
            }
        }
    }

    func checkoutRemoteAsLocal(_ b: GitBranch) {
        runOperation { try await Checkout.remoteBranchAsLocal($0, remoteBranch: b) }
    }

    // MARK: tag 操作

    func promptDeleteTag(_ t: GitTag) { self.prompt = .confirmDeleteTag(t) }

    func deleteTag(_ t: GitTag) {
        self.prompt = nil
        runOperation { try await Tag.delete($0, name: t.name) }
    }

    func pushTag(_ t: GitTag) {
        let remote = self.primaryRemote
        runOperation(successToast: L("已推送")) { try await Tag.push($0, name: t.name, remote: remote) }
    }

    // MARK: stash 操作

    func applyStash(_ s: GitStash) { runOperation { try await Stash.apply($0, s.name) } }
    func popStash(_ s: GitStash) { runOperation { try await Stash.pop($0, s.name) } }
    func promptDropStash(_ s: GitStash) { self.prompt = .confirmDropStash(s) }
    func dropStash(_ s: GitStash) {
        self.prompt = nil
        runOperation { try await Stash.drop($0, s.name) }
    }

    func promptStashToBranch(_ s: GitStash) { self.prompt = .stashToBranch(s) }

    // MARK: 逐 hunk 暂存

    /// 暂存当前 diff 里的某个 hunk（仅未暂存来源有意义）。
    func stageHunk(_ hunk: TextDiffHunk) {
        guard let diff = self.diff else { return }
        let patch = (diff.fileHeader + [hunk.patchText]).joined(separator: "\n")
        runOperation(fullReload: false) { try await ApplyPatch.stage($0, patch: patch) }
    }

    /// 取消暂存当前 diff 里的某个 hunk（仅已暂存来源有意义）。
    func unstageHunk(_ hunk: TextDiffHunk) {
        guard let diff = self.diff else { return }
        let patch = (diff.fileHeader + [hunk.patchText]).joined(separator: "\n")
        runOperation(fullReload: false) { try await ApplyPatch.unstage($0, patch: patch) }
    }

    // MARK: 冲突解决

    /// 用我方/对方版本解决冲突文件并标记已解决（git checkout --ours/--theirs + add）。
    func resolveConflict(_ c: GitChange, useMine: Bool) {
        let path = c.path
        runOperation { repo in
            _ = try await repo.git(["checkout", useMine ? "--ours" : "--theirs", "--", path]).run()
            try await Stage.paths(repo, [path])
        }
    }

    // MARK: 文件操作（暂存/取消/丢弃见主文件）

    func stashFile(_ c: GitChange) {
        let path = c.path
        runOperation { _ = try await $0.git(["stash", "push", "--", path]).run() }
    }

    func setAssumeUnchanged(_ c: GitChange, assume: Bool) {
        let path = c.path
        runOperation(fullReload: false) { try await AssumeUnchanged.set($0, path: path, assume: assume) }
    }

    func saveFileAsPatch(_ c: GitChange, staged: Bool) {
        guard let dest = Self.savePanel(suggested: "\(URL(fileURLWithPath: c.path).lastPathComponent).patch")
        else { return }
        let path = c.path
        runOperation(fullReload: false, successToast: L("已存为补丁")) {
            try await Patch.saveLocalChanges($0, paths: [path], staged: staged, to: dest)
        }
    }

    func addToGitIgnore(_ c: GitChange) {
        let pattern = c.path
        runOperation(fullReload: false) { try GitIgnore.append($0, pattern: pattern) }
    }

    func revealInFinder(_ c: GitChange) {
        guard let repo = self.repository else { return }
        let url = URL(fileURLWithPath: repo.path).appendingPathComponent(c.path)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func openFile(_ c: GitChange) {
        guard let repo = self.repository else { return }
        let url = URL(fileURLWithPath: repo.path).appendingPathComponent(c.path)
        NSWorkspace.shared.open(url)
    }

    func copyAbsolutePath(_ c: GitChange) {
        guard let repo = self.repository else { return }
        self.copyText(URL(fileURLWithPath: repo.path).appendingPathComponent(c.path).path)
    }

    // MARK: 远程操作（工具栏）

    func fetch() {
        runOperation(successToast: L("已 fetch")) { try await Fetch.all($0, prune: true) }
    }

    func pull() {
        let head = self.head
        runOperation(successToast: L("已 pull")) { repo in
            guard let (remote, branch) = Self.splitUpstream(head.upstream) else {
                throw GitOpError.noUpstream
            }
            try await Pull.run(repo, remote: remote, branch: branch)
        }
    }

    func push() {
        let branches = self.branches
        let headBranch = self.head.branch
        let remote = self.primaryRemote
        runOperation(successToast: L("已推送")) { repo in
            let current = branches.first { $0.isCurrent }
            if let up = current?.upstream, !up.isEmpty, let (r, rb) = Self.splitUpstream(up) {
                try await Push.branch(repo, localBranch: headBranch, remote: r, remoteBranch: rb)
            } else {
                try await Push.branch(
                    repo, localBranch: headBranch, remote: remote, remoteBranch: headBranch, setUpstream: true)
            }
        }
    }

    // MARK: 弹窗提交

    /// 文本类弹窗确认（新建分支/tag、重命名、设上游）。
    func submitPrompt(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let prompt = self.prompt else { return }
        self.prompt = nil
        guard !trimmed.isEmpty else { return }
        switch prompt {
        case let .createBranch(basedOn, _):
            runOperation { try await Checkout.newBranch($0, name: trimmed, basedOn: basedOn) }
        case let .createTag(basedOn, _):
            runOperation { try await Tag.createLightweight($0, name: trimmed, basedOn: basedOn) }
        case let .renameBranch(b):
            runOperation { try await Branch.rename($0, from: b.name, to: trimmed) }
        case let .setUpstream(b):
            runOperation { try await Branch.setUpstream($0, name: b.name, upstream: trimmed) }
        case let .stashToBranch(s):
            runOperation { try await Stash.toBranch($0, name: s.name, branch: trimmed) }
        default:
            break
        }
    }

    // MARK: 辅助

    func copyText(_ s: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
        self.flash(L("已复制"))
    }

    private static func savePanel(suggested: String) -> String? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggested
        panel.canCreateDirectories = true
        return panel.runModal() == .OK ? panel.url?.path : nil
    }
}
