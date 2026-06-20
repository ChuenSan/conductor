import AppKit
import SwiftUI

// MARK: - MCP 模块（资源 × client）
//
// 一台 MCP server 是「能力资源」，装进多个 client（Claude Desktop / Claude Code / Codex / Cursor /
// VS Code / Windsurf），跨事件共享。生效位置 = 它在哪些 client。视觉走极简扁平（Linear/Raycast）：
// 无玻璃、无图标方块、无药丸。折叠态只给三行安静信息 + 发丝分隔；装/停用/移除/编辑收进展开的竖列。

private enum AgentToolsMCPTransportFilter: String, CaseIterable, Identifiable {
    case all, stdio, remote, withEnv
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return L("全部传输")
        case .stdio: return "stdio"
        case .remote: return L("远程")
        case .withEnv: return L("需密钥")
        }
    }
}

private enum AgentToolsMCPAddTab: String, CaseIterable, Identifiable {
    case template, custom
    var id: String { rawValue }
    var title: String { self == .template ? L("模板库") : L("自定义") }
}

/// 逻辑 server：把扫描出的「每 client 一条」记录按 server 名聚合成一台资源。
private struct MCPServerGroup: Identifiable {
    let name: String
    let records: [AgentToolsMCPServerRecord]
    var id: String { name }

    var representative: AgentToolsMCPServerRecord {
        records.first(where: { $0.enabled }) ?? records[0]
    }
    var transport: AgentToolsMCPTransport { representative.transport }
    var endpointLabel: String { representative.endpointLabel }
    var envKeyCount: Int { records.map(\.envKeyCount).max() ?? 0 }
    var activeCount: Int { records.filter(\.enabled).count }
    var anyParked: Bool { records.contains { !$0.enabled } }

    func record(forClient displayName: String) -> AgentToolsMCPServerRecord? {
        records.first { $0.client == displayName }
    }
}

struct AgentToolsMCPWorkbenchView: View {
    @ObservedObject var store: AgentToolsConsoleStore

    @State private var query = ""
    @State private var transportFilter: AgentToolsMCPTransportFilter = .all
    @State private var clientFilter: String?
    @State private var expandedGroupID: String?
    @State private var showConfigFiles = false

    // 添加流程。
    @State private var showAddSheet = {
        #if DEBUG
        return ProcessInfo.processInfo.environment["CDR_DEBUG_ADD"] == "mcp"
        #else
        return false
        #endif
    }()
    @State private var addTab: AgentToolsMCPAddTab = .template
    @State private var selectedTargetIDs = Set<String>()
    @State private var customJSON = ""
    @State private var editingServer: AgentToolsMCPServerRecord?
    @State private var editingClientJSON: AgentToolsMCPClientAdapter?
    @State private var recordPendingDelete: AgentToolsMCPServerRecord?

    private var clients: [AgentToolsMCPClientAdapter] { AgentToolsMCPScanner.writableClients }

    // MARK: 分组 + 过滤

    private var allGroups: [MCPServerGroup] {
        Dictionary(grouping: store.mcpServers, by: \.name)
            .map { MCPServerGroup(name: $0.key, records: $0.value.sorted { lhs, rhs in
                lhs.client.localizedCaseInsensitiveCompare(rhs.client) == .orderedAscending
            }) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var filteredGroups: [MCPServerGroup] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return allGroups.filter { group in
            if !trimmed.isEmpty {
                let hit = group.name.lowercased().contains(trimmed)
                    || group.endpointLabel.lowercased().contains(trimmed)
                    || group.records.contains { $0.client.lowercased().contains(trimmed) }
                guard hit else { return false }
            }
            switch transportFilter {
            case .all: break
            case .stdio: guard group.transport == .stdio else { return false }
            case .remote: guard group.transport == .http || group.transport == .sse else { return false }
            case .withEnv: guard group.envKeyCount > 0 else { return false }
            }
            if let clientFilter,
               let adapter = clients.first(where: { $0.id == clientFilter }) {
                guard group.record(forClient: adapter.displayName) != nil else { return false }
            }
            return true
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .agentToolsPage()
        .overlay(alignment: .top) { AgentToolsNoticeBanner(text: store.mcpNotice) { store.mcpNotice = nil } }
        .sheet(isPresented: $showAddSheet) { addSheet }
        .sheet(item: $editingClientJSON) { adapter in
            AgentToolsJSONEditorSheet(
                title: L("编辑 %@ 的 MCP 配置", adapter.displayName),
                subtitle: adapter.path,
                hint: L("直接编辑该应用的 mcpServers：形如 { \"my-server\": { \"command\": \"npx\", \"args\": [...] } }。保存即写入文件。"),
                initialText: store.mcpClientJSON(for: adapter),
                onSave: { store.saveMCPClientJSON($0, for: adapter) },
                onClose: { editingClientJSON = nil })
        }
        .confirmationDialog(
            L("移除 MCP server？"),
            isPresented: Binding(
                get: { recordPendingDelete != nil },
                set: { if !$0 { recordPendingDelete = nil } }),
            titleVisibility: .visible,
            presenting: recordPendingDelete
        ) { record in
            Button(L("从 %@ 移除", record.client), role: .destructive) {
                store.removeMCPServer(record)
                recordPendingDelete = nil
            }
            Button(L("取消"), role: .cancel) { recordPendingDelete = nil }
        } message: { record in
            Text(L("将从 %@ 的配置文件删除 %@，不可撤销。只想临时关闭就用「停用」。", record.client, record.name))
        }
        .onAppear {
            if store.mcpServers.isEmpty { store.refreshMCP() }
        }
    }

    // MARK: 顶部（干净两行：标题+动作 / 搜索+筛选）

    private var header: some View {
        VStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("MCP")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(AppStyle.textPrimary)
                Text(summaryLine)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(AppStyle.textTertiary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                ToolActionButton(title: L("添加"), systemImage: "plus", role: .primary,
                                 height: 30, fontSize: 11.5, horizontalPadding: 12) { beginAdd() }
                IconOnlyButton(systemName: store.isScanningMCP ? "arrow.triangle.2.circlepath" : "arrow.clockwise",
                               help: L("重新扫描"), size: 30, symbolSize: 12) { store.refreshMCP() }
                    .disabled(store.isScanningMCP)
            }
            HStack(spacing: 8) {
                AgentToolsSearchField(placeholder: L("搜索 server / 入口 / 应用"), text: $query)
                AgentToolsMenuButton(title: filterTitle, icon: "line.3.horizontal.decrease") {
                    Section(L("传输")) {
                        ForEach(AgentToolsMCPTransportFilter.allCases) { option in
                            Button { withAnimation(AgentToolsMotion.selection) { transportFilter = option } } label: {
                                Label(option.title, systemImage: transportFilter == option ? "checkmark" : "")
                            }
                        }
                    }
                    Section(L("应用")) {
                        Button { withAnimation(AgentToolsMotion.selection) { clientFilter = nil } } label: {
                            Label(L("全部应用"), systemImage: clientFilter == nil ? "checkmark" : "")
                        }
                        ForEach(clients) { client in
                            Button { withAnimation(AgentToolsMotion.selection) { clientFilter = client.id } } label: {
                                Label(client.displayName, systemImage: clientFilter == client.id ? "checkmark" : "")
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 4)
        .padding(.bottom, 12)
    }

    private var summaryLine: String {
        let groups = allGroups
        guard !groups.isEmpty else { return L("还没有 server") }
        let covered = Set(store.mcpServers.filter(\.enabled).map(\.client)).count
        var parts = [L("%ld 个 server", groups.count), L("在 %ld 个应用", covered)]
        let needsEnv = groups.filter { $0.envKeyCount > 0 }.count
        if needsEnv > 0 { parts.append(L("%ld 需密钥", needsEnv)) }
        return parts.joined(separator: " · ")
    }

    private var filterTitle: String {
        if transportFilter != .all { return transportFilter.title }
        if let clientFilter, let a = clients.first(where: { $0.id == clientFilter }) { return shortClientName(a) }
        return L("筛选")
    }

    // MARK: 内容（扁平列表 + 发丝分隔）

    private var content: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if filteredGroups.isEmpty {
                    emptyState
                } else {
                    ForEach(Array(filteredGroups.enumerated()), id: \.element.id) { index, group in
                        if index > 0 { hairline }
                        groupRow(group)
                    }
                }
                Spacer(minLength: 18)
                configFilesFooter
                if let error = store.mcpScanError {
                    Text(error)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(AppStyle.errorRed)
                        .lineLimit(4)
                        .padding(.horizontal, 14)
                        .padding(.top, 8)
                }
            }
            .padding(.bottom, 16)
        }
        .scrollIndicators(.never)
    }

    private var hairline: some View {
        Rectangle()
            .fill(AppStyle.separator.opacity(0.4))
            .frame(height: 1)
            .padding(.leading, 14)
    }

    // MARK: 单行 server

    private func groupRow(_ group: MCPServerGroup) -> some View {
        let expanded = expandedGroupID == group.id
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(AgentToolsMotion.reveal) { expandedGroupID = expanded ? nil : group.id }
            } label: {
                collapsedRow(group, expanded: expanded)
            }
            .buttonStyle(.plain)

            if expanded {
                expandedDetail(group)
                    .transition(AgentToolsMotion.revealTransition)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(expanded ? AppStyle.hoverFill.opacity(0.5) : Color.clear)
                .padding(.horizontal, 6))
    }

    private func collapsedRow(_ group: MCPServerGroup, expanded: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(group.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppStyle.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(transportLabel(group))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(transportTextColor(group.transport))
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(AppStyle.textTertiary)
                    .rotationEffect(.degrees(expanded ? 90 : 0))
            }
            Text(group.endpointLabel)
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundStyle(AppStyle.textTertiary)
                .lineLimit(1)
                .truncationMode(.middle)
            presenceLine(group)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }

    private func transportLabel(_ group: MCPServerGroup) -> String {
        group.envKeyCount > 0 ? group.transport.title + " · " + L("需密钥") : group.transport.title
    }

    /// 在哪些应用：已装的实色名字（带圆点），未装收成「· 未装 N」。
    private func presenceLine(_ group: MCPServerGroup) -> some View {
        let installed = clients.filter { group.record(forClient: $0.displayName)?.enabled == true }
        let parked = clients.filter { c in
            if let r = group.record(forClient: c.displayName) { return !r.enabled }
            return false
        }
        return HStack(spacing: 6) {
            Circle()
                .fill(installed.isEmpty ? AppStyle.textTertiary.opacity(0.5) : AppStyle.accent)
                .frame(width: 5, height: 5)
            if installed.isEmpty {
                Text(L("未安装"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppStyle.textTertiary)
            } else {
                Text(installed.map { shortClientName($0) }.joined(separator: " · "))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppStyle.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            if !parked.isEmpty {
                Text(L("· %ld 停用", parked.count))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppStyle.waitAmber)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: 展开详情（每个应用一行，动作做成文字链接）

    private func expandedDetail(_ group: MCPServerGroup) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(clients) { client in
                clientControlRow(group, client)
                if client.id != clients.last?.id {
                    Rectangle().fill(AppStyle.separator.opacity(0.25)).frame(height: 1)
                }
            }
            HStack(spacing: 14) {
                AgentToolsLinkButton(title: L("编辑 server 配置"), icon: "square.and.pencil", tint: AppStyle.accent) {
                    beginEditing(group.representative)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 4)
        }
        .padding(.bottom, 8)
    }

    private func clientControlRow(_ group: MCPServerGroup, _ client: AgentToolsMCPClientAdapter) -> some View {
        let record = group.record(forClient: client.displayName)
        let state: MCPLightState = record == nil ? .absent : (record!.enabled ? .active : .parked)
        return HStack(spacing: 8) {
            Circle()
                .fill(state.dotColor)
                .frame(width: 6, height: 6)
            Text(client.displayName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(state == .absent ? AppStyle.textTertiary : AppStyle.textPrimary)
            Spacer(minLength: 8)
            switch state {
            case .absent:
                AgentToolsLinkButton(title: L("安装"), tint: AppStyle.accent) { install(group, toClient: client.id) }
            case .active:
                Text(L("已安装")).font(.system(size: 11, weight: .medium)).foregroundStyle(AppStyle.textTertiary)
                AgentToolsLinkButton(title: L("停用")) { if let record { store.setMCPServerEnabled(record, enabled: false) } }
                AgentToolsLinkButton(title: L("移除"), tint: AppStyle.errorRed) { recordPendingDelete = record }
            case .parked:
                Text(L("已停用")).font(.system(size: 11, weight: .medium)).foregroundStyle(AppStyle.waitAmber)
                AgentToolsLinkButton(title: L("启用"), tint: AppStyle.doneGreen) { if let record { store.setMCPServerEnabled(record, enabled: true) } }
                AgentToolsLinkButton(title: L("移除"), tint: AppStyle.errorRed) { recordPendingDelete = record }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    /// 把代表配置写进某个 client。env 值要读原文才不丢。
    private func install(_ group: MCPServerGroup, toClient id: String) {
        let rep = group.representative
        var env: [String: String] = [:]
        if let raw = store.mcpRawConfig(for: rep), let rawEnv = raw["env"] as? [String: Any] {
            for (key, value) in rawEnv { env[key] = "\(value)" }
        }
        store.installCustomMCPServer(
            name: rep.name, transport: rep.transport,
            command: rep.command ?? "", args: rep.args, url: rep.url ?? "",
            env: env, to: [id])
    }

    // MARK: 配置文件页脚（折叠，扁平）

    private var configFilesFooter: some View {
        VStack(alignment: .leading, spacing: 0) {
            hairline
            Button {
                withAnimation(AgentToolsMotion.reveal) { showConfigFiles.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .rotationEffect(.degrees(showConfigFiles ? 90 : 0))
                    Text(L("配置文件与诊断"))
                        .font(.system(size: 11.5, weight: .medium))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(AppStyle.textSecondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showConfigFiles {
                VStack(spacing: 0) {
                    ForEach(clients) { client in
                        configFileRow(client)
                    }
                    HStack(spacing: 14) {
                        AgentToolsLinkButton(title: L("复制摘要"), icon: "doc.on.doc") { store.copyText(mcpSummaryText) }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                }
                .transition(AgentToolsMotion.revealTransition)
            }
        }
    }

    private func configFileRow(_ client: AgentToolsMCPClientAdapter) -> some View {
        let exists = FileManager.default.fileExists(atPath: client.expandedPath)
        return HStack(spacing: 8) {
            Circle()
                .fill(exists ? AppStyle.doneGreen : AppStyle.textTertiary.opacity(0.5))
                .frame(width: 5, height: 5)
            VStack(alignment: .leading, spacing: 1) {
                Text(client.displayName)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(AppStyle.textSecondary)
                Text(client.path)
                    .font(.system(size: 9.5, weight: .regular, design: .monospaced))
                    .foregroundStyle(AppStyle.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
            AgentToolsLinkButton(title: L("编辑"), icon: "curlybraces") { editingClientJSON = client }
            IconOnlyButton(systemName: "folder", help: L("在 Finder 中显示"), size: 22, symbolSize: 10) {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: client.expandedPath)])
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
    }

    private var mcpSummaryText: String {
        var lines = [
            "Conductor MCP Summary",
            "servers: \(allGroups.count)",
            "records: \(store.mcpServers.count)",
            "clients.covered: \(Set(store.mcpServers.filter(\.enabled).map(\.client)).count)",
        ]
        for server in store.mcpServers {
            let flag = server.enabled ? "" : " (disabled)"
            lines.append("- \(server.client) / \(server.name) / \(server.transport.title) / \(server.endpointLabel)\(flag)")
        }
        if let error = store.mcpScanError { lines.append("error: \(error)") }
        return lines.joined(separator: "\n")
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 26, weight: .regular))
                .foregroundStyle(AppStyle.textTertiary)
            Text(query.isEmpty && transportFilter == .all && clientFilter == nil ? L("还没有 MCP server") : L("没有匹配的 server"))
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(AppStyle.textPrimary)
            Text(L("从模板库或自定义装一台，再选要生效的应用。"))
                .font(.system(size: 11.5, weight: .regular))
                .foregroundStyle(AppStyle.textTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
            ToolActionButton(title: L("添加 server"), systemImage: "plus", role: .primary,
                             height: 30, fontSize: 11.5, horizontalPadding: 14) { beginAdd() }
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 56)
    }

    // MARK: 添加 / 编辑 sheet

    private func beginAdd() {
        editingServer = nil
        resetComposer()
        addTab = .template
        selectedTargetIDs = []
        showAddSheet = true
    }

    private func beginEditing(_ server: AgentToolsMCPServerRecord) {
        let raw = store.mcpRawConfig(for: server) ?? [:]
        customJSON = Self.prettyJSON([server.name: raw]) ?? "{\n  \"\(server.name)\": {}\n}"
        editingServer = server
        addTab = .custom
        showAddSheet = true
    }

    private var addSheet: some View {
        VStack(spacing: 0) {
            HStack {
                Text(editingServer == nil ? L("添加 MCP Server") : L("编辑 MCP Server"))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(AppStyle.textPrimary)
                Spacer()
                IconOnlyButton(systemName: "xmark", help: L("关闭"), size: 28, symbolSize: 12, weight: .bold) {
                    showAddSheet = false
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 12)

            if editingServer == nil {
                Picker("", selection: $addTab) {
                    ForEach(AgentToolsMCPAddTab.allCases) { tab in Text(tab.title).tag(tab) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 18)
                .padding(.bottom, 12)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if editingServer == nil { targetPicker }
                    if editingServer == nil && addTab == .template {
                        templateLibrary
                    } else {
                        customComposer
                    }
                }
                .padding(18)
            }
            .scrollIndicators(.never)
        }
        .frame(width: 620, height: 600)
        .background(AppStyle.windowBackground)
    }

    private var targetPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            AgentToolsFormLabel(L("生效到哪些应用")) {
                AgentToolsLinkButton(title: L("全选")) { selectedTargetIDs = Set(clients.map(\.id)) }
                AgentToolsLinkButton(title: L("清空")) { selectedTargetIDs.removeAll() }
            }
            AgentToolsFormGroup {
                ForEach(Array(clients.enumerated()), id: \.element.id) { index, client in
                    if index > 0 { AgentToolsFormDivider() }
                    AgentToolsCheckRow(
                        title: client.displayName,
                        subtitle: client.path,
                        isOn: selectedTargetIDs.contains(client.id)) {
                            if selectedTargetIDs.contains(client.id) { selectedTargetIDs.remove(client.id) }
                            else { selectedTargetIDs.insert(client.id) }
                        }
                }
            }
        }
    }

    private var templateLibrary: some View {
        VStack(alignment: .leading, spacing: 8) {
            AgentToolsFormLabel(L("模板库"))
            AgentToolsFormGroup {
                ForEach(Array(filteredTemplates.enumerated()), id: \.element.id) { index, template in
                    if index > 0 { AgentToolsFormDivider() }
                    templateRow(template)
                }
            }
        }
    }

    private var filteredTemplates: [AgentToolsMCPTemplate] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return AgentToolsMCPScanner.templates }
        return AgentToolsMCPScanner.templates.filter { template in
            template.name.lowercased().contains(trimmed)
                || template.description.lowercased().contains(trimmed)
                || template.tags.contains { $0.lowercased().contains(trimmed) }
        }
    }

    private func templateRow(_ template: AgentToolsMCPTemplate) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(template.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppStyle.textPrimary)
                    Text(template.transport.title)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(transportTextColor(template.transport))
                    if template.requiresEnv {
                        Text(L("需密钥"))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(AppStyle.waitAmber)
                    }
                }
                Text(template.description)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(AppStyle.textTertiary)
                    .lineLimit(2)
                Text(template.workbenchEndpointPreview)
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(AppStyle.textTertiary.opacity(0.8))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            ToolActionButton(
                title: selectedTargetIDs.isEmpty ? L("先选应用") : L("安装"),
                systemImage: "arrow.down.circle",
                height: 26, fontSize: 11, horizontalPadding: 11) {
                    store.installMCPTemplate(template, to: selectedTargetIDs)
                    showAddSheet = false
                }
                .disabled(selectedTargetIDs.isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var customComposer: some View {
        let editing = editingServer != nil
        return VStack(alignment: .leading, spacing: 10) {
            AgentToolsFormLabel(editing ? L("编辑 server（JSON）") : L("自定义 server（JSON）"))
            if let editingServer {
                Text(L("正在编辑 %@ · %@", editingServer.name, editingServer.client))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppStyle.accent)
            }
            Text(L("键是 server 名称，值是 command/args/env 或 url —— 直接贴 / 改这段 JSON。"))
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(AppStyle.textTertiary)
            TextEditor(text: $customJSON)
                .font(.system(size: 11.5, weight: .regular, design: .monospaced))
                .foregroundStyle(AppStyle.textPrimary)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 200)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).fill(AppStyle.hoverFill.opacity(0.6)))
                .overlay(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).strokeBorder(AppStyle.separator.opacity(0.2), lineWidth: 1))
            HStack(spacing: 10) {
                if parseCustomServerJSON() == nil && !customJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(L("JSON 无效")).font(.system(size: 11, weight: .medium)).foregroundStyle(AppStyle.errorRed)
                } else if !editing {
                    Text(L("将安装到 %ld 个应用", selectedTargetIDs.count))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(selectedTargetIDs.isEmpty ? AppStyle.waitAmber : AppStyle.textTertiary)
                }
                Spacer(minLength: 0)
                if editing {
                    ToolActionButton(title: L("取消"), height: 28, fontSize: 11, horizontalPadding: 12) { cancelEditing() }
                    ToolActionButton(title: L("保存修改"), systemImage: "checkmark", role: .primary,
                                     height: 28, fontSize: 11, horizontalPadding: 12) { saveEdit() }
                        .disabled(!canSaveCustom)
                } else {
                    ToolActionButton(title: L("安装"), systemImage: "plus", role: .primary,
                                     height: 28, fontSize: 11, horizontalPadding: 12) { installCustomFromJSON() }
                        .disabled(!canInstallCustom)
                }
            }
        }
    }

    private func saveEdit() {
        guard let editingServer, let parsed = parseCustomServerJSON() else { return }
        store.updateMCPServer(editingServer, newName: parsed.name, transport: parsed.transport,
                              command: parsed.command, args: parsed.args, url: parsed.url, env: parsed.env)
        cancelEditing()
    }

    private func cancelEditing() {
        editingServer = nil
        resetComposer()
        showAddSheet = false
    }

    private func resetComposer() { customJSON = Self.customServerTemplate }

    private var canSaveCustom: Bool { parseCustomServerJSON() != nil }
    private var canInstallCustom: Bool { !selectedTargetIDs.isEmpty && parseCustomServerJSON() != nil }

    private typealias CustomServerSpec =
        (name: String, transport: AgentToolsMCPTransport, command: String, args: [String], url: String, env: [String: String])

    private func parseAllCustomServers() -> [CustomServerSpec] {
        guard let data = customJSON.data(using: .utf8),
              var object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [] }
        for key in ["mcpServers", "servers"] {
            if object.count == 1, let inner = object[key] as? [String: Any] { object = inner; break }
        }
        return object
            .compactMap { name, value -> CustomServerSpec? in
                guard let body = value as? [String: Any] else { return nil }
                return Self.parseServerEntry(name: name, body: body)
            }
            .sorted { $0.name < $1.name }
    }

    private func parseCustomServerJSON() -> CustomServerSpec? { parseAllCustomServers().first }

    private static func parseServerEntry(name rawName: String, body: [String: Any]) -> CustomServerSpec? {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        let command = (body["command"] as? String) ?? ""
        let url = (body["url"] as? String) ?? ""
        let args = (body["args"] as? [Any])?.compactMap { $0 as? String } ?? []
        var env: [String: String] = [:]
        if let rawEnv = body["env"] as? [String: Any] {
            for (key, value) in rawEnv { env[key] = "\(value)" }
        }
        let typeHint = ((body["type"] as? String) ?? (body["transport"] as? String) ?? "").lowercased()
        let transport: AgentToolsMCPTransport = typeHint == "sse" ? .sse
            : (!url.isEmpty || typeHint == "http") ? .http : .stdio
        guard !command.isEmpty || !url.isEmpty else { return nil }
        return (name, transport, command, args, url, env)
    }

    private func installCustomFromJSON() {
        let servers = parseAllCustomServers()
        guard !servers.isEmpty else { return }
        for s in servers {
            store.installCustomMCPServer(name: s.name, transport: s.transport, command: s.command,
                                         args: s.args, url: s.url, env: s.env, to: selectedTargetIDs)
        }
        resetComposer()
        showAddSheet = false
    }

    private static let customServerTemplate = """
    {
      "my-server": {
        "command": "npx",
        "args": ["-y", "@modelcontextprotocol/server-name"]
      }
    }
    """

    private static func prettyJSON(_ object: [String: Any]) -> String? {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: client 标识

    private func shortClientName(_ client: AgentToolsMCPClientAdapter) -> String {
        switch client.id {
        case "claude_desktop": return "Desktop"
        case "claude_code": return "Claude Code"
        case "codex": return "Codex"
        case "cursor": return "Cursor"
        case "vscode": return "VS Code"
        case "windsurf": return "Windsurf"
        default: return client.displayName
        }
    }
}

/// client 在某 server 上的三态。
private enum MCPLightState {
    case absent, active, parked
    @MainActor var dotColor: Color {
        switch self {
        case .absent: return AppStyle.textTertiary.opacity(0.5)
        case .active: return AppStyle.accent
        case .parked: return AppStyle.waitAmber
        }
    }
}

private extension AgentToolsMCPTemplate {
    var workbenchEndpointPreview: String {
        if let url, !url.isEmpty { return url }
        if let command, !command.isEmpty { return ([command] + args).joined(separator: " ") }
        return "-"
    }
}

@MainActor private func transportTextColor(_ transport: AgentToolsMCPTransport) -> Color {
    switch transport {
    case .stdio: return AppStyle.textSecondary
    case .http: return AppStyle.doneGreen
    case .sse: return AppStyle.waitAmber
    case .unknown: return AppStyle.textTertiary
    }
}

// 通用 env/args 文本辅助（"KEY=value, KEY2=value2" ↔ 字典；空白分隔 args）。
// 新 JSON composer 不再用它们，但保留供测试与其它调用方使用。
func mcpWorkbenchSplitArgs(_ text: String) -> [String] {
    text.split(whereSeparator: \.isWhitespace).map(String.init)
}

func mcpWorkbenchFormatEnv(_ env: [String: Any]) -> String {
    env.keys.sorted().map { key in
        let value = env[key]
        return "\(key)=\(value.map { "\($0)" } ?? "")"
    }.joined(separator: ", ")
}

func mcpWorkbenchParseEnv(_ text: String) -> [String: String] {
    var result: [String: String] = [:]
    for raw in text.split(separator: ",") {
        let pair = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let equals = pair.firstIndex(of: "=") else { continue }
        let key = String(pair[..<equals]).trimmingCharacters(in: .whitespacesAndNewlines)
        let value = String(pair[pair.index(after: equals)...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { continue }
        result[key] = value
    }
    return result
}
