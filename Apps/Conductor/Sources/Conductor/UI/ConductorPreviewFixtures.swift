#if DEBUG
import ConductorCore
import SwiftUI

@MainActor
enum ConductorPreviewFixtures {
    static func glassShellModel(
        sidebarVisible: Bool = true,
        commandPaletteVisible: Bool = false,
        notificationPanelVisible: Bool = false
    ) -> ConductorWindowModel {
        let workspaceSet = previewWorkspaces()
        return ConductorWindowModel(
            previewWorkspaces: workspaceSet.workspaces,
            selectedWorkspaceID: workspaceSet.selectedID,
            theme: .codexDark,
            notifications: workspaceSet.notifications,
            sidebarVisible: sidebarVisible,
            commandPaletteVisible: commandPaletteVisible,
            notificationPanelVisible: notificationPanelVisible
        )
    }

    private static func previewWorkspaces() -> (
        workspaces: [WorkspaceState],
        selectedID: WorkspaceID,
        notifications: TerminalNotificationState
    ) {
        var build = WorkspaceState(title: "Build & Agents")
        let rootPaneID = build.focusedPaneID
        let rootTerminalID = build.focusedPane?.selectedTabID ?? TerminalID()
        _ = build.newTerminal(title: "codex-plan", workingDirectory: "~/Desktop/conductor")
        let agentTerminalID = build.focusedPane?.selectedTabID ?? rootTerminalID
        let serverPaneID = build.splitWorkspaceEdge(.right, title: "swift run Conductor", workingDirectory: "Apps/Conductor")
        let serverTerminalID = serverPaneID.flatMap { build.panes[$0]?.selectedTabID } ?? agentTerminalID
        let logsPaneID = build.splitWorkspaceEdge(.down, title: "long-output stress", workingDirectory: "Apps/Conductor/Scripts")
        let logsTerminalID = logsPaneID.flatMap { build.panes[$0]?.selectedTabID } ?? serverTerminalID

        var design = WorkspaceState(title: "Glass Lab")
        _ = design.newTerminal(title: "preview fixtures", workingDirectory: "Apps/Conductor/Sources")
        _ = design.splitWorkspaceEdge(.right, title: "visual tokens", workingDirectory: ".trellis/spec/frontend")

        var release = WorkspaceState(title: "Release Notes")
        _ = release.newTerminal(title: "changelog", workingDirectory: "~/Desktop/conductor")

        let records = [
            TerminalNotificationRecord(
                workspaceID: build.id,
                paneID: serverPaneID,
                terminalID: serverTerminalID,
                title: "Conductor build finished",
                body: "Swift build completed with the local GhosttyKit surface linked.",
                createdAt: Date().addingTimeInterval(-90),
                kind: .agent
            ),
            TerminalNotificationRecord(
                workspaceID: build.id,
                paneID: logsPaneID,
                terminalID: logsTerminalID,
                title: "Stress route still running",
                body: "Long-output validation is producing metadata only; transcript stays out of SwiftUI.",
                createdAt: Date().addingTimeInterval(-240),
                kind: .notification
            ),
            TerminalNotificationRecord(
                workspaceID: build.id,
                paneID: rootPaneID,
                terminalID: rootTerminalID,
                title: "Terminal bell",
                body: "Foreground task requested attention.",
                createdAt: Date().addingTimeInterval(-520),
                isRead: true,
                kind: .bell
            )
        ]

        return (
            workspaces: [build, design, release],
            selectedID: build.id,
            notifications: TerminalNotificationState(records: records)
        )
    }
}

struct ConductorGlassShellPreviews: PreviewProvider {
    @MainActor
    static var previews: some View {
        Group {
            ConductorRootView(model: ConductorPreviewFixtures.glassShellModel())
                .frame(width: 1320, height: 860)
                .previewDisplayName("Conductor Glass Shell")

            ConductorRootView(model: ConductorPreviewFixtures.glassShellModel(commandPaletteVisible: true))
                .frame(width: 1320, height: 860)
                .previewDisplayName("Command Center Glass")

            ConductorRootView(model: ConductorPreviewFixtures.glassShellModel(sidebarVisible: false))
                .frame(width: 1120, height: 760)
                .previewDisplayName("Collapsed Sidebar Glass")

            NotificationPanelView(model: ConductorPreviewFixtures.glassShellModel(notificationPanelVisible: true))
                .frame(width: 390, height: 520)
                .padding(32)
                .background(ConductorWindowBackdrop(theme: .codexDark))
                .previewDisplayName("Notification Glass Feed")
        }
    }
}
#endif
