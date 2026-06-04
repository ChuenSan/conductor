import ConductorCore

enum SessionRecoverySurfaceTarget: Equatable {
    case terminal(workspaceID: WorkspaceID, terminalID: TerminalID)
    case webTab(workspaceID: WorkspaceID, tabID: WebTabID)
    case fileTab(workspaceID: WorkspaceID, tabID: String)
}
