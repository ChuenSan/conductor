import AppKit
import Combine
import CmuxCore

private enum TerminalAreaTransition: Equatable {
    case horizontal(direction: CGFloat)
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
    /// 工具面板当前选中的分段。
    @Published var toolsTab: ToolsTab = .cli
    /// Codex 用量监视器（状态栏常驻配额条 + 周期刷新）。
    let usageMonitor = UsageMonitor()
    /// CLI hook 收件箱监听（agent 完成 → 系统通知）。
    private let hooksInbox = HooksInbox()
    /// 已检测到、可一键启动的 CLI（供 pane 右键「新建终端运行」子菜单使用）。
    @Published private(set) var launchableAgents: [LaunchableAgent] = []
    /// 每个 pane 当前在跑的 Agent（agent id）。空表示只是普通 shell。用于 pane 头条 / tab 显示 logo。
    @Published private(set) var paneAgents: [PaneID: String] = [:]
    private var agentPollTimer: Timer?
    /// 命令面板（懒创建）。
    private lazy var commandPalette = CommandPaletteController(coordinator: self)
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
            .appendingPathComponent("cmux", isDirectory: true)
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        stateStore = StateStore(fileURL: appSupport.appendingPathComponent("state.json"))

        registry = SessionRegistry(
            factory: { [weak self] pane in
                let surface = GhosttySurface()
                // 内容恢复：这个 pane 有待回放快照 → 带上，attach 时回放。
                if let file = self?.pendingRestoreFiles.removeValue(forKey: pane) {
                    surface.restoreContentFile = file
                }
                return surface
            },
            onPaneExited: { [weak self] pane in self?.handlePaneExited(pane) }
        )
        restoreOrSeed(rootCwd: rootCwd)
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
            AppCommand(id: "focusNextPane", title: L("聚焦下一面板"), defaultKeybinding: "cmd+alt+right") { [weak self] in self?.focusNext() },
            AppCommand(id: "focusPrevPane", title: L("聚焦上一面板"), defaultKeybinding: "cmd+alt+left") { [weak self] in self?.focusPrev() },
            AppCommand(id: "increaseFontSize", title: L("放大字号"), defaultKeybinding: "cmd+=") { [weak self] in self?.adjustFontSize(1) },
            AppCommand(id: "decreaseFontSize", title: L("缩小字号"), defaultKeybinding: "cmd+-") { [weak self] in self?.adjustFontSize(-1) },
            AppCommand(id: "resetFontSize", title: L("复位字号"), defaultKeybinding: "cmd+0") { [weak self] in self?.resetFontSize() },
            AppCommand(id: "openSettings", title: L("打开设置"), defaultKeybinding: "cmd+,") { [weak self] in self?.openSettings() },
            AppCommand(id: "toggleZoom", title: L("放大/还原面板"), defaultKeybinding: "cmd+enter") { [weak self] in self?.toggleZoom() },
            AppCommand(id: "commandPalette", title: L("命令面板"), defaultKeybinding: "cmd+k") { [weak self] in self?.openCommandPalette() },
        ])
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

    /// 命令面板的条目：命令表 + 工作区 + 当前工作区的标签。
    private func paletteItems() -> [PaletteItem] {
        var items: [PaletteItem] = []
        for c in commandRegistry.commands where c.id != "commandPalette" {
            let kb = commandRegistry.effectiveKeybinding(for: c.id) ?? ""
            items.append(PaletteItem(id: "cmd:\(c.id)", icon: "command", title: c.title, subtitle: kb, run: c.run))
        }
        for ws in store.workspaces {
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
        return items
    }

    func openSettings() {
        cliToolsPresentation.close()
        sessionPresentation.close()
        settingsPresentation.open()
    }

    func closeSettings() {
        settingsPresentation.close()
    }

    /// 是否有右侧侧栏面板（设置 / CLI 工具 / 会话）正在展示。用于让快捷操作面板让位。
    var isSidePanelPresented: Bool {
        settingsPresentation.isPresented || cliToolsPresentation.isPresented || sessionPresentation.isPresented
    }

    func openCLITools() {
        settingsPresentation.close()
        sessionPresentation.close()
        cliToolsPresentation.open()
    }

    /// 打开工具面板到指定分段。
    func openTools(_ tab: ToolsTab) {
        toolsTab = tab
        settingsPresentation.close()
        sessionPresentation.close()
        cliToolsPresentation.open()
    }

    /// 打开 Agent 会话管理面板。`scopePath` 限定目录范围；`targetPane` 供「当前面板续聊」使用。
    func openSessionManager(scopePath: String? = nil, targetPane: PaneID? = nil) {
        sessionScopePath = scopePath
        sessionTargetPane = targetPane ?? activePane()
        settingsPresentation.close()
        cliToolsPresentation.close()
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
        run(.newTab(newTabID: TabID(nextID("t")), newPaneID: paneID))
        if let cwd = record.cwd { paneCwds[paneID] = cwd }
        (registry.surface(for: paneID) as? GhosttySurface)?
            .enqueueCommand(resumeCommand(command, pane: paneID))
        tagPaneAgentOptimistically(paneID, command: record.agent == "codex" ? "codex" : "claude")
        closeSessionManager()
    }

    private func resumeCommand(_ command: String, pane: PaneID) -> String {
        "CMUX_PANE_ID=\(pane.value) \(command)"
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
            let tab = CmuxCore.Tab.single(id: TabID(nextID("t")), title: "zsh", pane: PaneID(nextID("p")))
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
        let tab = CmuxCore.Tab.single(id: TabID(nextID("t")), title: "zsh", pane: pane)
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
        prewarmUsageReport()
        SessionManagerStore.shared.refresh()
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
            self?.focusPane(byID: paneID)
        }
        hooksInbox.onEvent = { [weak self] event in
            self?.handleHookEvent(event)
        }
        hooksInbox.start()
    }

    private func handleHookEvent(_ event: HookEvent) {
        // 通知标题尽量带上 pane 标题/工作区，方便辨认是哪个会话。
        var title = event.title
        if let paneID = event.paneID.map({ PaneID($0) }), let paneTitle = paneTitles[paneID] {
            title = "\(event.title) · \(paneTitle)"
        }
        NotificationManager.shared.notify(paneID: event.paneID, title: title, body: event.message)
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
            await MainActor.run { self?.applyPaneAgents(map) }
        }
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
            setLaunchableAgents(cache.tools.filter(\.isInstalled).map {
                LaunchableAgent(
                    id: $0.id, title: $0.name, command: $0.id,
                    logo: $0.logo, fallbackSystemImage: $0.fallbackSystemImage)
            })
            return
        }
        Task { [weak self] in
            let tools = await Task.detached(priority: .utility) { () -> [CLIToolStatus] in
                LoginShellPathCache.shared.captureOnce()
                _ = LoginShellPathCache.shared.currentOrCapture()
                return AgentCatalog.all.map { agent in
                    let path = agent.resolveBinary()
                    return CLIToolStatus(
                        id: agent.id, name: agent.name,
                        logo: agent.logo, fallbackSystemImage: agent.fallbackSystemImage,
                        path: path, version: path != nil ? agent.readVersion() : nil)
                }
            }.value
            CLIDetectionStore.save(tools)
            await MainActor.run {
                self?.setLaunchableAgents(tools.filter(\.isInstalled).map {
                    LaunchableAgent(
                        id: $0.id, title: $0.name, command: $0.id,
                        logo: $0.logo, fallbackSystemImage: $0.fallbackSystemImage)
                })
            }
        }
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
        NSLog("[cmux] 配置已热更新")
    }

    /// 设置面板改配置：内存即时更新 + 应用终端/外壳/键位 + 落盘到 config.yaml。
    func applyConfig(_ new: AppConfig) {
        ConfigStore.shared.set(new)
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
        if let override = fontSizeOverride { c.appearance.font.size = override }
        return c.validated()
    }

    func adjustFontSize(_ delta: Int) {
        let base = fontSizeOverride ?? ConfigStore.shared.config.appearance.font.size
        fontSizeOverride = min(max(base + delta, 6), 72)
        applyTerminalAppearance(effectiveConfig())
    }

    func resetFontSize() {
        guard fontSizeOverride != nil else { return }
        fontSizeOverride = nil
        applyTerminalAppearance(effectiveConfig())
    }

    // MARK: - 命令入口（键位调用）

    func newTab() {
        run(.newTab(newTabID: TabID(nextID("t")), newPaneID: PaneID(nextID("p"))))
    }

    /// 一键启动 Agent：新开一个标签页，待 shell 就绪后自动执行 `command`（如 `codex`）。
    func launchAgent(command: String) {
        let paneID = PaneID(nextID("p"))
        run(.newTab(newTabID: TabID(nextID("t")), newPaneID: paneID))
        (registry.surface(for: paneID) as? GhosttySurface)?.enqueueCommand(launchCommand(command, pane: paneID))
        tagPaneAgentOptimistically(paneID, command: command)
    }

    /// 在当前 tab 内分屏启动 Agent。
    func launchAgentInSplit(command: String, axis: SplitAxis) {
        let paneID = PaneID(nextID("p"))
        plannedEntrances[paneID] = .split(axis: axis)
        run(.split(axis: axis, newPaneID: paneID, splitID: SplitID(nextID("s")), cwd: inheritableCwd()))
        (registry.surface(for: paneID) as? GhosttySurface)?.enqueueCommand(launchCommand(command, pane: paneID))
        tagPaneAgentOptimistically(paneID, command: command)
    }

    /// 给启动命令注入 `CMUX_PANE_ID`，让 agent 的 hook 知道是哪个 pane（用于通知点击跳转）。
    private func launchCommand(_ command: String, pane: PaneID) -> String {
        "CMUX_PANE_ID=\(pane.value) \(command)"
    }

    /// 启动后立即按命令乐观标记 pane 的 agent，让 logo 即时出现（轮询随后会校正/清除）。
    private func tagPaneAgentOptimistically(_ pane: PaneID, command: String) {
        guard let agentID = AgentCatalog.all.first(where: { $0.command == command })?.id else { return }
        var map = paneAgents
        map[pane] = agentID
        applyPaneAgents(map)
    }

    /// 由 CLI 检测面板回填可启动的 Agent 列表（带 logo），供右键菜单复用。
    func setLaunchableAgents(_ agents: [LaunchableAgent]) {
        launchableAgents = agents
    }

    func split(_ axis: SplitAxis) {
        let paneID = PaneID(nextID("p"))
        plannedEntrances[paneID] = .split(axis: axis)
        run(.split(axis: axis, newPaneID: paneID, splitID: SplitID(nextID("s")), cwd: inheritableCwd()))
    }

    /// 分屏新 pane 继承当前 pane 的目录（目录已不存在则回退工作区根/家目录）。
    private func inheritableCwd() -> String? {
        guard let cwd = activeCwd else { return nil }
        return CwdResolver.resolve(cwd: cwd, workspacePath: activeWorkspace()?.path ?? cwd)
    }

    func closeActivePane() {
        pushClosedRecordForActivePane()
        run(.closeActivePane)
    }

    /// 关闭整个 tab（含其所有 pane）。可关非 active 的 tab。
    func closeTab(_ id: TabID) {
        pushClosedTabRecord(id)
        run(.closeTab(id))
    }

    // MARK: - 误关恢复（⌘⇧T）

    /// 关 tab 前快照：完整分屏树 + 每个 pane 的 cwd + 终端内容 + agent 会话。
    private func pushClosedTabRecord(_ id: TabID) {
        guard let wsIndex = activeWorkspaceIndex(),
              let tab = store.workspaces[wsIndex].tabs.first(where: { $0.id == id }) else { return }
        for pane in tab.rootSplit.leaves() { captureScrollback(pane) }
        recentlyClosed.push(.tab(
            workspaceID: store.workspaces[wsIndex].id, tab: tab,
            paneCwds: capturedCwds(tab), paneSessions: capturedSessions(tab)))
    }

    /// 趁 surface 还活着，把 pane 的屏幕+回滚文本快照到盘（恢复时回放）。
    private func captureScrollback(_ pane: PaneID) {
        guard let surface = registry.surface(for: pane) as? GhosttySurface,
              let text = surface.readAllText() else { return }
        ScrollbackStore.save(text, for: pane)
    }

    /// 关 pane 前快照：tab 内最后一个 pane 时整 tab 入栈，否则记单 pane（含原分屏方向）。
    private func pushClosedRecordForActivePane() {
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

    private func capturedCwds(_ tab: CmuxCore.Tab) -> [String: String] {
        var map: [String: String] = [:]
        for pane in tab.rootSplit.leaves() {
            if let cwd = paneCwds[pane] { map[pane.value] = cwd }
        }
        return map
    }

    private func capturedSessions(_ tab: CmuxCore.Tab) -> [String: AgentSessionRef] {
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
                let tab = CmuxCore.Tab.single(id: TabID(nextID("t")), title: "zsh", pane: pane)
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
        zoomedPane = (zoomedPane == active) ? nil : active
        rebuild()
    }

    /// 手动重命名 tab（空 = 清除，回到 cwd 自动标题）。
    func renameTab(_ id: TabID, to title: String) {
        guard let wsIndex = activeWorkspaceIndex(),
              let tabIndex = store.workspaces[wsIndex].tabs.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        store.workspaces[wsIndex].tabs[tabIndex].customTitle = trimmed.isEmpty ? nil : trimmed
        scheduleSave()
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

    // MARK: - 工作区管理（直接改 store，与 add/selectWorkspace 一致）

    func renameWorkspace(_ id: WorkspaceID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let i = store.workspaces.firstIndex(where: { $0.id == id }) else { return }
        guard store.workspaces[i].name != trimmed else { return }
        store.workspaces[i].name = trimmed
        scheduleSave()
    }

    /// 删除工作区：释放它所有 pane 的 surface 再移除。保留至少一个工作区。
    func removeWorkspace(_ id: WorkspaceID) {
        guard store.workspaces.count > 1,
              let ws = store.workspaces.first(where: { $0.id == id }) else { return }
        let panes = ws.tabs.flatMap { $0.rootSplit.leaves() }
        registry.apply(panes.map { .closeSurface(pane: $0) })
        store.remove(id)   // 若删的是 active，会切到第一个剩余工作区
        rebuild()
        scheduleSave()
    }

    /// 拖动重排工作区。
    func moveWorkspace(_ id: WorkspaceID, toIndex: Int) {
        guard let from = store.workspaces.firstIndex(where: { $0.id == id }) else { return }
        let clamped = max(0, min(toIndex, store.workspaces.count - 1))
        guard clamped != from else { return }
        let moved = store.workspaces.remove(at: from)
        store.workspaces.insert(moved, at: clamped)
        scheduleSave()
    }

    func focusNext() {
        guard let pane = activePane(), let tree = activeTree(), let next = tree.pane(after: pane) else { return }
        run(.focusPane(next))
    }

    func focusPrev() {
        guard let pane = activePane(), let tree = activeTree(), let prev = tree.pane(before: pane) else { return }
        run(.focusPane(prev))
    }

    func selectTab(_ id: TabID) {
        guard let wsIndex = activeWorkspaceIndex(),
              let current = store.workspaces[wsIndex].activeTab,
              current != id,
              let from = store.workspaces[wsIndex].tabs.firstIndex(where: { $0.id == current }),
              let to = store.workspaces[wsIndex].tabs.firstIndex(where: { $0.id == id })
        else { return }
        pendingAreaTransition = .horizontal(direction: to > from ? 1 : -1)
        run(.selectTab(id))
    }

    func selectWorkspace(_ id: WorkspaceID) {
        guard let current = store.activeWorkspace,
              current != id,
              let from = store.workspaces.firstIndex(where: { $0.id == current }),
              let to = store.workspaces.firstIndex(where: { $0.id == id })
        else { return }
        pendingAreaTransition = .horizontal(direction: to > from ? 1 : -1)
        store.activeWorkspace = id
        rebuild()
        scheduleSave()
    }

    func addWorkspace(path: String) {
        let name = (path as NSString).lastPathComponent.isEmpty ? path : (path as NSString).lastPathComponent
        let pane = PaneID(nextID("p"))
        let tab = Tab.single(id: TabID(nextID("t")), title: "zsh", pane: pane)
        let ws = Workspace(id: WorkspaceID(nextID("w")), name: name, path: path, tabs: [tab], activeTab: tab.id)
        store.upsert(ws)   // 设为 active
        registry.apply([.createSurface(pane: pane, cwd: path), .focusSurface(pane: pane)])
        rebuild()
        scheduleSave()
    }

    // MARK: - 核心循环

    func run(_ command: WorkspaceCommand) {
        let effects = command.apply(to: &store)
        registry.apply(effects)
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
        refreshActiveRings()
        scheduleSave()
    }

    private func setPaneLabel(_ pane: PaneID, _ label: String) {
        let value = label.isEmpty ? L("终端") : label
        guard paneTitles[pane] != value else { return }
        paneTitles[pane] = value
        func walk(_ view: NSView) {
            if let container = view as? PaneContainerView, container.paneID == pane { container.setTitle(value) }
            view.subviews.forEach(walk)
        }
        containerView.subviews.forEach(walk)
    }

    /// cwd 变化：更新标签 + 全路径 + git 分支（状态栏）。
    private func updatePaneCwd(_ pane: PaneID, _ path: String) {
        paneCwds[pane] = path
        let branch = AppCoordinator.gitBranch(for: path)
        if paneBranches[pane] != branch { paneBranches[pane] = branch }
        setPaneLabel(pane, AppCoordinator.shortName(path))
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
        func walk(_ view: NSView) {
            if let container = view as? PaneContainerView { container.isActive = (container.paneID == active) }
            view.subviews.forEach(walk)
        }
        containerView.subviews.forEach(walk)
    }

    private func handlePaneExited(_ pane: PaneID) {
        NSLog("[cmux] pane exited (child process gone): \(pane.value)")
        // v1：聚焦再关闭（在 active tab 内退出时正确；跨 tab 退出留待后续）。
        run(.focusPane(pane))
        run(.closeActivePane)
    }

    private func rebuild() {
        containerView.subviews.forEach { $0.removeFromSuperview() }
        paneContainers = paneContainers.filter { registry.surface(for: $0.key) != nil }
        guard let tab = activeTabModel() else {
            pendingAreaTransition = nil
            return
        }
        let active = self.activePane()
        // 放大态校验：被放大的 pane 不在当前 tab 了 → 取消放大。
        if let zp = zoomedPane, !tab.rootSplit.contains(zp) { zoomedPane = nil }
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
        if let transition = pendingAreaTransition {
            animateTerminalArea(tree, transition: transition)
            pendingAreaTransition = nil
        }
        // 新建的 pane 入场淡入
        for (pane, motion) in pendingEntrances { paneContainers[pane]?.animateEntrance(motion) }
        pendingEntrances.removeAll()
        focusActivePane()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in self?.refreshVisibleSurfaces() }
    }

    private func animateTerminalArea(_ tree: NSView, transition: TerminalAreaTransition) {
        tree.wantsLayer = true
        guard let layer = tree.layer else { return }
        layer.removeAnimation(forKey: "terminalAreaTransition")

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let distance = min(max(containerView.bounds.width * 0.075, 28), 92)
        let transformFrom: CATransform3D
        let duration: CFTimeInterval

        switch transition {
        case let .horizontal(direction):
            if reduceMotion {
                transformFrom = CATransform3DIdentity
                duration = 0.12
            } else {
                let offset = distance * direction
                let t = CGAffineTransform(translationX: offset, y: 0).scaledBy(x: 0.985, y: 0.985)
                transformFrom = CATransform3DMakeAffineTransform(t)
                duration = 0.24
            }
        }

        layer.opacity = 1
        layer.transform = CATransform3DIdentity

        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = reduceMotion ? 0.92 : 0.72
        fade.toValue = 1

        let transform = CABasicAnimation(keyPath: "transform")
        transform.fromValue = NSValue(caTransform3D: transformFrom)
        transform.toValue = NSValue(caTransform3D: CATransform3DIdentity)

        let group = CAAnimationGroup()
        group.animations = [fade, transform]
        group.duration = duration
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        group.isRemovedOnCompletion = true
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
        surface.onRequestFocus = { [weak self] in self?.markActive(pane) }
        surface.onBeginPaneDrag = { [weak container] event in container?.beginPaneDrag(event) }
        surface.onCwdChange = { [weak self] url in self?.updatePaneCwd(pane, url.path) }
        surface.onScrollbar = { [weak container] total, offset, len in
            container?.updateScrollbar(total: total, offset: offset, len: len)
        }
        container.onScroll = { [weak surface] dy in surface?.scrollByPixels(dy) }
        container.setAgentLogo(agentLogoImage(for: paneAgents[pane]))
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

    private func nextID(_ prefix: String) -> String {
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

    private func activeTree() -> SplitNode? { activeTabModel()?.rootSplit }
    private func activePane() -> PaneID? { activeTabModel()?.activePane }
}
