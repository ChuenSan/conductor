import AppKit
import SwiftUI

private enum AgentToolsMCPWorkbenchSection: String, CaseIterable, Identifiable {
    case overview
    case library
    case install
    case clients
    case servers
    case diagnostics

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return L("总览")
        case .library: return L("中央库")
        case .install: return L("导入")
        case .clients: return L("应用")
        case .servers: return L("已配置")
        case .diagnostics: return L("诊断")
        }
    }

    var subtitle: String {
        switch self {
        case .overview: return L("MCP 状态、入口和待处理项")
        case .library: return L("精选 MCP server 模板")
        case .install: return L("自定义 stdio / HTTP / SSE")
        case .clients: return L("选择 MCP 要安装到哪些应用")
        case .servers: return L("本机配置里已存在的 servers")
        case .diagnostics: return L("配置文件、错误和导出")
        }
    }

    var sidebarHint: String {
        switch self {
        case .overview: return L("状态")
        case .library: return L("模板")
        case .install: return L("写入")
        case .clients: return L("安装到")
        case .servers: return L("清单")
        case .diagnostics: return L("文件/日志")
        }
    }

    var icon: String {
        switch self {
        case .overview: return "gauge.with.dots.needle.50percent"
        case .library: return "square.stack.3d.up"
        case .install: return "plus.app"
        case .clients: return "cpu"
        case .servers: return "list.bullet.rectangle"
        case .diagnostics: return "wrench.and.screwdriver"
        }
    }
}

private enum AgentToolsMCPWorkbenchFilter: String, CaseIterable, Identifiable {
    case all
    case stdio
    case remote
    case withEnv

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return L("全部")
        case .stdio: return "stdio"
        case .remote: return L("远程")
        case .withEnv: return "env"
        }
    }
}

struct AgentToolsMCPWorkbenchView: View {
    @ObservedObject var store: AgentToolsConsoleStore

    @State private var selectedSection: AgentToolsMCPWorkbenchSection = .library
    @State private var query = ""
    @State private var serverFilter: AgentToolsMCPWorkbenchFilter = .all
    @State private var selectedTargetIDs = Set(AgentToolsMCPScanner.writableClients.map(\.id))
    @State private var customName = ""
    @State private var customTransport: AgentToolsMCPTransport = .stdio
    @State private var customCommand = ""
    @State private var customArgs = ""
    @State private var customURL = ""
    @State private var customEnv = ""

    private var filteredServers: [AgentToolsMCPServerRecord] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return store.mcpServers.filter { server in
            let matchesQuery = trimmed.isEmpty
                || server.name.lowercased().contains(trimmed)
                || server.client.lowercased().contains(trimmed)
                || server.endpointLabel.lowercased().contains(trimmed)
                || server.configPath.lowercased().contains(trimmed)
            guard matchesQuery else { return false }
            switch serverFilter {
            case .all: return true
            case .stdio: return server.transport == .stdio
            case .remote: return server.transport == .http || server.transport == .sse
            case .withEnv: return server.envKeyCount > 0
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

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 208)

            VStack(spacing: 0) {
                header
                content
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .agentToolsPage()
        .onAppear {
            if store.mcpServers.isEmpty { store.refreshMCP() }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            AgentToolsWorkbenchBrand(
                icon: "point.3.connected.trianglepath.dotted",
                title: "MCP Manager",
                subtitle: L("Servers / Clients"))

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    AgentToolsWorkbenchRailSection(L("工作台")) {
                        railButton(.overview)
                        railButton(.library)
                        railButton(.install)
                    }

                    AgentToolsWorkbenchRailSection(L("应用")) {
                        railButton(.clients)
                        railButton(.servers)
                    }

                    AgentToolsWorkbenchRailSection(L("维护")) {
                        railButton(.diagnostics)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 10)
            }
            .scrollIndicators(.never)

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 6) {
                Text("MCP")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(AppStyle.textTertiary)
                HStack(spacing: 6) {
                    ToolBadge(text: L("%ld Servers", store.mcpServers.count), color: AppStyle.textTertiary, style: .muted, height: 20)
                    ToolBadge(text: L("%ld 目标", selectedTargetIDs.count), color: selectedTargetIDs.isEmpty ? AppStyle.waitAmber : AppStyle.accent, style: .muted, height: 20)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .background(AppStyle.hoverFill.opacity(0.14))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func railButton(_ section: AgentToolsMCPWorkbenchSection) -> some View {
        AgentToolsWorkbenchRailButton(
            icon: section.icon,
            title: section.title,
            subtitle: section.sidebarHint,
            badge: badge(for: section),
            selected: selectedSection == section) {
                withAnimation(AgentToolsMotion.route) { selectedSection = section }
            }
    }

    private func badge(for section: AgentToolsMCPWorkbenchSection) -> String? {
        switch section {
        case .overview: return nil
        case .library: return "\(AgentToolsMCPScanner.templates.count)"
        case .install: return nil
        case .clients: return "\(AgentToolsMCPScanner.writableClients.count)"
        case .servers: return store.mcpServers.isEmpty ? nil : "\(store.mcpServers.count)"
        case .diagnostics: return store.mcpScanError == nil ? nil : "!"
        }
    }

    private var header: some View {
        AgentToolsModuleHeader(
            title: selectedSection.title,
            subtitle: selectedSection.subtitle,
            icon: selectedSection.icon) {
                HStack(spacing: 8) {
                    if selectedSection == .library || selectedSection == .servers {
                        AgentToolsSearchField(placeholder: L("搜索 server / client / command / path"), text: $query)
                            .frame(minWidth: 240, idealWidth: 320, maxWidth: 420)
                    }

                    Menu {
                        Button(L("中央模板库")) { selectedSection = .library }
                        Button(L("自定义导入")) { selectedSection = .install }
                        Button(L("选择应用")) { selectedSection = .clients }
                    } label: {
                        Label(L("添加"), systemImage: "plus")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(AppStyle.textSecondary)
                            .padding(.horizontal, 10)
                            .frame(height: 34)
                            .background(Capsule().fill(AppStyle.hoverFill.opacity(0.92)))
                            .overlay(Capsule().strokeBorder(AppStyle.separator.opacity(0.18), lineWidth: 1))
                    }
                    .menuStyle(.borderlessButton)

                    if selectedSection == .servers {
                        AgentToolsMenuButton(title: serverFilter.title, icon: "line.3.horizontal.decrease.circle") {
                            ForEach(AgentToolsMCPWorkbenchFilter.allCases) { option in
                                Button(option.title) {
                                    withAnimation(AgentToolsMotion.selection) { serverFilter = option }
                                }
                            }
                        }
                    }

                    ToolActionButton(
                        title: store.isScanningMCP ? L("扫描中") : L("重新扫描"),
                        systemImage: store.isScanningMCP ? nil : "arrow.clockwise",
                        height: 34,
                        fontSize: 11.5,
                        horizontalPadding: 12,
                        help: L("重新扫描本机 MCP 配置")) {
                            store.refreshMCP()
                        }
                        .disabled(store.isScanningMCP)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 2)
            .padding(.bottom, 10)
    }

    private var content: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                switch selectedSection {
                case .overview:
                    overviewContent
                case .library:
                    libraryContent
                case .install:
                    installContent
                case .clients:
                    clientsContent
                case .servers:
                    serversContent
                case .diagnostics:
                    diagnosticsContent
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .scrollIndicators(.never)
    }

    @ViewBuilder
    private var overviewContent: some View {
        metricStrip
        quickActions
        clientsSummary
        if let error = store.mcpScanError {
            ToolStatusLine(icon: "exclamationmark.triangle.fill", text: error, color: AppStyle.errorRed)
        }
    }

    private var metricStrip: some View {
        let clients = Set(store.mcpServers.map(\.client)).count
        let remote = store.mcpServers.filter { $0.transport == .http || $0.transport == .sse }.count
        let env = store.mcpServers.filter { $0.envKeyCount > 0 }.count
        return HStack(alignment: .top, spacing: 30) {
            AgentToolsStat(value: "\(store.mcpServers.count)", title: "Servers", valueColor: AppStyle.accent)
            AgentToolsStat(value: "\(clients)", title: L("应用"))
            AgentToolsStat(value: "\(remote)", title: L("远程"))
            AgentToolsStat(value: "\(env)", title: "Env")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.md)
        .padding(.vertical, 14)
        .agentToolsGlass()
    }

    private var quickActions: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 8)], spacing: 8) {
            actionTile(icon: "square.stack.3d.up", title: L("安装精选 Server"), detail: L("从中央模板库写入选中应用"), target: .library)
            actionTile(icon: "plus.app", title: L("自定义导入"), detail: L("手动写入 stdio / HTTP / SSE server"), target: .install)
            actionTile(icon: "macwindow", title: L("选择应用"), detail: L("控制要安装到哪些 Agent 工具"), target: .clients)
            actionTile(icon: "list.bullet.rectangle", title: L("审计已配置"), detail: L("查看并清理本机 MCP servers"), target: .servers)
        }
    }

    private func actionTile(icon: String, title: String, detail: String, target: AgentToolsMCPWorkbenchSection) -> some View {
        Button {
            withAnimation(AgentToolsMotion.route) { selectedSection = target }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppStyle.accent)
                    .frame(width: 30, height: 30)
                    .background(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).fill(AppStyle.accent.opacity(0.12)))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundStyle(AppStyle.textPrimary)
                        .lineLimit(1)
                    Text(detail)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(AppStyle.textTertiary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .agentToolsGlass(cornerRadius: Radius.sm)
        }
        .buttonStyle(PressScaleStyle())
    }

    private var clientsSummary: some View {
        AgentToolsSection(L("安装目标")) {
            targetApplicationList(compact: true)
        }
    }

    @ViewBuilder
    private var libraryContent: some View {
        targetSummaryBar

        LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 8)], spacing: 8) {
            ForEach(filteredTemplates) { template in
                templateCard(template)
            }
        }
    }

    private func templateCard(_ template: AgentToolsMCPTemplate) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Image(systemName: template.transport == .stdio ? "terminal" : "network")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(mcpWorkbenchTransportColor(template.transport))
                    .frame(width: 26, height: 26)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(mcpWorkbenchTransportColor(template.transport).opacity(0.12)))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(template.name)
                            .font(.system(size: 12.5, weight: .bold))
                            .foregroundStyle(AppStyle.textPrimary)
                            .lineLimit(1)
                        if template.requiresEnv {
                            ToolBadge(text: "env", color: AppStyle.waitAmber, height: 16)
                        }
                    }
                    Text(template.transport.title)
                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(AppStyle.textTertiary)
                }
                Spacer(minLength: 0)
            }

            Text(template.description)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(AppStyle.textTertiary)
                .lineLimit(3)

            Text(template.workbenchEndpointPreview)
                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                .foregroundStyle(AppStyle.textTertiary)
                .lineLimit(1)
                .truncationMode(.middle)

            HStack(spacing: 5) {
                ForEach(template.tags.prefix(3), id: \.self) { tag in
                    ToolBadge(text: tag, color: AppStyle.textTertiary, style: .muted, height: 17)
                }
                Spacer(minLength: 0)
                ToolActionButton(
                    title: selectedTargetIDs.isEmpty ? L("选择应用") : L("安装到 %ld 个应用", selectedTargetIDs.count),
                    systemImage: "square.and.arrow.down",
                    height: 25,
                    fontSize: 11,
                    horizontalPadding: 10) {
                        store.installMCPTemplate(template, to: selectedTargetIDs)
                    }
                    .disabled(selectedTargetIDs.isEmpty)
            }
        }
        .padding(11)
        .agentToolsGlass(cornerRadius: Radius.sm)
    }

    @ViewBuilder
    private var installContent: some View {
        targetSummaryBar
        customComposer
    }

    @ViewBuilder
    private var clientsContent: some View {
        targetSummaryBar
        targetApplicationList(compact: false)
    }

    private var targetSummaryBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "macwindow")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(AppStyle.accent)
            Text(selectedTargetSummary)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(AppStyle.textSecondary)
                .lineLimit(1)
            Spacer(minLength: 0)
            ToolActionButton(title: L("全选"), systemImage: "checklist", height: 24, fontSize: 10.5, horizontalPadding: 8) {
                selectedTargetIDs = Set(AgentToolsMCPScanner.writableClients.map(\.id))
            }
            ToolActionButton(title: L("清空"), systemImage: "xmark.circle", height: 24, fontSize: 10.5, horizontalPadding: 8) {
                selectedTargetIDs.removeAll()
            }
            ToolActionButton(title: L("管理应用"), systemImage: "slider.horizontal.3", height: 24, fontSize: 10.5, horizontalPadding: 8) {
                withAnimation(AgentToolsMotion.route) { selectedSection = .clients }
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .agentToolsGlass()
    }

    private var selectedTargetSummary: String {
        let names = AgentToolsMCPScanner.writableClients
            .filter { selectedTargetIDs.contains($0.id) }
            .map(\.displayName)
        if names.isEmpty { return L("还没有选择安装应用") }
        if names.count <= 3 { return L("安装到 %@", names.joined(separator: "、")) }
        return L("安装到 %@ 等 %ld 个应用", names.prefix(3).joined(separator: "、"), names.count)
    }

    private func targetApplicationList(compact: Bool) -> some View {
        LazyVStack(spacing: 7) {
            ForEach(AgentToolsMCPScanner.writableClients) { client in
                targetApplicationRow(client, compact: compact)
            }
        }
    }

    private func targetApplicationRow(_ client: AgentToolsMCPClientAdapter, compact: Bool) -> some View {
        let selected = selectedTargetIDs.contains(client.id)
        let count = configuredCount(for: client)
        let exists = FileManager.default.fileExists(atPath: client.expandedPath)
        return HStack(spacing: 10) {
            Image(systemName: mcpTargetIcon(client))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(selected ? AppStyle.accent : AppStyle.textTertiary)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill((selected ? AppStyle.accent : AppStyle.textTertiary).opacity(0.11)))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(client.displayName)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(AppStyle.textPrimary)
                        .lineLimit(1)
                    ToolBadge(text: exists ? L("已检测") : L("未创建"), color: exists ? AppStyle.doneGreen : AppStyle.textTertiary, style: .muted, height: 18)
                    ToolBadge(text: L("%ld Servers", count), color: count > 0 ? AppStyle.accent : AppStyle.textTertiary, style: .muted, height: 18)
                }
                if !compact {
                    Text(client.path)
                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(AppStyle.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: 0)

            if !compact {
                IconOnlyButton(systemName: "doc.text", help: L("打开配置文件"), size: 24, symbolSize: 10.5) {
                    NSWorkspace.shared.open(URL(fileURLWithPath: client.expandedPath))
                }
                IconOnlyButton(systemName: "folder", help: L("在 Finder 中显示"), size: 24, symbolSize: 10.5) {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: client.expandedPath)])
                }
            }

            Toggle(isOn: Binding(
                get: { selectedTargetIDs.contains(client.id) },
                set: { enabled in
                    if enabled { selectedTargetIDs.insert(client.id) }
                    else { selectedTargetIDs.remove(client.id) }
                }
            )) {
                Text(L("用于安装"))
                    .font(.system(size: 10.5, weight: .semibold))
            }
            .toggleStyle(.switch)
            .labelsHidden()
            .help(selected ? L("会安装到 %@", client.displayName) : L("不会安装到 %@", client.displayName))
        }
        .padding(.horizontal, 11)
        .padding(.vertical, compact ? 8 : 10)
        .agentToolsGlass(cornerRadius: Radius.sm)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .stroke(selected ? AppStyle.accent.opacity(0.30) : Color.clear, lineWidth: 1))
    }

    private var targetPicker: some View {
        AgentToolsSection(L("部署目标")) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 7)], spacing: 7) {
                ForEach(AgentToolsMCPScanner.writableClients) { client in
                    Toggle(isOn: Binding(
                        get: { selectedTargetIDs.contains(client.id) },
                        set: { enabled in
                            if enabled { selectedTargetIDs.insert(client.id) }
                            else { selectedTargetIDs.remove(client.id) }
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(client.displayName)
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(AppStyle.textSecondary)
                            Text(client.path)
                                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                                .foregroundStyle(AppStyle.textTertiary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    .toggleStyle(.checkbox)
                }
            }
            .padding(10)
            .agentToolsGlass(cornerRadius: Radius.sm)
        }
    }

    private var customComposer: some View {
        AgentToolsSection(L("自定义 server")) {
            VStack(alignment: .leading, spacing: 9) {
                textInput(L("名称"), text: $customName)
                Picker("", selection: $customTransport) {
                    Text("stdio").tag(AgentToolsMCPTransport.stdio)
                    Text("HTTP").tag(AgentToolsMCPTransport.http)
                    Text("SSE").tag(AgentToolsMCPTransport.sse)
                }
                .pickerStyle(.segmented)
                if customTransport == .stdio {
                    textInput(L("命令"), text: $customCommand)
                    textInput(L("参数，用空格分隔"), text: $customArgs)
                } else {
                    textInput("URL", text: $customURL)
                }
                textInput("Env KEY=value, KEY2=value2", text: $customEnv)
                HStack(spacing: 8) {
                    ToolBadge(text: L("%ld 个应用", selectedTargetIDs.count), color: selectedTargetIDs.isEmpty ? AppStyle.waitAmber : AppStyle.accent, style: .muted, height: 20)
                    Spacer(minLength: 0)
                    ToolActionButton(
                        title: L("安装到选中应用"),
                        systemImage: "plus",
                        height: 28,
                        fontSize: 11,
                        horizontalPadding: 10) {
                            store.installCustomMCPServer(
                                name: customName,
                                transport: customTransport,
                                command: customCommand,
                                args: mcpWorkbenchSplitArgs(customArgs),
                                url: customURL,
                                env: mcpWorkbenchParseEnv(customEnv),
                                to: selectedTargetIDs)
                        }
                        .disabled(!canInstallCustom)
                }
            }
            .padding(10)
            .agentToolsGlass(cornerRadius: Radius.sm)
        }
    }

    private func textInput(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.plain)
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(AppStyle.textPrimary)
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(AppStyle.hoverFill.opacity(0.82)))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .strokeBorder(AppStyle.separator.opacity(0.16), lineWidth: 1))
    }

    private var canInstallCustom: Bool {
        guard !selectedTargetIDs.isEmpty,
              !customName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        switch customTransport {
        case .stdio:
            return !customCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .http, .sse:
            return !customURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .unknown:
            return false
        }
    }

    private var serversContent: some View {
        let servers = filteredServers
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                ToolsSectionLabel("MCP Servers")
                Spacer()
                Text(L("%ld 个 server", servers.count))
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(AppStyle.textTertiary)
            }

            VStack(spacing: 0) {
                tableHeader
                LazyVStack(spacing: 1) {
                    ForEach(servers) { server in
                        serverRow(server)
                    }
                    if servers.isEmpty {
                        emptyState
                    }
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
            .agentToolsGlass()

            if let error = store.mcpScanError {
                ToolBadge(text: error, color: AppStyle.errorRed, style: .muted, height: 22)
            }
        }
    }

    private var tableHeader: some View {
        HStack(spacing: 8) {
            Text("Server").frame(minWidth: 180, maxWidth: .infinity, alignment: .leading)
            Text(L("客户端")).frame(width: 112, alignment: .leading)
            Text(L("传输")).frame(width: 70, alignment: .leading)
            Text(L("入口")).frame(width: 180, alignment: .leading)
            Text(L("操作")).frame(width: 36, alignment: .trailing)
        }
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(AppStyle.textTertiary)
        .padding(.horizontal, 9)
        .frame(height: 28)
    }

    private func serverRow(_ server: AgentToolsMCPServerRecord) -> some View {
        let selected = store.selectedMCPServerID == server.id
        return Button {
            withAnimation(AgentToolsMotion.selection) { store.selectedMCPServerID = server.id }
        } label: {
            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: server.transport == .stdio ? "terminal" : "network")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(mcpWorkbenchTransportColor(server.transport))
                        .frame(width: 24, height: 24)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(mcpWorkbenchTransportColor(server.transport).opacity(0.12)))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(server.name)
                            .font(.system(size: 12.5, weight: .bold))
                            .foregroundStyle(AppStyle.textPrimary)
                            .lineLimit(1)
                        Text(server.sourceKeyPath)
                            .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(AppStyle.textTertiary)
                            .lineLimit(1)
                    }
                }
                .frame(minWidth: 180, maxWidth: .infinity, alignment: .leading)

                Text(server.client)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppStyle.textSecondary)
                    .lineLimit(1)
                    .frame(width: 112, alignment: .leading)

                ToolBadge(text: server.transport.title, color: mcpWorkbenchTransportColor(server.transport), style: .muted, height: 18)
                    .frame(width: 70, alignment: .leading)

                Text(server.endpointLabel)
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(AppStyle.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(width: 180, alignment: .leading)

                IconOnlyButton(
                    systemName: "trash",
                    help: L("移除 MCP server"),
                    size: 24,
                    symbolSize: 10.5,
                    tint: AppStyle.errorRed) {
                        store.removeMCPServer(server)
                    }
                    .frame(width: 36, alignment: .trailing)
            }
            .padding(.horizontal, 9)
            .frame(height: AgentToolsChrome.rowHeight)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(selected ? AppStyle.accent.opacity(0.12) : Color.clear))
            .contentShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        }
        .buttonStyle(PressScaleStyle())
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(AppStyle.textTertiary)
            Text(L("未发现 MCP servers"))
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(AppStyle.textPrimary)
            Text(L("支持扫描 Claude Desktop、Claude Code、Codex、Cursor、VS Code 和 Windsurf 的常见 MCP 配置。"))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppStyle.textTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
    }

    @ViewBuilder
    private var diagnosticsContent: some View {
        AgentToolsSection(L("配置文件")) {
            LazyVStack(spacing: 7) {
                ForEach(AgentToolsMCPScanner.writableClients) { client in
                    configFileRow(client)
                }
            }
            .padding(10)
            .agentToolsGlass(cornerRadius: Radius.sm)
        }

        AgentToolsSection(L("诊断")) {
            VStack(alignment: .leading, spacing: 9) {
                AgentToolsInfoRow(label: "Servers", value: "\(store.mcpServers.count)")
                AgentToolsInfoRow(label: L("客户端"), value: "\(Set(store.mcpServers.map(\.client)).count)")
                AgentToolsInfoRow(label: L("远程"), value: "\(store.mcpServers.filter { $0.transport == .http || $0.transport == .sse }.count)")
                AgentToolsInfoRow(label: "Env", value: "\(store.mcpServers.filter { $0.envKeyCount > 0 }.count)")
                if let error = store.mcpScanError {
                    Text(error)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(AppStyle.errorRed)
                        .lineLimit(6)
                        .textSelection(.enabled)
                }
                HStack(spacing: 8) {
                    ToolActionButton(title: L("复制摘要"), systemImage: "doc.on.doc", height: 28, fontSize: 11, horizontalPadding: 10) {
                        store.copyText(mcpSummaryText)
                    }
                    ToolActionButton(title: L("重新扫描"), systemImage: "arrow.clockwise", height: 28, fontSize: 11, horizontalPadding: 10) {
                        store.refreshMCP()
                    }
                    .disabled(store.isScanningMCP)
                }
            }
            .padding(10)
            .agentToolsGlass(cornerRadius: Radius.sm)
        }
    }

    private var mcpSummaryText: String {
        var lines = [
            "Conductor MCP Summary",
            "servers: \(store.mcpServers.count)",
            "clients: \(Set(store.mcpServers.map(\.client)).count)",
            "targets.selected: \(selectedTargetIDs.count)",
        ]
        for server in store.mcpServers {
            lines.append("- \(server.client) / \(server.name) / \(server.transport.title) / \(server.endpointLabel)")
        }
        if let error = store.mcpScanError {
            lines.append("error: \(error)")
        }
        return lines.joined(separator: "\n")
    }

    private func configFileRow(_ client: AgentToolsMCPClientAdapter) -> some View {
        let exists = FileManager.default.fileExists(atPath: client.expandedPath)
        return HStack(spacing: 8) {
            Image(systemName: exists ? "doc.text" : "doc.badge.plus")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(exists ? AppStyle.accent : AppStyle.textTertiary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(client.displayName)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(AppStyle.textSecondary)
                Text(client.path)
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(AppStyle.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
            ToolBadge(text: exists ? L("存在") : L("未创建"), color: exists ? AppStyle.doneGreen : AppStyle.textTertiary, style: .muted, height: 18)
            IconOnlyButton(systemName: "folder", help: L("在 Finder 中显示"), size: 24, symbolSize: 10.5) {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: client.expandedPath)])
            }
        }
    }

    private func configuredCount(for client: AgentToolsMCPClientAdapter) -> Int {
        store.mcpServers.filter { $0.client == client.displayName }.count
    }

    private func mcpTargetIcon(_ client: AgentToolsMCPClientAdapter) -> String {
        switch client.id {
        case "claude_desktop", "claude_code": return "sparkles"
        case "codex": return "terminal"
        case "cursor": return "cursorarrow"
        case "vscode": return "chevron.left.forwardslash.chevron.right"
        case "windsurf": return "wind"
        default: return "macwindow"
        }
    }
}

private extension AgentToolsMCPTemplate {
    var workbenchEndpointPreview: String {
        if let url, !url.isEmpty { return url }
        if let command, !command.isEmpty {
            return ([command] + args).joined(separator: " ")
        }
        return "-"
    }
}

@MainActor private func mcpWorkbenchTransportColor(_ transport: AgentToolsMCPTransport) -> Color {
    switch transport {
    case .stdio: return AppStyle.accent
    case .http: return AppStyle.doneGreen
    case .sse: return AppStyle.waitAmber
    case .unknown: return AppStyle.textTertiary
    }
}

private func mcpWorkbenchSplitArgs(_ text: String) -> [String] {
    text.split(whereSeparator: \.isWhitespace).map(String.init)
}

private func mcpWorkbenchParseEnv(_ text: String) -> [String: String] {
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
