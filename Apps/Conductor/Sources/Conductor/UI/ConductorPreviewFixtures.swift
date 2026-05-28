#if DEBUG
import ConductorCore
import SwiftUI

@MainActor
enum ConductorPreviewFixtures {
    static func glassShellModel(
        sidebarVisible: Bool = true,
        commandPaletteVisible: Bool = false,
        settingsPanelVisible: Bool = false,
        workspaceOverviewVisible: Bool = false
    ) -> ConductorWindowModel {
        let workspaceSet = previewWorkspaces()
        return ConductorWindowModel(
            previewWorkspaces: workspaceSet.workspaces,
            selectedWorkspaceID: workspaceSet.selectedID,
            theme: .codexDark,
            sidebarVisible: sidebarVisible,
            commandPaletteVisible: commandPaletteVisible,
            settingsPanelVisible: settingsPanelVisible,
            workspaceOverviewVisible: workspaceOverviewVisible
        )
    }

    private static func previewWorkspaces() -> (
        workspaces: [WorkspaceState],
        selectedID: WorkspaceID
    ) {
        var build = WorkspaceState(title: "Build & Agents")
        _ = build.newTerminal(title: "codex-plan", workingDirectory: "~/Desktop/conductor")
        _ = build.splitWorkspaceEdge(.right, title: "swift run Conductor", workingDirectory: "Apps/Conductor")
        _ = build.splitWorkspaceEdge(.down, title: "long-output stress", workingDirectory: "Apps/Conductor/Scripts")

        var design = WorkspaceState(title: "Design Tokens")
        _ = design.newTerminal(title: "preview fixtures", workingDirectory: "Apps/Conductor/Sources")
        _ = design.splitWorkspaceEdge(.right, title: "visual tokens", workingDirectory: ".trellis/spec/frontend")

        var release = WorkspaceState(title: "Release Notes")
        _ = release.newTerminal(title: "changelog", workingDirectory: "~/Desktop/conductor")

        return (
            workspaces: [build, design, release],
            selectedID: build.id
        )
    }
}

struct ConductorGlassShellPreviews: PreviewProvider {
    @MainActor
    static var previews: some View {
        Group {
            ConductorRootView(model: ConductorPreviewFixtures.glassShellModel())
                .frame(width: 1320, height: 860)
                .previewDisplayName("Conductor Shell")

            ConductorRootView(model: ConductorPreviewFixtures.glassShellModel(commandPaletteVisible: true))
                .frame(width: 1320, height: 860)
                .previewDisplayName("Command Palette")

            ConductorRootView(model: ConductorPreviewFixtures.glassShellModel(settingsPanelVisible: true))
                .frame(width: 1320, height: 860)
                .previewDisplayName("Appearance Settings")

            ConductorRootView(model: ConductorPreviewFixtures.glassShellModel(workspaceOverviewVisible: true))
                .frame(width: 1320, height: 860)
                .previewDisplayName("Workspace Overview")

            ConductorRootView(model: ConductorPreviewFixtures.glassShellModel(sidebarVisible: false))
                .frame(width: 1120, height: 760)
                .previewDisplayName("Collapsed Sidebar")
        }
    }
}
#endif
