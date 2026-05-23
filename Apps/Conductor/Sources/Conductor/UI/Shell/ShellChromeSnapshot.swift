import ConductorCore
import Foundation

struct ShellChromeSnapshot: Equatable, Sendable {
    let selectedWorkspaceID: WorkspaceID
    let selectedTerminalCount: Int
    let commandPaletteVisible: Bool
    let settingsPanelVisible: Bool
    let workspaceOverviewVisible: Bool
    let notificationPanelVisible: Bool

    @MainActor
    init(model: ConductorWindowModel) {
        RenderCounter.increment("shell-chrome-snapshot")
        self.selectedWorkspaceID = model.workspace.id
        self.selectedTerminalCount = model.workspace.panes.values.reduce(0) { $0 + $1.tabs.count }
        self.commandPaletteVisible = model.commandPaletteVisible
        self.settingsPanelVisible = model.settingsPanelVisible
        self.workspaceOverviewVisible = model.workspaceOverviewVisible
        self.notificationPanelVisible = model.notificationPanelVisible
    }
}
