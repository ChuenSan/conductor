import Foundation

struct PanelCoordinator: Equatable, Sendable {
    var commandPaletteVisible = false
    var settingsVisible = false
    var workspaceOverviewVisible = false
    var terminalSearchVisible = false

    mutating func toggleCommandPalette() {
        commandPaletteVisible.toggle()
        if commandPaletteVisible {
            settingsVisible = false
            workspaceOverviewVisible = false
            terminalSearchVisible = false
        }
    }

    mutating func toggleSettings() {
        settingsVisible.toggle()
        if settingsVisible {
            commandPaletteVisible = false
            workspaceOverviewVisible = false
            terminalSearchVisible = false
        }
    }

    mutating func toggleWorkspaceOverview() {
        workspaceOverviewVisible.toggle()
        if workspaceOverviewVisible {
            commandPaletteVisible = false
            settingsVisible = false
            terminalSearchVisible = false
        }
    }

    mutating func closeTransientPanels() {
        commandPaletteVisible = false
        settingsVisible = false
        workspaceOverviewVisible = false
        terminalSearchVisible = false
    }

    @discardableResult
    mutating func dismissVisibleShellPanel() -> Bool {
        guard commandPaletteVisible ||
            settingsVisible ||
            workspaceOverviewVisible ||
            terminalSearchVisible else {
            return false
        }
        closeTransientPanels()
        return true
    }
}
