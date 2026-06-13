import ConductorGit
import Foundation
import SwiftUI

/// Git 面板分段。
enum GitTab: String, CaseIterable, Identifiable {
    case changes
    case history
    case branches

    var id: String { self.rawValue }

    var title: String {
        switch self {
        case .changes: L("变更")
        case .history: L("历史")
        case .branches: L("分支")
        }
    }

    var icon: String {
        switch self {
        case .changes: "doc.on.doc"
        case .history: "clock.arrow.circlepath"
        case .branches: "arrow.triangle.branch"
        }
    }
}

/// 当前选中的变更 + 其 diff 来源。
struct GitChangeSelection: Equatable {
    var path: String
    var source: GitDiffSource
}

/// Git 侧面板视图模型：把 ConductorGit 引擎接到 SwiftUI。所有命令在后台跑，
/// 结果回到主 actor 更新 `@Published`。绑定「当前工作目录」（聚焦 pane 的 cwd）。
@MainActor
final class GitPanelModel: ObservableObject {
    @Published private(set) var directory: String?
    @Published private(set) var repository: GitRepository?
    /// 绑定目录是否是 git 仓库。false 时面板显示「非 git 仓库」空状态。
    @Published private(set) var isRepo = false

    @Published private(set) var head = GitHeadInfo()
    @Published private(set) var changes: [GitChange] = []
    @Published private(set) var commits: [GitCommit] = []
    @Published private(set) var branches: [GitBranch] = []
    @Published private(set) var tags: [GitTag] = []
    @Published private(set) var stashes: [GitStash] = []

    @Published var tab: GitTab = .changes
    @Published var commitMessage = ""
    @Published var amend = false

    /// 当前弹出的输入/确认对话框（新建分支、reset 模式、删除确认……）。
    @Published var prompt: GitPrompt?
    /// blame / 单文件历史等子视图。
    @Published var inspector: GitInspector?
    @Published private(set) var blame: GitBlame?
    @Published private(set) var fileHistoryCommits: [GitCommit] = []
    @Published private(set) var inspectorLoading = false

    @Published private(set) var isLoading = false
    @Published private(set) var isWorking = false
    @Published var errorMessage: String?
    /// 短暂的成功提示（如「已复制」「已 fetch」）。
    @Published var toast: String?

    @Published var selection: GitChangeSelection?
    @Published private(set) var diff: TextDiff?
    @Published private(set) var diffLoading = false

    /// 已暂存的变更（index 列）。
    var stagedChanges: [GitChange] { self.changes.filter(\.isStaged) }
    /// 未暂存/未跟踪的变更（workTree 列）。
    var unstagedChanges: [GitChange] { self.changes.filter(\.hasWorkTreeChange) }

    var canCommit: Bool {
        !self.commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (!self.stagedChanges.isEmpty || self.amend)
            && !self.isWorking
    }

    // MARK: - 绑定 / 刷新

    /// 绑定到某目录：发现所属仓库并加载。打开面板时调用。
    func bind(to directory: String?) {
        self.directory = directory
        self.errorMessage = nil
        guard let directory, !directory.isEmpty else {
            self.resetToNonRepo()
            return
        }
        Task { await self.discoverAndLoad(directory) }
    }

    private func discoverAndLoad(_ directory: String) async {
        self.isLoading = true
        let repo = await GitRepository.discover(at: directory)
        self.repository = repo
        self.isRepo = repo != nil
        if repo != nil {
            await self.reloadAll()
        } else {
            self.resetToNonRepo()
        }
        self.isLoading = false
    }

    private func resetToNonRepo() {
        self.repository = nil
        self.isRepo = false
        self.head = GitHeadInfo()
        self.changes = []
        self.commits = []
        self.branches = []
        self.selection = nil
        self.diff = nil
    }

    /// 全量刷新：并行拉 head / 状态 / 历史 / 分支。
    func refresh() {
        guard self.repository != nil else { return }
        Task {
            self.isLoading = true
            await self.reloadAll()
            self.isLoading = false
        }
    }

    private func reloadAll() async {
        guard let repo = self.repository else { return }
        async let head = (try? await QueryHead.run(repo)) ?? GitHeadInfo()
        async let changes = (try? await QueryLocalChanges.run(repo)) ?? []
        async let commits = (try? await QueryCommits.run(repo, maxCount: 200)) ?? []
        async let branches = (try? await QueryBranches.run(repo)) ?? []
        async let tags = (try? await QueryTags.run(repo)) ?? []
        async let stashes = (try? await QueryStashes.run(repo)) ?? []
        self.head = await head
        self.changes = await changes
        self.commits = await commits
        self.branches = await branches
        self.tags = await tags
        self.stashes = await stashes
        self.reconcileSelection()
    }

    /// 供操作方法在改完仓库后强制全量刷新。
    func reloadEverything() async { await self.reloadAll() }

    /// 只刷新状态（暂存/取消暂存/丢弃后）。
    private func reloadChanges() async {
        guard let repo = self.repository else { return }
        async let head = (try? await QueryHead.run(repo)) ?? GitHeadInfo()
        async let changes = (try? await QueryLocalChanges.run(repo)) ?? []
        self.head = await head
        self.changes = await changes
        self.reconcileSelection()
    }

    /// 状态变化后修正/刷新当前 diff 选择。
    private func reconcileSelection() {
        guard let selection else { return }
        let stillExists = self.changes.contains {
            $0.path == selection.path
                && (selection.source == .staged ? $0.isStaged : $0.hasWorkTreeChange)
        }
        if stillExists {
            self.loadDiff()
        } else {
            self.selection = nil
            self.diff = nil
        }
    }

    // MARK: - diff

    func select(_ change: GitChange, source: GitDiffSource) {
        self.selection = GitChangeSelection(path: change.path, source: source)
        self.loadDiff()
    }

    private func loadDiff() {
        guard let repo = self.repository, let selection else { return }
        Task {
            self.diffLoading = true
            self.diff = try? await Diff.file(repo, path: selection.path, source: selection.source)
            self.diffLoading = false
        }
    }

    // MARK: - 写操作

    /// 跑一个改仓库的操作：置忙、清错、执行、刷新、错误兜底。供各操作方法（含扩展）复用。
    /// `fullReload` 为 true 时全量刷新（分支/历史/tag 变了），否则只刷状态。
    func runOperation(
        fullReload: Bool = true,
        successToast: String? = nil,
        _ work: @escaping (GitRepository) async throws -> Void)
    {
        guard let repo = self.repository else { return }
        Task {
            self.isWorking = true
            self.errorMessage = nil
            do {
                try await work(repo)
                if fullReload { await self.reloadAll() } else { await self.reloadChanges() }
                if let successToast { self.flash(successToast) }
            } catch {
                self.errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            self.isWorking = false
        }
    }

    /// 闪一条短暂提示。
    func flash(_ message: String) {
        self.toast = message
    }

    // MARK: - 检视器（blame / 单文件历史）

    func openBlame(path: String) {
        guard let repo = self.repository else { return }
        self.inspector = .blame(path: path)
        self.blame = nil
        Task {
            self.inspectorLoading = true
            self.blame = try? await Blame.run(repo, path: path)
            self.inspectorLoading = false
        }
    }

    func openFileHistory(path: String) {
        guard let repo = self.repository else { return }
        self.inspector = .fileHistory(path: path)
        self.fileHistoryCommits = []
        Task {
            self.inspectorLoading = true
            self.fileHistoryCommits = (try? await FileHistory.run(repo, path: path)) ?? []
            self.inspectorLoading = false
        }
    }

    func closeInspector() {
        self.inspector = nil
        self.blame = nil
        self.fileHistoryCommits = []
    }

    /// 跑一个写操作并刷新；失败时把错误显示出来。
    private func perform(_ work: @escaping (GitRepository) async throws -> Void) {
        guard let repo = self.repository else { return }
        Task {
            self.isWorking = true
            self.errorMessage = nil
            do {
                try await work(repo)
                await self.reloadChanges()
            } catch {
                self.errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            self.isWorking = false
        }
    }

    func stage(_ change: GitChange) {
        let path = change.path
        self.perform { try await Stage.paths($0, [path]) }
    }

    func unstage(_ change: GitChange) {
        let path = change.path
        self.perform { try await Unstage.paths($0, [path]) }
    }

    func stageAll() {
        self.perform { try await Stage.all($0) }
    }

    func unstageAll() {
        self.perform { try await Unstage.all($0) }
    }

    func discard(_ change: GitChange) {
        self.perform { try await Discard.changes($0, [change]) }
    }

    func commit() {
        guard self.canCommit else { return }
        let message = self.commitMessage
        let amend = self.amend
        guard let repo = self.repository else { return }
        Task {
            self.isWorking = true
            self.errorMessage = nil
            do {
                try await Commit.run(repo, message: message, amend: amend)
                self.commitMessage = ""
                self.amend = false
                await self.reloadAll()
            } catch {
                self.errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            self.isWorking = false
        }
    }

    func checkout(_ branch: GitBranch) {
        guard branch.isLocal, !branch.isCurrent, let repo = self.repository else { return }
        let name = branch.name
        Task {
            self.isWorking = true
            self.errorMessage = nil
            do {
                try await Checkout.branch(repo, name)
                await self.reloadAll()
            } catch {
                self.errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            self.isWorking = false
        }
    }
}
