import Testing
@testable import ConductorCore

@Test func newWorkspaceHasOnePane() {
    let workspace = WorkspaceState()
    #expect(workspace.root.leaves.count == 1)
    #expect(workspace.focusedPane?.tabs.count == 1)
}
