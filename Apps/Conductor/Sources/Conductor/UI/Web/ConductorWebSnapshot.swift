import ConductorCore
import Foundation

struct ConductorWebSnapshot: Equatable {
    let tab: WorkspaceWebTabState?
    let otherTabs: [WorkspaceWebTabState]
    let navigationGeneration: Int
    let reloadGeneration: Int
    let stopGeneration: Int
    let backGeneration: Int
    let forwardGeneration: Int
    let addressFocusGeneration: Int
    let findFocusGeneration: Int
    let findNextGeneration: Int
    let findPreviousGeneration: Int

    @MainActor
    init(model: ConductorWindowModel) {
        let tab = model.selectedWorkspaceWebTab
        let selectedTabID = tab?.id
        self.tab = tab
        self.otherTabs = model.workspaceWebTabs.filter { other in
            guard other.url != nil else { return false }
            guard let selectedTabID else { return true }
            return other.id != selectedTabID
        }
        self.navigationGeneration = tab.map { model.workspaceWebTabNavigationGenerationByID[$0.id] ?? 0 } ?? 0
        self.reloadGeneration = tab.map { model.workspaceWebTabReloadGenerationByID[$0.id] ?? 0 } ?? 0
        self.stopGeneration = tab.map { model.workspaceWebTabStopGenerationByID[$0.id] ?? 0 } ?? 0
        self.backGeneration = tab.map { model.workspaceWebTabBackGenerationByID[$0.id] ?? 0 } ?? 0
        self.forwardGeneration = tab.map { model.workspaceWebTabForwardGenerationByID[$0.id] ?? 0 } ?? 0
        self.addressFocusGeneration = tab.map { model.workspaceWebAddressFocusGenerationByID[$0.id] ?? 0 } ?? 0
        self.findFocusGeneration = tab.map { model.workspaceWebFindFocusGenerationByID[$0.id] ?? 0 } ?? 0
        self.findNextGeneration = tab.map { model.workspaceWebFindNextGenerationByID[$0.id] ?? 0 } ?? 0
        self.findPreviousGeneration = tab.map { model.workspaceWebFindPreviousGenerationByID[$0.id] ?? 0 } ?? 0
    }
}
