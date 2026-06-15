import AppKit
import ConductorCore
import SwiftUI

private enum AgentToolsHooksWorkbenchSection: String, CaseIterable, Identifiable {
    case overview
    case recipes
    case builder
    case clients
    case configured
    case diagnostics

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return L("总览")
        case .recipes: return L("配方库")
        case .builder: return L("构建器")
        case .clients: return L("应用")
        case .configured: return L("已配置")
        case .diagnostics: return L("诊断")
        }
    }

    var subtitle: String {
        switch self {
        case .overview: return L("Hook 状态、入口和覆盖情况")
        case .recipes: return L("Conductor 推荐自动化配方")
        case .builder: return L("自定义事件、命令和 timeout")
        case .clients: return L("选择 Hooks 要安装到哪些应用")
        case .configured: return L("审计和清理已写入的 hooks")
        case .diagnostics: return L("配置文件、错误和导出")
        }
    }

    var sidebarHint: String {
        switch self {
        case .overview: return L("状态")
        case .recipes: return L("市场")
        case .builder: return L("写入")
        case .clients: return L("安装到")
        case .configured: return L("清单")
        case .diagnostics: return L("文件/日志")
        }
    }

    var icon: String {
        switch self {
        case .overview: return "gauge.with.dots.needle.50percent"
        case .recipes: return "sparkles"
        case .builder: return "hammer"
        case .clients: return "cpu"
        case .configured: return "list.bullet.rectangle"
        case .diagnostics: return "wrench.and.screwdriver"
        }
    }
}

private enum AgentToolsHooksWorkbenchFilter: String, CaseIterable, Identifiable {
    case all
    case managed
    case custom
    case claude
    case codex

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return L("全部")
        case .managed: return "Conductor"
        case .custom: return L("自定义")
        case .claude: return "Claude"
        case .codex: return "Codex"
        }
    }
}

struct AgentToolsHooksWorkbenchView: View {
    @ObservedObject var store: AgentToolsConsoleStore

    @State private var selectedSection: AgentToolsHooksWorkbenchSection = .recipes
    @State private var query = ""
    @State private var filter: AgentToolsHooksWorkbenchFilter = .all
    @State private var selectedSources = Set(HookSource.allCases)
    @State private var customEvent = HookEventName.stop
    @State private var customCommand = ""
    @State private var customTimeout = "5000"

    private var rows: [HookEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return store.hookEntries.filter { entry in
            let matchesQuery = trimmed.isEmpty
                || entry.event.lowercased().contains(trimmed)
                || entry.command.lowercased().contains(trimmed)
                || entry.source.displayName.lowercased().contains(trimmed)
            guard matchesQuery else { return false }
            switch filter {
            case .all: return true
            case .managed: return entry.managedByConductor
            case .custom: return !entry.managedByConductor
            case .claude: return entry.source == .claude
            case .codex: return entry.source == .codex
            }
        }
    }

    private var commonEvents: [String] {
        [
            HookEventName.stop,
            HookEventName.userPromptSubmit,
            HookEventName.sessionStart,
            HookEventName.notification,
            HookEventName.subagentStop,
        ]
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
            if store.hookEntries.isEmpty { store.refreshHooks() }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            AgentToolsWorkbenchBrand(
                icon: "link",
                title: "Hooks Manager",
                subtitle: L("Events / Recipes"))

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    AgentToolsWorkbenchRailSection(L("工作台")) {
                        railButton(.overview)
                        railButton(.recipes)
                        railButton(.builder)
                    }

                    AgentToolsWorkbenchRailSection(L("应用")) {
                        railButton(.clients)
                        railButton(.configured)
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
                Text("Hooks")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(AppStyle.textTertiary)
                HStack(spacing: 6) {
                    ToolBadge(text: L("%ld Hooks", store.hookEntries.count), color: AppStyle.textTertiary, style: .muted, height: 20)
                    ToolBadge(text: L("%ld 目标", selectedSources.count), color: selectedSources.isEmpty ? AppStyle.waitAmber : AppStyle.accent, style: .muted, height: 20)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .background(AppStyle.hoverFill.opacity(0.14))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func railButton(_ section: AgentToolsHooksWorkbenchSection) -> some View {
        AgentToolsWorkbenchRailButton(
            icon: section.icon,
            title: section.title,
            subtitle: section.sidebarHint,
            badge: badge(for: section),
            selected: selectedSection == section) {
                withAnimation(AgentToolsMotion.route) { selectedSection = section }
            }
    }

    private func badge(for section: AgentToolsHooksWorkbenchSection) -> String? {
        switch section {
        case .overview: return nil
        case .recipes: return "\(HookRecipes.all.count)"
        case .builder: return nil
        case .clients: return "\(HookSource.allCases.count)"
        case .configured: return store.hookEntries.isEmpty ? nil : "\(store.hookEntries.count)"
        case .diagnostics: return store.hookError == nil ? nil : "!"
        }
    }

    private var header: some View {
        AgentToolsModuleHeader(
            title: selectedSection.title,
            subtitle: selectedSection.subtitle,
            icon: selectedSection.icon) {
                HStack(spacing: 8) {
                    if selectedSection == .recipes || selectedSection == .configured {
                        AgentToolsSearchField(placeholder: L("搜索 event / command / client"), text: $query)
                            .frame(minWidth: 240, idealWidth: 320, maxWidth: 420)
                    }

                    Menu {
                        Button(L("配方库")) { selectedSection = .recipes }
                        Button(L("自定义 hook")) { selectedSection = .builder }
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

                    if selectedSection == .configured {
                        AgentToolsMenuButton(title: filter.title, icon: "line.3.horizontal.decrease.circle") {
                            ForEach(AgentToolsHooksWorkbenchFilter.allCases) { option in
                                Button(option.title) {
                                    withAnimation(AgentToolsMotion.selection) { filter = option }
                                }
                            }
                        }
                    }

                    ToolActionButton(
                        title: store.isLoadingHooks ? L("读取中") : L("刷新"),
                        systemImage: store.isLoadingHooks ? nil : "arrow.clockwise",
                        height: 34,
                        fontSize: 11.5,
                        horizontalPadding: 12,
                        help: L("重新读取 Claude / Codex hook 配置")) {
                            store.refreshHooks()
                        }
                        .disabled(store.isLoadingHooks)
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
                case .recipes:
                    recipesContent
                case .builder:
                    builderContent
                case .clients:
                    clientsContent
                case .configured:
                    configuredContent
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
        sourceSummary
        if let error = store.hookError {
            ToolStatusLine(icon: "exclamationmark.triangle.fill", text: error, color: AppStyle.errorRed)
        }
    }

    private var metricStrip: some View {
        let managed = store.hookEntries.filter(\.managedByConductor).count
        let custom = store.hookEntries.count - managed
        let installedPairs = store.hookRecipeStates.values.reduce(0) { $0 + $1.count }
        return HStack(alignment: .top, spacing: 30) {
            AgentToolsStat(value: "\(store.hookEntries.count)", title: "Hooks", valueColor: AppStyle.accent)
            AgentToolsStat(value: "\(managed)", title: "Conductor")
            AgentToolsStat(value: "\(custom)", title: L("自定义"))
            AgentToolsStat(value: "\(installedPairs)", title: L("已安装配方"))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.md)
        .padding(.vertical, 14)
        .agentToolsGlass()
    }

    private var quickActions: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 8)], spacing: 8) {
            actionTile(icon: "sparkles", title: L("安装推荐配方"), detail: L("通知、提示音、横幅和日志"), target: .recipes)
            actionTile(icon: "hammer", title: L("构建自定义 Hook"), detail: L("选择事件并写入命令"), target: .builder)
            actionTile(icon: "macwindow", title: L("选择应用"), detail: L("控制要安装到哪些 Agent 工具"), target: .clients)
            actionTile(icon: "list.bullet.rectangle", title: L("审计已配置"), detail: L("查看并清理 hook 清单"), target: .configured)
        }
    }

    private func actionTile(icon: String, title: String, detail: String, target: AgentToolsHooksWorkbenchSection) -> some View {
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

    private var sourceSummary: some View {
        AgentToolsSection(L("安装目标")) {
            targetApplicationList(compact: true)
        }
    }

    @ViewBuilder
    private var recipesContent: some View {
        targetSummaryBar

        LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 8)], spacing: 8) {
            ForEach(filteredRecipes) { recipe in
                recipeCard(recipe)
            }
        }
    }

    private var filteredRecipes: [HookRecipe] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return HookRecipes.all }
        return HookRecipes.all.filter { recipe in
            recipe.title.lowercased().contains(trimmed)
                || recipe.detail.lowercased().contains(trimmed)
                || recipe.command.lowercased().contains(trimmed)
        }
    }

    private func recipeCard(_ recipe: HookRecipe) -> some View {
        let sources = store.hookRecipeStates[recipe.id] ?? []
        let installed = !sources.isEmpty
        return VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Image(systemName: recipe.icon)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(installed ? AppStyle.accent : AppStyle.textTertiary)
                    .frame(width: 26, height: 26)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill((installed ? AppStyle.accent : AppStyle.textTertiary).opacity(0.12)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(recipe.title)
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundStyle(AppStyle.textPrimary)
                        .lineLimit(1)
                    Text(L("Stop hook"))
                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(AppStyle.textTertiary)
                }
                Spacer(minLength: 0)
            }

            Text(recipe.detail)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(AppStyle.textTertiary)
                .lineLimit(3)

            HStack(spacing: 5) {
                ForEach(HookSource.allCases, id: \.self) { source in
                    ToolBadge(
                        text: source.displayName,
                        color: sources.contains(source) ? hookWorkbenchSourceColor(source) : AppStyle.textTertiary,
                        style: sources.contains(source) ? .soft : .muted,
                        height: 18)
                }
                Spacer(minLength: 0)
                ToolActionButton(
                    title: installed ? L("移除") : selectedSources.isEmpty ? L("选择应用") : L("安装到 %ld 个应用", selectedSources.count),
                    role: installed ? .secondary : .primary,
                    height: 25,
                    fontSize: 11,
                    horizontalPadding: 10) {
                        installed ? store.uninstallHookRecipe(recipe) : store.installHookRecipe(recipe, to: selectedSources)
                    }
                    .disabled(!installed && selectedSources.isEmpty)
            }
        }
        .padding(11)
        .agentToolsGlass(cornerRadius: Radius.sm)
    }

    @ViewBuilder
    private var builderContent: some View {
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
            Text(selectedSourceSummary)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(AppStyle.textSecondary)
                .lineLimit(1)
            Spacer(minLength: 0)
            ToolActionButton(title: L("全选"), systemImage: "checklist", height: 24, fontSize: 10.5, horizontalPadding: 8) {
                selectedSources = Set(HookSource.allCases)
            }
            ToolActionButton(title: L("清空"), systemImage: "xmark.circle", height: 24, fontSize: 10.5, horizontalPadding: 8) {
                selectedSources.removeAll()
            }
            ToolActionButton(title: L("管理应用"), systemImage: "slider.horizontal.3", height: 24, fontSize: 10.5, horizontalPadding: 8) {
                withAnimation(AgentToolsMotion.route) { selectedSection = .clients }
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .agentToolsGlass()
    }

    private var selectedSourceSummary: String {
        let names = HookSource.allCases
            .filter { selectedSources.contains($0) }
            .map(\.displayName)
        if names.isEmpty { return L("还没有选择安装应用") }
        return L("安装到 %@", names.joined(separator: "、"))
    }

    private func targetApplicationList(compact: Bool) -> some View {
        LazyVStack(spacing: 7) {
            ForEach(HookSource.allCases, id: \.self) { source in
                targetApplicationRow(source, compact: compact)
            }
        }
    }

    private func targetApplicationRow(_ source: HookSource, compact: Bool) -> some View {
        let selected = selectedSources.contains(source)
        let entries = store.hookEntries.filter { $0.source == source }
        let managed = entries.filter(\.managedByConductor).count
        let exists = FileManager.default.fileExists(atPath: source.configURL.path)
        return HStack(spacing: 10) {
            Image(systemName: hookSourceIcon(source))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(selected ? hookWorkbenchSourceColor(source) : AppStyle.textTertiary)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill((selected ? hookWorkbenchSourceColor(source) : AppStyle.textTertiary).opacity(0.11)))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(source.displayName)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(AppStyle.textPrimary)
                        .lineLimit(1)
                    ToolBadge(text: exists ? L("已检测") : L("未创建"), color: exists ? AppStyle.doneGreen : AppStyle.textTertiary, style: .muted, height: 18)
                    ToolBadge(text: L("%ld Hooks", entries.count), color: entries.isEmpty ? AppStyle.textTertiary : hookWorkbenchSourceColor(source), style: .muted, height: 18)
                    if managed > 0 {
                        ToolBadge(text: L("%ld Conductor", managed), color: AppStyle.accent, style: .muted, height: 18)
                    }
                }
                if !compact {
                    Text(source.configURL.path)
                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(AppStyle.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: 0)

            if !compact {
                IconOnlyButton(systemName: "doc.text", help: L("打开配置文件"), size: 24, symbolSize: 10.5) {
                    NSWorkspace.shared.open(source.configURL)
                }
                IconOnlyButton(systemName: "folder", help: L("在 Finder 中显示"), size: 24, symbolSize: 10.5) {
                    NSWorkspace.shared.activateFileViewerSelecting([source.configURL])
                }
            }

            Toggle(isOn: Binding(
                get: { selectedSources.contains(source) },
                set: { enabled in
                    if enabled { selectedSources.insert(source) }
                    else { selectedSources.remove(source) }
                }
            )) {
                Text(L("用于安装"))
                    .font(.system(size: 10.5, weight: .semibold))
            }
            .toggleStyle(.switch)
            .labelsHidden()
            .help(selected ? L("会安装到 %@", source.displayName) : L("不会安装到 %@", source.displayName))
        }
        .padding(.horizontal, 11)
        .padding(.vertical, compact ? 8 : 10)
        .agentToolsGlass(cornerRadius: Radius.sm)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .stroke(selected ? AppStyle.accent.opacity(0.30) : Color.clear, lineWidth: 1))
    }

    private var targetPicker: some View {
        AgentToolsSection(L("写入目标")) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 7)], spacing: 7) {
                ForEach(HookSource.allCases, id: \.self) { source in
                    Toggle(isOn: Binding(
                        get: { selectedSources.contains(source) },
                        set: { enabled in
                            if enabled { selectedSources.insert(source) }
                            else { selectedSources.remove(source) }
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(source.displayName)
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(AppStyle.textSecondary)
                            Text(source.configURL.path)
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
        AgentToolsSection(L("自定义 hook")) {
            VStack(alignment: .leading, spacing: 9) {
                AgentToolsMenuButton(title: customEvent, icon: "bolt") {
                    ForEach(commonEvents, id: \.self) { event in
                        Button(event) { customEvent = event }
                    }
                }
                textInput(L("事件名"), text: $customEvent)
                textInput(L("命令"), text: $customCommand)
                textInput(L("Timeout ms"), text: $customTimeout)
                HStack(spacing: 8) {
                    ToolBadge(text: L("%ld 个应用", selectedSources.count), color: selectedSources.isEmpty ? AppStyle.waitAmber : AppStyle.accent, style: .muted, height: 20)
                    Spacer(minLength: 0)
                    ToolActionButton(
                        title: L("安装到选中应用"),
                        systemImage: "plus",
                        height: 28,
                        fontSize: 11,
                        horizontalPadding: 10) {
                            store.installCustomHook(
                                sources: selectedSources,
                                event: customEvent,
                                command: customCommand,
                                timeout: Int(customTimeout) ?? 5000)
                        }
                        .disabled(selectedSources.isEmpty || customCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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

    private var configuredContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                ToolsSectionLabel(L("已配置 hooks"))
                Spacer()
                Text(L("%ld 条", rows.count))
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(AppStyle.textTertiary)
            }

            VStack(spacing: 0) {
                tableHeader
                LazyVStack(spacing: 1) {
                    ForEach(rows) { entry in
                        hookRow(entry)
                    }
                    if rows.isEmpty {
                        emptyState
                    }
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
            .agentToolsGlass()

            if let error = store.hookError {
                ToolBadge(text: error, color: AppStyle.errorRed, style: .muted, height: 22)
            }
        }
    }

    private var tableHeader: some View {
        HStack(spacing: 8) {
            Text(L("事件")).frame(width: 104, alignment: .leading)
            Text(L("来源")).frame(width: 70, alignment: .leading)
            Text(L("命令")).frame(minWidth: 220, maxWidth: .infinity, alignment: .leading)
            Text(L("操作")).frame(width: 54, alignment: .trailing)
        }
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(AppStyle.textTertiary)
        .padding(.horizontal, 9)
        .frame(height: 28)
    }

    private func hookRow(_ entry: HookEntry) -> some View {
        let selected = store.selectedHookEntryID == entry.id
        return Button {
            withAnimation(AgentToolsMotion.selection) { store.selectedHookEntryID = entry.id }
        } label: {
            HStack(spacing: 8) {
                HStack(spacing: 7) {
                    Image(systemName: hookWorkbenchEventIcon(entry.event))
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(entry.managedByConductor ? AppStyle.accent : AppStyle.textTertiary)
                        .frame(width: 20)
                    Text(entry.event)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(AppStyle.textSecondary)
                        .lineLimit(1)
                }
                .frame(width: 104, alignment: .leading)

                ToolBadge(text: entry.source.displayName, color: hookWorkbenchSourceColor(entry.source), style: .muted, height: 18)
                    .frame(width: 70, alignment: .leading)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(hookWorkbenchTitle(entry))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AppStyle.textPrimary)
                            .lineLimit(1)
                        if entry.managedByConductor {
                            ToolBadge(text: "Conductor", color: AppStyle.accent, height: 16)
                        }
                    }
                    Text(entry.command)
                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(AppStyle.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(minWidth: 220, maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 4) {
                    if entry.managedByConductor {
                        IconOnlyButton(
                            systemName: "trash",
                            help: L("移除该 conductor hook"),
                            size: 24,
                            symbolSize: 10.5,
                            tint: AppStyle.errorRed) {
                                store.removeHookEntry(entry)
                            }
                    }
                }
                .frame(width: 54, alignment: .trailing)
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
            Image(systemName: "link")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(AppStyle.textTertiary)
            Text(L("还没有任何 hook"))
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(AppStyle.textPrimary)
            Text(L("可以从配方库安装推荐 hook，也可以用构建器写入自定义命令。"))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppStyle.textTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
    }

    @ViewBuilder
    private var diagnosticsContent: some View {
        AgentToolsSection(L("配置文件")) {
            LazyVStack(spacing: 7) {
                ForEach(HookSource.allCases, id: \.self) { source in
                    configFileRow(source)
                }
            }
            .padding(10)
            .agentToolsGlass(cornerRadius: Radius.sm)
        }

        AgentToolsSection(L("诊断")) {
            VStack(alignment: .leading, spacing: 9) {
                AgentToolsInfoRow(label: "Hooks", value: "\(store.hookEntries.count)")
                AgentToolsInfoRow(label: "Conductor", value: "\(store.hookEntries.filter(\.managedByConductor).count)")
                AgentToolsInfoRow(label: L("配方"), value: "\(HookRecipes.all.count)")
                AgentToolsInfoRow(label: L("已安装"), value: "\(store.hookRecipeStates.values.reduce(0) { $0 + $1.count })")
                if let error = store.hookError {
                    Text(error)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(AppStyle.errorRed)
                        .lineLimit(6)
                        .textSelection(.enabled)
                }
                HStack(spacing: 8) {
                    ToolActionButton(title: L("复制摘要"), systemImage: "doc.on.doc", height: 28, fontSize: 11, horizontalPadding: 10) {
                        store.copyText(hookSummaryText)
                    }
                    ToolActionButton(title: L("刷新"), systemImage: "arrow.clockwise", height: 28, fontSize: 11, horizontalPadding: 10) {
                        store.refreshHooks()
                    }
                    .disabled(store.isLoadingHooks)
                }
            }
            .padding(10)
            .agentToolsGlass(cornerRadius: Radius.sm)
        }
    }

    private var hookSummaryText: String {
        var lines = [
            "Conductor Hook Summary",
            "hooks: \(store.hookEntries.count)",
            "managed: \(store.hookEntries.filter(\.managedByConductor).count)",
            "targets.selected: \(selectedSources.map(\.displayName).sorted().joined(separator: ","))",
        ]
        for entry in store.hookEntries {
            lines.append("- \(entry.source.displayName) / \(entry.event) / \(entry.command)")
        }
        if let error = store.hookError {
            lines.append("error: \(error)")
        }
        return lines.joined(separator: "\n")
    }

    private func configFileRow(_ source: HookSource) -> some View {
        let exists = FileManager.default.fileExists(atPath: source.configURL.path)
        return HStack(spacing: 8) {
            Image(systemName: exists ? "doc.text" : "doc.badge.plus")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(exists ? hookWorkbenchSourceColor(source) : AppStyle.textTertiary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(source.displayName)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(AppStyle.textSecondary)
                Text(source.configURL.path)
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(AppStyle.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
            ToolBadge(text: exists ? L("存在") : L("未创建"), color: exists ? AppStyle.doneGreen : AppStyle.textTertiary, style: .muted, height: 18)
            IconOnlyButton(systemName: "doc.text", help: L("打开配置文件"), size: 24, symbolSize: 10.5) {
                NSWorkspace.shared.open(source.configURL)
            }
            IconOnlyButton(systemName: "folder", help: L("在 Finder 中显示"), size: 24, symbolSize: 10.5) {
                NSWorkspace.shared.activateFileViewerSelecting([source.configURL])
            }
        }
    }
}

private func hookWorkbenchEventIcon(_ event: String) -> String {
    switch event {
    case HookEventName.stop: return "stop.circle"
    case HookEventName.sessionStart: return "play.circle"
    case HookEventName.userPromptSubmit: return "paperplane"
    case HookEventName.subagentStop: return "person.2"
    case HookEventName.notification: return "bell"
    default: return "link"
    }
}

private func hookWorkbenchTitle(_ entry: HookEntry) -> String {
    if entry.command.contains("#conductor:notify") { return L("完成通知") }
    if entry.command.contains("#conductor:sound") { return L("完成提示音") }
    if entry.command.contains("#conductor:banner") { return L("系统横幅") }
    if entry.command.contains("#conductor:log") { return L("完成日志") }
    if entry.managedByConductor { return L("Conductor hook") }
    return L("自定义命令")
}

@MainActor private func hookWorkbenchSourceColor(_ source: HookSource) -> Color {
    switch source {
    case .claude: return .orange
    case .codex: return AppStyle.doneGreen
    }
}

private func hookSourceIcon(_ source: HookSource) -> String {
    switch source {
    case .claude: return "sparkles"
    case .codex: return "terminal"
    }
}
