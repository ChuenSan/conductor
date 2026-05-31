import Foundation

/// Pure rule for "which terminals can the user currently see?". Used to
/// scope per-tick work (agent state polling) and to mark every other
/// surface occluded so libghostty can pause its rendering.
///
/// Visibility rule: in the selected workspace, the currently-selected tab
/// of every pane shown by `WorkspaceState.visibleRoot`. `visibleRoot`
/// already collapses to a single leaf when a pane is zoomed, so zoom is
/// honored automatically. A `selectedWorkspaceID` that does not match any
/// workspace yields the empty set (no crash).
public enum WorkspaceVisibility {
    public static func visibleTerminalIDs(
        workspaces: [WorkspaceState],
        selectedWorkspaceID: WorkspaceID
    ) -> Set<TerminalID> {
        guard let selected = workspaces.first(where: { $0.id == selectedWorkspaceID }) else {
            return []
        }
        var ids = Set<TerminalID>()
        for paneID in selected.visibleRoot.leaves {
            if let pane = selected.panes[paneID] {
                ids.insert(pane.selectedTabID)
            }
        }
        return ids
    }
}
