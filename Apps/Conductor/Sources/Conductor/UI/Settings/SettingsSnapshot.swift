import ConductorCore
import Foundation

enum SettingsSectionID: String, CaseIterable, Identifiable, Sendable {
    case overview
    case interface
    case terminal
    case shell
    case usage
    case automation
    case updates
    case commands
    case themes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview:
            ConductorLocalization.text(zh: "概览", en: "Overview")
        case .interface:
            ConductorLocalization.text(zh: "界面外观", en: "Interface")
        case .terminal:
            ConductorLocalization.text(zh: "终端体验", en: "Terminal")
        case .shell:
            ConductorLocalization.text(zh: "启动/代理", en: "Startup")
        case .usage:
            ConductorLocalization.text(zh: "用量", en: "Usage")
        case .automation:
            ConductorLocalization.text(zh: "自动化/通知", en: "Automation")
        case .updates:
            ConductorLocalization.text(zh: "更新", en: "Updates")
        case .commands:
            ConductorLocalization.text(zh: "快捷键", en: "Shortcuts")
        case .themes:
            ConductorLocalization.text(zh: "主题", en: "Themes")
        }
    }

    var subtitle: String {
        switch self {
        case .overview:
            ConductorLocalization.text(zh: "当前配置和入口", en: "Current configuration and entry points")
        case .interface:
            ConductorLocalization.text(zh: "窗口、语言和壳层文字", en: "Window, language, and shell text")
        case .terminal:
            ConductorLocalization.text(zh: "字体、显示、输入", en: "Font, display, input")
        case .shell:
            ConductorLocalization.text(zh: "命令、目录、网络", en: "Command, directory, network")
        case .usage:
            ConductorLocalization.text(zh: "Token 记录和本地用量", en: "Token records and local usage")
        case .automation:
            ConductorLocalization.text(zh: "安装检测、任务提醒和通知", en: "Install checks, task alerts, and notifications")
        case .updates:
            ConductorLocalization.text(zh: "检查、下载、替换运行时", en: "Check, download, and replace runtime")
        case .commands:
            ConductorLocalization.text(zh: "快捷键与命令入口", en: "Shortcuts and commands")
        case .themes:
            ConductorLocalization.text(zh: "整套窗口、终端和强调色", en: "Window, terminal, and accent colors")
        }
    }

    var systemImage: String {
        switch self {
        case .overview:
            "rectangle.grid.2x2"
        case .interface:
            "textformat"
        case .terminal:
            "terminal"
        case .shell:
            "network"
        case .usage:
            "chart.bar"
        case .automation:
            "bolt.horizontal"
        case .updates:
            "arrow.triangle.2.circlepath"
        case .commands:
            "command"
        case .themes:
            "swatchpalette"
        }
    }
}

struct SettingsSnapshot: Equatable {
    let selectedSection: SettingsSectionID
    let theme: TerminalTheme
    let appearance: AppearancePreferences
    let agentHookSettingsMessage: String?
    let notificationAuthorizationState: AgentReplyNotificationAuthorizationState
    let notificationDeliveryTestMessage: String?
    let agentCLIStatuses: [AgentHookProvider: AgentCLIStatus]
    let terminalFontDownloadStates: [TerminalFontPreset: TerminalFontDownloadState]
    let updatePreferences: ConductorUpdatePreferences
    let updateState: ConductorUpdateState
    let sessionRestoreReport: WorkspacePersistenceLoadReport
    let sessionJournalSummary: ConductorSessionJournalSummary
    let sessionJournalRecentEvents: [ConductorSessionJournalEvent]
    let sessionSurfaceInspection: SessionSurfaceInspectionSnapshot

    init(
        selectedSection: SettingsSectionID,
        theme: TerminalTheme,
        appearance: AppearancePreferences,
        agentHookSettingsMessage: String?,
        notificationAuthorizationState: AgentReplyNotificationAuthorizationState,
        notificationDeliveryTestMessage: String?,
        agentCLIStatuses: [AgentHookProvider: AgentCLIStatus],
        terminalFontDownloadStates: [TerminalFontPreset: TerminalFontDownloadState],
        updatePreferences: ConductorUpdatePreferences,
        updateState: ConductorUpdateState,
        sessionRestoreReport: WorkspacePersistenceLoadReport,
        sessionJournalSummary: ConductorSessionJournalSummary,
        sessionJournalRecentEvents: [ConductorSessionJournalEvent],
        sessionSurfaceInspection: SessionSurfaceInspectionSnapshot
    ) {
        self.selectedSection = selectedSection
        self.theme = theme
        self.appearance = appearance
        self.agentHookSettingsMessage = agentHookSettingsMessage
        self.notificationAuthorizationState = notificationAuthorizationState
        self.notificationDeliveryTestMessage = notificationDeliveryTestMessage
        self.agentCLIStatuses = agentCLIStatuses
        self.terminalFontDownloadStates = terminalFontDownloadStates
        self.updatePreferences = updatePreferences
        self.updateState = updateState
        self.sessionRestoreReport = sessionRestoreReport
        self.sessionJournalSummary = sessionJournalSummary
        self.sessionJournalRecentEvents = sessionJournalRecentEvents
        self.sessionSurfaceInspection = sessionSurfaceInspection
    }
}
