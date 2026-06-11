import Foundation

/// 用户/键位触发的工作区命令。`apply` 是纯函数：修改 store（in-out），返回应用层要执行的副作用。
/// 所有"会发生什么"的逻辑集中在此并可单测；应用层只负责把 SessionEffect 翻译成真实终端操作。
public enum WorkspaceCommand {
    /// `cwd` 非空时新 tab 的 shell 在该目录启动，nil 回退工作区根目录。
    case newTab(newTabID: TabID, newPaneID: PaneID, cwd: String? = nil)
    /// `cwd` 非空时新 pane 在该目录起 shell（继承当前 pane 的目录），nil 回退工作区根目录。
    case split(axis: SplitAxis, newPaneID: PaneID, splitID: SplitID, cwd: String?)
    case closeActivePane
    case closeTab(TabID)
    case moveTab(id: TabID, toIndex: Int)
    case focusPane(PaneID)
    case selectTab(TabID)
    /// 恢复一个被关闭的 tab（误关恢复 / ⌘⇧T）。`workspaceID` 为 nil 或已不存在时进当前工作区。
    case restoreTab(tab: Tab, workspaceID: WorkspaceID?, paneCwds: [String: String])
    /// 把误关的单个 pane 以原方向分屏接回原 tab。要求 tab 仍存在（调用方负责回退成 restoreTab）。
    case restorePane(pane: PaneID, tabID: TabID, workspaceID: WorkspaceID, cwd: String?, axis: SplitAxis, splitID: SplitID)

    @discardableResult
    public func apply(to store: inout WorkspaceStore) -> [SessionEffect] {
        guard let wsIndex = activeWorkspaceIndex(in: store) else { return [] }
        let cwd = store.workspaces[wsIndex].path

        switch self {
        case let .newTab(newTabID, newPaneID, tabCwd):
            store.workspaces[wsIndex].addTab(
                Tab.single(id: newTabID, title: "zsh", pane: newPaneID)
            )
            return [.createSurface(pane: newPaneID, cwd: tabCwd ?? cwd), .focusSurface(pane: newPaneID)]

        case let .split(axis, newPaneID, splitID, paneCwd):
            guard let tabIndex = activeTabIndex(in: store, wsIndex: wsIndex) else { return [] }
            let target = store.workspaces[wsIndex].tabs[tabIndex].activePane
            store.workspaces[wsIndex].tabs[tabIndex].rootSplit =
                store.workspaces[wsIndex].tabs[tabIndex].rootSplit
                    .splitting(target, with: newPaneID, axis: axis, ratio: 0.5, splitID: splitID)
            store.workspaces[wsIndex].tabs[tabIndex].activePane = newPaneID
            return [.createSurface(pane: newPaneID, cwd: paneCwd ?? cwd), .focusSurface(pane: newPaneID)]

        case .closeActivePane:
            guard let tabIndex = activeTabIndex(in: store, wsIndex: wsIndex) else { return [] }
            let closing = store.workspaces[wsIndex].tabs[tabIndex].activePane
            if let newTree = store.workspaces[wsIndex].tabs[tabIndex].rootSplit.removing(closing) {
                store.workspaces[wsIndex].tabs[tabIndex].rootSplit = newTree
                let nextFocus = newTree.leaves().first ?? closing
                store.workspaces[wsIndex].tabs[tabIndex].activePane = nextFocus
                return [.closeSurface(pane: closing), .focusSurface(pane: nextFocus)]
            } else {
                // tab 内最后一个 pane：关掉整个 tab
                let tabID = store.workspaces[wsIndex].tabs[tabIndex].id
                store.workspaces[wsIndex].closeTab(tabID)
                var effects: [SessionEffect] = [.closeSurface(pane: closing)]
                if let newActiveTab = store.workspaces[wsIndex].activeTab,
                   let t = store.workspaces[wsIndex].tabs.first(where: { $0.id == newActiveTab }) {
                    effects.append(.focusSurface(pane: t.activePane))
                }
                return effects
            }

        case let .closeTab(tabID):
            // 关闭整个 tab：释放它所有 pane 的 surface，并把焦点交给回退后的 active tab。
            guard let tab = store.workspaces[wsIndex].tabs.first(where: { $0.id == tabID }) else { return [] }
            let panes = tab.rootSplit.leaves()
            store.workspaces[wsIndex].closeTab(tabID)
            var effects = panes.map { SessionEffect.closeSurface(pane: $0) }
            if let newActive = store.workspaces[wsIndex].activeTab,
               let t = store.workspaces[wsIndex].tabs.first(where: { $0.id == newActive }) {
                effects.append(.focusSurface(pane: t.activePane))
            }
            return effects

        case let .moveTab(tabID, toIndex):
            // 重排 tab，纯结构调整，无 surface 副作用。
            var tabs = store.workspaces[wsIndex].tabs
            guard let from = tabs.firstIndex(where: { $0.id == tabID }) else { return [] }
            let clamped = max(0, min(toIndex, tabs.count - 1))
            guard clamped != from else { return [] }
            let moved = tabs.remove(at: from)
            tabs.insert(moved, at: clamped)
            store.workspaces[wsIndex].tabs = tabs
            return []

        case let .focusPane(pane):
            guard let tabIndex = activeTabIndex(in: store, wsIndex: wsIndex),
                  store.workspaces[wsIndex].tabs[tabIndex].rootSplit.contains(pane) else { return [] }
            store.workspaces[wsIndex].tabs[tabIndex].activePane = pane
            return [.focusSurface(pane: pane)]

        case let .selectTab(tabID):
            guard store.workspaces[wsIndex].tabs.contains(where: { $0.id == tabID }) else { return [] }
            store.workspaces[wsIndex].activeTab = tabID
            if let t = store.workspaces[wsIndex].tabs.first(where: { $0.id == tabID }) {
                return [.focusSurface(pane: t.activePane)]
            }
            return []

        case let .restoreTab(tab, workspaceID, paneCwds):
            // 原工作区还在就回原处，否则进当前 active 工作区。
            let targetIndex = workspaceID
                .flatMap { id in store.workspaces.firstIndex(where: { $0.id == id }) } ?? wsIndex
            // 防御：记录里的 pane 不应出现在现有树里（弹栈保证只恢复一次），撞了就放弃。
            let incoming = Set(tab.rootSplit.leaves())
            let existing = store.workspaces.flatMap { $0.tabs.flatMap { $0.rootSplit.leaves() } }
            guard incoming.isDisjoint(with: existing) else { return [] }
            store.workspaces[targetIndex].addTab(tab)   // 同时设为 active tab
            store.activeWorkspace = store.workspaces[targetIndex].id
            let wsPath = store.workspaces[targetIndex].path
            var restoreEffects = tab.rootSplit.leaves().map {
                SessionEffect.createSurface(pane: $0, cwd: paneCwds[$0.value] ?? wsPath)
            }
            restoreEffects.append(.focusSurface(pane: tab.activePane))
            return restoreEffects

        case let .restorePane(pane, tabID, workspaceID, paneCwd, axis, splitID):
            guard let targetWs = store.workspaces.firstIndex(where: { $0.id == workspaceID }),
                  let tabIndex = store.workspaces[targetWs].tabs.firstIndex(where: { $0.id == tabID }),
                  !store.workspaces.contains(where: { $0.tabs.contains { $0.rootSplit.contains(pane) } })
            else { return [] }
            let anchor = store.workspaces[targetWs].tabs[tabIndex].activePane
            store.workspaces[targetWs].tabs[tabIndex].rootSplit =
                store.workspaces[targetWs].tabs[tabIndex].rootSplit
                    .splitting(anchor, with: pane, axis: axis, ratio: 0.5, splitID: splitID)
            store.workspaces[targetWs].tabs[tabIndex].activePane = pane
            store.workspaces[targetWs].activeTab = tabID
            store.activeWorkspace = workspaceID
            return [
                .createSurface(pane: pane, cwd: paneCwd ?? store.workspaces[targetWs].path),
                .focusSurface(pane: pane),
            ]
        }
    }

    private func activeWorkspaceIndex(in store: WorkspaceStore) -> Int? {
        guard let id = store.activeWorkspace else { return nil }
        return store.workspaces.firstIndex(where: { $0.id == id })
    }

    private func activeTabIndex(in store: WorkspaceStore, wsIndex: Int) -> Int? {
        guard let id = store.workspaces[wsIndex].activeTab else { return nil }
        return store.workspaces[wsIndex].tabs.firstIndex(where: { $0.id == id })
    }
}
