struct ShellChromeSnapshot: Equatable, Sendable {
    let commandPaletteVisible: Bool
    let settingsPanelVisible: Bool
    let workspaceOverviewVisible: Bool

    @MainActor
    init(model: ConductorWindowModel) {
        self.commandPaletteVisible = model.commandPaletteVisible
        self.settingsPanelVisible = model.settingsPanelVisible
        self.workspaceOverviewVisible = model.workspaceOverviewVisible
    }
}
