import AppKit
import ConductorCore

@MainActor
extension AppCoordinator {
    func openTaskCards() {
        taskCardsPanel.show(coordinator: self, over: window)
    }

    func toggleTaskCards() {
        taskCardsPanel.toggle(coordinator: self, over: window)
    }

    /// 把任务牌甩到了某个终端 pane 上。无变量直接在该 pane 跑 + 收起面板；
    /// 有 {{变量}} 则发信号让仍开着的面板弹填值，填完在该 pane 跑。
    func handleTaskDrop(taskID: String, onPane paneID: PaneID) {
        guard let card = taskCardStore.cards.first(where: { $0.id == taskID }) else { return }
        if card.variableNames.isEmpty {
            runTaskCard(card, paneID: paneID)
            taskCardsPanel.hide()
        } else {
            taskCardStore.requestDropFill(cardID: taskID, paneID: paneID.value)
        }
    }

    /// 运行一张任务卡片 = 把它的意图打进一个终端，谁在那跑谁就执行（shell 当命令跑、agent 当 prompt）。
    /// - resolvedPrompt: 变量填好后的内容（nil 用卡片原文）。
    /// - paneID: 甩到的具体终端 pane。
    /// - inCurrentPane: 点牌时 = 当前活动终端。
    /// - workspaceID: 都没给时的兜底（在该工作区开新标签跑）。
    func runTaskCard(_ card: TaskCard,
                     resolvedPrompt: String? = nil,
                     workspaceID: String? = nil,
                     inCurrentPane: Bool = false,
                     paneID: PaneID? = nil) {
        let prompt = (resolvedPrompt ?? card.prompt).trimmingCharacters(in: .whitespacesAndNewlines)

        // 「让什么执行 = 甩给谁」：落到某个 pane（或当前终端）→ 直接打进那个终端。
        if let target = paneID ?? (inCurrentPane ? activeTabModel()?.activePane : nil) {
            guard paneExists(target) else {
                ToastHUD.shared.show(L("没有可用终端"), icon: "exclamationmark.triangle.fill", over: window)
                return
            }
            runShellLine(prompt, in: target)
            taskCardStore.markRan(card.id)
            ToastHUD.shared.show(L("已甩给 %@", taskRunnerLabel(for: target)), icon: "paperplane.fill", over: window)
            return
        }

        // 兜底：没有目标终端 → 在工作区开新标签跑（shell 命令 / agent prompt）。
        guard let workspace = resolveTaskCardWorkspace(id: workspaceID ?? card.workspaceID) else {
            ToastHUD.shared.show(L("没有可用工作区"), icon: "exclamationmark.triangle.fill", over: window)
            return
        }
        switch card.executor {
        case .shell:
            runShellTaskCard(card, prompt: prompt, in: workspace)
        case let .agent(agentID):
            runAgentTaskCard(card, prompt: prompt, agentID: agentID, in: workspace)
        }
    }

    private func resolveTaskCardWorkspace(id: String?) -> Workspace? {
        if let id,
           let workspace = visibleWorkspaces.first(where: { $0.id.value == id }) {
            return workspace
        }
        if let active = store.activeWorkspace,
           let workspace = visibleWorkspaces.first(where: { $0.id == active }) {
            return workspace
        }
        return visibleWorkspaces.first
    }

    private func runShellTaskCard(_ card: TaskCard, prompt: String, in workspace: Workspace) {
        if store.activeWorkspace != workspace.id {
            selectWorkspace(workspace.id)
        }
        let pane = PaneID(nextID("p"))
        run(.newTab(newTabID: TabID(nextID("t")), newPaneID: pane, cwd: workspace.path))

        if !prompt.isEmpty {
            (registry.surface(for: pane) as? GhosttySurface)?.enqueueCommand(prompt)
        }
        taskCardStore.markRan(card.id)
        ToastHUD.shared.show(L("任务已在 Shell 中执行"), icon: "terminal.fill", over: window)
    }

    private func runAgentTaskCard(_ card: TaskCard, prompt: String, agentID: String, in workspace: Workspace) {
        if store.activeWorkspace != workspace.id {
            selectWorkspace(workspace.id)
        }
        do {
            _ = try automationRunAgent(
                agent: agentID,
                command: nil,
                cwd: workspace.path,
                prompt: prompt,
                submit: true)
            taskCardStore.markRan(card.id)
            ToastHUD.shared.show(
                L("任务已交给 %@", taskCardAgentTitle(agentID)),
                icon: "sparkles",
                over: window)
        } catch {
            ToastHUD.shared.show(
                L("任务启动失败：%@", error.localizedDescription),
                icon: "exclamationmark.triangle.fill",
                over: window)
        }
    }

    private func taskCardAgentTitle(_ agentID: String) -> String {
        launchableAgents.first { $0.id == agentID }?.title
            ?? AgentCatalog.all.first { $0.id == agentID }?.name
            ?? agentID
    }
}
