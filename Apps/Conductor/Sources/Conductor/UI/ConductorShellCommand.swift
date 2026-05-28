import AppKit
import ConductorCore
import Foundation

@MainActor
enum ConductorShellCommand: String, CaseIterable {
    case newWorkspace
    case newTerminal
    case newWebTab
    case focusWebAddress
    case reloadSelectedWebTab
    case openSelectedWebTabExternally
    case copySelectedWebTabURL
    case copySelectedWebTabReference
    case closeSelectedTab
    case closeOtherTabs
    case closeTabsToRight
    case closeFocusedPane
    case splitRight
    case splitDown
    case selectNextTab
    case selectPreviousTab
    case focusNextPane
    case focusPreviousPane
    case focusPaneLeft
    case focusPaneRight
    case focusPaneUp
    case focusPaneDown
    case resizePaneLeft
    case resizePaneRight
    case resizePaneUp
    case resizePaneDown
    case equalizeSplits
    case toggleZoom
    case moveTabLeft
    case moveTabRight
    case moveTabToNextPane
    case moveTabToNewRightSplit
    case moveTabToNewDownSplit
    case toggleCommandPalette
    case toggleWorkspaceOverview
    case toggleSettings
    case toggleFileManager
    case toggleFullScreen
    case resetWorkspace
    case showTerminalSearch
    case findNext
    case findPrevious
    case flashFocusedPane
    case duplicateSelectedTab
    case newTerminalAtFocusedDirectory
    case openFocusedDirectory
    case copyFocusedDirectory
    case duplicateWorkspace
    case closeCurrentWorkspace

    var allowsWhenSettingsPanelVisible: Bool {
        switch self {
        case .toggleSettings:
            true
        default:
            false
        }
    }

    var signpostName: StaticString {
        switch self {
        case .newWorkspace:
            return "command-new-workspace"
        case .newTerminal, .newTerminalAtFocusedDirectory:
            return "command-new-terminal"
        case .newWebTab:
            return "command-new-web-tab"
        case .focusWebAddress, .reloadSelectedWebTab, .openSelectedWebTabExternally, .copySelectedWebTabURL, .copySelectedWebTabReference:
            return "command-web-tab"
        case .closeSelectedTab, .closeOtherTabs, .closeTabsToRight:
            return "command-close-tab"
        case .closeFocusedPane:
            return "command-close-pane"
        case .splitRight, .splitDown:
            return "command-split"
        case .selectNextTab, .selectPreviousTab:
            return "command-select-tab"
        case .focusNextPane, .focusPreviousPane, .focusPaneLeft, .focusPaneRight, .focusPaneUp, .focusPaneDown:
            return "command-focus-pane"
        case .resizePaneLeft, .resizePaneRight, .resizePaneUp, .resizePaneDown:
            return "command-resize-pane"
        case .equalizeSplits:
            return "command-equalize-splits"
        case .toggleZoom:
            return "command-toggle-zoom"
        case .moveTabLeft, .moveTabRight, .moveTabToNextPane, .moveTabToNewRightSplit, .moveTabToNewDownSplit:
            return "command-move-tab"
        case .toggleCommandPalette:
            return "command-toggle-palette"
        case .toggleWorkspaceOverview:
            return "command-toggle-overview"
        case .toggleSettings:
            return "command-toggle-settings"
        case .toggleFileManager:
            return "command-file-manager"
        case .toggleFullScreen:
            return "command-toggle-fullscreen"
        case .resetWorkspace:
            return "command-reset-workspace"
        case .showTerminalSearch, .findNext, .findPrevious:
            return "command-terminal-search"
        case .flashFocusedPane:
            return "command-flash-pane"
        case .duplicateSelectedTab:
            return "command-duplicate-tab"
        case .openFocusedDirectory, .copyFocusedDirectory:
            return "command-directory"
        case .duplicateWorkspace, .closeCurrentWorkspace:
            return "command-workspace"
        }
    }

    func canPerform(model: ConductorWindowModel) -> Bool {
        switch self {
        case .closeOtherTabs:
            model.workspace.canCloseOtherTabs(in: model.workspace.focusedPaneID)
        case .closeTabsToRight:
            if let pane = model.workspace.focusedPane {
                model.workspace.canCloseTabsToRight(of: pane.selectedTabID, in: pane.id)
            } else {
                false
            }
        case .closeFocusedPane:
            model.canCloseFocusedPane
        case .splitRight, .splitDown:
            model.canSplit
        case .equalizeSplits, .toggleZoom,
             .resizePaneLeft, .resizePaneRight, .resizePaneUp, .resizePaneDown:
            model.workspace.root.leaves.count > 1
        case .moveTabLeft:
            model.canMoveSelectedTabLeft
        case .moveTabRight:
            model.canMoveSelectedTabRight
        case .moveTabToNextPane:
            model.canMoveSelectedTabToNextPane
        case .moveTabToNewRightSplit, .moveTabToNewDownSplit:
            model.canMoveSelectedTabToNewSplit
        case .focusWebAddress:
            model.selectedWorkspaceWebTab != nil
        case .reloadSelectedWebTab:
            model.selectedWorkspaceWebTab?.url != nil
        case .openSelectedWebTabExternally, .copySelectedWebTabURL, .copySelectedWebTabReference:
            model.selectedWorkspaceWebTab?.url != nil
        case .showTerminalSearch:
            model.selectedWorkspaceWebTab != nil || model.selectedWorkspaceFileTab != nil || model.fileManagerPanelRequest != nil || model.focusedTerminalID != nil
        case .findNext, .findPrevious:
            model.selectedWorkspaceWebTab?.url != nil || model.terminalSearchVisible || model.selectedWorkspaceFileTab != nil || model.fileManagerPanelRequest != nil
        case .toggleFileManager:
            model.fileManagerPanelRequest != nil || model.focusedWorkingDirectoryURL != nil
        case .closeCurrentWorkspace:
            model.workspaces.count > 1
        case .newTerminalAtFocusedDirectory, .openFocusedDirectory, .copyFocusedDirectory:
            model.focusedWorkingDirectoryURL != nil
        default:
            true
        }
    }

    @discardableResult
    func perform(model: ConductorWindowModel, window: NSWindow? = nil) -> Bool {
        guard canPerform(model: model) else { return false }
        switch self {
        case .newWorkspace:
            model.newWorkspace()
        case .newTerminal:
            model.newTerminal()
        case .newWebTab:
            model.newWorkspaceWebTab()
        case .focusWebAddress:
            model.focusSelectedWorkspaceWebAddress()
        case .reloadSelectedWebTab:
            model.reloadOrStopSelectedWorkspaceWebTab()
        case .openSelectedWebTabExternally:
            model.openSelectedWorkspaceWebTabExternally()
        case .copySelectedWebTabURL:
            model.copySelectedWorkspaceWebTabURL()
        case .copySelectedWebTabReference:
            model.copySelectedWorkspaceWebTabReference()
        case .closeSelectedTab:
            model.closeSelectedTab()
        case .closeOtherTabs:
            model.closeOtherTabs(in: model.workspace.focusedPaneID)
        case .closeTabsToRight:
            model.closeTabsToRight(in: model.workspace.focusedPaneID)
        case .closeFocusedPane:
            model.closePane(model.workspace.focusedPaneID)
        case .splitRight:
            model.splitRight()
        case .splitDown:
            model.splitDown()
        case .selectNextTab:
            model.selectNextTab()
        case .selectPreviousTab:
            model.selectPreviousTab()
        case .focusNextPane:
            model.focusNextPane()
        case .focusPreviousPane:
            model.focusPreviousPane()
        case .focusPaneLeft:
            model.focusPane(direction: .left)
        case .focusPaneRight:
            model.focusPane(direction: .right)
        case .focusPaneUp:
            model.focusPane(direction: .up)
        case .focusPaneDown:
            model.focusPane(direction: .down)
        case .resizePaneLeft:
            model.resizeFocusedSplit(direction: .left)
        case .resizePaneRight:
            model.resizeFocusedSplit(direction: .right)
        case .resizePaneUp:
            model.resizeFocusedSplit(direction: .up)
        case .resizePaneDown:
            model.resizeFocusedSplit(direction: .down)
        case .equalizeSplits:
            model.equalizeSplits()
        case .toggleZoom:
            model.toggleZoom()
        case .moveTabLeft:
            model.moveSelectedTabLeft()
        case .moveTabRight:
            model.moveSelectedTabRight()
        case .moveTabToNextPane:
            model.moveSelectedTabToNextPane()
        case .moveTabToNewRightSplit:
            model.moveSelectedTabToNewSplit(.right)
        case .moveTabToNewDownSplit:
            model.moveSelectedTabToNewSplit(.down)
        case .toggleCommandPalette:
            model.toggleCommandPalette()
        case .toggleWorkspaceOverview:
            model.toggleWorkspaceOverview()
        case .toggleSettings:
            model.toggleSettingsPanel()
        case .toggleFileManager:
            model.toggleFileManagerPanel()
        case .toggleFullScreen:
            (window ?? NSApp.keyWindow)?.toggleFullScreen(nil)
        case .resetWorkspace:
            model.resetWorkspace()
        case .showTerminalSearch:
            model.showTerminalSearch()
        case .findNext:
            model.navigateTerminalSearch(previous: false)
        case .findPrevious:
            model.navigateTerminalSearch(previous: true)
        case .flashFocusedPane:
            model.flashFocusedPane()
        case .duplicateSelectedTab:
            model.duplicateSelectedTab()
        case .newTerminalAtFocusedDirectory:
            model.newTerminalAtFocusedDirectory()
        case .openFocusedDirectory:
            model.openFocusedDirectory()
        case .copyFocusedDirectory:
            model.copyFocusedDirectory()
        case .duplicateWorkspace:
            model.duplicateWorkspace(model.workspace.id)
        case .closeCurrentWorkspace:
            model.closeWorkspace(model.workspace.id)
        }
        return true
    }
}
