import AppKit
import Combine
import ConductorCore
import UniformTypeIdentifiers

private enum TerminalAreaTransition: Equatable {
    case zoom(expanding: Bool)
}

/// 一条「等你回复」记录：hook Notification 事件带来的消息 + 进入等待的时刻。
struct BlockedPaneInfo: Equatable {
    let message: String
    let since: Date
}

/// 应用协调器：持有 WorkspaceStore + SessionRegistry，把命令经 reducer 应用到状态、
/// 执行副作用（建/关/聚焦真终端），并把当前 active tab 的分屏树重建进窗口。
/// ObservableObject：SwiftUI 外壳（Tab 栏/侧栏）观察 store 变化自动刷新。
@MainActor
final class AppCoordinator: ObservableObject {
    @Published private(set) var store: WorkspaceStore
    /// 每个 pane 的显示标签（当前目录名，来自 libghostty 的 cwd 事件）。
    @Published private(set) var paneTitles: [PaneID: String] = [:]
    /// 每个 pane 的 cwd 全路径 + git 分支（状态栏用）。
    @Published private(set) var paneCwds: [PaneID: String] = [:]
    @Published private(set) var paneBranches: [PaneID: String] = [:]

    var activeCwd: String? { activePane().flatMap { paneCwds[$0] } }
    var activeBranch: String? { activePane().flatMap { paneBranches[$0] } }
    private(set) var registry: SessionRegistry!
    /// 终端分屏区（AppKit，承载 libghostty 视图）。SwiftUI 通过 representable 嵌入它。
    let containerView = NSView()
    /// 按 PaneID 复用 pane 容器：避免每次重建都 reparent 活动的 Metal 终端视图（会变白）。
    private var paneContainers: [PaneID: PaneContainerView] = [:]
    /// 即将创建的 pane → 入场动势；container 首次上树时取走。
    private var plannedEntrances: [PaneID: PaneEntranceMotion] = [:]
    /// 本次刚新建、需要入场动画的 pane。
    private var pendingEntrances: [PaneID: PaneEntranceMotion] = [:]
    /// 下一次终端区整体重建的空间转场（tab/workspace 切换用）。
    private var pendingAreaTransition: TerminalAreaTransition?
    /// 被放大占满 tab 的 pane（会话级，不持久化）。
    private var zoomedPane: PaneID?
    /// config.yaml 文件监听（热更新）。
    private var configWatcher: ConfigWatcher?
    /// 命令注册表：键位 → 命令，O(1) 分发；键位由 config 覆盖。
    let commandRegistry = CommandRegistry()
    /// 左侧工作区栏展示状态。
    @Published private(set) var sidebarPresentation = SidebarPresentationState()
    /// 侧栏列表模式（工作区 / 文件夹）。两种模式右侧各是一套独立的标签/分屏数据：
    /// 文件夹模式用一个隐藏的「浏览上下文」工作区承载，与常规工作区互不污染。
    @Published private(set) var sidebarListMode: SidebarListMode = .workspaces
    /// 主窗口内设置面板展示状态。
    @Published private(set) var settingsPresentation = SettingsPresentationState()
    /// 主窗口内工具面板展示状态（CLI / 用量 / Skills / Hooks，与设置面板互斥）。
    @Published private(set) var cliToolsPresentation = SettingsPresentationState()
    /// Agent 会话管理面板展示状态（与设置 / 工具面板互斥）。
    @Published private(set) var sessionPresentation = SettingsPresentationState()
    /// 会话面板筛选范围（工作区路径或 pane cwd）；nil 表示全部。
    @Published private(set) var sessionScopePath: String?
    /// 会话面板「当前面板续聊」的目标 pane。
    @Published private(set) var sessionTargetPane: PaneID?
    /// Git 面板展示状态（与设置 / 工具 / 会话面板互斥）。
    @Published private(set) var gitPresentation = SettingsPresentationState()
    /// Git 面板视图模型（懒创建，打开时绑定当前工作目录）。
    lazy var gitPanel = GitPanelModel()
    /// 工具面板当前选中的分段。
    @Published var toolsTab: ToolsTab = .cli
    /// Codex 用量监视器（状态栏常驻配额条 + 周期刷新）。
    let usageMonitor = UsageMonitor()
    /// CLI hook 收件箱监听（agent 完成 → 系统通知）。
    private let hooksInbox = HooksInbox()
    /// 工作区侧栏元数据（自动化状态/进度/日志 + 端口 + PR）。
    let workspaceMetadata = WorkspaceMetadataCenter()
    /// 自动化 socket 服务（conductor CLI 的对端）。
    private var automationServer: AutomationSocketServer?
    private var automationService: AutomationService?
    /// Agent 完成账本（状态栏铃铛 / 通知中心）。
    let activityLog = AgentActivityLog()
    /// 当前配置生效后可一键启动的 CLI（供 pane 右键「新建终端运行」子菜单使用）。
    @Published private(set) var launchableAgents: [LaunchableAgent] = []
    /// 本机自动检测到的 CLI。配置为空时用它作为默认入口；配置非空时只作为“重新扫描”来源。
    private var detectedLaunchableAgents: [LaunchableAgent] = []
    /// 每个 pane 当前在跑的 Agent（agent id）。空表示只是普通 shell。用于 pane 头条 / tab 显示 logo。
    @Published private(set) var paneAgents: [PaneID: String] = [:]
    /// 正在「思考」的 agent pane 集合（纯 hook 信号），驱动 tab / 工作区 / 文件夹树的思考动效。
    @Published private(set) var thinkingPanes: Set<PaneID> = []
    /// 「完成未读」：agent 跑完时不在屏上（其他标签/工作区）的 pane。
    /// 对应 tab 胶囊与侧栏工作区行亮小绿点，切过去看一眼即消。
    @Published private(set) var unseenDonePanes: Set<PaneID> = []
    /// 「等你回复」收件箱：agent 卡在权限确认/提问（hook Notification 事件）的 pane。
    /// 状态栏亮琥珀计数，弹层里可不切 pane 快捷回复。
    @Published private(set) var blockedPanes: [PaneID: BlockedPaneInfo] = [:]
    /// 每个 pane 的任务队列：当前一条 Stop 后自动发下一条（夜间挂机/流水线）。
    @Published private(set) var paneQueues: [PaneID: [String]] = [:]
    /// OSC 9;4 进度上报（pane 头条进度徽标）；remove 即删。
    @Published private(set) var paneProgress: [PaneID: PaneProgressInfo] = [:]
    /// app 在后台期间完成的任务数 → Dock 图标角标；激活即清零。
    private var dockBadgeCount = 0
    /// 终端里悬停的链接 URL（状态栏浏览器式显示）；nil = 没悬停在链接上。
    @Published var hoveredLink: String?
    /// hook 驱动的思考状态：UserPromptSubmit 点亮、Stop 熄灭（pane → 点亮时刻）。
    /// 事件可能丢（agent 崩溃/被 kill），靠超时 + agent 存活检查兜底回收。
    private var hookThinkingSince: [PaneID: Date] = [:]
    /// 头条活计时的起点账本：pane 进入思考集合时记 busy 时刻为起点，离开即清。
    private var thinkingStartTimes: [PaneID: Date] = [:]
    private static let hookThinkingTimeout: TimeInterval = 600
    private var agentPollTimer: Timer?
    /// 命令面板（懒创建）。
    private lazy var commandPalette = CommandPaletteController(coordinator: self)
    /// 键位速查面板（懒创建）。
    private lazy var shortcutCheatSheet = ShortcutCheatSheetController()
    /// 片段占位符填值面板（懒创建）。
    private lazy var snippetFillPanel = SnippetFillPanelController()
    /// pane 任务队列面板（懒创建）。
    private lazy var queuePanel = QueuePanelController()
    /// Mission Control 任务总览（懒创建）。
    private lazy var missionControl = MissionControlController()
    weak var window: NSWindow?
    private let stateStore: StateStore
    private var saveWorkItem: DispatchWorkItem?
    /// 最近关闭的 tab/pane（误关恢复，⌘⇧T 弹栈）。@Published 让右键菜单的可用态跟着变。
    @Published private(set) var recentlyClosed = RecentlyClosedStack()
    /// 待回放的内容快照（pane → 文件路径）：surface 工厂创建时取走。
    private var pendingRestoreFiles: [PaneID: String] = [:]
    /// 退出捕获到的各 pane agent 会话（pane.value → 引用），随 save() 落盘。
    private var capturedPaneSessions: [String: AgentSessionRef] = [:]

    var hasRecentlyClosed: Bool { !recentlyClosed.isEmpty }

    init(rootCwd: String) {
        store = WorkspaceStore(workspaces: [], activeWorkspace: nil)
        containerView.autoresizingMask = [.width, .height]

        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("conductor", isDirectory: true)
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        stateStore = StateStore(fileURL: appSupport.appendingPathComponent("state.json"))

        registry = SessionRegistry(
            factory: { [weak self] pane in
                let surface = GhosttySurface()
                // 每个 pane 注入自动化身份：hook 与 conductor CLI 都靠它们定位 pane / 连 socket。
                surface.extraEnvironment = [
                    ("CONDUCTOR_PANE_ID", pane.value),
                    ("CONDUCTOR_SOCKET", AutomationSocketServer.defaultSocketURL.path),
                ]
                // 内容恢复：这个 pane 有待回放快照 → 带上，attach 时回放。
                if let file = self?.pendingRestoreFiles.removeValue(forKey: pane) {
                    surface.restoreContentFile = file
                }
                return surface
            },
            onPaneExited: { [weak self] pane in self?.handlePaneExited(pane) }
        )
        restoreOrSeed(rootCwd: rootCwd)
        // 模式跟着持久化的活动工作区走（两者总是一起保存，活动工作区是事实源）：
        // 上次退出时停在文件夹模式 → 这次启动右侧直接还原浏览上下文。
        sidebarListMode = (store.activeWorkspace == Self.folderContextID) ? .folders : .workspaces
        registerCommands()
    }

    // MARK: - 命令注册

    private func registerCommands() {
        commandRegistry.register([
            AppCommand(id: "newTab", title: L("新建标签"), defaultKeybinding: "cmd+t") { [weak self] in self?.newTab() },
            AppCommand(id: "splitRight", title: L("向右分屏"), defaultKeybinding: "cmd+d") { [weak self] in self?.split(.vertical) },
            AppCommand(id: "splitDown", title: L("向下分屏"), defaultKeybinding: "cmd+shift+d") { [weak self] in self?.split(.horizontal) },
            AppCommand(id: "closePane", title: L("关闭面板"), defaultKeybinding: "cmd+w") { [weak self] in self?.closeActivePane() },
            AppCommand(id: "reopenClosedTab", title: L("恢复最近关闭"), defaultKeybinding: "cmd+shift+t") { [weak self] in self?.reopenClosed() },
            AppCommand(id: "focusPaneLeft", title: L("聚焦左侧面板"), defaultKeybinding: "cmd+alt+left") { [weak self] in self?.focusDirectional(.left) },
            AppCommand(id: "focusPaneRight", title: L("聚焦右侧面板"), defaultKeybinding: "cmd+alt+right") { [weak self] in self?.focusDirectional(.right) },
            AppCommand(id: "focusPaneUp", title: L("聚焦上方面板"), defaultKeybinding: "cmd+alt+up") { [weak self] in self?.focusDirectional(.up) },
            AppCommand(id: "focusPaneDown", title: L("聚焦下方面板"), defaultKeybinding: "cmd+alt+down") { [weak self] in self?.focusDirectional(.down) },
            AppCommand(id: "increaseFontSize", title: L("放大字号"), defaultKeybinding: "cmd+=") { [weak self] in self?.adjustFontSize(1) },
            AppCommand(id: "decreaseFontSize", title: L("缩小字号"), defaultKeybinding: "cmd+-") { [weak self] in self?.adjustFontSize(-1) },
            AppCommand(id: "resetFontSize", title: L("复位字号"), defaultKeybinding: "cmd+0") { [weak self] in self?.resetFontSize() },
            AppCommand(id: "openSettings", title: L("打开设置"), defaultKeybinding: "cmd+,") { [weak self] in self?.openSettings() },
            AppCommand(id: "toggleZoom", title: L("放大/还原面板"), defaultKeybinding: "cmd+enter") { [weak self] in self?.toggleZoom() },
            AppCommand(id: "commandPalette", title: L("命令面板"), defaultKeybinding: "cmd+k") { [weak self] in self?.openCommandPalette() },
            AppCommand(id: "shortcutCheatSheet", title: L("键位速查"), defaultKeybinding: "cmd+/") { [weak self] in self?.openShortcutCheatSheet() },
            AppCommand(id: "missionControl", title: L("任务总览"), defaultKeybinding: "cmd+shift+m") { [weak self] in self?.openMissionControl() },
            AppCommand(id: "queuePrompt", title: L("任务队列（当前面板）"), defaultKeybinding: "cmd+shift+enter") { [weak self] in self?.openQueuePanel() },
            AppCommand(id: "openSnippets", title: L("命令片段库"), defaultKeybinding: nil) { [weak self] in self?.openTools(.snippets) },
            AppCommand(id: "coCreate", title: L("共创计划"), defaultKeybinding: nil) { [weak self] in self?.openTools(.coCreate) },
            AppCommand(id: "equalizeSplits", title: L("均分面板"), defaultKeybinding: "cmd+ctrl+e") { [weak self] in self?.equalizeSplits() },
            AppCommand(id: "nextTab", title: L("下一标签"), defaultKeybinding: "cmd+shift+rightbrace") { [weak self] in self?.cycleTab(forward: true) },
            AppCommand(id: "prevTab", title: L("上一标签"), defaultKeybinding: "cmd+shift+leftbrace") { [weak self] in self?.cycleTab(forward: false) },
            AppCommand(id: "toggleRecentTab", title: L("最近标签往返"), defaultKeybinding: "ctrl+tab") { [weak self] in self?.toggleRecentTab() },
            AppCommand(id: "findInTerminal", title: L("终端内搜索"), defaultKeybinding: "cmd+f") { [weak self] in self?.openTerminalSearch() },
            AppCommand(id: "searchSelection", title: L("以选中内容搜索"), defaultKeybinding: "cmd+e") { [weak self] in self?.searchSelectionInTerminal() },
            AppCommand(id: "findNext", title: L("查找下一个"), defaultKeybinding: "cmd+g") { [weak self] in self?.navigateTerminalSearch(forward: true) },
            AppCommand(id: "findPrev", title: L("查找上一个"), defaultKeybinding: "cmd+shift+g") { [weak self] in self?.navigateTerminalSearch(forward: false) },
        ] + (1...9).map { n in
            AppCommand(id: "selectTab\(n)", title: L("切到标签 %ld", n), defaultKeybinding: "cmd+\(n)") { [weak self] in
                self?.selectTab(atIndex: n - 1)
            }
        })
    }

    /// ⌘1–⌘9：按序号直达当前工作区的标签；序号越界则忽略。
    func selectTab(atIndex index: Int) {
        guard let ws = activeWorkspace(), ws.tabs.indices.contains(index) else { return }
        selectTab(ws.tabs[index].id)
    }

    /// ⌘F：在活动 pane 上打开搜索条。
    func openTerminalSearch() {
        guard let tab = activeTabModel() else { return }
        container(for: tab.activePane)?.showSearch()
    }

    /// ⌘E：把终端里选中的文字作为搜索词（macOS「使用所选内容查找」惯例）。
    /// 没有选区时退化为打开空搜索条。
    func searchSelectionInTerminal() {
        guard let tab = activeTabModel(),
              let surface = registry.surface(for: tab.activePane) as? GhosttySurface else { return }
        if surface.hasSelection {
            // core 自己起搜索并回发 START_SEARCH（带选区文字）→ 搜索条自动带词浮现
            surface.performAction("search_selection")
        } else {
            container(for: tab.activePane)?.showSearch()
        }
    }

    /// ⌘G / ⇧⌘G：跳上/下一个匹配，焦点在终端时也能用；搜索条还没开就先打开。
    func navigateTerminalSearch(forward: Bool) {
        guard let tab = activeTabModel() else { return }
        guard let container = container(for: tab.activePane), container.isSearchVisible else {
            openTerminalSearch()
            return
        }
        (registry.surface(for: tab.activePane) as? GhosttySurface)?
            .performAction(forward ? "navigate_search:next" : "navigate_search:previous")
    }

    /// 一键切换 深/浅 主题（custom → 深色）。
    func toggleTheme() {
        var c = ConfigStore.shared.config
        c.appearance.theme = (c.appearance.theme == "light") ? "dark" : "light"
        applyConfig(c)
    }

    func openCommandPalette() {
        commandPalette.toggle(items: paletteItems(), over: window)
    }

    // MARK: - 键位速查（⌘/）

    /// ⌘/：键位速查面板——命令表全量展示当前有效键位（含 config 覆盖后的）。
    func openShortcutCheatSheet() {
        shortcutCheatSheet.toggle(items: shortcutCheatItems(), over: window)
    }

    /// 速查条目：按注册顺序全量展示；⌘1–⌘9 九条合并成一行。
    private func shortcutCheatItems() -> [ShortcutCheatItem] {
        let overrides = ConfigStore.shared.config.keybindings
        var items: [ShortcutCheatItem] = []
        var mergedTabRow = false
        for cmd in commandRegistry.commands {
            if cmd.id.hasPrefix("selectTab") {
                guard !mergedTabRow else { continue }
                mergedTabRow = true
                let first = commandRegistry.effectiveKeybinding(for: "selectTab1").map(ShortcutSymbolizer.symbolize)
                let last = commandRegistry.effectiveKeybinding(for: "selectTab9").map(ShortcutSymbolizer.symbolize)
                items.append(ShortcutCheatItem(
                    id: "selectTabRange", title: L("切到标签 1–9"),
                    display: first.flatMap { f in last.map { "\(f) … \($0)" } },
                    customized: (1...9).contains { overrides["selectTab\($0)"] != nil }))
                continue
            }
            items.append(ShortcutCheatItem(
                id: cmd.id, title: cmd.title,
                display: commandRegistry.effectiveKeybinding(for: cmd.id).map(ShortcutSymbolizer.symbolize),
                customized: overrides[cmd.id] != nil))
        }
        return items
    }

    // MARK: - Mission Control（任务总览）

    /// ⌘⇧M：全局 pane 卡片墙——所有工作区的终端实况（思考计时/等回复/完成未读/画面预览）。
    func openMissionControl() {
        missionControl.toggle(coordinator: self, over: window)
    }

    /// 某 pane 的思考起点（Mission Control 卡片计时用）；没在思考返回 nil。
    func thinkingSince(for pane: PaneID) -> Date? {
        thinkingStartTimes[pane]
    }

    /// 某 pane 当前屏幕文本（Mission Control 卡片预览用）。
    func viewportPreview(for pane: PaneID) -> String? {
        (registry.surface(for: pane) as? GhosttySurface)?.readViewportText()
    }

    // MARK: - 片段

    /// 把片段发到当前活动 pane：autoRun 直接执行，否则摆在提示符上可编辑。
    /// 命令带 `{{占位符}}` 时先弹填值面板。
    func sendSnippet(_ snippet: Snippet) {
        resolvePlaceholders(of: snippet) { [weak self] command in
            guard let self,
                  let tab = self.activeTabModel(),
                  let surface = self.registry.surface(for: tab.activePane) as? GhosttySurface else { return }
            if snippet.autoRun {
                surface.enqueueCommand(command)
            } else {
                surface.enqueueTypedText(command)
            }
            surface.focus()
        }
    }

    /// 当前活动终端 cd 到目录（侧栏文件夹树的「cd 到这里」）。
    func cdActivePane(to path: String) {
        guard let tab = activeTabModel(),
              let surface = registry.surface(for: tab.activePane) as? GhosttySurface else { return }
        surface.enqueueCommand("cd " + ShellQuoting.quote(path))
        surface.focus()
    }

    /// 有占位符 → 弹填值面板，确认后回调；没有 → 直接回调。
    private func resolvePlaceholders(of snippet: Snippet, then deliver: @escaping (String) -> Void) {
        guard snippet.placeholders.isEmpty else {
            snippetFillPanel.show(snippet: snippet, over: window) { deliver($0) }
            return
        }
        deliver(snippet.command)
    }

    /// 命令面板的条目：命令表 + 工作区 + 当前工作区的标签 + 片段 + 最近会话。
    private func paletteItems() -> [PaletteItem] {
        var items: [PaletteItem] = []
        for c in commandRegistry.commands where c.id != "commandPalette" {
            let kb = commandRegistry.effectiveKeybinding(for: c.id) ?? ""
            items.append(PaletteItem(id: "cmd:\(c.id)", icon: "command", title: c.title, subtitle: kb, run: c.run))
        }
        for ws in visibleWorkspaces {
            let id = ws.id
            items.append(PaletteItem(id: "ws:\(id.value)", icon: "folder", title: L("工作区：%@", ws.name),
                                     subtitle: ws.path) { [weak self] in self?.selectWorkspace(id) })
        }
        if let ws = activeWorkspace() {
            for tab in ws.tabs {
                let tid = tab.id
                let t = tab.customTitle ?? (paneTitles[tab.activePane] ?? L("终端"))
                items.append(PaletteItem(id: "tab:\(tid.value)", icon: "macwindow", title: L("标签：%@", t),
                                         subtitle: "") { [weak self] in self?.selectTab(tid) })
            }
        }
        for snippet in SnippetStore.shared.snippets {
            items.append(PaletteItem(id: "snippet:\(snippet.id)", icon: snippet.autoRun ? "bolt" : "text.cursor",
                                     title: L("片段：%@", snippet.name),
                                     subtitle: snippet.command) { [weak self] in self?.sendSnippet(snippet) })
        }
        // 最近会话：回车在新标签续聊。副标题带 agent + 目录，可按路径搜。
        let home = NSHomeDirectory()
        for record in SessionManagerStore.shared.records.prefix(12) {
            let dir = record.cwd.map { $0.hasPrefix(home) ? "~" + $0.dropFirst(home.count) : $0 }
            items.append(PaletteItem(
                id: "session:\(record.id)", icon: "bubble.left.and.text.bubble.right",
                title: L("续聊：%@", record.title),
                subtitle: dir.map { "\(record.agent) · \($0)" } ?? record.agent
            ) { [weak self] in self?.resumeSession(record, inPane: nil) })
        }
        return items
    }

    func openSettings() {
        cliToolsPresentation.close()
        sessionPresentation.close()
        gitPresentation.close()
        settingsPresentation.open()
    }

    func closeSettings() {
        settingsPresentation.close()
    }

    /// 打开 Git 面板：与其它右侧面板互斥，打开时绑定当前聚焦目录并刷新。
    func openGit() {
        settingsPresentation.close()
        cliToolsPresentation.close()
        sessionPresentation.close()
        gitPresentation.open()
        gitPanel.bind(to: currentWorkingDirectory())
    }

    func closeGit() {
        gitPresentation.close()
    }

    func toggleGit() {
        if gitPresentation.isPresented {
            gitPresentation.close()
        } else {
            openGit()
        }
    }

    /// 当前聚焦 pane 的工作目录，回退到活动工作区路径。Git 面板绑定它。
    func currentWorkingDirectory() -> String? {
        if let pane = activePane(), let cwd = paneCwds[pane] { return cwd }
        return activeWorkspace()?.path
    }

    /// 是否有右侧侧栏面板（设置 / CLI 工具 / 会话 / Git）正在展示。用于让快捷操作面板让位。
    var isSidePanelPresented: Bool {
        settingsPresentation.isPresented || cliToolsPresentation.isPresented
            || sessionPresentation.isPresented || gitPresentation.isPresented
    }

    func openCLITools() {
        // 共创计划不在面板分段里，普通入口重新打开时回到 CLI，避免落在无分段对应的页面。
        if toolsTab == .coCreate { toolsTab = .cli }
        settingsPresentation.close()
        sessionPresentation.close()
        gitPresentation.close()
        cliToolsPresentation.open()
    }

    /// 打开工具面板到指定分段。
    func openTools(_ tab: ToolsTab) {
        toolsTab = tab
        settingsPresentation.close()
        sessionPresentation.close()
        gitPresentation.close()
        cliToolsPresentation.open()
    }

    /// 打开 Agent 会话管理面板。`scopePath` 限定目录范围；`targetPane` 供「当前面板续聊」使用。
    func openSessionManager(scopePath: String? = nil, targetPane: PaneID? = nil) {
        sessionScopePath = scopePath
        sessionTargetPane = targetPane ?? activePane()
        settingsPresentation.close()
        cliToolsPresentation.close()
        gitPresentation.close()
        sessionPresentation.open()
        SessionManagerStore.shared.refresh()
    }

    func closeSessionManager() {
        sessionPresentation.close()
    }

    /// 某 pane 目录下可续聊的最近会话（供右键子菜单）。
    func sessionsForPane(_ pane: PaneID, limit: Int = 8) -> [AgentSessionRecord] {
        let dir = paneCwds[pane] ?? activeWorkspace()?.path ?? ""
        guard !dir.isEmpty else { return [] }
        return SessionManagerStore.shared.recordsForDirectory(dir, limit: limit)
    }

    /// 续聊：在指定 pane 执行 resume 命令；pane 为 nil 时新开标签（cwd 尽量跟会话目录走）。
    func resumeSession(_ record: AgentSessionRecord, inPane pane: PaneID?) {
        guard let command = record.resumeCommand else { return }
        if let pane {
            markActive(pane)
            (registry.surface(for: pane) as? GhosttySurface)?
                .enqueueCommand(resumeCommand(command, pane: pane))
            tagPaneAgentOptimistically(pane, command: record.agent == "codex" ? "codex" : "claude")
            closeSessionManager()
            return
        }
        let paneID = PaneID(nextID("p"))
        // shell 直接起在会话目录（目录没了回退工作区根/家目录），而不是先起在工作区根再假装
        let sessionCwd = record.cwd.map {
            CwdResolver.resolve(cwd: $0, workspacePath: activeWorkspace()?.path ?? $0)
        }
        run(.newTab(newTabID: TabID(nextID("t")), newPaneID: paneID, cwd: sessionCwd))
        if let cwd = sessionCwd { paneCwds[paneID] = cwd }
        (registry.surface(for: paneID) as? GhosttySurface)?
            .enqueueCommand(resumeCommand(command, pane: paneID))
        tagPaneAgentOptimistically(paneID, command: record.agent == "codex" ? "codex" : "claude")
        closeSessionManager()
    }

    private func resumeCommand(_ command: String, pane: PaneID) -> String {
        "CONDUCTOR_PANE_ID=\(pane.value) \(command)"
    }

    func closeCLITools() {
        cliToolsPresentation.close()
    }

    func toggleCLITools() {
        if cliToolsPresentation.isPresented {
            cliToolsPresentation.close()
        } else {
            openCLITools()
        }
    }

    func toggleSidebar() {
        sidebarPresentation.toggle()
    }

    func expandSidebar() {
        sidebarPresentation.expand()
    }

    // MARK: - 持久化

    private func restoreOrSeed(rootCwd: String) {
        let result = stateStore.load()
        guard result.outcome == .loaded, !result.state.store.workspaces.isEmpty else {
            seedDefault(rootCwd: rootCwd)
            return
        }
        store = result.state.store
        // 修复：空 tab 的工作区（历史 bug 留下的残局）补一个新 tab，选中后不至于一片空白。
        for index in store.workspaces.indices where store.workspaces[index].tabs.isEmpty {
            let tab = ConductorCore.Tab.single(id: TabID(nextID("t")), title: "zsh", pane: PaneID(nextID("p")))
            store.workspaces[index].addTab(tab)
        }
        // 为所有 pane 起 shell，回到各自上次的目录（目录没了回退工作区根/家目录）。
        let savedCwds = result.state.paneCwds
        for ws in store.workspaces {
            for tab in ws.tabs {
                for pane in tab.rootSplit.leaves() {
                    let cwd = CwdResolver.resolve(
                        cwd: savedCwds[pane.value] ?? ws.path, workspacePath: ws.path)
                    // 预填运行时 cwd/标题，shell 回报事件前状态栏与 tab 标题就正确。
                    paneCwds[pane] = cwd
                    paneTitles[pane] = AppCoordinator.shortName(cwd)
                    // 有内容快照 → 标记待回放（surface 工厂取走）。
                    if let file = ScrollbackStore.pendingFile(for: pane) {
                        pendingRestoreFiles[pane] = file
                    }
                    registry.apply([.createSurface(pane: pane, cwd: cwd)])
                    // 上次这里跑着 agent → 把 resume 命令预输入到提示符（按 Enter 才执行）。
                    stageSessionResume(result.state.paneSessions[pane.value], for: pane)
                }
            }
        }
    }

    private func seedDefault(rootCwd: String) {
        let pane = PaneID(nextID("p"))
        let tab = ConductorCore.Tab.single(id: TabID(nextID("t")), title: "zsh", pane: pane)
        let ws = Workspace(id: WorkspaceID(nextID("w")), name: "home", path: rootCwd,
                           tabs: [tab], activeTab: tab.id)
        store = WorkspaceStore(workspaces: [ws], activeWorkspace: ws.id)
        registry.apply([.createSurface(pane: pane, cwd: rootCwd), .focusSurface(pane: pane)])
    }

    func save() {
        // 只持久化还活着的 pane 的 cwd，避免字典随关闭累积。
        let live = Set(store.workspaces.flatMap { $0.tabs.flatMap { $0.rootSplit.leaves() } })
        var cwds: [String: String] = [:]
        for (pane, path) in paneCwds where live.contains(pane) { cwds[pane.value] = path }
        let sessions = capturedPaneSessions.filter { live.contains(PaneID($0.key)) }
        try? stateStore.save(PersistedState(store: store, paneCwds: cwds, paneSessions: sessions))
    }

    private func scheduleSave() {
        saveWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.save() }
        saveWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: item)
    }

    func attach(to window: NSWindow) {
        self.window = window
        syncNativeAppearance()
        rebuild()
        // SwiftUI 布局是异步的：等容器上墙后再聚焦初始终端。
        DispatchQueue.main.async { [weak self] in self?.focusActivePane() }
        startConfigWatch()
        detectLaunchableAgents()
        startAgentPolling()
        startNotifications()
        startAutomation()
        prewarmUsageReport()
        SessionManagerStore.shared.refresh()
        // 回到前台 → Dock 角标使命结束
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.clearDockBadge() }
        }
        // 窗口被完全遮挡/最小化 → 所有终端渲染器休眠；重新可见 → 唤醒在屏的并重画
        NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.syncWindowOcclusion() }
        }
    }

    /// 窗口可见性 → 终端渲染器开/睡。不可见时连当前 tab 的 surface 也睡（光标闪烁等动画停画）。
    private func syncWindowOcclusion() {
        guard let window else { return }
        if window.occlusionState.contains(.visible) {
            refreshVisibleSurfaces()   // 只唤醒在屏的（occlusion true + 强制重画）
        } else {
            for ws in store.workspaces {
                for tab in ws.tabs {
                    for pane in tab.rootSplit.leaves() {
                        (registry.surface(for: pane) as? GhosttySurface)?.setOcclusion(false)
                    }
                }
            }
        }
    }

    /// 自动化启动：socket 服务（conductor CLI 入口）+ 工作区元数据扫描（端口 / PR）。
    private func startAutomation() {
        let service = AutomationService(coordinator: self)
        automationService = service
        let server = AutomationSocketServer { [weak service] line in
            await service?.handleLine(line)
                ?? AutomationCodec.encode(AutomationResponse(id: nil, error: .internalError("服务已停止")))
        }
        if server.start() { automationServer = server }

        workspaceMetadata.workspacesProvider = { [weak self] in
            guard let self else { return [] }
            // 文件夹浏览上下文是隐藏工作区，不参与元数据扫描
            return store.workspaces
                .filter { $0.id != Self.folderContextID }
                .map { ($0.id, $0.path) }
        }
        workspaceMetadata.branchProvider = { path in
            Self.gitBranch(at: path)
        }
        workspaceMetadata.start()
    }

    /// 免 spawn 读当前分支：解析 `.git/HEAD` 的 `ref: refs/heads/<branch>`。
    nonisolated static func gitBranch(at path: String) -> String? {
        guard let head = try? String(contentsOfFile: path + "/.git/HEAD", encoding: .utf8) else {
            return nil
        }
        let trimmed = head.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("ref: refs/heads/") else {
            return trimmed.isEmpty ? nil : String(trimmed.prefix(8))   // detached HEAD → 短 SHA
        }
        return String(trimmed.dropFirst("ref: refs/heads/".count))
    }

    /// 启动后低优先级预扫一次 30 天用量并写缓存，让用量面板首次打开即有数据。
    private func prewarmUsageReport() {
        Task.detached(priority: .utility) {
            let report = UsageScanner().scan(daysBack: 30)
            UsageReportStore.save(report, daysBack: 30)
        }
    }

    // MARK: - 通知（agent 完成）

    private func startNotifications() {
        NotificationManager.shared.configure()
        NotificationManager.shared.onActivatePane = { [weak self] paneID in
            self?.revealPane(PaneID(paneID))
        }
        hooksInbox.onEvent = { [weak self] event in
            self?.handleHookEvent(event)
        }
        hooksInbox.start()
    }

    private func handleHookEvent(_ event: HookEvent) {
        let pane = event.paneID.map { PaneID($0) }

        // busy（UserPromptSubmit）：纯状态事件，点亮思考动效即返回，不发通知
        if event.type == "busy" {
            if let pane {
                setHookThinking(pane, active: true)
                clearBlocked(pane)   // 又跑起来了 → 不再等回复
            }
            return
        }

        // blocked（Notification）：agent 在等用户确认/输入 → 进「等你回复」收件箱
        if event.type == "blocked" {
            guard let pane, paneExists(pane) else { return }
            let message = event.message.isEmpty ? L("Agent 在等待你的确认或输入") : event.message
            blockedPanes[pane] = BlockedPaneInfo(message: message, since: Date())
            paneContainers[pane]?.setAwaitingReply(true)
            // 人不在 app 里才推系统通知（在的话状态栏琥珀计数已经够显眼）
            if !NSApp.isActive {
                let title = paneTitles[pane].map { L("等你回复 · %@", $0) } ?? L("Agent 等你回复")
                NotificationManager.shared.notify(paneID: event.paneID, title: title, body: message,
                                                  bodyFallback: L("Agent 在等待你的确认或输入"))
            }
            bumpDockBadgeIfInactive()
            return
        }

        // done / 旧脚本无 type（Stop）：熄灭思考动效 + 发完成通知 + 记入活动账本
        // 本轮思考用时（busy 点亮 → done 熄灭）；hook 没装或事件丢失时为 nil，1 秒内的不值一提。
        let duration = pane.flatMap { hookThinkingSince[$0] }
            .map { Date().timeIntervalSince($0) }
            .flatMap { $0 >= 1 ? $0 : nil }
        if let pane {
            setHookThinking(pane, active: false)
            clearBlocked(pane)
        }
        // 通知标题尽量带上 pane 标题/工作区，方便辨认是哪个会话。
        var title = event.title
        if let pane, let paneTitle = paneTitles[pane] {
            title = "\(event.title) · \(paneTitle)"
        }
        activityLog.record(paneID: pane, agentID: pane.flatMap { paneAgents[$0] },
                           title: title, message: event.message, duration: duration)
        var body = event.message
        if let duration {
            let took = L("耗时 %@", AgentActivityEntry.durationText(duration))
            body = body.isEmpty ? took : body + "\n" + took
        }
        NotificationManager.shared.notify(paneID: event.paneID, title: title, body: body)
        // 完成时不在屏上 → 记未读绿点；就在屏上 → 边框闪绿两下；app 在后台 → Dock 角标 +1
        if let pane {
            markUnseenDoneIfHidden(pane)
            if activeTabModel()?.rootSplit.contains(pane) == true {
                paneContainers[pane]?.flashHighlight(tint: NSColor(AppStyle.doneGreen))
            }
        }
        bumpDockBadgeIfInactive()
        // 任务队列接力：这条干完了，队首的下一条自动发出
        if let pane { dispatchNextQueued(pane) }
    }

    // MARK: - OSC 通知 / 进度（终端序列直达，无需 hook）

    /// OSC 9/99/777 桌面通知：任何 CLI `printf '\e]9;...\a'` 即可触达。
    /// 与 hook 的 done 事件走同一套出口（账本/系统通知/绿点/闪边/角标），但不动思考状态。
    /// 自动化 `notify` 方法也走这里（同一视觉语言）。
    func handleDesktopNotification(_ pane: PaneID, title: String, body: String) {
        var resolvedTitle = title.isEmpty ? L("终端通知") : title
        if let paneTitle = paneTitles[pane] {
            resolvedTitle = "\(resolvedTitle) · \(paneTitle)"
        }
        activityLog.record(paneID: pane, agentID: paneAgents[pane],
                           title: resolvedTitle, message: body, duration: nil)
        let visible = activeTabModel()?.rootSplit.contains(pane) == true
        // 正盯着这个 pane 时只闪边提示；离屏或 app 在后台才推系统通知
        if !NSApp.isActive || !visible {
            NotificationManager.shared.notify(paneID: pane.value, title: resolvedTitle, body: body)
        }
        markUnseenDoneIfHidden(pane)
        if visible {
            paneContainers[pane]?.flashHighlight(tint: NSColor(AppStyle.accent))
        }
        bumpDockBadgeIfInactive()
    }

    /// OSC 9;4 进度上报 → pane 头条进度徽标。remove 清除。
    private func applyProgressReport(_ pane: PaneID, state: PaneProgressState, percent: Int?) {
        if state == .remove {
            paneProgress.removeValue(forKey: pane)
        } else {
            paneProgress[pane] = PaneProgressInfo(state: state, percent: percent)
        }
        paneContainers[pane]?.setProgress(paneProgress[pane])
    }

    // MARK: - 等你回复（blocked 收件箱）

    private func clearBlocked(_ pane: PaneID) {
        guard blockedPanes.removeValue(forKey: pane) != nil else { return }
        paneContainers[pane]?.setAwaitingReply(false)
    }

    /// 不切 pane 的快捷按键回复：`"enter"` / `"esc"` / 单字符（如选项数字 "1"）。
    /// 数字/Esc 在 TUI 选择框里即时生效，不补回车。
    func sendQuickKey(_ key: String, to pane: PaneID) {
        guard let surface = registry.surface(for: pane) as? GhosttySurface else { return }
        switch key {
        case "enter": surface.sendEnterKey()
        case "esc": surface.sendEscapeKey()
        default: surface.sendTextInput(key)
        }
        clearBlocked(pane)
    }

    /// 不切 pane 的快捷文本回复：输入整段文字并回车提交。
    func sendQuickReply(_ text: String, to pane: PaneID) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let surface = registry.surface(for: pane) as? GhosttySurface else { return }
        surface.sendTextInput(trimmed)
        // 稍等 TUI 消化完文本再发真实回车（与命令注入同一招）
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak surface] in
            surface?.sendEnterKey()
        }
        clearBlocked(pane)
    }

    // MARK: - 任务队列（pane 级接力）

    /// 给 pane 排一条任务：agent 当前这条 Stop 后自动发出。
    func enqueuePrompt(_ text: String, for pane: PaneID) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        paneQueues[pane, default: []].append(trimmed)
        syncQueueBadge(pane)
    }

    func removeQueuedPrompt(at index: Int, for pane: PaneID) {
        guard var queue = paneQueues[pane], queue.indices.contains(index) else { return }
        queue.remove(at: index)
        paneQueues[pane] = queue.isEmpty ? nil : queue
        syncQueueBadge(pane)
    }

    func clearQueue(for pane: PaneID) {
        guard paneQueues[pane] != nil else { return }
        paneQueues[pane] = nil
        syncQueueBadge(pane)
    }

    /// 手动立即发队首（不等 Stop）。
    func sendNextQueuedNow(for pane: PaneID) {
        dispatchNextQueued(pane)
    }

    /// 弹出队首并发到终端（文本 + 真实回车）。队列空或 pane 已关则无事发生。
    private func dispatchNextQueued(_ pane: PaneID) {
        guard var queue = paneQueues[pane], !queue.isEmpty,
              let surface = registry.surface(for: pane) as? GhosttySurface else { return }
        let text = queue.removeFirst()
        paneQueues[pane] = queue.isEmpty ? nil : queue
        syncQueueBadge(pane)
        surface.sendTextInput(text)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak surface] in
            surface?.sendEnterKey()
        }
    }

    private func syncQueueBadge(_ pane: PaneID) {
        paneContainers[pane]?.setQueuedCount(paneQueues[pane]?.count ?? 0)
    }

    /// 打开当前活动 pane 的任务队列面板（⌘⇧⏎ / 右键菜单）。
    func openQueuePanel() {
        guard let pane = activePane() else { return }
        openQueuePanel(for: pane)
    }

    func openQueuePanel(for pane: PaneID) {
        queuePanel.toggle(pane: pane, title: paneTitles[pane] ?? L("终端"),
                          coordinator: self, over: window)
    }

    // MARK: - 二次意见（让另一个 agent 审查）

    /// 该 pane 可用的「二次意见」审查者：排除它自己正在跑的 agent。
    func secondOpinionAgents(excluding pane: PaneID) -> [LaunchableAgent] {
        launchableAgents.filter { $0.id != paneAgents[pane] }
    }

    /// 把 pane 的近期输出落成临时文件，分屏起另一个 agent 来出第二意见。
    func requestSecondOpinion(for pane: PaneID, reviewerCommand: String) {
        guard let surface = registry.surface(for: pane) as? GhosttySurface,
              let raw = surface.readAllText() else {
            ToastHUD.shared.show(L("没有可审查的内容"), icon: "exclamationmark.circle.fill", over: window)
            return
        }
        // 取末尾一段（约 12k 字符）：审的是「刚才干了什么」，不是整卷回滚
        let tail = String(raw.suffix(12_000)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tail.isEmpty else {
            ToastHUD.shared.show(L("没有可审查的内容"), icon: "exclamationmark.circle.fill", over: window)
            return
        }
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("conductor-second-opinion-\(Int(Date().timeIntervalSince1970)).txt")
        do {
            try tail.write(to: file, atomically: true, encoding: .utf8)
        } catch {
            ToastHUD.shared.show(L("写临时文件失败：%@", error.localizedDescription),
                                 icon: "exclamationmark.circle.fill", over: window)
            return
        }
        let prompt = L("文件 %@ 是另一个 AI 助手刚在这个项目里的终端工作记录。请通读后给出严格的第二意见：1) 结论或方案有无错漏；2) 有无更好的做法或被忽略的风险。直接给结论。", file.path)
        markActive(pane)
        launchAgentInSplit(command: "\(reviewerCommand) \(ShellQuoting.quote(prompt))",
                           axis: .vertical, agentTag: reviewerCommand)
    }

    // MARK: - 完成未读（绿点 / Dock 角标）

    /// done 时 pane 不在当前可见 tab 里（别的标签/工作区）→ 记未读。
    private func markUnseenDoneIfHidden(_ pane: PaneID) {
        guard paneExists(pane),
              activeTabModel().map({ !$0.rootSplit.contains(pane) }) ?? true else { return }
        unseenDonePanes.insert(pane)
    }

    /// 该 tab 是否有「完成未读」的 pane（tab 胶囊绿点）。
    func tabHasUnseenDone(_ tab: ConductorCore.Tab) -> Bool {
        !unseenDonePanes.isEmpty && tab.rootSplit.leaves().contains { unseenDonePanes.contains($0) }
    }

    /// 该工作区的「完成未读」数（侧栏工作区行绿点）。
    func workspaceUnseenDoneCount(_ ws: Workspace) -> Int {
        guard !unseenDonePanes.isEmpty else { return 0 }
        return ws.tabs.reduce(0) { sum, tab in
            sum + tab.rootSplit.leaves().filter { unseenDonePanes.contains($0) }.count
        }
    }

    /// 看到即消：当前 tab 上屏后清掉它名下的未读绿点；已关闭的 pane 一并清理。
    private func sweepUnseenDone(visible: Set<PaneID>) {
        guard !unseenDonePanes.isEmpty else { return }
        let cleaned = unseenDonePanes.filter { !visible.contains($0) && registry.surface(for: $0) != nil }
        if cleaned != unseenDonePanes { unseenDonePanes = cleaned }
    }

    /// pane 关闭后清理它名下的「等你回复」与任务队列（随 rebuild 顺手扫）。
    private func pruneDeadPaneState() {
        if !blockedPanes.isEmpty {
            let alive = blockedPanes.filter { registry.surface(for: $0.key) != nil }
            if alive.count != blockedPanes.count { blockedPanes = alive }
        }
        if !paneQueues.isEmpty {
            let alive = paneQueues.filter { registry.surface(for: $0.key) != nil }
            if alive.count != paneQueues.count { paneQueues = alive }
        }
        if !paneProgress.isEmpty {
            let alive = paneProgress.filter { registry.surface(for: $0.key) != nil }
            if alive.count != paneProgress.count { paneProgress = alive }
        }
    }

    private func bumpDockBadgeIfInactive() {
        guard !NSApp.isActive else { return }
        dockBadgeCount += 1
        NSApp.dockTile.badgeLabel = "\(dockBadgeCount)"
    }

    private func clearDockBadge() {
        guard dockBadgeCount != 0 else { return }
        dockBadgeCount = 0
        NSApp.dockTile.badgeLabel = nil
    }

    /// 状态栏中枢上次跳到的思考中 pane（轮转游标）。
    private var lastAttentionPane: PaneID?

    /// 状态栏中枢点击：跳到下一个需要关注的 pane——等你回复最优先（agent 卡着），
    /// 其次完成未读（看一眼即消），都没有就在思考中的 pane 间轮转。
    func revealNextAttentionPane() {
        let blocked = blockedPanes.keys.filter { paneExists($0) }.sorted { $0.value < $1.value }
        if let target = blocked.first {
            revealPane(target)
            return
        }
        let done = unseenDonePanes.filter { paneExists($0) }.sorted { $0.value < $1.value }
        if let target = done.first {
            revealPane(target)
            return
        }
        let thinking = thinkingPanes.filter { paneExists($0) }.sorted { $0.value < $1.value }
        guard !thinking.isEmpty else { return }
        var next = thinking[0]
        if let last = lastAttentionPane, let idx = thinking.firstIndex(of: last) {
            next = thinking[(idx + 1) % thinking.count]
        }
        lastAttentionPane = next
        revealPane(next)
    }

    /// pane 是否还活着（关掉的终端在通知中心里置灰）。
    func paneExists(_ pane: PaneID) -> Bool {
        registry.surface(for: pane) != nil
    }

    /// 通知中心点击跳转：聚焦目标 pane 并闪边框定位（切工作区/标签后稍等布局落定）。
    func revealPane(_ pane: PaneID) {
        guard paneExists(pane) else { return }
        focusPane(byID: pane.value)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.container(for: pane)?.flashHighlight()
        }
    }

    /// 点击通知后跳到对应 pane：切到它所在的工作区/标签并聚焦。
    func focusPane(byID paneIDString: String) {
        let target = PaneID(paneIDString)
        for ws in store.workspaces {
            for tab in ws.tabs where tab.rootSplit.contains(target) {
                if store.activeWorkspace != ws.id { selectWorkspace(ws.id) }
                if activeTabModel()?.id != tab.id { selectTab(tab.id) }
                markActive(target)
                window?.makeKeyAndOrderFront(nil)
                return
            }
        }
    }

    // MARK: - per-pane Agent 识别

    /// 周期轮询各 pane 的前台进程，识别在跑哪个 Agent（codex/claude/...），更新头条与 tab 的 logo。
    private func startAgentPolling() {
        guard agentPollTimer == nil else { return }
        pollPaneAgents()
        let timer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pollPaneAgents() }
        }
        timer.tolerance = 0.5
        agentPollTimer = timer
    }

    private func pollPaneAgents() {
        // 主线程收集 pane → 前台 pid（ghostty 调用需在主线程）。
        var pids: [(PaneID, Int32)] = []
        for ws in store.workspaces {
            for tab in ws.tabs {
                for pane in tab.rootSplit.leaves() {
                    if let pid = (registry.surface(for: pane) as? GhosttySurface)?.foregroundPID() {
                        pids.append((pane, pid))
                    }
                }
            }
        }
        let tokens: [(id: String, token: String)] = AgentCatalog.all.map { ($0.id, $0.command.lowercased()) }
        Task.detached(priority: .utility) { [weak self] in
            var map: [PaneID: String] = [:]
            for (pane, pid) in pids {
                guard let cmdline = ProcessInspector.commandLine(pid: pid) else { continue }
                if let match = tokens.first(where: { cmdline.contains($0.token) }) {
                    map[pane] = match.id
                }
            }
            await MainActor.run {
                self?.applyPaneAgents(map)
                self?.pruneHookThinking(agents: map)
            }
        }
    }

    /// hook 思考状态的兜底回收（hook 事件可能丢：agent 崩溃/被 kill）：
    /// agent 进程已不在的 pane、点亮超时的条目，随轮询清掉。
    private func pruneHookThinking(agents: [PaneID: String]) {
        guard !hookThinkingSince.isEmpty else { return }
        let cutoff = Date().addingTimeInterval(-Self.hookThinkingTimeout)
        hookThinkingSince = hookThinkingSince.filter { pane, since in
            agents[pane] != nil && since > cutoff
        }
        publishThinking()
    }

    /// 发布 hook 思考集合（仅在变化时触发 UI 更新）。
    private func publishThinking() {
        let combined = Set(hookThinkingSince.keys)
        if combined != thinkingPanes { thinkingPanes = combined }
        syncThinkingTimers(combined)
    }

    /// 头条活计时跟随思考集合：新进入的记起点并点亮，离开的清账并收起。
    private func syncThinkingTimers(_ thinking: Set<PaneID>) {
        for pane in thinking where thinkingStartTimes[pane] == nil {
            let since = hookThinkingSince[pane] ?? Date()
            thinkingStartTimes[pane] = since
            paneContainers[pane]?.setThinkingSince(since)
        }
        for pane in thinkingStartTimes.keys where !thinking.contains(pane) {
            thinkingStartTimes.removeValue(forKey: pane)
            paneContainers[pane]?.setThinkingSince(nil)
        }
    }

    /// hook 信号：即时点亮/熄灭，不等下一个轮询点。
    private func setHookThinking(_ pane: PaneID, active: Bool) {
        if active {
            hookThinkingSince[pane] = Date()
        } else {
            hookThinkingSince.removeValue(forKey: pane)
        }
        publishThinking()
    }

    /// 该工作区是否有 pane 在「思考」（侧栏工作区行动效用）。
    func isWorkspaceThinking(_ ws: Workspace) -> Bool {
        ws.tabs.contains { tab in
            tab.rootSplit.leaves().contains { thinkingPanes.contains($0) }
        }
    }

    /// 思考中 pane 的 cwd 列表（侧栏文件夹树动效用）。
    var thinkingCwds: [String] {
        thinkingPanes.compactMap { paneCwds[$0] }
    }

    private func applyPaneAgents(_ map: [PaneID: String]) {
        guard map != paneAgents else { return }
        paneAgents = map
        for (pane, container) in paneContainers {
            container.setAgentLogo(agentLogoImage(for: paneAgents[pane]))
        }
    }

    /// 取某 agent 的头条用 logo（已按主题处理单色标）。
    private func agentLogoImage(for agentID: String?) -> NSImage? {
        guard let agentID,
              let agent = launchableAgents.first(where: { $0.id == agentID })
              ?? AgentCatalog.all.first(where: { $0.id == agentID }).map({
                  LaunchableAgent(id: $0.id, title: $0.name, command: $0.command,
                                  logo: $0.logo, fallbackSystemImage: $0.fallbackSystemImage)
              })
        else { return nil }
        guard let original = CLIToolLogo.image(named: agent.logo)?.copy() as? NSImage else { return nil }
        original.size = NSSize(width: 14, height: 14)
        // 头条是自绘的，单色标需预先按主题着色（draw 时不会自动套用模板色）。
        if CLIToolLogo.isMonochrome(agent.logo) {
            return tinted(original, color: NSColor(AppStyle.textSecondary))
        }
        return original
    }

    private func tinted(_ image: NSImage, color: NSColor) -> NSImage {
        let result = NSImage(size: image.size)
        result.lockFocus()
        image.draw(at: .zero, from: NSRect(origin: .zero, size: image.size), operation: .sourceOver, fraction: 1)
        color.set()
        NSRect(origin: .zero, size: image.size).fill(using: .sourceAtop)
        result.unlockFocus()
        return result
    }

    /// 启动时填充可启动的 Agent：优先用磁盘缓存，避免每次启动都跑昂贵的 shell 探测。
    /// 缓存缺失时才后台检测一次并落盘（面板打开时会复用同一份缓存）。
    private func detectLaunchableAgents() {
        if let cache = CLIDetectionStore.load() {
            detectedLaunchableAgents = launchableAgents(from: cache.tools)
            refreshLaunchableAgentsFromConfig()
            return
        }
        Task { [weak self] in
            let tools = await Task.detached(priority: .utility) { () -> [CLIToolStatus] in
                AgentCatalog.detectStatuses()
            }.value
            CLIDetectionStore.save(tools)
            await MainActor.run {
                self?.detectedLaunchableAgents = self?.launchableAgents(from: tools) ?? []
                self?.refreshLaunchableAgentsFromConfig()
            }
        }
    }

    func scanAIAgentsIntoConfig() {
        Task { [weak self] in
            let tools = await Task.detached(priority: .userInitiated) { AgentCatalog.detectStatuses() }.value
            let cache = CLIDetectionStore.save(tools)
            let detected = tools.filter(\.isInstalled).map {
                AIAgentConfig(id: $0.id, title: $0.name, command: $0.id, enabled: true)
            }
            await MainActor.run {
                guard let self else { return }
                self.detectedLaunchableAgents = self.launchableAgents(from: cache.tools)
                var config = ConfigStore.shared.config
                config.terminal.aiAgents = self.mergeConfiguredAgents(
                    existing: config.terminal.aiAgents,
                    detected: detected)
                self.applyConfig(config)
            }
        }
    }

    private func mergeConfiguredAgents(
        existing: [AIAgentConfig],
        detected: [AIAgentConfig]
    ) -> [AIAgentConfig] {
        var out = AIAgentConfig.validatedList(existing)
        let existingIDs = Set(out.map(\.id))
        out.append(contentsOf: detected.filter { !existingIDs.contains($0.id) })
        return AIAgentConfig.validatedList(out)
    }

    private func launchableAgents(from tools: [CLIToolStatus]) -> [LaunchableAgent] {
        tools.filter(\.isInstalled).map {
            LaunchableAgent(
                id: $0.id, title: $0.name, command: $0.id,
                logo: $0.logo, fallbackSystemImage: $0.fallbackSystemImage)
        }
    }

    private func refreshLaunchableAgentsFromConfig() {
        let configured = AIAgentConfig.validatedList(ConfigStore.shared.config.terminal.aiAgents)
            .filter(\.enabled)
        guard !configured.isEmpty else {
            applyLaunchableAgents(detectedLaunchableAgents)
            return
        }
        applyLaunchableAgents(configured.map { config in
            let descriptor = AgentCatalog.all.first { $0.id == config.id }
            return LaunchableAgent(
                id: config.id,
                title: config.title,
                command: config.command,
                logo: descriptor?.logo ?? config.id,
                fallbackSystemImage: descriptor?.fallbackSystemImage ?? "terminal")
        })
    }

    // MARK: - 配置热更新

    private func startConfigWatch() {
        let watcher = ConfigWatcher { [weak self] in self?.reloadConfig() }
        watcher.start(directory: ConfigLoader.configURL.deletingLastPathComponent())
        configWatcher = watcher
    }

    /// config.yaml 变更：重载 → 更新所有终端 surface + 重套外壳主题色（免重启）。
    private func reloadConfig() {
        let old = ConfigStore.shared.config
        ConfigStore.shared.reload()
        let new = ConfigStore.shared.config
        guard new != old else { return }

        applyTerminalAppearance(effectiveConfig())   // 保留 ⌘+/- 的字号覆盖
        // 外壳主题色（SwiftUI 部分由 ConfigStore @Published 自动重渲染）
        restyleChrome()
        // 键位可能改了 → 重建命令索引
        commandRegistry.rebuildIndex()
        NSLog("[conductor] 配置已热更新")
    }

    /// 设置面板改配置：内存即时更新 + 应用终端/外壳/键位 + 落盘到 config.yaml。
    func applyConfig(_ new: AppConfig) {
        ConfigStore.shared.set(new)
        refreshLaunchableAgentsFromConfig()
        applyTerminalAppearance(effectiveConfig())
        restyleChrome()
        commandRegistry.rebuildIndex()
        ConfigStore.shared.persist()   // 写盘；watcher 自写幂等（new==old → no-op）
    }

    /// 把一份配置的终端外观应用到所有 surface（不重建、不丢 scrollback）。热更新与字号缩放共用。
    private func applyTerminalAppearance(_ config: AppConfig) {
        GhosttyRuntime.shared.applyConfig(config)
        for ws in store.workspaces {
            for tab in ws.tabs {
                for pane in tab.rootSplit.leaves() {
                    (registry.surface(for: pane) as? GhosttySurface)?.reloadConfig()
                }
            }
        }
    }

    /// 让原生控件（右键菜单 / 颜色选择器 / 下拉…）跟随 app 主题，而非系统外观。
    /// 否则系统深色 + app 浅色主题时，原生菜单会是黑的。
    private func syncNativeAppearance() {
        NSApp.appearance = NSAppearance(named: AppStyle.theme.isDark ? .darkAqua : .aqua)
    }

    private func restyleChrome() {
        syncNativeAppearance()
        window?.backgroundColor = NSColor(AppStyle.windowBackground)
        paneContainers.values.forEach { $0.restyle() }
        func walk(_ v: NSView) {
            if let split = v as? RatioSplitView { split.restyleForCurrentTheme() }
            else if v is NSSplitView { v.needsDisplay = true }
            v.subviews.forEach(walk)
        }
        containerView.subviews.forEach(walk)
    }

    // MARK: - 字号缩放（会话级，层叠在 config 之上，不写回文件）

    /// 当前会话的字号覆盖（nil = 用 config 里的字号）。
    private var fontSizeOverride: Int?

    private func effectiveConfig() -> AppConfig {
        var c = ConfigStore.shared.config
        if let override = fontSizeOverride {
            c.appearance.font.size = override
            // 高级里的 font-size 覆盖在 ghostty 配置里排在 appearance 之后；
            // 会话级缩放要同时压过它，否则设过高级字号后 ⌘+/- 失效。
            if c.ghosttyOverrides["font-size"] != nil {
                c.ghosttyOverrides["font-size"] = "\(override)"
            }
        }
        return c.validated()
    }

    /// 配置层面的当前字号：高级覆盖优先，其次外观基础值。
    private var configuredFontSize: Int {
        let cfg = ConfigStore.shared.config
        return Int(cfg.ghosttyOverrides["font-size"] ?? "") ?? cfg.appearance.font.size
    }

    func adjustFontSize(_ delta: Int) {
        let base = fontSizeOverride ?? configuredFontSize
        let clamped = min(max(base + delta, 6), 72)
        fontSizeOverride = clamped
        applyTerminalAppearance(effectiveConfig())
        // toast 反馈当前字号；连按时文字原地刷新，碰到上下限直说
        var text = L("字号 %ld pt", clamped)
        if clamped == base, delta < 0 { text = L("已是最小字号（%ld pt）", clamped) }
        if clamped == base, delta > 0 { text = L("已是最大字号（%ld pt）", clamped) }
        ToastHUD.shared.show(text,
                             icon: delta > 0 ? "textformat.size.larger" : "textformat.size.smaller",
                             over: window)
    }

    func resetFontSize() {
        guard fontSizeOverride != nil else { return }
        fontSizeOverride = nil
        applyTerminalAppearance(effectiveConfig())
        ToastHUD.shared.show(L("字号已复位（%ld pt）", configuredFontSize),
                             icon: "textformat.size", over: window)
    }

    /// 侧栏文件夹树「在此目录开终端」：新标签在指定目录起 shell。
    func newTab(atDirectory path: String) {
        run(.newTab(newTabID: TabID(nextID("t")), newPaneID: PaneID(nextID("p")), cwd: path))
    }

    // MARK: - 命令入口（键位调用）

    /// ⌘T：新标签的 shell 在当前 pane 的目录启动（Terminal.app 惯例）；拿不到则回退工作区根。
    func newTab() {
        let paneID = PaneID(nextID("p"))
        let cwd = inheritableCwd()
        run(.newTab(newTabID: TabID(nextID("t")), newPaneID: paneID, cwd: cwd))
        // 预填运行时 cwd，shell 回报事件前状态栏/标签标题就正确
        if let cwd { paneCwds[paneID] = cwd }
    }

    /// 一键启动 Agent：新开一个标签页，待 shell 就绪后自动执行 `command`（如 `codex`）。
    func launchAgent(command: String) {
        if let agent = launchableAgents.first(where: { $0.command == command || $0.id == command })
            ?? detectedLaunchableAgents.first(where: { $0.command == command || $0.id == command })
            ?? AgentCatalog.all.first(where: { $0.command == command || $0.id == command }).map({
                LaunchableAgent(
                    id: $0.id,
                    title: $0.name,
                    command: $0.command,
                    logo: $0.logo,
                    fallbackSystemImage: $0.fallbackSystemImage)
            })
        {
            launchAIAgentSession(agent)
            return
        }
        let paneID = PaneID(nextID("p"))
        run(.newTab(newTabID: TabID(nextID("t")), newPaneID: paneID))
        (registry.surface(for: paneID) as? GhosttySurface)?.enqueueCommand(launchCommand(command, pane: paneID))
        tagPaneAgentOptimistically(paneID, command: command)
    }

    /// 新建一个 AI Agent 会话 tab。可指定工作区和 cwd，供工作区右键与 tab 加号菜单复用。
    func launchAIAgentSession(_ agent: LaunchableAgent, workspaceID: WorkspaceID? = nil, cwd: String? = nil) {
        if let workspaceID, store.activeWorkspace != workspaceID {
            selectWorkspace(workspaceID)
        }
        let paneID = PaneID(nextID("p"))
        let launchCwd = cwd
        run(.newTab(newTabID: TabID(nextID("t")), newPaneID: paneID, cwd: launchCwd))
        if let launchCwd { paneCwds[paneID] = launchCwd }
        (registry.surface(for: paneID) as? GhosttySurface)?.enqueueCommand(launchCommand(agent.command, pane: paneID))
        tagPaneAgent(paneID, agentID: agent.id)
    }

    /// 在当前 tab 内分屏启动 Agent。`agentTag` 用于带参数命令（如二次意见）的 logo 即时识别。
    func launchAgentInSplit(command: String, axis: SplitAxis, agentTag: String? = nil) {
        let paneID = PaneID(nextID("p"))
        plannedEntrances[paneID] = .split(axis: axis)
        run(.split(axis: axis, newPaneID: paneID, splitID: SplitID(nextID("s")), cwd: inheritableCwd()))
        (registry.surface(for: paneID) as? GhosttySurface)?.enqueueCommand(launchCommand(command, pane: paneID))
        tagPaneAgentOptimistically(paneID, command: agentTag ?? command)
    }

    /// 给启动命令注入 `CONDUCTOR_PANE_ID`，让 agent 的 hook 知道是哪个 pane（用于通知点击跳转）。
    private func launchCommand(_ command: String, pane: PaneID) -> String {
        "CONDUCTOR_PANE_ID=\(pane.value) \(command)"
    }

    /// 启动后立即按命令乐观标记 pane 的 agent，让 logo 即时出现（轮询随后会校正/清除）。
    private func tagPaneAgentOptimistically(_ pane: PaneID, command: String) {
        guard let agentID = launchableAgents.first(where: { $0.command == command || $0.id == command })?.id
            ?? AgentCatalog.all.first(where: { $0.command == command || $0.id == command })?.id
        else { return }
        tagPaneAgent(pane, agentID: agentID)
    }

    private func tagPaneAgent(_ pane: PaneID, agentID: String) {
        var map = paneAgents
        map[pane] = agentID
        applyPaneAgents(map)
    }

    /// 由 CLI 检测面板回填可启动的 Agent 列表（带 logo），供右键菜单复用。
    func setLaunchableAgents(_ agents: [LaunchableAgent]) {
        detectedLaunchableAgents = agents
        refreshLaunchableAgentsFromConfig()
    }

    private func applyLaunchableAgents(_ agents: [LaunchableAgent]) {
        launchableAgents = agents
    }

    func split(_ axis: SplitAxis) {
        let paneID = PaneID(nextID("p"))
        plannedEntrances[paneID] = .split(axis: axis)
        run(.split(axis: axis, newPaneID: paneID, splitID: SplitID(nextID("s")), cwd: inheritableCwd()))
    }

    /// 分屏 / ⌘T 新 shell 继承当前 pane 的目录（目录已不存在则回退工作区根/家目录）。
    private func inheritableCwd() -> String? {
        guard let cwd = activeCwd else { return nil }
        return CwdResolver.resolve(cwd: cwd, workspacePath: activeWorkspace()?.path ?? cwd)
    }

    func closeActivePane() {
        let thinkingCount = activePane().map { thinkingPanes.contains($0) ? 1 : 0 } ?? 0
        guard confirmInterruptThinking(count: thinkingCount,
                                       message: L("关闭这个面板？"),
                                       confirmTitle: L("仍要关闭")) else { return }
        pushClosedRecordForActivePane()
        run(.closeActivePane)
    }

    /// 关闭整个 tab（含其所有 pane）。可关非 active 的 tab。
    func closeTab(_ id: TabID) {
        let panes = activeWorkspace()?.tabs.first(where: { $0.id == id })?.rootSplit.leaves() ?? []
        let thinkingCount = panes.filter { thinkingPanes.contains($0) }.count
        guard confirmInterruptThinking(count: thinkingCount,
                                       message: L("关闭这个标签？"),
                                       confirmTitle: L("仍要关闭")) else { return }
        pushClosedTabRecord(id)
        run(.closeTab(id))
    }

    // MARK: - 误关保护

    /// 退出守门：有思考中的 agent 先确认（AppDelegate.applicationShouldTerminate 调用）。
    func shouldTerminateApp() -> Bool {
        confirmInterruptThinking(
            count: thinkingPanes.filter { paneExists($0) }.count,
            message: L("现在退出 Conductor？"),
            confirmTitle: L("仍要退出"))
    }

    /// 要关的范围里有 agent 正在思考 → 先弹确认（Terminal.app 惯例：回车放行、Esc 取消）。
    /// 返回 true = 放行；没有思考中的 agent 时不打扰。
    private func confirmInterruptThinking(count: Int, message: String, confirmTitle: String) -> Bool {
        guard count > 0 else { return true }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = message
        alert.informativeText = L("有 %ld 个 Agent 正在思考，会被打断。", count)
        alert.addButton(withTitle: confirmTitle)
        alert.addButton(withTitle: L("取消"))
        alert.buttons.first?.hasDestructiveAction = true
        return alert.runModal() == .alertFirstButtonReturn
    }

    // MARK: - 误关恢复（⌘⇧T）

    /// 关 tab 前快照：完整分屏树 + 每个 pane 的 cwd + 终端内容 + agent 会话。
    func pushClosedTabRecord(_ id: TabID) {
        guard let wsIndex = activeWorkspaceIndex(),
              let tab = store.workspaces[wsIndex].tabs.first(where: { $0.id == id }) else { return }
        for pane in tab.rootSplit.leaves() { captureScrollback(pane) }
        recentlyClosed.push(.tab(
            workspaceID: store.workspaces[wsIndex].id, tab: tab,
            paneCwds: capturedCwds(tab), paneSessions: capturedSessions(tab)))
    }

    /// 右键「导出输出为文本」：把 pane 的屏幕+回滚文本另存为 .txt（agent 长输出存档）。
    func exportScrollback(_ pane: PaneID) {
        guard let surface = registry.surface(for: pane) as? GhosttySurface,
              let text = surface.readAllText(),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            ToastHUD.shared.show(L("没有可导出的内容"), icon: "exclamationmark.circle.fill", over: window)
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = exportFileName(for: pane)
        // 默认落在 pane 的当前目录，顺手
        if let cwd = paneCwds[pane] { panel.directoryURL = URL(fileURLWithPath: cwd) }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            ToastHUD.shared.show(L("已导出 %@", url.lastPathComponent),
                                 icon: "square.and.arrow.down.fill", over: window)
        } catch {
            ToastHUD.shared.show(L("导出失败：%@", error.localizedDescription),
                                 icon: "exclamationmark.circle.fill", over: window)
        }
    }

    /// 导出默认文件名：pane 标题（去掉路径分隔符）+ 时间戳。
    private func exportFileName(for pane: PaneID) -> String {
        let raw = paneTitles[pane] ?? "terminal"
        let safe = raw.map { "/:".contains($0) ? "-" : $0 }.map(String.init).joined()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "\(safe)-\(formatter.string(from: Date())).txt"
    }

    /// 趁 surface 还活着，把 pane 的屏幕+回滚文本快照到盘（恢复时回放）。
    private func captureScrollback(_ pane: PaneID) {
        guard let surface = registry.surface(for: pane) as? GhosttySurface,
              let text = surface.readAllText() else { return }
        ScrollbackStore.save(text, for: pane)
    }

    /// 关 pane 前快照：tab 内最后一个 pane 时整 tab 入栈，否则记单 pane（含原分屏方向）。
    func pushClosedRecordForActivePane() {
        guard let wsIndex = activeWorkspaceIndex(),
              let tabIndex = activeTabIndex(wsIndex: wsIndex) else { return }
        let tab = store.workspaces[wsIndex].tabs[tabIndex]
        if tab.paneCount <= 1 {
            pushClosedTabRecord(tab.id)
        } else {
            let pane = tab.activePane
            captureScrollback(pane)
            recentlyClosed.push(.pane(
                workspaceID: store.workspaces[wsIndex].id, tabID: tab.id, pane: pane,
                cwd: paneCwds[pane], axis: Self.parentAxis(of: pane, in: tab.rootSplit) ?? .vertical,
                session: agentSessionRef(for: pane)))
        }
    }

    private func capturedCwds(_ tab: ConductorCore.Tab) -> [String: String] {
        var map: [String: String] = [:]
        for pane in tab.rootSplit.leaves() {
            if let cwd = paneCwds[pane] { map[pane.value] = cwd }
        }
        return map
    }

    private func capturedSessions(_ tab: ConductorCore.Tab) -> [String: AgentSessionRef] {
        var map: [String: AgentSessionRef] = [:]
        for pane in tab.rootSplit.leaves() {
            if let ref = agentSessionRef(for: pane) { map[pane.value] = ref }
        }
        return map
    }

    /// pane 正在跑 claude/codex 时，按 cwd 在会话目录里定位最近的会话 ID。
    private func agentSessionRef(for pane: PaneID) -> AgentSessionRef? {
        guard let agent = paneAgents[pane], let cwd = paneCwds[pane] else { return nil }
        return AgentSessionLocator.locate(agent: agent, cwd: cwd)
    }

    /// 把 resume 命令预输入到 pane 的提示符上（不回车，按 Enter 才续聊）。
    private func stageSessionResume(_ ref: AgentSessionRef?, for pane: PaneID) {
        guard let command = ref?.resumeCommand else { return }
        (registry.surface(for: pane) as? GhosttySurface)?.enqueueTypedText(command)
    }

    /// 找 pane 在树里的父分屏方向（恢复时按原方向接回去）。
    static func parentAxis(of pane: PaneID, in node: SplitNode) -> SplitAxis? {
        guard case let .split(_, axis, _, first, second) = node else { return nil }
        if case let .leaf(p) = first, p == pane { return axis }
        if case let .leaf(p) = second, p == pane { return axis }
        return Self.parentAxis(of: pane, in: first) ?? Self.parentAxis(of: pane, in: second)
    }

    /// ⌘⇧T：弹出最近关闭的 tab/pane，重建 shell 回到原目录并回放关闭前的终端内容
    /// （文本回放，进程不复活）。
    func reopenClosed() {
        guard let record = recentlyClosed.pop() else { return }
        switch record {
        case let .tab(workspaceID, tab, cwds, sessions):
            let target: WorkspaceID? =
                store.workspaces.contains(where: { $0.id == workspaceID }) ? workspaceID : nil
            for (key, path) in cwds { paneCwds[PaneID(key)] = path }
            stageContentRestore(for: tab.rootSplit.leaves())
            run(.restoreTab(tab: tab, workspaceID: target, paneCwds: cwds))
            for pane in tab.rootSplit.leaves() {
                stageSessionResume(sessions[pane.value], for: pane)
            }
        case let .pane(workspaceID, tabID, pane, cwd, axis, session):
            if let cwd { paneCwds[pane] = cwd }
            stageContentRestore(for: [pane])
            let tabAlive = store.workspaces.first(where: { $0.id == workspaceID })?
                .tabs.contains(where: { $0.id == tabID }) ?? false
            if tabAlive {
                plannedEntrances[pane] = .split(axis: axis)
                run(.restorePane(pane: pane, tabID: tabID, workspaceID: workspaceID,
                                 cwd: cwd, axis: axis, splitID: SplitID(nextID("s"))))
            } else {
                // 原 tab 没了：作为单 pane 新 tab 恢复
                let tab = ConductorCore.Tab.single(id: TabID(nextID("t")), title: "zsh", pane: pane)
                let target: WorkspaceID? =
                    store.workspaces.contains(where: { $0.id == workspaceID }) ? workspaceID : nil
                run(.restoreTab(tab: tab, workspaceID: target,
                                paneCwds: cwd.map { [pane.value: $0] } ?? [:]))
            }
            stageSessionResume(session, for: pane)
        }
    }

    /// 把这些 pane 的内容快照标记为待回放（surface 工厂创建时取走）。
    private func stageContentRestore(for panes: [PaneID]) {
        for pane in panes {
            if let file = ScrollbackStore.pendingFile(for: pane) {
                pendingRestoreFiles[pane] = file
            }
        }
    }

    /// 退出前调用：给所有活着的 pane 拍内容快照 + 记下正在跑的 agent 会话，
    /// 并清掉没人引用的孤儿快照。从未显示过的 pane（后台 tab）读不到文本 → 保留它上次的快照不动。
    func captureAllScrollbackForRestart() {
        var keep = Set<PaneID>()
        capturedPaneSessions.removeAll()
        for ws in store.workspaces {
            for tab in ws.tabs {
                for pane in tab.rootSplit.leaves() {
                    captureScrollback(pane)
                    keep.insert(pane)
                    if let ref = agentSessionRef(for: pane) {
                        capturedPaneSessions[pane.value] = ref
                    }
                }
            }
        }
        // 误关栈里的 pane 的快照也要留着（⌘⇧T 恢复时回放）……虽然栈不跨重启，
        // 但保留无害；真正要清的是两边都不认识的孤儿。
        for record in recentlyClosed.records {
            switch record {
            case let .tab(_, tab, _, _): keep.formUnion(tab.rootSplit.leaves())
            case let .pane(_, _, pane, _, _, _): keep.insert(pane)
            }
        }
        ScrollbackStore.cleanup(keeping: keep)
    }

    /// 拖动重排 tab。
    func moveTab(_ id: TabID, toIndex: Int) {
        run(.moveTab(id: id, toIndex: toIndex))
    }

    /// ⌘Enter：把当前 pane 放大占满 tab，再按还原。
    func toggleZoom() {
        guard let active = activePane() else { return }
        let expanding = zoomedPane != active
        pendingAreaTransition = .zoom(expanding: expanding)
        zoomedPane = expanding ? active : nil
        rebuild()
    }

    /// 手动重命名 tab（空 = 清除，回到 cwd 自动标题）。
    func renameTab(_ id: TabID, to title: String) {
        guard let wsIndex = activeWorkspaceIndex(),
              let tabIndex = store.workspaces[wsIndex].tabs.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        store.workspaces[wsIndex].tabs[tabIndex].customTitle = trimmed.isEmpty ? nil : trimmed
        refreshWindowTitle()
        scheduleSave()
    }

    /// 窗口标题跟随「工作区 · 标签」，Mission Control / ⌘` 窗口切换器里一眼可辨。
    private func refreshWindowTitle() {
        guard let window else { return }
        var parts: [String] = []
        if let ws = activeWorkspace() { parts.append(ws.name) }
        if let tab = activeTabModel() {
            parts.append(tab.customTitle ?? (paneTitles[tab.activePane] ?? L("终端")))
        }
        let title = parts.isEmpty ? "Conductor" : parts.joined(separator: " · ")
        if window.title != title { window.title = title }
    }

    // MARK: - 通用动作（右键菜单等共用）

    /// 复制字符串到系统剪贴板（如 pane / 工作区路径）。
    func copyToClipboard(_ string: String) {
        guard !string.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }

    /// 在 Finder 中选中并显示某路径。
    func revealInFinder(_ path: String) {
        guard !path.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    // MARK: - 侧栏模式 ↔ 右侧上下文（工作区 / 文件夹各一套分屏数据）

    /// 文件夹模式的隐藏工作区 id：固定值，跨启动稳定（随 state.json 一起持久化）。
    static let folderContextID = WorkspaceID("w-folder-context")

    /// 常规工作区列表（不含文件夹模式的隐藏浏览上下文）。侧栏 / 命令面板用它。
    var visibleWorkspaces: [Workspace] {
        store.workspaces.filter { $0.id != Self.folderContextID }
    }

    private static let lastRegularWorkspaceKey = "sidebar.lastRegularWorkspace"

    /// 切换侧栏模式：左边换列表，右边整套标签/分屏跟着换上下文。
    /// 工作区 ↔ 文件夹来回切，各自的布局原样保留。
    func setSidebarListMode(_ mode: SidebarListMode) {
        guard mode != sidebarListMode else { return }
        sidebarListMode = mode
        switch mode {
        case .folders:
            if let current = store.activeWorkspace, current != Self.folderContextID {
                UserDefaults.standard.set(current.value, forKey: Self.lastRegularWorkspaceKey)
            }
            switchContext(to: ensureFolderContext())
        case .workspaces:
            switchContext(to: resolvedRegularWorkspace())
        }
    }

    /// 文件夹模式的浏览上下文（懒创建：首次切到文件夹模式才建，从家目录起一个标签）。
    private func ensureFolderContext() -> WorkspaceID {
        if store.workspaces.contains(where: { $0.id == Self.folderContextID }) {
            return Self.folderContextID
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let pane = PaneID(nextID("p"))
        let tab = Tab.single(id: TabID(nextID("t")), title: "zsh", pane: pane)
        let ws = Workspace(id: Self.folderContextID, name: L("文件夹"), path: home,
                           tabs: [tab], activeTab: tab.id)
        store.workspaces.append(ws)   // 不走 upsert：置 active 统一交给 switchContext
        registry.apply([.createSurface(pane: pane, cwd: home)])
        return Self.folderContextID
    }

    /// 切回工作区模式时的落点：上次离开的那个；没了就第一个常规工作区。
    private func resolvedRegularWorkspace() -> WorkspaceID? {
        if let saved = UserDefaults.standard.string(forKey: Self.lastRegularWorkspaceKey) {
            let id = WorkspaceID(saved)
            if id != Self.folderContextID, store.workspaces.contains(where: { $0.id == id }) {
                return id
            }
        }
        return visibleWorkspaces.first?.id
    }

    /// 真正执行右侧整套数据的切换（带轻微缩放转场，强调「换了一套」）。
    private func switchContext(to id: WorkspaceID?) {
        guard let id, store.activeWorkspace != id else { return }
        store.activeWorkspace = id
        pendingAreaTransition = .zoom(expanding: true)
        rebuild()
        scheduleSave()
    }

    /// 工作区变更后让侧栏模式跟上（通知/命令面板可能直接跳进另一套上下文）。
    private func syncListModeWithActiveWorkspace() {
        let mode: SidebarListMode = (store.activeWorkspace == Self.folderContextID) ? .folders : .workspaces
        if sidebarListMode != mode { sidebarListMode = mode }
        if mode == .workspaces, let id = store.activeWorkspace,
           UserDefaults.standard.string(forKey: Self.lastRegularWorkspaceKey) != id.value {
            UserDefaults.standard.set(id.value, forKey: Self.lastRegularWorkspaceKey)
        }
    }

    // MARK: - 工作区管理（直接改 store，与 add/selectWorkspace 一致）

    func renameWorkspace(_ id: WorkspaceID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let i = store.workspaces.firstIndex(where: { $0.id == id }) else { return }
        guard store.workspaces[i].name != trimmed else { return }
        store.workspaces[i].name = trimmed
        refreshWindowTitle()
        scheduleSave()
    }

    /// 删除工作区：释放它所有 pane 的 surface 再移除。保留至少一个常规工作区；
    /// 文件夹模式的隐藏上下文不可删。
    func removeWorkspace(_ id: WorkspaceID) {
        guard id != Self.folderContextID,
              visibleWorkspaces.count > 1,
              let ws = store.workspaces.first(where: { $0.id == id }) else { return }
        let panes = ws.tabs.flatMap { $0.rootSplit.leaves() }
        registry.apply(panes.map { .closeSurface(pane: $0) })
        store.remove(id)   // 若删的是 active，会切到第一个剩余工作区
        workspaceMetadata.forget(workspace: id)
        // 兜底：别让删除把人「切」进隐藏的文件夹上下文
        if store.activeWorkspace == Self.folderContextID, sidebarListMode == .workspaces {
            store.activeWorkspace = visibleWorkspaces.first?.id
        }
        rebuild()
        scheduleSave()
    }

    /// 拖动重排工作区（索引按可见列表算，隐藏的文件夹上下文固定排在末尾）。
    func moveWorkspace(_ id: WorkspaceID, toIndex: Int) {
        guard id != Self.folderContextID else { return }
        var visible = visibleWorkspaces
        let hidden = store.workspaces.filter { $0.id == Self.folderContextID }
        guard let from = visible.firstIndex(where: { $0.id == id }) else { return }
        let clamped = max(0, min(toIndex, visible.count - 1))
        guard clamped != from else { return }
        let moved = visible.remove(at: from)
        visible.insert(moved, at: clamped)
        store.workspaces = visible + hidden
        scheduleSave()
    }

    enum FocusDirection { case left, right, up, down }

    /// ⌘⌥方向键：按几何位置聚焦该方向最近的 pane（tmux 风）。
    /// 打分 = 主轴距离 + 3×横向偏移，偏好正对的邻居；该方向没有 pane 则原地不动。
    func focusDirectional(_ direction: FocusDirection) {
        guard let tab = activeTabModel(), let active = activePane(),
              let fromView = paneContainers[active], fromView.window != nil else { return }
        let leaves = Set(tab.rootSplit.leaves())
        let from = fromView.convert(fromView.bounds, to: nil)   // 窗口坐标系（y 向上）
        var best: PaneID?
        var bestScore = CGFloat.greatestFiniteMagnitude
        for (pane, container) in paneContainers {
            guard pane != active, leaves.contains(pane), container.window != nil else { continue }
            let frame = container.convert(container.bounds, to: nil)
            let dx = frame.midX - from.midX
            let dy = frame.midY - from.midY
            let primary: CGFloat
            let ortho: CGFloat
            switch direction {
            case .left: (primary, ortho) = (-dx, abs(dy))
            case .right: (primary, ortho) = (dx, abs(dy))
            case .up: (primary, ortho) = (dy, abs(dx))
            case .down: (primary, ortho) = (-dy, abs(dx))
            }
            guard primary > 1 else { continue }   // 必须确实位于那个方向
            let score = primary + ortho * 3
            if score < bestScore {
                bestScore = score
                best = pane
            }
        }
        if let best { focusOnly(best) }
    }

    /// 仅切换焦点：只更新活动 pane，不重建视图树，避免每次切焦点都卡一下。
    private func focusOnly(_ pane: PaneID) {
        guard let wsIndex = activeWorkspaceIndex(),
              let tabIndex = activeTabIndex(wsIndex: wsIndex),
              store.workspaces[wsIndex].tabs[tabIndex].rootSplit.contains(pane) else { return }
        store.workspaces[wsIndex].tabs[tabIndex].activePane = pane
        (registry.surface(for: pane) as? GhosttySurface)?.focus()
        refreshActiveRings()
        scheduleSave()
    }

    /// 将当前 tab 内所有分屏均分（n-way 等比例）。
    func equalizeSplits() {
        guard let wsIndex = activeWorkspaceIndex(),
              let tabIndex = activeTabIndex(wsIndex: wsIndex) else { return }
        let tab = store.workspaces[wsIndex].tabs[tabIndex]
        let normalized = tab.rootSplit.withAllRatiosEqualized()
        guard normalized != tab.rootSplit else { return }
        store.workspaces[wsIndex].tabs[tabIndex].rootSplit = normalized
        rebuild()
        scheduleSave()
    }

    // MARK: - 最近标签往返（⌃Tab）

    /// 当前/上一个看过的标签（可跨工作区）。rebuild 时更新，不持久化。
    private var tabVisitCurrent: (ws: WorkspaceID, tab: TabID)?
    private var tabVisitPrevious: (ws: WorkspaceID, tab: TabID)?

    /// rebuild 时记账：活动标签变了 → 旧的退为「上一个」。
    private func trackTabVisit(_ tab: TabID) {
        guard let wsID = store.activeWorkspace else { return }
        guard tabVisitCurrent?.ws != wsID || tabVisitCurrent?.tab != tab else { return }
        if let current = tabVisitCurrent { tabVisitPrevious = current }
        tabVisitCurrent = (ws: wsID, tab: tab)
    }

    /// ⌃Tab：跳回上一个看过的标签（跨工作区也行），再按一次跳回来。
    func toggleRecentTab() {
        guard let prev = tabVisitPrevious,
              let wsIndex = store.workspaces.firstIndex(where: { $0.id == prev.ws }),
              let tab = store.workspaces[wsIndex].tabs.first(where: { $0.id == prev.tab })
        else { return }
        if store.activeWorkspace != prev.ws {
            store.activeWorkspace = prev.ws
            syncListModeWithActiveWorkspace()
        }
        store.workspaces[wsIndex].activeTab = prev.tab
        registry.apply([.focusSurface(pane: tab.activePane)])
        rebuild()
        scheduleSave()
    }

    /// 循环切 tab。
    func cycleTab(forward: Bool) {
        guard let wsIndex = activeWorkspaceIndex(),
              let current = store.workspaces[wsIndex].activeTab else { return }
        let tabs = store.workspaces[wsIndex].tabs
        guard !tabs.isEmpty else { return }
        let ids = tabs.map(\.id)
        guard let idx = ids.firstIndex(of: current) else { return }
        let next = forward ? (idx + 1) % ids.count : (idx - 1 + ids.count) % ids.count
        run(.selectTab(ids[next]))
    }

    func selectTab(_ id: TabID) {
        guard let wsIndex = activeWorkspaceIndex(),
              let current = store.workspaces[wsIndex].activeTab,
              current != id,
              store.workspaces[wsIndex].tabs.contains(where: { $0.id == id })
        else { return }
        run(.selectTab(id))
    }

    func selectWorkspace(_ id: WorkspaceID) {
        guard let current = store.activeWorkspace,
              current != id,
              store.workspaces.contains(where: { $0.id == id })
        else { return }
        store.activeWorkspace = id
        syncListModeWithActiveWorkspace()
        rebuild()
        scheduleSave()
    }

    func addWorkspace(path: String) {
        let name = (path as NSString).lastPathComponent.isEmpty ? path : (path as NSString).lastPathComponent
        let pane = PaneID(nextID("p"))
        let tab = Tab.single(id: TabID(nextID("t")), title: "zsh", pane: pane)
        let ws = Workspace(id: WorkspaceID(nextID("w")), name: name, path: path, tabs: [tab], activeTab: tab.id)
        store.upsert(ws)   // 设为 active
        syncListModeWithActiveWorkspace()
        registry.apply([.createSurface(pane: pane, cwd: path), .focusSurface(pane: pane)])
        rebuild()
        scheduleSave()
    }

    // MARK: - 核心循环

    func run(_ command: WorkspaceCommand) {
        let effects = command.apply(to: &store)
        registry.apply(effects)
        // ⌘⇧T 恢复可能把 active 切到另一套上下文（工作区 ↔ 文件夹），侧栏模式跟上
        syncListModeWithActiveWorkspace()
        rebuild()
        scheduleSave()
    }

    /// 拖动分隔条时把新比例写回模型（不 rebuild，避免打断拖动）；持久化随之保存。
    private func updateSplitRatio(_ splitID: SplitID, _ ratio: Double) {
        guard let wsIndex = activeWorkspaceIndex(),
              let tabIndex = activeTabIndex(wsIndex: wsIndex) else { return }
        let current = store.workspaces[wsIndex].tabs[tabIndex].rootSplit
        let updated = current.updatingRatio(of: splitID, to: ratio)
        guard updated != current else { return }
        store.workspaces[wsIndex].tabs[tabIndex].rootSplit = updated
        scheduleSave()
    }

    /// 拖放重排：把 `moving` pane 移到 `target` pane 的某一侧。
    func movePane(_ moving: PaneID, relativeTo target: PaneID, edge: PaneDropEdge) {
        guard moving != target,
              let wsIndex = activeWorkspaceIndex(),
              let tabIndex = activeTabIndex(wsIndex: wsIndex) else { return }
        let tree = store.workspaces[wsIndex].tabs[tabIndex].rootSplit
        guard tree.contains(moving), tree.contains(target), let removed = tree.removing(moving) else { return }
        let axis: SplitAxis = (edge == .left || edge == .right) ? .vertical : .horizontal
        let newPaneFirst = (edge == .left || edge == .top)
        let newTree = removed.splitting(target, with: moving, axis: axis, ratio: 0.5,
                                        splitID: SplitID(nextID("s")), newPaneFirst: newPaneFirst)
        store.workspaces[wsIndex].tabs[tabIndex].rootSplit = newTree
        store.workspaces[wsIndex].tabs[tabIndex].activePane = moving
        rebuild()
        scheduleSave()
    }

    /// 点击某 pane：更新模型 active + 聚焦其终端 + 刷新焦点环（不整树 rebuild）。
    func markActive(_ pane: PaneID) {
        guard let wsIndex = activeWorkspaceIndex(),
              let tabIndex = activeTabIndex(wsIndex: wsIndex),
              store.workspaces[wsIndex].tabs[tabIndex].rootSplit.contains(pane) else { return }
        store.workspaces[wsIndex].tabs[tabIndex].activePane = pane
        (registry.surface(for: pane) as? GhosttySurface)?.focus()
        clearBlocked(pane)   // 人已经到场，这个 pane 不再「等你回复」
        refreshActiveRings()
        scheduleSave()
    }

    private func setPaneLabel(_ pane: PaneID, _ label: String) {
        let value = label.isEmpty ? L("终端") : label
        guard paneTitles[pane] != value else { return }
        paneTitles[pane] = value
        // 容器按 pane 常驻缓存，直接查表；不在屏上的也一并更新（切回来即正确）
        paneContainers[pane]?.setTitle(value)
        refreshWindowTitle()   // 活动标签若无自定义名，窗口标题跟着 shell 标题走
    }

    /// cwd 变化：更新标签 + 全路径 + git 分支（状态栏）。防抖 100ms，避免频繁 cd 时 SwiftUI 过载。
    private var cwdDebounceWorkItems: [PaneID: DispatchWorkItem] = [:]
    private func updatePaneCwd(_ pane: PaneID, _ path: String) {
        cwdDebounceWorkItems[pane]?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.paneCwds[pane] = path
                let branch = AppCoordinator.gitBranch(for: path)
                if self.paneBranches[pane] != branch { self.paneBranches[pane] = branch }
                self.setPaneLabel(pane, AppCoordinator.shortName(path))
            }
        }
        cwdDebounceWorkItems[pane] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: work)
    }

    /// 读 .git/HEAD（向上找）取当前分支；游离 HEAD 返回短 sha；非仓库返回 nil。
    static func gitBranch(for path: String) -> String? {
        var dir = URL(fileURLWithPath: path)
        for _ in 0..<30 {
            let head = dir.appendingPathComponent(".git/HEAD")
            if let content = try? String(contentsOf: head, encoding: .utf8) {
                let line = content.trimmingCharacters(in: .whitespacesAndNewlines)
                let prefix = "ref: refs/heads/"
                return line.hasPrefix(prefix) ? String(line.dropFirst(prefix.count)) : String(line.prefix(7))
            }
            let parent = dir.deletingLastPathComponent()
            if parent.path == dir.path { break }
            dir = parent
        }
        return nil
    }

    static func shortName(_ path: String) -> String {
        if path == NSHomeDirectory() { return "~" }
        let base = (path as NSString).lastPathComponent
        return base.isEmpty ? path : base
    }

    private func refreshActiveRings() {
        let active = activePane()
        // 每次切焦点都走：查字典即可，别递归整棵 AppKit 视图树
        for container in paneContainers.values {
            container.isActive = (container.paneID == active)
        }
    }

    private func handlePaneExited(_ pane: PaneID) {
        NSLog("[conductor] pane exited (child process gone): \(pane.value)")
        // 聚焦再关闭：聚焦用轻量路径避免 rebuild。
        focusOnly(pane)
        run(.closeActivePane)
    }

    private func rebuild() {
        containerView.subviews.forEach { $0.removeFromSuperview() }
        paneContainers = paneContainers.filter { registry.surface(for: $0.key) != nil }
        pruneDeadPaneState()
        guard let tab = activeTabModel() else {
            pendingAreaTransition = nil
            sweepUnseenDone(visible: [])
            refreshWindowTitle()
            return
        }
        sweepUnseenDone(visible: Set(tab.rootSplit.leaves()))
        trackTabVisit(tab.id)
        let active = self.activePane()
        // 放大态校验：被放大的 pane 不在当前 tab 了 → 取消放大。
        if let zp = zoomedPane, !tab.rootSplit.contains(zp) { zoomedPane = nil }
        // 头条「已放大」徽标跟随真实放大态（点击徽标可还原）。
        for (pane, container) in paneContainers { container.isZoomed = (pane == zoomedPane) }
        let multiPane = tab.rootSplit.leaves().count > 1

        let tree: NSView
        if let zp = zoomedPane, let zoomed = container(for: zp) {
            // 放大：只渲染该 pane，占满
            zoomed.isActive = true
            zoomed.canDrag = false
            tree = zoomed
        } else {
            tree = SplitTreeBuilder.build(
                tab.rootSplit,
                paneView: { [weak self] pane in
                    guard let self, let container = self.container(for: pane) else { return NSView() }
                    container.isActive = (pane == active)
                    container.canDrag = multiPane   // 仅多 pane 时允许拖拽重排
                    return container
                },
                onRatioChange: { [weak self] splitID, ratio in
                    self?.updateSplitRatio(splitID, ratio)
                }
            )
        }
        tree.frame = containerView.bounds
        tree.autoresizingMask = [.width, .height]
        containerView.addSubview(tree)
        tree.needsLayout = true
        tree.layoutSubtreeIfNeeded()
        if let transition = pendingAreaTransition {
            animateTerminalArea(tree, transition: transition)
            pendingAreaTransition = nil
        }
        // 新建的 pane 入场淡入
        for (pane, motion) in pendingEntrances { paneContainers[pane]?.animateEntrance(motion) }
        pendingEntrances.removeAll()
        refreshWindowTitle()   // 切工作区/标签、增删 tab 都经过 rebuild，标题在此跟上
        focusActivePane()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in self?.refreshVisibleSurfaces() }
    }

    private func animateTerminalArea(_ tree: NSView, transition: TerminalAreaTransition) {
        tree.wantsLayer = true
        guard let layer = tree.layer else { return }
        layer.removeAnimation(forKey: "terminalAreaTransition")

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let transformFrom: CATransform3D
        let opacityFrom: Float
        let duration: CFTimeInterval

        switch transition {
        case let .zoom(expanding):
            if reduceMotion {
                transformFrom = CATransform3DIdentity
                opacityFrom = 0.92
                duration = 0.12
            } else {
                let scale: CGFloat = expanding ? 0.93 : 1.035
                transformFrom = CATransform3DMakeAffineTransform(CGAffineTransform(scaleX: scale, y: scale))
                opacityFrom = expanding ? 0.78 : 0.88
                duration = expanding ? 0.26 : 0.2
            }
        }

        layer.opacity = 1
        layer.transform = CATransform3DIdentity

        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = opacityFrom
        fade.toValue = 1

        let transform = CABasicAnimation(keyPath: "transform")
        transform.fromValue = NSValue(caTransform3D: transformFrom)
        transform.toValue = NSValue(caTransform3D: CATransform3DIdentity)

        let group = CAAnimationGroup()
        group.animations = [fade, transform]
        group.duration = duration
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        group.isRemovedOnCompletion = true
        group.allowHighFrameRate()
        layer.add(group, forKey: "terminalAreaTransition")
    }

    /// 复用每个 pane 的容器（终端视图常驻其中），避免 reparent 活动 Metal 视图导致变白。
    private func container(for pane: PaneID) -> PaneContainerView? {
        if let existing = paneContainers[pane] { return existing }
        guard let surface = registry.surface(for: pane) as? GhosttySurface else { return nil }
        let container = PaneContainerView(paneID: pane, hostView: surface.hostView, title: paneTitles[pane] ?? L("终端"))
        container.onFocus = { [weak self] p in self?.markActive(p) }
        container.onMove = { [weak self] moving, target, edge in self?.movePane(moving, relativeTo: target, edge: edge) }
        container.onContextAction = { [weak self] action in
            guard let self else { return }
            markActive(pane)   // 先聚焦此 pane，命令作用于它
            let surface = registry.surface(for: pane) as? GhosttySurface
            switch action {
            case .copy: surface?.performAction("copy_to_clipboard")
            case .paste: surface?.performAction("paste_from_clipboard")
            case .selectAll: surface?.performAction("select_all")
            case .clear: surface?.performAction("clear_screen")
            case .splitRight: split(.vertical)
            case .splitDown: split(.horizontal)
            case .zoom: toggleZoom()
            case .copyCwd: copyToClipboard(paneCwds[pane] ?? activeWorkspace()?.path ?? "")
            case .openInFinder: revealInFinder(paneCwds[pane] ?? activeWorkspace()?.path ?? "")
            case .exportText: exportScrollback(pane)
            case .close: closeActivePane()
            }
        }
        container.agentItemsProvider = { [weak self] in
            (self?.launchableAgents ?? []).map { agent in
                let image = CLIToolLogo.image(named: agent.logo)?.copy() as? NSImage
                image?.size = NSSize(width: 15, height: 15)
                if CLIToolLogo.isMonochrome(agent.logo) { image?.isTemplate = true }
                return PaneAgentMenuItem(command: agent.command, title: agent.title, image: image)
            }
        }
        container.onLaunchAgent = { [weak self] command in self?.launchAgentInSplit(command: command, axis: .vertical) }
        container.sessionItemsProvider = { [weak self] in self?.sessionsForPane(pane) ?? [] }
        container.onResumeSession = { [weak self] record in self?.resumeSession(record, inPane: pane) }
        container.onManageSessions = { [weak self] in
            let dir = self?.paneCwds[pane] ?? self?.activeWorkspace()?.path
            self?.openSessionManager(scopePath: dir, targetPane: pane)
        }
        // 二次意见：让另一个 agent 分屏审查本 pane 的输出
        container.secondOpinionItemsProvider = { [weak self] in
            (self?.secondOpinionAgents(excluding: pane) ?? []).map { agent in
                let image = CLIToolLogo.image(named: agent.logo)?.copy() as? NSImage
                image?.size = NSSize(width: 15, height: 15)
                if CLIToolLogo.isMonochrome(agent.logo) { image?.isTemplate = true }
                return PaneAgentMenuItem(command: agent.command, title: agent.title, image: image)
            }
        }
        container.onSecondOpinion = { [weak self] command in
            self?.requestSecondOpinion(for: pane, reviewerCommand: command)
        }
        container.onManageQueue = { [weak self] in self?.openQueuePanel(for: pane) }
        surface.onRequestFocus = { [weak self] in self?.markActive(pane) }
        surface.onBeginPaneDrag = { [weak container] event in container?.beginPaneDrag(event) }
        surface.onCwdChange = { [weak self] url in self?.updatePaneCwd(pane, url.path) }
        surface.onScrollbar = { [weak container] total, offset, len in
            container?.updateScrollbar(total: total, offset: offset, len: len)
        }
        container.onScroll = { [weak surface] dy in surface?.scrollByPixels(dy) }
        // ⌘F 搜索条 ↔ libghostty 搜索动作
        container.onSearchQuery = { [weak surface] text in
            _ = surface?.performAction("search:" + text)
        }
        container.onSearchNavigate = { [weak surface] forward in
            _ = surface?.performAction(forward ? "navigate_search:next" : "navigate_search:previous")
        }
        container.onSearchEnded = { [weak surface] in
            _ = surface?.performAction("end_search")
            surface?.focus()
        }
        surface.onSearchStart = { [weak container] needle in
            container?.showSearch(initialNeedle: needle.isEmpty ? nil : needle)
        }
        surface.onSearchEnd = { [weak container] in container?.searchEndedExternally() }
        surface.onSearchTotal = { [weak container] total in container?.setSearchTotal(total) }
        surface.onSearchSelected = { [weak container] sel in container?.setSearchSelected(sel) }
        // 链接悬停：状态栏显示目标 URL（浏览器式）
        surface.onLinkHover = { [weak self] url in self?.hoveredLink = url }
        // OSC 9/99/777 通知 + OSC 9;4 进度：终端序列直达通知中枢/头条
        surface.onDesktopNotification = { [weak self] title, body in
            self?.handleDesktopNotification(pane, title: title, body: body)
        }
        surface.onProgressReport = { [weak self] state, percent in
            self?.applyProgressReport(pane, state: state, percent: percent)
        }
        container.setAgentLogo(agentLogoImage(for: paneAgents[pane]))
        container.setThinkingSince(thinkingStartTimes[pane])   // 已在思考的 pane，新容器直接亮表
        container.setAwaitingReply(blockedPanes[pane] != nil)
        container.setQueuedCount(paneQueues[pane]?.count ?? 0)
        container.setProgress(paneProgress[pane])
        paneContainers[pane] = container
        pendingEntrances[pane] = plannedEntrances.removeValue(forKey: pane) ?? .fade
        return container
    }

    private func refreshVisibleSurfaces() {
        guard let tab = activeTabModel() else { return }
        for pane in tab.rootSplit.leaves() {
            (registry.surface(for: pane) as? GhosttySurface)?.forceRedraw()
        }
    }

    private func focusActivePane() {
        guard let tab = activeTabModel(),
              let surface = registry.surface(for: tab.activePane) as? GhosttySurface else { return }
        window?.makeFirstResponder(surface.hostView)
        surface.focus()
    }

    // MARK: - helpers

    func nextID(_ prefix: String) -> String {
        "\(prefix)-\(UUID().uuidString)"
    }

    private func activeWorkspaceIndex() -> Int? {
        guard let id = store.activeWorkspace else { return nil }
        return store.workspaces.firstIndex { $0.id == id }
    }

    private func activeTabIndex(wsIndex: Int) -> Int? {
        guard let id = store.workspaces[wsIndex].activeTab else { return nil }
        return store.workspaces[wsIndex].tabs.firstIndex { $0.id == id }
    }

    private func activeWorkspace() -> Workspace? {
        guard let id = store.activeWorkspace else { return nil }
        return store.workspaces.first { $0.id == id }
    }

    private func activeTabModel() -> Tab? {
        guard let ws = activeWorkspace(), let tid = ws.activeTab else { return nil }
        return ws.tabs.first { $0.id == tid }
    }

    private func activePane() -> PaneID? { activeTabModel()?.activePane }
}
