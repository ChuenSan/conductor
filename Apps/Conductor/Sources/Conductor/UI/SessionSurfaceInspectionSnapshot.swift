import ConductorCore
import Foundation

struct SessionSurfaceInspectionSnapshot: Equatable {
    var workspaces: [Workspace]

    var terminalCount: Int {
        workspaces.reduce(0) { $0 + $1.terminals.count }
    }

    var browserCount: Int {
        workspaces.reduce(0) { $0 + $1.webTabs.count }
    }

    var fileCount: Int {
        workspaces.reduce(0) { $0 + $1.files.count }
    }

    var issueCount: Int {
        recoveryIssues.count
    }

    var criticalIssueCount: Int {
        recoveryIssues.filter { $0.severity == .critical }.count
    }

    var warningIssueCount: Int {
        recoveryIssues.filter { $0.severity == .warning }.count
    }

    var recoveryIssues: [RecoveryIssue] {
        workspaces.flatMap { workspace in
            workspace.terminals.flatMap { terminal in
                terminal.issues.map { issue in
                    RecoveryIssue(
                        severity: Self.severity(for: issue),
                        kind: issue,
                        surfaceKind: .terminal,
                        workspaceID: workspace.id,
                        workspaceTitle: workspace.title,
                        terminalID: terminal.id,
                        webTabID: nil,
                        fileTabID: nil,
                        surfaceTitle: terminal.title,
                        title: Self.title(for: issue),
                        detail: Self.detail(for: issue, surfaceTitle: terminal.title),
                        impact: Self.impact(for: issue),
                        suggestedAction: Self.suggestedAction(for: issue),
                        primaryAction: Self.primaryAction(for: issue)
                    )
                }
            } + workspace.webTabs.flatMap { webTab in
                webTab.issues.map { issue in
                    RecoveryIssue(
                        severity: Self.severity(for: issue),
                        kind: issue,
                        surfaceKind: .browser,
                        workspaceID: workspace.id,
                        workspaceTitle: workspace.title,
                        terminalID: nil,
                        webTabID: webTab.id,
                        fileTabID: nil,
                        surfaceTitle: webTab.title,
                        title: Self.title(for: issue),
                        detail: Self.detail(for: issue, surfaceTitle: webTab.title),
                        impact: Self.impact(for: issue),
                        suggestedAction: Self.suggestedAction(for: issue),
                        primaryAction: Self.primaryAction(for: issue)
                    )
                }
            } + workspace.files.flatMap { file in
                file.issues.map { issue in
                    RecoveryIssue(
                        severity: Self.severity(for: issue),
                        kind: issue,
                        surfaceKind: .file,
                        workspaceID: workspace.id,
                        workspaceTitle: workspace.title,
                        terminalID: nil,
                        webTabID: nil,
                        fileTabID: file.id,
                        surfaceTitle: file.title,
                        title: Self.title(for: issue),
                        detail: Self.detail(for: issue, surfaceTitle: file.path),
                        impact: Self.impact(for: issue),
                        suggestedAction: Self.suggestedAction(for: issue),
                        primaryAction: Self.primaryAction(for: issue)
                    )
                }
            }
        }
    }

    struct RecoveryIssue: Equatable, Identifiable {
        var severity: Severity
        var kind: String
        var surfaceKind: SurfaceKind
        var workspaceID: WorkspaceID
        var workspaceTitle: String
        var terminalID: TerminalID?
        var webTabID: WebTabID?
        var fileTabID: String?
        var surfaceTitle: String
        var title: String
        var detail: String
        var impact: String
        var suggestedAction: String
        var primaryAction: Action

        var id: String {
            [
                workspaceID.description,
                surfaceKind.rawValue,
                terminalID?.description ?? webTabID?.rawValue.uuidString ?? fileTabID ?? surfaceTitle,
                kind
            ].joined(separator: ":")
        }

        struct Action: Equatable {
            var kind: String
            var title: String
            var detail: String
            var systemImage: String
            var destructive: Bool
        }
    }

    enum Severity: String, Equatable {
        case critical
        case warning
        case info
    }

    enum SurfaceKind: String, Equatable {
        case terminal
        case browser
        case file
    }

    struct Workspace: Equatable {
        var id: WorkspaceID
        var title: String
        var selected: Bool
        var terminals: [Terminal]
        var webTabs: [WebTab]
        var files: [FileTab]
    }

    struct Terminal: Equatable {
        var id: TerminalID
        var paneID: PaneID
        var title: String
        var workingDirectory: String?
        var selected: Bool
        var focused: Bool
        var userTitle: String?
        var hasAgentSnapshot: Bool
        var agentDisplayName: String?
        var agentState: String?
        var agentSessionIdentifier: String?
        var agentResumeCommand: String?
        var lastCommandExitCode: Int?
        var lastCommandFinishedAt: Date?
        var searchActive: Bool
        var searchNeedle: String?
        var restoredFromSession: Bool
        var processReattached: Bool
        var issues: [String]
    }

    struct WebTab: Equatable {
        var id: WebTabID
        var title: String
        var url: String?
        var pendingAddress: String
        var selected: Bool
        var loading: Bool
        var errorMessage: String?
        var historyCount: Int
        var currentHistoryIndex: Int?
        var canGoBack: Bool
        var canGoForward: Bool
        var scrollY: Double?
        var hasInteractionState: Bool
        var runtimeEventCount: Int
        var latestRuntimeEvent: WorkspaceWebRuntimeEvent?
        var issues: [String]
    }

    struct FileTab: Equatable {
        var id: String
        var title: String
        var path: String
        var rootPath: String
        var selected: Bool
        var dirty: Bool
        var externallyChanged: Bool
        var exists: Bool
        var issues: [String]
    }

    private static func severity(for issue: String) -> Severity {
        switch issue {
        case "file_missing", "web_error":
            return .critical
        case "missing_working_directory", "agent_resume_metadata_missing", "history_missing", "scroll_position_missing", "web_runtime_error", "file_changed_on_disk":
            return .warning
        default:
            return .info
        }
    }

    private static func title(for issue: String) -> String {
        switch issue {
        case "missing_working_directory":
            return "Working directory was not restored"
        case "agent_resume_metadata_missing":
            return "Agent resume metadata is missing"
        case "terminal_process_restarted":
            return "Terminal process was restarted"
        case "blank_web_tab":
            return "Browser tab has no address"
        case "web_error":
            return "Browser tab reported a load error"
        case "web_runtime_error":
            return "Browser page reported a runtime error"
        case "history_missing":
            return "Browser history was not captured"
        case "scroll_position_missing":
            return "Scroll position was not captured"
        case "file_missing":
            return "File tab points to a missing file"
        case "file_changed_on_disk":
            return "File changed on disk"
        default:
            return issue.replacingOccurrences(of: "_", with: " ")
        }
    }

    private static func detail(for issue: String, surfaceTitle: String) -> String {
        switch issue {
        case "missing_working_directory":
            return "The terminal can still open, but commands may start from the fallback directory."
        case "agent_resume_metadata_missing":
            return "The agent is active, but Conductor has no safe command for resuming it after relaunch."
        case "terminal_process_restarted":
            return "Conductor restored the terminal context, but the original shell or agent process was not reattached."
        case "blank_web_tab":
            return "This restored browser surface has no URL or pending address."
        case "web_error":
            return "The page can be focused so the user can reload or inspect the error."
        case "web_runtime_error":
            return "Console and page error details are available from the browser snapshot."
        case "history_missing":
            return "Back/forward restoration may be limited for this browser tab."
        case "scroll_position_missing":
            return "The page restored, but the exact reading position may not return."
        case "file_missing":
            return surfaceTitle
        case "file_changed_on_disk":
            return "Review the file before saving over external changes."
        default:
            return surfaceTitle
        }
    }

    private static func suggestedAction(for issue: String) -> String {
        switch issue {
        case "missing_working_directory":
            return "Focus the terminal and confirm the current directory."
        case "agent_resume_metadata_missing":
            return "Run the agent once with a supported resume hint so Conductor can capture it."
        case "terminal_process_restarted":
            return "Review the restored output, then resume the agent or rerun the command if needed."
        case "blank_web_tab":
            return "Close the empty tab or navigate it to the intended URL."
        case "web_error":
            return "Focus the tab and reload after checking the address."
        case "web_runtime_error":
            return "Run a browser snapshot and inspect the latest runtime event."
        case "history_missing":
            return "Continue browsing; Conductor will rebuild explicit history from navigation."
        case "scroll_position_missing":
            return "Scroll once after restore so the next snapshot captures position."
        case "file_missing":
            return "Restore the file path or close the stale tab."
        case "file_changed_on_disk":
            return "Compare the disk version before saving."
        default:
            return "Inspect this restored surface."
        }
    }

    private static func impact(for issue: String) -> String {
        switch issue {
        case "missing_working_directory":
            return "Commands may run from a fallback directory until the terminal is checked."
        case "agent_resume_metadata_missing":
            return "The session can be restored visually, but automatic agent continuation is not safe."
        case "terminal_process_restarted":
            return "Scrollback and context are restored, but the original live process is gone."
        case "blank_web_tab":
            return "This tab cannot restore useful browsing context until it has an address."
        case "web_error":
            return "The tab restored, but the page is not currently usable."
        case "web_runtime_error":
            return "The page loaded, but recent script or console errors may explain broken behavior."
        case "history_missing":
            return "Back and forward may be incomplete for this restored tab."
        case "scroll_position_missing":
            return "The page may reopen near the top instead of the last reading position."
        case "file_missing":
            return "The file tab cannot reopen content until the path exists again."
        case "file_changed_on_disk":
            return "Saving now could overwrite changes made outside Conductor."
        default:
            return "This surface needs a quick manual check."
        }
    }

    private static func primaryAction(for issue: String) -> RecoveryIssue.Action {
        switch issue {
        case "blank_web_tab":
            return RecoveryIssue.Action(
                kind: "focus_web_address",
                title: "Enter address",
                detail: "Open the browser address field for this tab.",
                systemImage: "text.cursor",
                destructive: false
            )
        case "web_error":
            return RecoveryIssue.Action(
                kind: "reload_web_tab",
                title: "Reload tab",
                detail: "Select this browser tab and retry the page load.",
                systemImage: "arrow.clockwise",
                destructive: false
            )
        case "file_missing":
            return RecoveryIssue.Action(
                kind: "focus_file_tab",
                title: "Review file tab",
                detail: "Select the stale file tab so the path can be restored or closed.",
                systemImage: "doc.text.magnifyingglass",
                destructive: false
            )
        case "file_changed_on_disk":
            return RecoveryIssue.Action(
                kind: "focus_file_tab",
                title: "Compare before saving",
                detail: "Select this file tab and review the external disk changes.",
                systemImage: "arrow.triangle.2.circlepath.doc.on.clipboard",
                destructive: false
            )
        case "agent_resume_metadata_missing", "terminal_process_restarted":
            return RecoveryIssue.Action(
                kind: "focus_terminal",
                title: "Open terminal",
                detail: "Select the restored terminal and decide whether to resume or rerun.",
                systemImage: "terminal",
                destructive: false
            )
        default:
            return RecoveryIssue.Action(
                kind: "focus_surface",
                title: "Show surface",
                detail: "Jump to the affected terminal, browser, or file tab.",
                systemImage: "arrow.right.circle",
                destructive: false
            )
        }
    }
}
