import AppKit
import ConductorCore
import SwiftUI

private enum AgentToolsAgentFilter: String, CaseIterable, Identifiable {
    case all
    case launchable
    case configured
    case skillTargets
    case running
    case sessions
    case attention

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return L("全部")
        case .launchable: return L("可启动")
        case .configured: return L("已配置")
        case .skillTargets: return L("可接收 Skill")
        case .running: return L("运行中")
        case .sessions: return L("可续聊")
        case .attention: return L("待处理")
        }
    }
}

private enum AgentToolsAgentSort: String, CaseIterable, Identifiable {
    case status
    case name
    case skills
    case sessions

    var id: String { rawValue }

    var title: String {
        switch self {
        case .status: return L("状态")
        case .name: return L("名称")
        case .skills: return "Skills"
        case .sessions: return L("会话")
        }
    }
}

private struct AgentToolsAgentRow: Identifiable {
    let id: String
    let canonicalAgentID: String?
    let title: String
    let command: String
    let logoName: String
    let fallbackSystemImage: String
    let descriptor: AgentDescriptor?
    let cliTool: CLIToolStatus?
    let configuredAgent: AIAgentConfig?
    let launchableAgent: LaunchableAgent?
    let skillTool: SkillToolInfo?
    let syncedSkillCount: Int
    let recentSessionCount: Int
    let latestSessionAt: Date?
    let runningPaneCount: Int
    let thinkingPaneCount: Int
    let unseenDonePaneCount: Int
    let queuedPaneCount: Int

    var isConfigured: Bool { configuredAgent != nil }
    var isLaunchDisabled: Bool { configuredAgent?.enabled == false }
    var canLaunch: Bool {
        if isLaunchDisabled { return false }
        return launchableAgent != nil || configuredAgent?.enabled == true || cliTool?.isInstalled == true
    }
    var hasAttention: Bool {
        (!canLaunch && descriptor != nil) || (skillTool != nil && skillTool?.enabled == false)
    }
    var launchLabel: String {
        if isLaunchDisabled { return L("已停用") }
        if canLaunch { return configuredAgent == nil ? L("自动检测") : L("可启动") }
        if configuredAgent != nil { return L("命令待确认") }
        return L("未安装")
    }
    @MainActor var launchColor: Color {
        if isLaunchDisabled { return AppStyle.textTertiary }
        if canLaunch { return AppStyle.doneGreen }
        if configuredAgent != nil { return AppStyle.waitAmber }
        return AppStyle.textTertiary
    }
    var skillLabel: String {
        guard let skillTool else { return "-" }
        if !skillTool.enabled { return L("已停用") }
        if skillTool.installed || skillTool.isCustom || skillTool.hasPathOverride {
            return L("%ld Skills", syncedSkillCount)
        }
        return L("未检测")
    }
    @MainActor var skillColor: Color {
        guard let skillTool else { return AppStyle.textTertiary }
        if !skillTool.enabled { return AppStyle.waitAmber }
        if skillTool.installed || skillTool.isCustom || skillTool.hasPathOverride { return AppStyle.accent }
        return AppStyle.textTertiary
    }
    var runtimeLabel: String {
        if thinkingPaneCount > 0 { return L("思考中") }
        if runningPaneCount > 0 { return L("%ld pane", runningPaneCount) }
        return "-"
    }
    @MainActor var runtimeColor: Color {
        if thinkingPaneCount > 0 { return AppStyle.accent }
        if runningPaneCount > 0 { return AppStyle.doneGreen }
        return AppStyle.textTertiary
    }
}

private enum AgentToolsAgentRegistry {
    static let skillKeyByAgentID: [String: String] = [
        "codex": "codex",
        "claude": "claude_code",
        "gemini": "gemini_cli",
        "cursor": "cursor",
        "copilot": "github_copilot",
        "grok": "grok",
        "opencode": "opencode",
        "amp": "amp",
        "auggie": "augment",
        "augment": "augment",
    ]

    static let agentIDBySkillKey: [String: String] = {
        var out: [String: String] = [:]
        for (agent, skill) in skillKeyByAgentID where out[skill] == nil {
            out[skill] = agent
        }
        return out
    }()

    @MainActor static func rows(
        store: AgentToolsConsoleStore,
        runtime: AgentToolsRuntimeSnapshot,
        config: AppConfig,
        sessions: [AgentSessionRecord]
    ) -> [AgentToolsAgentRow] {
        let descriptors = Dictionary(uniqueKeysWithValues: AgentCatalog.all.map { ($0.id, $0) })
        let cliTools = Dictionary(uniqueKeysWithValues: store.cliTools.map { ($0.id, $0) })
        let configured = Dictionary(uniqueKeysWithValues: AIAgentConfig.validatedList(config.terminal.aiAgents).map { ($0.id, $0) })
        let launchables = Dictionary(uniqueKeysWithValues: runtime.launchableAgents.map { ($0.id, $0) })
        let skillToolsByKey = Dictionary(uniqueKeysWithValues: store.skillTools.map { ($0.key, $0) })
        let skillCountByTool = Dictionary(grouping: store.managedSkills.flatMap(\.targets), by: \.tool)
            .mapValues(\.count)
        let sessionsByAgent = Dictionary(grouping: sessions, by: \.agent)
        let runtimePaneIDsByAgent = Dictionary(grouping: runtime.paneAgentsByPaneID, by: \.value)
            .mapValues { pairs in pairs.map(\.key) }

        var ids = Set(descriptors.keys)
        ids.formUnion(cliTools.keys)
        ids.formUnion(configured.keys)
        ids.formUnion(launchables.keys)
        for tool in store.skillTools {
            ids.insert(agentIDBySkillKey[tool.key] ?? "skill:\(tool.key)")
        }

        return ids.map { id in
            let skillKey = id.hasPrefix("skill:")
                ? String(id.dropFirst("skill:".count))
                : skillKeyByAgentID[id]
            let skillTool = skillKey.flatMap { skillToolsByKey[$0] }
            let descriptor = descriptors[id]
            let cliTool = cliTools[id]
            let configAgent = configured[id]
            let launchable = launchables[id]
            let canonicalAgentID = id.hasPrefix("skill:") ? nil : id
            let panes = canonicalAgentID.flatMap { runtimePaneIDsByAgent[$0] } ?? []
            let agentSessions = canonicalAgentID.flatMap { sessionsByAgent[$0] } ?? []
            let title = configAgent?.title
                ?? launchable?.title
                ?? cliTool?.name
                ?? descriptor?.name
                ?? skillTool?.displayName
                ?? id
            let command = configAgent?.command
                ?? launchable?.command
                ?? descriptor?.command
                ?? canonicalAgentID
                ?? ""
            return AgentToolsAgentRow(
                id: id,
                canonicalAgentID: canonicalAgentID,
                title: title,
                command: command,
                logoName: descriptor?.logo ?? cliTool?.logo ?? logoName(forSkillKey: skillKey, fallback: id),
                fallbackSystemImage: descriptor?.fallbackSystemImage ?? cliTool?.fallbackSystemImage ?? "cpu",
                descriptor: descriptor,
                cliTool: cliTool,
                configuredAgent: configAgent,
                launchableAgent: launchable,
                skillTool: skillTool,
                syncedSkillCount: skillKey.flatMap { skillCountByTool[$0] } ?? 0,
                recentSessionCount: agentSessions.count,
                latestSessionAt: agentSessions.map(\.modifiedAt).max(),
                runningPaneCount: panes.count,
                thinkingPaneCount: panes.filter { runtime.thinkingPaneIDs.contains($0) }.count,
                unseenDonePaneCount: panes.filter { runtime.unseenDonePaneIDs.contains($0) }.count,
                queuedPaneCount: panes.filter { runtime.queuedPaneIDs.contains($0) }.count)
        }
        .sorted(by: sort)
    }

    static func sort(_ lhs: AgentToolsAgentRow, _ rhs: AgentToolsAgentRow) -> Bool {
        let lhsScore = statusScore(lhs)
        let rhsScore = statusScore(rhs)
        if lhsScore != rhsScore { return lhsScore > rhsScore }
        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }

    static func statusScore(_ row: AgentToolsAgentRow) -> Int {
        var score = 0
        if row.canLaunch { score += 100 }
        if row.skillTool != nil { score += 40 }
        if row.runningPaneCount > 0 { score += 30 }
        if row.isConfigured { score += 20 }
        if row.recentSessionCount > 0 { score += 10 }
        if row.hasAttention { score += 5 }
        return score
    }

    private static func logoName(forSkillKey key: String?, fallback: String) -> String {
        switch key {
        case "claude_code": return "claude"
        case "gemini_cli": return "gemini"
        case "github_copilot": return "copilot"
        case "augment": return "augment"
        case "command_code": return "commandcode"
        case let key?: return key
        case nil: return fallback
        }
    }
}

struct AgentToolsAgentsView: View {
    @ObservedObject var store: AgentToolsConsoleStore
    let runtime: AgentToolsRuntimeSnapshot
    let onLaunch: (String) -> Void
    let onApplyConfig: (AppConfig) -> Void
    let onScanAgentsIntoConfig: () -> Void
    let onOpenModule: (AgentToolsManagementModule) -> Void

    @ObservedObject private var configStore = ConfigStore.shared
    @ObservedObject private var sessionStore = SessionManagerStore.shared
    @State private var query = ""
    @State private var filter: AgentToolsAgentFilter = .all
    @State private var sort: AgentToolsAgentSort = .status

    private var allRows: [AgentToolsAgentRow] {
        AgentToolsAgentRegistry.rows(
            store: store,
            runtime: runtime,
            config: configStore.config,
            sessions: sessionStore.records)
    }

    private var rows: [AgentToolsAgentRow] {
        var list = allRows
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !q.isEmpty {
            list = list.filter {
                $0.title.lowercased().contains(q)
                    || $0.id.lowercased().contains(q)
                    || $0.command.lowercased().contains(q)
                    || ($0.cliTool?.path?.lowercased().contains(q) ?? false)
                    || ($0.skillTool?.skillsDirectory.lowercased().contains(q) ?? false)
            }
        }
        list = list.filter { row in
            switch filter {
            case .all: return true
            case .launchable: return row.canLaunch
            case .configured: return row.isConfigured
            case .skillTargets: return row.skillTool != nil
            case .running: return row.runningPaneCount > 0
            case .sessions: return row.recentSessionCount > 0
            case .attention: return row.hasAttention
            }
        }
        switch sort {
        case .status:
            list.sort(by: AgentToolsAgentRegistry.sort)
        case .name:
            list.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .skills:
            list.sort {
                $0.syncedSkillCount == $1.syncedSkillCount
                    ? $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                    : $0.syncedSkillCount > $1.syncedSkillCount
            }
        case .sessions:
            list.sort {
                $0.recentSessionCount == $1.recentSessionCount
                    ? $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                    : $0.recentSessionCount > $1.recentSessionCount
            }
        }
        return list
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            toolbar
            metricStrip
            registryTable
        }
        .agentToolsPage()
        .onAppear {
            store.start()
            if store.skillTools.isEmpty { store.refreshAgentRegistry() }
            sessionStore.refresh()
            selectDefaultIfNeeded()
        }
        .onChange(of: allRows.map(\.id)) { _, _ in selectDefaultIfNeeded() }
    }

    private var header: some View {
        AgentToolsModuleHeader(
            title: "Agents",
            subtitle: L("启动入口、Skill 目标、运行状态和可续聊会话"),
            icon: "cpu") {
            ToolActionButton(
                title: L("自动加入已检测"),
                systemImage: "wand.and.stars",
                height: 34,
                fontSize: 11.5,
                horizontalPadding: 12,
                help: L("把已检测到的 Agent 加入启动入口")) {
                    onScanAgentsIntoConfig()
                    store.scanCLI()
                }
            ToolActionButton(
                title: store.isScanningCLI || store.isLoadingAgentRegistry ? L("扫描中") : L("重新扫描"),
                systemImage: store.isScanningCLI || store.isLoadingAgentRegistry ? nil : "arrow.clockwise",
                height: 34,
                fontSize: 11.5,
                horizontalPadding: 12,
                help: L("重新扫描 Agent 与 Skill 目标")) {
                    store.scanCLI()
                    store.refreshAgentRegistry()
                    sessionStore.refresh(force: true)
                }
            .disabled(store.isScanningCLI || store.isLoadingAgentRegistry)
            ToolActionButton(
                title: L("新增自定义 Agent"),
                systemImage: "plus",
                height: 34,
                fontSize: 11.5,
                horizontalPadding: 12,
                help: L("添加自定义 Agent 启动命令"),
                action: addCustomAgent)
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            AgentToolsSearchField(placeholder: L("搜索 Agent / 命令 / 目录"), text: $query)

            AgentToolsMenuButton(title: filter.title, icon: "line.3.horizontal.decrease.circle") {
                ForEach(AgentToolsAgentFilter.allCases) { option in
                    Button(option.title) { withAnimation(AgentToolsMotion.selection) { filter = option } }
                }
            }

            AgentToolsMenuButton(title: sort.title, icon: "arrow.up.arrow.down") {
                ForEach(AgentToolsAgentSort.allCases) { option in
                    Button(option.title) { withAnimation(AgentToolsMotion.selection) { sort = option } }
                }
            }

            Spacer(minLength: 0)

            if let error = store.agentRegistryError {
                ToolBadge(text: error, color: AppStyle.errorRed, style: .muted, height: 22)
                    .lineLimit(1)
            }
        }
    }

    private var metricStrip: some View {
        HStack(alignment: .top, spacing: 30) {
            AgentToolsStat(
                value: "\(allRows.filter(\.canLaunch).count)",
                title: L("可启动"),
                sub: L("%ld 个 Agent", allRows.count))
            AgentToolsStat(
                value: "\(AIAgentConfig.validatedList(configStore.config.terminal.aiAgents).count)",
                title: L("已配置"),
                sub: L("启动入口"),
                action: { onOpenModule(.cli) })
            AgentToolsStat(
                value: "\(store.skillTargetCount)",
                title: L("Skill 目标"),
                sub: "Skills",
                action: { onOpenModule(.skills) })
            AgentToolsStat(
                value: "\(runtime.paneAgentsByPaneID.count)",
                title: L("运行中"),
                sub: runtime.paneAgentsByPaneID.isEmpty ? L("无运行") : L("活跃 pane"),
                valueColor: runtime.paneAgentsByPaneID.isEmpty ? AppStyle.textPrimary : AppStyle.doneGreen)
            AgentToolsStat(
                value: "\(sessionStore.records.count)",
                title: L("可续聊"),
                sub: L("历史会话"))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.md)
        .padding(.vertical, 14)
        .agentToolsGlass()
    }

    private var registryTable: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                ToolsSectionLabel(L("Agent 注册表"))
                Spacer()
                Text(L("%ld 个 Agent", rows.count))
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(AppStyle.textTertiary)
            }
            VStack(spacing: 0) {
                tableHeader
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(rows) { row in
                            agentRow(row)
                        }
                        if rows.isEmpty {
                            Text(L("无匹配结果"))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(AppStyle.textTertiary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 24)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .scrollIndicators(.visible)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
            .agentToolsGlass()
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var tableHeader: some View {
        ViewThatFits(in: .horizontal) {
            tableHeaderRow(showSessions: true, minAgentWidth: 190, launchWidth: 90, skillsWidth: 110, runtimeWidth: 110, actionWidth: 82)
            tableHeaderRow(showSessions: false, minAgentWidth: 170, launchWidth: 82, skillsWidth: 92, runtimeWidth: 88, actionWidth: 58)
        }
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(AppStyle.textTertiary)
        .padding(.horizontal, 9)
        .frame(height: 28)
    }

    private func tableHeaderRow(showSessions: Bool,
                                minAgentWidth: CGFloat,
                                launchWidth: CGFloat,
                                skillsWidth: CGFloat,
                                runtimeWidth: CGFloat,
                                actionWidth: CGFloat) -> some View {
        HStack(spacing: 8) {
            Text("Agent").frame(minWidth: minAgentWidth, maxWidth: .infinity, alignment: .leading)
            Text(L("启动")).frame(width: launchWidth)
            Text("Skills").frame(width: skillsWidth)
            Text(L("运行态")).frame(width: runtimeWidth)
            if showSessions {
                Text(L("会话")).frame(width: 90)
            }
            Text(L("操作")).frame(width: actionWidth)
        }
    }

    private func agentRow(_ row: AgentToolsAgentRow) -> some View {
        let selected = store.selectedAgentID == row.id
        return Button {
            withAnimation(AgentToolsMotion.selection) { store.selectedAgentID = row.id }
        } label: {
            ViewThatFits(in: .horizontal) {
                agentRowContent(row, showSessions: true, minAgentWidth: 190, launchWidth: 90, skillsWidth: 110, runtimeWidth: 110, actionWidth: 82)
                agentRowContent(row, showSessions: false, minAgentWidth: 170, launchWidth: 82, skillsWidth: 92, runtimeWidth: 88, actionWidth: 58)
            }
            .padding(.horizontal, 9)
            .frame(height: 44)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(selected ? AppStyle.accent.opacity(0.12) : Color.clear))
            .overlay(alignment: .leading) {
                // 选中态签名：左侧一道 accent 键线（编辑式重点，非分隔硬线）。
                if selected {
                    Capsule().fill(AppStyle.accent).frame(width: 3, height: 18)
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
            .animation(AgentToolsMotion.selection, value: selected)
        }
        .buttonStyle(PressScaleStyle())
        .simultaneousGesture(TapGesture(count: 2).onEnded {
            if row.canLaunch { onLaunch(row.command) }
        })
        .contextMenu { contextMenu(for: row) }
    }

    private func agentRowContent(_ row: AgentToolsAgentRow,
                                 showSessions: Bool,
                                 minAgentWidth: CGFloat,
                                 launchWidth: CGFloat,
                                 skillsWidth: CGFloat,
                                 runtimeWidth: CGFloat,
                                 actionWidth: CGFloat) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 10) {
                AgentToolsAgentLogo(row: row)
                    .frame(width: 22, height: 22)
                    .frame(width: 32, height: 32)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(AppStyle.hoverFill))
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.title)
                        .font(.system(size: 12.4, weight: .semibold))
                        .foregroundStyle(AppStyle.textPrimary)
                        .lineLimit(1)
                    HStack(spacing: 5) {
                        Text(row.id)
                            .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                        if !row.command.isEmpty {
                            Text(row.command)
                                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    .foregroundStyle(AppStyle.textTertiary)
                }
                Spacer(minLength: 0)
            }
            .frame(minWidth: minAgentWidth, maxWidth: .infinity, alignment: .leading)

            statusCell(row.launchLabel, color: row.launchColor)
                .frame(width: launchWidth)

            statusCell(row.skillLabel, color: row.skillColor)
                .frame(width: skillsWidth)

            statusCell(row.runtimeLabel, color: row.runtimeColor)
                .frame(width: runtimeWidth)

            if showSessions {
                Text(row.recentSessionCount > 0 ? "\(row.recentSessionCount)" : "-")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(row.recentSessionCount > 0 ? AppStyle.textSecondary : AppStyle.textTertiary)
                    .frame(width: 90)
            }

            HStack(spacing: showSessions ? 6 : 4) {
                IconOnlyButton(
                    systemName: "play.fill",
                    help: L("启动到新标签"),
                    size: 24,
                    symbolSize: 9.5,
                    tint: row.canLaunch ? AppStyle.accent : AppStyle.textTertiary) {
                        if row.canLaunch { onLaunch(row.command) }
                    }
                    .disabled(!row.canLaunch)
                IconOnlyButton(
                    systemName: "sidebar.right",
                    help: L("查看详情"),
                    size: 24,
                    symbolSize: 10,
                    tint: AppStyle.textTertiary) {
                        withAnimation(AgentToolsMotion.selection) { store.selectedAgentID = row.id }
                    }
            }
            .frame(width: actionWidth)
        }
    }

    /// 去填充的状态格：裸彩色文字，靠颜色和列对齐表意，不再套 chip。
    private func statusCell(_ label: String, color: Color) -> some View {
        Text(label)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    @ViewBuilder
    private func contextMenu(for row: AgentToolsAgentRow) -> some View {
        if row.canLaunch {
            Button(L("启动到新标签")) { onLaunch(row.command) }
        }
        if !row.command.isEmpty {
            Button(L("复制命令")) { copy(row.command) }
        }
        if let path = row.cliTool?.path {
            Button(L("复制路径")) { copy(path) }
            Button(L("在 Finder 中显示")) { reveal(path) }
        }
        if let tool = row.skillTool {
            Button(L("显示 Skills 目录")) { reveal(tool.skillsDirectory) }
            Button(tool.enabled ? L("停用 Skill 目标") : L("启用 Skill 目标")) {
                store.setSkillToolEnabled(tool, enabled: !tool.enabled)
            }
        }
        Divider()
        if row.configuredAgent == nil {
            Button(L("加入启动入口")) { setLaunchEntry(row, enabled: true) }
        } else {
            Button(row.isLaunchDisabled ? L("启用启动入口") : L("停用启动入口")) {
                setLaunchEntry(row, enabled: row.isLaunchDisabled)
            }
        }
        Button(L("复制诊断信息")) { copy(diagnostics(for: row)) }
    }

    private func selectDefaultIfNeeded() {
        guard store.selectedAgentID == nil else { return }
        store.selectedAgentID = allRows.first(where: \.canLaunch)?.id ?? allRows.first?.id
    }

    private func addCustomAgent() {
        let alert = NSAlert()
        alert.messageText = L("新增自定义 Agent")
        alert.informativeText = L("填写名称和启动命令，保存后会出现在新建 Agent 会话入口。")
        alert.addButton(withTitle: L("保存"))
        alert.addButton(withTitle: L("取消"))

        let nameField = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        nameField.placeholderString = L("名称")
        let commandField = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        commandField.placeholderString = L("Agent 启动命令")
        let stack = NSStackView(views: [nameField, commandField])
        stack.orientation = .vertical
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 0, bottom: 0, right: 0)
        alert.accessoryView = stack

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let command = commandField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { return }
        let title = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalTitle = title.isEmpty ? command : title
        let id = agentID(from: finalTitle)
        var config = configStore.config
        config.terminal.aiAgents.removeAll { $0.id == id }
        config.terminal.aiAgents.append(AIAgentConfig(id: id, title: finalTitle, command: command, enabled: true))
        onApplyConfig(config)
        withAnimation(AgentToolsMotion.selection) { store.selectedAgentID = id }
    }

    private func setLaunchEntry(_ row: AgentToolsAgentRow, enabled: Bool) {
        guard !row.command.isEmpty else { return }
        var config = configStore.config
        if let index = config.terminal.aiAgents.firstIndex(where: { $0.id == row.id }) {
            config.terminal.aiAgents[index].enabled = enabled
        } else {
            config.terminal.aiAgents.append(AIAgentConfig(
                id: row.canonicalAgentID ?? agentID(from: row.title),
                title: row.title,
                command: row.command,
                enabled: enabled))
        }
        onApplyConfig(config)
    }

    private func agentID(from raw: String) -> String {
        let lower = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let scalars = lower.unicodeScalars.map { scalar in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : "-"
        }
        let collapsed = String(scalars)
            .split(separator: "-")
            .joined(separator: "-")
        return collapsed.isEmpty ? "agent-\(Int(Date().timeIntervalSince1970))" : collapsed
    }

    private func diagnostics(for row: AgentToolsAgentRow) -> String {
        [
            "Conductor Agent Diagnostics",
            "id: \(row.id)",
            "title: \(row.title)",
            "command: \(row.command)",
            "launch: \(row.launchLabel)",
            "cli.path: \(row.cliTool?.path ?? "-")",
            "cli.version: \(row.cliTool?.version ?? "-")",
            "configured: \(row.configuredAgent == nil ? "false" : "true")",
            "skill.key: \(row.skillTool?.key ?? "-")",
            "skill.dir: \(row.skillTool?.skillsDirectory ?? "-")",
            "skill.synced: \(row.syncedSkillCount)",
            "runtime.panes: \(row.runningPaneCount)",
            "sessions: \(row.recentSessionCount)",
        ].joined(separator: "\n")
    }

    private func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private func reveal(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }
}

struct AgentToolsAgentsInspector: View {
    @ObservedObject var store: AgentToolsConsoleStore
    let runtime: AgentToolsRuntimeSnapshot
    let onLaunch: (String) -> Void
    let onApplyConfig: (AppConfig) -> Void
    let onOpenModule: (AgentToolsManagementModule) -> Void

    @ObservedObject private var configStore = ConfigStore.shared
    @ObservedObject private var sessionStore = SessionManagerStore.shared

    private var rows: [AgentToolsAgentRow] {
        AgentToolsAgentRegistry.rows(
            store: store,
            runtime: runtime,
            config: configStore.config,
            sessions: sessionStore.records)
    }

    private var selectedRow: AgentToolsAgentRow? {
        guard let id = store.selectedAgentID else { return nil }
        return rows.first { $0.id == id }
    }

    var body: some View {
        AgentToolsInspectorShell {
            if let row = selectedRow {
                selected(row)
            } else {
                defaultState
            }
        }
    }

    private var defaultState: some View {
        VStack(alignment: .leading, spacing: 12) {
            AgentToolsSection(L("Agents 概览")) {
                AgentToolsInfoRow(label: L("可启动"), value: "\(rows.filter(\.canLaunch).count)")
                AgentToolsInfoRow(label: L("已配置"), value: "\(AIAgentConfig.validatedList(configStore.config.terminal.aiAgents).count)")
                AgentToolsInfoRow(label: L("Skill 目标"), value: "\(store.skillTargetCount)")
                AgentToolsInfoRow(label: L("运行中"), value: "\(runtime.paneAgentsByPaneID.count)")
                AgentToolsInfoRow(label: L("可续聊"), value: "\(sessionStore.records.count)")
            }
            Text(L("选择一个 Agent 查看启动命令、Skill 目录、运行状态和会话。"))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppStyle.textTertiary)
                .lineSpacing(3)
        }
    }

    private func selected(_ row: AgentToolsAgentRow) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                AgentToolsAgentLogo(row: row)
                    .frame(width: 26, height: 26)
                    .frame(width: 40, height: 40)
                    .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(AppStyle.hoverFill))
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.title)
                        .font(.system(size: 14.5, weight: .bold))
                        .foregroundStyle(AppStyle.textPrimary)
                        .lineLimit(1)
                    Text(row.id)
                        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(AppStyle.textTertiary)
                        .lineLimit(1)
                }
            }

            AgentToolsSection(L("启动")) {
                AgentToolsInfoRow(label: L("状态"), value: row.launchLabel)
                AgentToolsInfoRow(label: L("命令"), value: row.command.isEmpty ? "-" : row.command, monospaced: !row.command.isEmpty)
                AgentToolsInfoRow(label: L("配置"), value: row.configuredAgent == nil ? L("自动检测") : (row.isLaunchDisabled ? L("已停用") : L("已启用")))
                if let version = row.cliTool?.version { AgentToolsInfoRow(label: L("版本"), value: version) }
            }

            if let path = row.cliTool?.path {
                AgentToolsSection(L("CLI 路径")) {
                    Text(path)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(AppStyle.textSecondary)
                        .textSelection(.enabled)
                        .lineLimit(3)
                        .truncationMode(.middle)
                }
            }

            AgentToolsSection("Skills") {
                AgentToolsInfoRow(label: L("状态"), value: row.skillLabel)
                AgentToolsInfoRow(label: L("已同步"), value: "\(row.syncedSkillCount)")
                if let tool = row.skillTool {
                    Text(tool.skillsDirectory)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(AppStyle.textSecondary)
                        .textSelection(.enabled)
                        .lineLimit(3)
                        .truncationMode(.middle)
                }
            }

            AgentToolsSection(L("运行态")) {
                AgentToolsInfoRow(label: L("运行中"), value: "\(row.runningPaneCount)")
                AgentToolsInfoRow(label: L("思考中"), value: "\(row.thinkingPaneCount)")
                AgentToolsInfoRow(label: L("完成未读"), value: "\(row.unseenDonePaneCount)")
                AgentToolsInfoRow(label: L("排队中"), value: "\(row.queuedPaneCount)")
            }

            AgentToolsSection(L("会话")) {
                AgentToolsInfoRow(label: L("可续聊"), value: "\(row.recentSessionCount)")
                AgentToolsInfoRow(label: L("最近"), value: row.latestSessionAt.map { UsageFormatting.agoText($0) } ?? "-")
            }

            VStack(alignment: .leading, spacing: 8) {
                ToolActionButton(
                    title: L("启动到新标签"),
                    systemImage: "play.fill",
                    role: .primary,
                    height: 28,
                    fontSize: 11,
                    horizontalPadding: 10) {
                        onLaunch(row.command)
                    }
                    .disabled(!row.canLaunch)
                    .opacity(row.canLaunch ? 1 : 0.55)

                ToolActionButton(
                    title: L("复制命令"),
                    systemImage: "doc.on.doc",
                    height: 28,
                    fontSize: 11,
                    horizontalPadding: 10) {
                        copy(row.command)
                    }
                    .disabled(row.command.isEmpty)

                AgentToolsLinkButton(title: L("打开 Skills 模块"), icon: "wand.and.stars") {
                    onOpenModule(.skills)
                }
                .padding(.top, 2)
            }
        }
    }

    private func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

private struct AgentToolsAgentLogo: View {
    let row: AgentToolsAgentRow

    var body: some View {
        if let image = CLIToolLogo.image(named: row.logoName) {
            if CLIToolLogo.isMonochrome(row.logoName) {
                Image(nsImage: image)
                    .resizable()
                    .renderingMode(.template)
                    .interpolation(.high)
                    .scaledToFit()
                    .foregroundStyle(AppStyle.textPrimary)
            } else {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            }
        } else {
            Image(systemName: row.fallbackSystemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppStyle.accent)
        }
    }
}
