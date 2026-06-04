import ConductorCore
import AppKit
import SwiftUI

private func L(_ zh: String, _ en: String) -> String {
    ConductorLocalization.text(zh: zh, en: en)
}

struct SessionRecoveryOverviewCard: View {
    let report: WorkspacePersistenceLoadReport
    let journalSummary: ConductorSessionJournalSummary
    let recentEvents: [ConductorSessionJournalEvent]
    let surfaceInspection: SessionSurfaceInspectionSnapshot
    let canRestorePrevious: Bool
    let restorePrevious: () -> Void
    let focusSurface: (SessionRecoverySurfaceTarget) -> Void
    let performIssueAction: (SessionSurfaceInspectionSnapshot.RecoveryIssue) -> Void

    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorTheme) private var theme

    private var statusTitle: String {
        switch report.state {
        case .restored:
            return L("会话已恢复", "Session Restored")
        case .restoredFromPrevious:
            return L("已使用上一份快照", "Fallback Snapshot Used")
        case .restoredFromJournal:
            return L("已从记录恢复", "Journal Replay Used")
        case .failed:
            return L("恢复失败", "Restore Failed")
        case .missing:
            return L("新会话", "New Session")
        case .reset:
            return L("已重置", "Reset")
        case .disabled:
            return L("恢复已关闭", "Restore Disabled")
        }
    }

    private var statusSubtitle: String {
        switch report.state {
        case .restored, .restoredFromPrevious, .restoredFromJournal:
            return L(
                "\(report.restoredWorkspaceCount) 个工作区 · \(report.restoredWebTabCount) 个网页 · \(report.restoredFileTabCount) 个文件",
                "\(report.restoredWorkspaceCount) workspaces · \(report.restoredWebTabCount) web tabs · \(report.restoredFileTabCount) files"
            )
        case .failed:
            return report.message
        case .missing:
            return L("没有可恢复的本地状态，当前从空工作台开始", "No local state was found; this workspace started fresh")
        case .reset:
            return L("状态被重置后打开了新的工作台", "State was reset and a fresh workspace opened")
        case .disabled:
            return L("当前启动方式没有写入会话状态", "This launch mode is not writing session state")
        }
    }

    private var statusImage: String {
        switch report.state {
        case .restored:
            return "checkmark.circle.fill"
        case .restoredFromPrevious:
            return "clock.arrow.circlepath"
        case .restoredFromJournal:
            return "list.bullet.rectangle"
        case .failed:
            return "exclamationmark.triangle.fill"
        case .missing, .reset:
            return "sparkles"
        case .disabled:
            return "nosign"
        }
    }

    private var statusColor: Color {
        switch report.state {
        case .restored:
            return Color.green
        case .restoredFromPrevious:
            return Color.orange
        case .restoredFromJournal:
            return Color.orange
        case .failed:
            return Color.red
        case .missing, .reset:
            return theme.floatingEmphasis
        case .disabled:
            return ConductorDesign.tertiaryText
        }
    }

    private var issues: [String] {
        var items: [String] = []
        if report.droppedWorkspaceCount > 0 {
            items.append(L(
                "\(report.droppedWorkspaceCount) 个无效工作区已跳过",
                "\(report.droppedWorkspaceCount) invalid workspaces were skipped"
            ))
        }
        if report.droppedWebTabCount > 0 || report.droppedFileTabCount > 0 {
            items.append(L(
                "\(report.droppedWebTabCount) 个网页、\(report.droppedFileTabCount) 个文件未恢复",
                "\(report.droppedWebTabCount) web tabs and \(report.droppedFileTabCount) files were not restored"
            ))
        }
        if let missingFile = report.missingFilePaths.first {
            let name = URL(fileURLWithPath: missingFile).lastPathComponent
            items.append(L(
                report.missingFilePaths.count > 1
                    ? "\(name) 等 \(report.missingFilePaths.count) 个文件不存在"
                    : "\(name) 不存在",
                report.missingFilePaths.count > 1
                    ? "\(report.missingFilePaths.count) files are missing, including \(name)"
                    : "\(name) is missing"
            ))
        }
        if !report.failedPaths.isEmpty {
            items.append(L(
                "\(report.failedPaths.count) 个状态文件不可用",
                "\(report.failedPaths.count) state files were unavailable"
            ))
        }
        if journalSummary.entryCount == 0 && report.state != .disabled {
            items.append(L("还没有会话记录；正常使用后会自动记录关键变化", "No journal entries yet; key changes are recorded during normal use"))
        }
        return items
    }

    private var totalIssueCount: Int {
        issues.count + surfaceInspection.issueCount
    }

    private var recoveryIssues: [SessionSurfaceInspectionSnapshot.RecoveryIssue] {
        Array(surfaceInspection.recoveryIssues.prefix(5))
    }

    private var resumableAgentRows: [(title: String, detail: String, command: String, target: SessionRecoverySurfaceTarget)] {
        var rows: [(title: String, detail: String, command: String, target: SessionRecoverySurfaceTarget)] = []
        for workspace in surfaceInspection.workspaces {
            for terminal in workspace.terminals {
                guard let command = terminal.agentResumeCommand else { continue }
                let agentName = terminal.agentDisplayName ?? L("AI 终端", "AI Terminal")
                let session = terminal.agentSessionIdentifier.map { " · \($0)" } ?? ""
                rows.append((
                    title: L("\(agentName) · \(terminal.title)", "\(agentName) · \(terminal.title)"),
                    detail: "\(workspace.title)\(session)",
                    command: command,
                    target: .terminal(workspaceID: workspace.id, terminalID: terminal.id)
                ))
            }
        }
        return Array(rows.prefix(3))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: statusImage)
                    .font(.conductorSystem(size: 15, weight: .semibold, scale: fontScale))
                    .foregroundStyle(statusColor)
                    .frame(width: 28, height: 28)
                    .background(statusColor.opacity(theme.usesDarkChrome ? 0.15 : 0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(statusTitle)
                        .font(.conductorSystem(size: 12.5, weight: .semibold, scale: fontScale))
                        .foregroundStyle(ConductorDesign.primaryText)
                        .lineLimit(1)
                    Text(statusSubtitle)
                        .font(.conductorSystem(size: 10.2, weight: .medium, scale: fontScale))
                        .foregroundStyle(ConductorDesign.tertiaryText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Button(action: restorePrevious) {
                    Label(L("恢复上一份", "Restore Previous"), systemImage: "clock.arrow.circlepath")
                        .font(.conductorSystem(size: 10.5, weight: .semibold, scale: fontScale))
                        .lineLimit(1)
                }
                .disabled(!canRestorePrevious)
                .buttonStyle(ConductorPressButtonStyle(pressedScale: 0.985, pressedOpacity: 0.96))
                .macNativeTooltip(canRestorePrevious
                    ? L("用上一份有效快照替换当前工作台", "Replace the current workbench with the previous valid snapshot")
                    : L("没有可恢复的上一份快照", "No previous snapshot is available"))
            }

            HStack(spacing: 8) {
                recoveryMetric(title: L("记录", "Journal"), value: "\(journalSummary.entryCount)")
                recoveryMetric(title: L("路径", "Source"), value: sourceDisplayName)
                recoveryMetric(title: L("问题", "Issues"), value: "\(totalIssueCount)")
            }

            HStack(spacing: 8) {
                surfaceMetric(
                    title: L("终端", "Terminals"),
                    count: surfaceInspection.terminalCount,
                    issueCount: surfaceInspection.workspaces.reduce(0) { total, workspace in
                        total + workspace.terminals.reduce(0) { $0 + $1.issues.count }
                    },
                    systemImage: "terminal"
                )
                surfaceMetric(
                    title: L("网页", "Browsers"),
                    count: surfaceInspection.browserCount,
                    issueCount: surfaceInspection.workspaces.reduce(0) { total, workspace in
                        total + workspace.webTabs.reduce(0) { $0 + $1.issues.count }
                    },
                    systemImage: "globe"
                )
                surfaceMetric(
                    title: L("文件", "Files"),
                    count: surfaceInspection.fileCount,
                    issueCount: surfaceInspection.workspaces.reduce(0) { total, workspace in
                        total + workspace.files.reduce(0) { $0 + $1.issues.count }
                    },
                    systemImage: "doc.text"
                )
            }

            if !resumableAgentRows.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text(L("可续接", "Resumable"))
                        .font(.conductorSystem(size: 9.8, weight: .semibold, scale: fontScale))
                        .foregroundStyle(ConductorDesign.tertiaryText)
                    ForEach(Array(resumableAgentRows.enumerated()), id: \.offset) { _, row in
                        HStack(spacing: 7) {
                            Button {
                                focusSurface(row.target)
                            } label: {
                                HStack(spacing: 7) {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                        .font(.conductorSystem(size: 9, weight: .semibold, scale: fontScale))
                                        .foregroundStyle(statusColor.opacity(0.88))
                                        .frame(width: 14)
                                        .accessibilityHidden(true)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(row.title)
                                            .font(.conductorSystem(size: 10.2, weight: .semibold, scale: fontScale))
                                            .foregroundStyle(ConductorDesign.secondaryText)
                                            .lineLimit(1)
                                        Text(row.detail)
                                            .font(.conductorSystem(size: 9.4, weight: .medium, scale: fontScale))
                                            .foregroundStyle(ConductorDesign.tertiaryText)
                                            .lineLimit(1)
                                    }
                                    Spacer(minLength: 6)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(ConductorPressButtonStyle(pressedScale: 0.992, pressedOpacity: 0.96))
                            .macNativeTooltip(row.command)

                            Button {
                                copyToPasteboard(row.command)
                            } label: {
                                Image(systemName: "doc.on.doc")
                                    .font(.conductorSystem(size: 9, weight: .semibold, scale: fontScale))
                                    .foregroundStyle(ConductorDesign.tertiaryText)
                                    .frame(width: 22, height: 22)
                                    .background(theme.floatingControlStrongFill.opacity(theme.usesDarkChrome ? 0.42 : 0.38))
                                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            }
                            .buttonStyle(ConductorPressButtonStyle(pressedScale: 0.94, pressedOpacity: 0.88))
                            .macNativeTooltip(L("复制续接命令", "Copy Resume Command"))
                        }
                    }
                }
                .padding(.top, 1)
            }

            if !issues.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(issues.prefix(3).enumerated()), id: \.offset) { _, issue in
                        Label(issue, systemImage: "exclamationmark.circle")
                            .font(.conductorSystem(size: 10.2, weight: .medium, scale: fontScale))
                            .foregroundStyle(ConductorDesign.secondaryText)
                            .lineLimit(2)
                    }
                }
                .padding(.top, 1)
            }

            if !recoveryIssues.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 7) {
                        Text(L("恢复检查", "Recovery Check"))
                            .font(.conductorSystem(size: 9.8, weight: .semibold, scale: fontScale))
                            .foregroundStyle(ConductorDesign.tertiaryText)
                        Spacer(minLength: 0)
                        Text(L("\(surfaceInspection.criticalIssueCount) 严重 · \(surfaceInspection.warningIssueCount) 警告", "\(surfaceInspection.criticalIssueCount) critical · \(surfaceInspection.warningIssueCount) warnings"))
                            .font(.conductorSystem(size: 9.2, weight: .medium, scale: fontScale))
                            .foregroundStyle(ConductorDesign.tertiaryText)
                            .lineLimit(1)
                    }
                    ForEach(recoveryIssues) { issue in
                        recoveryIssueRow(issue)
                    }
                }
                .padding(.top, 1)
            }

            if surfaceInspection.issueCount == 0 && (report.state == .restored || report.state == .restoredFromJournal) {
                HStack(spacing: 7) {
                    Image(systemName: "checkmark.seal")
                        .font(.conductorSystem(size: 9.5, weight: .semibold, scale: fontScale))
                        .foregroundStyle(Color.green.opacity(0.86))
                        .accessibilityHidden(true)
                    Text(L("恢复检查通过：终端、网页和文件 surface 没有发现需要处理的问题。", "Recovery check passed: terminal, browser, and file surfaces have no issues requiring action."))
                        .font(.conductorSystem(size: 10.1, weight: .medium, scale: fontScale))
                        .foregroundStyle(ConductorDesign.secondaryText)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 8)
                .frame(minHeight: 30, alignment: .leading)
                .background(theme.floatingControlStrongFill.opacity(theme.usesDarkChrome ? 0.30 : 0.28))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }

            if !recommendedRecoveryActions.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text(L("下一步", "Next Steps"))
                        .font(.conductorSystem(size: 9.8, weight: .semibold, scale: fontScale))
                        .foregroundStyle(ConductorDesign.tertiaryText)
                    ForEach(Array(recommendedRecoveryActions.enumerated()), id: \.offset) { _, action in
                        HStack(spacing: 7) {
                            Image(systemName: "arrow.turn.down.right")
                                .font(.conductorSystem(size: 8.8, weight: .semibold, scale: fontScale))
                                .foregroundStyle(ConductorDesign.tertiaryText)
                                .accessibilityHidden(true)
                            Text(action)
                                .font(.conductorSystem(size: 9.8, weight: .medium, scale: fontScale))
                                .foregroundStyle(ConductorDesign.secondaryText)
                                .lineLimit(2)
                            Spacer(minLength: 0)
                        }
                    }
                }
                .padding(.top, 1)
            }

            if !recentEvents.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text(L("最近记录", "Recent Journal"))
                        .font(.conductorSystem(size: 9.8, weight: .semibold, scale: fontScale))
                        .foregroundStyle(ConductorDesign.tertiaryText)
                    ForEach(recentEvents.suffix(3).reversed(), id: \.id) { event in
                        HStack(spacing: 7) {
                            Image(systemName: eventIcon(event.kind))
                                .font(.conductorSystem(size: 9, weight: .semibold, scale: fontScale))
                                .foregroundStyle(ConductorDesign.tertiaryText)
                                .frame(width: 14)
                                .accessibilityHidden(true)
                            Text(eventTitle(event.kind))
                                .font(.conductorSystem(size: 10.2, weight: .medium, scale: fontScale))
                                .foregroundStyle(ConductorDesign.secondaryText)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Text(eventCountSummary(event))
                                .font(.conductorSystem(size: 9.5, weight: .medium, scale: fontScale))
                                .foregroundStyle(ConductorDesign.tertiaryText)
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(theme.floatingControlFill.opacity(theme.usesDarkChrome ? 0.16 : 0.24))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(theme.floatingStroke.opacity(theme.usesDarkChrome ? 0.22 : 0.18), lineWidth: 0.6)
        }
        .accessibilityElement(children: .contain)
    }

    private var sourceDisplayName: String {
        guard let sourcePath = report.sourcePath else {
            return L("无", "None")
        }
        return URL(fileURLWithPath: sourcePath).lastPathComponent
    }

    private func recoveryMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.conductorSystem(size: 9.4, weight: .medium, scale: fontScale))
                .foregroundStyle(ConductorDesign.tertiaryText)
                .lineLimit(1)
            Text(value)
                .font(.conductorSystem(size: 10.5, weight: .semibold, scale: fontScale))
                .foregroundStyle(ConductorDesign.primaryText)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 9)
        .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
        .background(theme.floatingControlStrongFill.opacity(theme.usesDarkChrome ? 0.50 : 0.46))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private func surfaceMetric(
        title: String,
        count: Int,
        issueCount: Int,
        systemImage: String
    ) -> some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.conductorSystem(size: 9, weight: .semibold, scale: fontScale))
                .foregroundStyle(issueCount == 0 ? ConductorDesign.tertiaryText : statusColor)
                .frame(width: 13)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.conductorSystem(size: 9.3, weight: .medium, scale: fontScale))
                    .foregroundStyle(ConductorDesign.tertiaryText)
                    .lineLimit(1)
                Text(issueCount == 0
                    ? L("\(count) 个", "\(count)")
                    : L("\(count) 个 · \(issueCount) 需处理", "\(count) · \(issueCount) issues"))
                    .font(.conductorSystem(size: 9.7, weight: .semibold, scale: fontScale))
                    .foregroundStyle(ConductorDesign.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
        }
        .padding(.horizontal, 9)
        .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
        .background(theme.floatingControlStrongFill.opacity(theme.usesDarkChrome ? 0.38 : 0.34))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    @ViewBuilder
    private func recoveryIssueRow(_ issue: SessionSurfaceInspectionSnapshot.RecoveryIssue) -> some View {
        if target(for: issue) != nil {
            Button {
                performIssueAction(issue)
            } label: {
                recoveryIssueContent(issue, showsJump: true)
            }
            .buttonStyle(ConductorPressButtonStyle(pressedScale: 0.992, pressedOpacity: 0.96))
            .macNativeTooltip(localizedPrimaryActionDetail(issue))
            .accessibilityLabel(Text("\(localizedIssueTitle(issue))。\(localizedPrimaryActionTitle(issue))"))
        } else {
            recoveryIssueContent(issue, showsJump: false)
        }
    }

    private func recoveryIssueContent(
        _ issue: SessionSurfaceInspectionSnapshot.RecoveryIssue,
        showsJump: Bool
    ) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: issueIcon(issue))
                .font(.conductorSystem(size: 9.2, weight: .semibold, scale: fontScale))
                .foregroundStyle(issueColor(issue))
                .frame(width: 15, height: 18)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(surfacePrefix(issue))
                        .font(.conductorSystem(size: 8.8, weight: .semibold, scale: fontScale))
                        .foregroundStyle(issueColor(issue))
                        .lineLimit(1)
                    Text(localizedIssueTitle(issue))
                        .font(.conductorSystem(size: 10.2, weight: .semibold, scale: fontScale))
                        .foregroundStyle(ConductorDesign.secondaryText)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                Text("\(issue.workspaceTitle) · \(issue.surfaceTitle)")
                    .font(.conductorSystem(size: 9.2, weight: .medium, scale: fontScale))
                    .foregroundStyle(ConductorDesign.tertiaryText)
                    .lineLimit(1)
                Text(localizedIssueImpact(issue))
                    .font(.conductorSystem(size: 9.2, weight: .medium, scale: fontScale))
                    .foregroundStyle(ConductorDesign.tertiaryText.opacity(0.90))
                    .lineLimit(2)
            }
            if showsJump {
                HStack(spacing: 5) {
                    Image(systemName: issue.primaryAction.systemImage)
                        .font(.conductorSystem(size: 8.8, weight: .semibold, scale: fontScale))
                        .accessibilityHidden(true)
                    Text(localizedPrimaryActionTitle(issue))
                        .font(.conductorSystem(size: 9.3, weight: .semibold, scale: fontScale))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }
                .foregroundStyle(issue.primaryAction.destructive ? Color.red.opacity(0.90) : theme.floatingEmphasis)
                .padding(.horizontal, 7)
                .frame(height: 24)
                .background(theme.floatingControlStrongFill.opacity(theme.usesDarkChrome ? 0.46 : 0.42))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .padding(.top, 1)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(theme.floatingControlStrongFill.opacity(theme.usesDarkChrome ? 0.34 : 0.32))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private var recommendedRecoveryActions: [String] {
        if report.state == .failed && canRestorePrevious {
            return [L("如果当前工作台不对，恢复上一份有效快照。", "Restore the previous valid snapshot if this workbench looks wrong.")]
        }
        if !report.missingFilePaths.isEmpty {
            return [L("恢复缺失文件，或关闭已经失效的文件标签。", "Restore missing files or close stale file tabs.")]
        }
        if surfaceInspection.criticalIssueCount > 0 || surfaceInspection.warningIssueCount > 0 {
            return [L("点开有问题的 surface，确认目录、网页加载或文件状态。", "Jump to affected surfaces and confirm directories, page loads, or file state.")]
        }
        return []
    }

    private func target(for issue: SessionSurfaceInspectionSnapshot.RecoveryIssue) -> SessionRecoverySurfaceTarget? {
        switch issue.surfaceKind {
        case .terminal:
            guard let terminalID = issue.terminalID else { return nil }
            return .terminal(workspaceID: issue.workspaceID, terminalID: terminalID)
        case .browser:
            guard let webTabID = issue.webTabID else { return nil }
            return .webTab(workspaceID: issue.workspaceID, tabID: webTabID)
        case .file:
            guard let fileTabID = issue.fileTabID else { return nil }
            return .fileTab(workspaceID: issue.workspaceID, tabID: fileTabID)
        }
    }

    private func issueIcon(_ issue: SessionSurfaceInspectionSnapshot.RecoveryIssue) -> String {
        switch issue.severity {
        case .critical:
            return "exclamationmark.triangle.fill"
        case .warning:
            return "exclamationmark.circle.fill"
        case .info:
            return "info.circle"
        }
    }

    private func issueColor(_ issue: SessionSurfaceInspectionSnapshot.RecoveryIssue) -> Color {
        switch issue.severity {
        case .critical:
            return .red
        case .warning:
            return .orange
        case .info:
            return theme.floatingEmphasis
        }
    }

    private func surfacePrefix(_ issue: SessionSurfaceInspectionSnapshot.RecoveryIssue) -> String {
        switch issue.surfaceKind {
        case .terminal:
            return L("终端", "Terminal")
        case .browser:
            return L("网页", "Browser")
        case .file:
            return L("文件", "File")
        }
    }

    private func issueTitle(_ issue: String) -> String {
        switch issue {
        case "missing_working_directory":
            return L("缺少目录", "missing cwd")
        case "agent_resume_metadata_missing":
            return L("缺少恢复信息", "missing resume data")
        case "terminal_process_restarted":
            return L("进程已重启", "fresh process")
        case "blank_web_tab":
            return L("空白页", "blank tab")
        case "web_error":
            return L("加载错误", "load error")
        case "history_missing":
            return L("缺少历史", "missing history")
        case "scroll_position_missing":
            return L("缺少滚动位置", "missing scroll")
        case "file_missing":
            return L("文件不存在", "missing file")
        case "file_changed_on_disk":
            return L("磁盘已变更", "changed on disk")
        default:
            return issue.replacingOccurrences(of: "_", with: " ")
        }
    }

    private func localizedIssueTitle(_ issue: SessionSurfaceInspectionSnapshot.RecoveryIssue) -> String {
        issueTitle(issue.kind)
    }

    private func localizedSuggestedAction(_ issue: SessionSurfaceInspectionSnapshot.RecoveryIssue) -> String {
        switch issue.kind {
        case "missing_working_directory":
            return L("聚焦终端，确认当前目录是否符合预期。", "Focus the terminal and confirm its current directory.")
        case "agent_resume_metadata_missing":
            return L("下次运行时输出受支持的续接提示，让恢复信息可被记录。", "Run with a supported resume hint so recovery metadata can be captured.")
        case "terminal_process_restarted":
            return L("上下文已恢复，但原进程没有重新挂上；需要时续接 Agent 或重跑命令。", "Context was restored, but the original process was not reattached; resume the agent or rerun commands when needed.")
        case "blank_web_tab":
            return L("关闭空标签，或输入需要恢复的地址。", "Close the empty tab or navigate it to the intended address.")
        case "web_error":
            return L("跳到网页标签，检查地址并重新载入。", "Jump to the browser tab, check the address, and reload.")
        case "history_missing":
            return L("继续使用这个网页；后续导航会重建历史记录。", "Continue using the page; future navigation will rebuild history.")
        case "scroll_position_missing":
            return L("恢复后滚动一次，下次快照会记录阅读位置。", "Scroll once after restore so the next snapshot captures the reading position.")
        case "file_missing":
            return L("恢复文件路径，或关闭这个失效文件标签。", "Restore the file path or close the stale file tab.")
        case "file_changed_on_disk":
            return L("保存前先确认磁盘上的变更。", "Review the disk version before saving.")
        default:
            return issue.suggestedAction
        }
    }

    private func localizedIssueImpact(_ issue: SessionSurfaceInspectionSnapshot.RecoveryIssue) -> String {
        switch issue.kind {
        case "missing_working_directory":
            return L("命令可能会从兜底目录执行，先确认目录再继续。", "Commands may run from a fallback directory until the terminal is checked.")
        case "agent_resume_metadata_missing":
            return L("界面能恢复，但还不能安全自动续接这个 Agent。", "The session can be restored visually, but automatic agent continuation is not safe.")
        case "terminal_process_restarted":
            return L("上下文和输出已恢复，但原来的实时进程已经不在。", "Scrollback and context are restored, but the original live process is gone.")
        case "blank_web_tab":
            return L("没有地址时，这个网页标签没有可恢复的浏览上下文。", "This tab cannot restore useful browsing context until it has an address.")
        case "web_error":
            return L("标签已恢复，但页面当前不可用，先重载验证。", "The tab restored, but the page is not currently usable.")
        case "web_runtime_error":
            return L("页面加载了，但最近的脚本或控制台错误可能解释异常。", "The page loaded, but recent script or console errors may explain broken behavior.")
        case "history_missing":
            return L("这个标签恢复后的前进/后退可能不完整。", "Back and forward may be incomplete for this restored tab.")
        case "scroll_position_missing":
            return L("页面可能回到顶部，而不是上次阅读位置。", "The page may reopen near the top instead of the last reading position.")
        case "file_missing":
            return L("路径不存在前，这个文件标签无法重新打开内容。", "The file tab cannot reopen content until the path exists again.")
        case "file_changed_on_disk":
            return L("现在保存可能覆盖外部工具写入的内容。", "Saving now could overwrite changes made outside Conductor.")
        default:
            return issue.impact
        }
    }

    private func localizedPrimaryActionTitle(_ issue: SessionSurfaceInspectionSnapshot.RecoveryIssue) -> String {
        switch issue.primaryAction.kind {
        case "focus_web_address":
            return L("输入地址", "Enter Address")
        case "reload_web_tab":
            return L("重载网页", "Reload")
        case "focus_file_tab":
            return issue.kind == "file_changed_on_disk"
                ? L("先比较", "Compare")
                : L("查看文件", "Review")
        case "focus_terminal":
            return L("打开终端", "Open")
        default:
            return L("定位", "Show")
        }
    }

    private func localizedPrimaryActionDetail(_ issue: SessionSurfaceInspectionSnapshot.RecoveryIssue) -> String {
        switch issue.primaryAction.kind {
        case "focus_web_address":
            return L("切到这个网页标签，并把光标放到地址栏", "Select this browser tab and focus its address field")
        case "reload_web_tab":
            return L("切到这个网页标签，并重新载入当前地址", "Select this browser tab and retry the page load")
        case "focus_file_tab":
            return L("切到这个文件标签，确认路径或磁盘变更", "Select this file tab and review the path or disk changes")
        case "focus_terminal":
            return L("切到这个终端，确认目录、输出和续接方式", "Select this terminal and check directory, output, and resume options")
        default:
            return localizedSuggestedAction(issue)
        }
    }

    private func copyToPasteboard(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    private func eventTitle(_ kind: ConductorSessionJournalEvent.Kind) -> String {
        switch kind {
        case .snapshotSaved:
            return L("保存快照", "Snapshot saved")
        case .workspaceCreated:
            return L("新建工作区", "Workspace created")
        case .workspaceRenamed:
            return L("重命名工作区", "Workspace renamed")
        case .workspaceDuplicated:
            return L("复制工作区", "Workspace duplicated")
        case .workspaceClosed:
            return L("关闭工作区", "Workspace closed")
        case .workspaceSelected:
            return L("切换工作区", "Workspace selected")
        case .terminalCreated:
            return L("新建终端", "Terminal created")
        case .terminalDuplicated:
            return L("复制终端", "Terminal duplicated")
        case .terminalClosed, .paneClosed:
            return L("关闭终端", "Terminal closed")
        case .browserTabOpened:
            return L("打开网页", "Browser opened")
        case .browserTabNavigated:
            return L("网页跳转", "Browser navigated")
        case .browserTabClosed:
            return L("关闭网页", "Browser closed")
        case .fileTabOpened:
            return L("打开文件", "File opened")
        case .fileTabClosed:
            return L("关闭文件", "File closed")
        }
    }

    private func eventIcon(_ kind: ConductorSessionJournalEvent.Kind) -> String {
        switch kind {
        case .snapshotSaved:
            return "tray.and.arrow.down"
        case .workspaceCreated, .workspaceRenamed, .workspaceDuplicated, .workspaceClosed, .workspaceSelected:
            return "rectangle.grid.2x2"
        case .terminalCreated, .terminalDuplicated, .terminalClosed, .paneClosed:
            return "terminal"
        case .browserTabOpened, .browserTabNavigated, .browserTabClosed:
            return "globe"
        case .fileTabOpened, .fileTabClosed:
            return "doc.text"
        }
    }

    private func eventCountSummary(_ event: ConductorSessionJournalEvent) -> String {
        L(
            "\(event.workspaceCount) 工作区 · \(event.terminalCount) 终端",
            "\(event.workspaceCount) ws · \(event.terminalCount) terms"
        )
    }
}
