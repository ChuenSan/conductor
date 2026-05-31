import Testing
@testable import ConductorCore

@Test func visibleTerminalsInSinglePaneSingleWorkspace() {
    let workspace = WorkspaceState()
    let expected = workspace.focusedPane?.selectedTabID
    let visible = WorkspaceVisibility.visibleTerminalIDs(
        workspaces: [workspace],
        selectedWorkspaceID: workspace.id
    )
    #expect(visible == Set([expected].compactMap { $0 }))
}

@Test func visibleTerminalsCoverEveryPaneInSelectedWorkspace() {
    var workspace = WorkspaceState()
    let firstPaneSelected = workspace.focusedPane!.selectedTabID
    guard let secondPaneID = workspace.splitFocusedPane(.right, title: "agent") else {
        Issue.record("split should create second pane"); return
    }
    let secondPaneSelected = workspace.panes[secondPaneID]!.selectedTabID
    let visible = WorkspaceVisibility.visibleTerminalIDs(
        workspaces: [workspace],
        selectedWorkspaceID: workspace.id
    )
    #expect(visible == Set([firstPaneSelected, secondPaneSelected]))
}

@Test func visibleTerminalsExcludeUnselectedTabsInPane() {
    var workspace = WorkspaceState()
    let paneID = workspace.focusedPaneID
    let firstTab = workspace.focusedPane!.selectedTabID
    let secondTab = workspace.newTerminal(title: "server")
    // Selecting the second tab should make ONLY the second tab visible.
    workspace.selectTab(secondTab, in: paneID)
    let visible = WorkspaceVisibility.visibleTerminalIDs(
        workspaces: [workspace],
        selectedWorkspaceID: workspace.id
    )
    #expect(visible == Set([secondTab]))
    #expect(!visible.contains(firstTab))
}

@Test func visibleTerminalsHonorZoom() {
    var workspace = WorkspaceState()
    let firstPaneSelected = workspace.focusedPane!.selectedTabID
    guard let secondPaneID = workspace.splitFocusedPane(.right, title: "agent") else {
        Issue.record("split should create second pane"); return
    }
    let secondPaneSelected = workspace.panes[secondPaneID]!.selectedTabID
    workspace.toggleZoom() // zoom the just-created (focused) second pane
    let visible = WorkspaceVisibility.visibleTerminalIDs(
        workspaces: [workspace],
        selectedWorkspaceID: workspace.id
    )
    #expect(visible == Set([secondPaneSelected]))
    #expect(!visible.contains(firstPaneSelected))
}

@Test func visibleTerminalsExcludeOtherWorkspaces() {
    let workspaceA = WorkspaceState(title: "A")
    let workspaceB = WorkspaceState(title: "B")
    let aSelected = workspaceA.focusedPane!.selectedTabID
    let bSelected = workspaceB.focusedPane!.selectedTabID
    let visible = WorkspaceVisibility.visibleTerminalIDs(
        workspaces: [workspaceA, workspaceB],
        selectedWorkspaceID: workspaceA.id
    )
    #expect(visible == Set([aSelected]))
    #expect(!visible.contains(bSelected))
}

@Test func visibleTerminalsForUnknownSelectedIDIsEmpty() {
    let workspace = WorkspaceState()
    let visible = WorkspaceVisibility.visibleTerminalIDs(
        workspaces: [workspace],
        selectedWorkspaceID: WorkspaceID()
    )
    #expect(visible.isEmpty)
}

@Test func visibleTerminalsForEmptyWorkspaceListIsEmpty() {
    let visible = WorkspaceVisibility.visibleTerminalIDs(
        workspaces: [],
        selectedWorkspaceID: WorkspaceID()
    )
    #expect(visible.isEmpty)
}
