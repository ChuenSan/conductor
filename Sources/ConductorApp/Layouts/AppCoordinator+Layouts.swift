import AppKit
import ConductorCore

@MainActor
extension AppCoordinator {
    /// 把某工作区的现状存成命名布局：结构（标签/分屏树）+ 每 pane 的 cwd + 可恢复的 agent 会话。
    /// - startupCommands: 每个 pane（pane.value）复原时自动跑的命令（用户在"存为布局"里填）。
    @discardableResult
    func saveLayout(named name: String,
                    startupCommands: [String: String] = [:],
                    workspaceID: WorkspaceID? = nil) -> WorkspaceLayout? {
        let wsID = workspaceID ?? store.activeWorkspace
        guard let ws = store.workspaces.first(where: { $0.id == wsID }) else {
            ToastHUD.shared.show(L("没有可保存的工作区"), icon: "exclamationmark.triangle.fill", over: window)
            return nil
        }
        var panes: [String: LayoutPaneSpec] = [:]
        for tab in ws.tabs {
            for pane in tab.rootSplit.leaves() {
                var spec = LayoutPaneSpec()
                spec.cwd = paneCwds[pane]
                spec.session = sessionRefForPersistence(pane)   // 复用现有：hook 账本优先，否则按 cwd 定位
                let cmd = startupCommands[pane.value]?.trimmingCharacters(in: .whitespacesAndNewlines)
                spec.startupCommand = (cmd?.isEmpty ?? true) ? nil : cmd
                if !spec.isEmpty { panes[pane.value] = spec }
            }
        }
        let layout = WorkspaceLayout.fresh(
            name: name, tabs: ws.tabs, activeTab: ws.activeTab,
            panes: panes, sourcePath: ws.path)
        let saved = layoutStore.upsert(layout)
        ToastHUD.shared.show(L("已存为布局「%@」", saved.name), icon: "square.grid.2x2.fill", over: window)
        return saved
    }

    /// 给"存为布局"sheet 列出某工作区当前各 pane（标签标题 · 目录），让用户填启动命令。
    func layoutDraftPanes(for workspaceID: WorkspaceID?) -> [(pane: String, title: String, cwd: String)] {
        let wsID = workspaceID ?? store.activeWorkspace
        guard let ws = store.workspaces.first(where: { $0.id == wsID }) else { return [] }
        var rows: [(pane: String, title: String, cwd: String)] = []
        for tab in ws.tabs {
            let tabTitle = tab.customTitle ?? tab.title
            for pane in tab.rootSplit.leaves() {
                let cwd = paneCwds[pane].map { AppCoordinator.shortName($0) } ?? "~"
                rows.append((pane: pane.value, title: tabTitle, cwd: cwd))
            }
        }
        return rows
    }

    /// 复原布局到当前工作区：重建标签/分屏（重映射 pane/split id 避免撞车）→ 逐 pane cd →
    /// 有会话则续聊，否则跑该 pane 的启动命令。
    func restoreLayout(_ layout: WorkspaceLayout) {
        guard let wsID = store.activeWorkspace,
              let ws = store.workspaces.first(where: { $0.id == wsID }) else {
            ToastHUD.shared.show(L("没有可用工作区"), icon: "exclamationmark.triangle.fill", over: window)
            return
        }
        let wsPath = ws.path
        var lastTab: TabID?
        var restoredActiveTab: TabID?
        for layoutTab in layout.tabs {
            var paneMap: [PaneID: PaneID] = [:]
            let newRoot = remappedTree(layoutTab.rootSplit, paneMap: &paneMap)
            let newActive = paneMap[layoutTab.activePane] ?? newRoot.leaves().first ?? PaneID(nextID("p"))
            let newTabID = TabID(nextID("t"))
            let newTab = ConductorCore.Tab(
                id: newTabID, title: layoutTab.title,
                rootSplit: newRoot, activePane: newActive, customTitle: layoutTab.customTitle)
            if layout.activeTab == layoutTab.id {
                restoredActiveTab = newTabID
            }

            var cwds: [String: String] = [:]
            var primeMap: [PaneID: String] = [:]
            for (oldPane, newPane) in paneMap {
                let cwd = CwdResolver.resolve(
                    cwd: layout.panes[oldPane.value]?.cwd ?? wsPath, workspacePath: wsPath)
                cwds[newPane.value] = cwd
                primeMap[newPane] = cwd
            }
            primeRestoredPanes(primeMap)
            run(.restoreTab(tab: newTab, workspaceID: wsID, paneCwds: cwds))

            for (oldPane, newPane) in paneMap {
                let spec = layout.panes[oldPane.value]
                if let session = spec?.session, stageSessionRestore(session, for: newPane) { continue }
                if let cmd = spec?.startupCommand?.trimmingCharacters(in: .whitespacesAndNewlines), !cmd.isEmpty {
                    (registry.surface(for: newPane) as? GhosttySurface)?.enqueueCommand(cmd)
                }
            }
            lastTab = newTab.id
        }
        if let targetTab = restoredActiveTab ?? lastTab {
            selectTab(targetTab)
        }
        ToastHUD.shared.show(L("已复原布局「%@」", layout.name), icon: "square.grid.2x2.fill", over: window)
    }

    /// 深拷分屏树，所有 pane/split 换成新 id；返回 old→new 的 pane 映射。
    private func remappedTree(_ node: SplitNode, paneMap: inout [PaneID: PaneID]) -> SplitNode {
        switch node {
        case let .leaf(pane):
            let newPane = PaneID(nextID("p"))
            paneMap[pane] = newPane
            return .leaf(newPane)
        case let .split(_, axis, ratio, first, second):
            return .split(
                id: SplitID(nextID("s")), axis: axis, ratio: ratio,
                first: remappedTree(first, paneMap: &paneMap),
                second: remappedTree(second, paneMap: &paneMap))
        }
    }
}
