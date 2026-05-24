import ConductorCore
import Foundation

struct ConductorWebSnapshot: Equatable {
    let tab: WorkspaceWebTabState?
    let navigationGeneration: Int
    let reloadGeneration: Int
    let stopGeneration: Int
    let backGeneration: Int
    let forwardGeneration: Int

    @MainActor
    init(model: ConductorWindowModel) {
        let tab = model.selectedWorkspaceWebTab
        self.tab = tab
        self.navigationGeneration = tab.map { model.workspaceWebTabNavigationGenerationByID[$0.id] ?? 0 } ?? 0
        self.reloadGeneration = tab.map { model.workspaceWebTabReloadGenerationByID[$0.id] ?? 0 } ?? 0
        self.stopGeneration = tab.map { model.workspaceWebTabStopGenerationByID[$0.id] ?? 0 } ?? 0
        self.backGeneration = tab.map { model.workspaceWebTabBackGenerationByID[$0.id] ?? 0 } ?? 0
        self.forwardGeneration = tab.map { model.workspaceWebTabForwardGenerationByID[$0.id] ?? 0 } ?? 0
    }
}
