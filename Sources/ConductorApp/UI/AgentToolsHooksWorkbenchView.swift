import AppKit
import ConductorCore
import SwiftUI

// MARK: - Hooks 模块（反应 × 事件 × agent）
//
// 一条 hook 是「某个生命周期时刻触发的命令」，绑在某个 agent（Claude / Codex）的某个事件上。生效位置
// = 哪个事件 × 哪个 agent。视觉与 MCP 同一套极简扁平（无玻璃/无图标块/无药丸），但骨架是**按生命周期
// 事件分区的时间线**（MCP 没有的维度）：每个事件一节，节内是该时刻会跑的命令；agent 在展开里逐个管。

private struct HookLifecycleMeta: Identifiable {
    let event: String
    let when: String
    var id: String { event }
}

private enum AgentToolsHooksFilter: String, CaseIterable, Identifiable {
    case all, managed, custom, claude, codex
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return L("全部")
        case .managed: return L("托管")
        case .custom: return L("自定义")
        case .claude: return "Claude"
        case .codex: return "Codex"
        }
    }
}

private enum AgentToolsHooksAddTab: String, CaseIterable, Identifiable {
    case recipe, custom
    var id: String { rawValue }
    var title: String { self == .recipe ? L("配方库") : L("自定义") }
}

/// 一条逻辑 hook：同一事件、同一命令在各 agent 的记录聚合。
private struct HookGroup: Identifiable {
    let event: String
    let command: String
    let entries: [HookEntry]
    var id: String { "\(event)::\(command)" }

    var representative: HookEntry { entries.first(where: { $0.enabled }) ?? entries[0] }
    var managed: Bool { representative.managedByConductor }
    var timeout: Int? { representative.timeout }
    var activeCount: Int { entries.filter(\.enabled).count }
    func entry(for source: HookSource) -> HookEntry? { entries.first { $0.source == source } }
}

struct AgentToolsHooksWorkbenchView: View {
    @ObservedObject var store: AgentToolsConsoleStore

    @State private var query = ""
    @State private var filter: AgentToolsHooksFilter = .all
    @State private var expandedGroupID: String?
    @State private var showConfigFiles = false

    // 添加流程。
    @State private var showAddSheet = {
        #if DEBUG
        return ["hooks", "hooks-custom"].contains(ProcessInfo.processInfo.environment["CDR_DEBUG_ADD"])
        #else
        return false
        #endif
    }()
    @State private var addTab: AgentToolsHooksAddTab = {
        #if DEBUG
        return ProcessInfo.processInfo.environment["CDR_DEBUG_ADD"] == "hooks-custom" ? .custom : .recipe
        #else
        return .recipe
        #endif
    }()
    @State private var selectedSources = Set<HookSource>()
    @State private var customEvents: Set<String> = [HookEventName.stop]
    @State private var customCommand = ""
    @State private var customTimeout = "5000"
    @State private var editingEntry: HookEntry?
    @State private var editEvent = HookEventName.stop
    @State private var editingHookSource: HookSource?
    @State private var entryPendingDelete: HookEntry?

    private static let lifecycle: [HookLifecycleMeta] = [
        HookLifecycleMeta(event: HookEventName.sessionStart, when: L("会话开始时")),
        HookLifecycleMeta(event: HookEventName.userPromptSubmit, when: L("你提交输入时")),
        HookLifecycleMeta(event: HookEventName.preToolUse, when: L("工具执行前")),
        HookLifecycleMeta(event: HookEventName.stop, when: L("一轮答完时")),
        HookLifecycleMeta(event: HookEventName.subagentStop, when: L("子任务结束时")),
        HookLifecycleMeta(event: HookEventName.notification, when: L("需要你确认时")),
    ]

    // MARK: 分组 + 过滤

    private var allGroups: [HookGroup] {
        Dictionary(grouping: store.hookEntries, by: { "\($0.event)::\($0.command)" })
            .values
            .compactMap { entries -> HookGroup? in
                guard let first = entries.first else { return nil }
                return HookGroup(event: first.event, command: first.command,
                                 entries: entries.sorted { $0.source.rawValue < $1.source.rawValue })
            }
    }

    private var filteredGroups: [HookGroup] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return allGroups.filter { group in
            if !trimmed.isEmpty {
                let hit = group.event.lowercased().contains(trimmed)
                    || group.command.lowercased().contains(trimmed)
                    || hookWorkbenchTitle(group.representative).lowercased().contains(trimmed)
                guard hit else { return false }
            }
            switch filter {
            case .all: return true
            case .managed: return group.managed
            case .custom: return !group.managed
            case .claude: return group.entry(for: .claude) != nil
            case .codex: return group.entry(for: .codex) != nil
            }
        }
    }

    private var eventSections: [(meta: HookLifecycleMeta, groups: [HookGroup])] {
        let byEvent = Dictionary(grouping: filteredGroups, by: \.event)
        var sections: [(HookLifecycleMeta, [HookGroup])] = []
        for meta in Self.lifecycle {
            if let groups = byEvent[meta.event], !groups.isEmpty { sections.append((meta, sortGroups(groups))) }
        }
        let known = Set(Self.lifecycle.map(\.event))
        for event in byEvent.keys.sorted() where !known.contains(event) {
            if let groups = byEvent[event], !groups.isEmpty {
                sections.append((HookLifecycleMeta(event: event, when: L("自定义事件")), sortGroups(groups)))
            }
        }
        return sections
    }

    private func sortGroups(_ groups: [HookGroup]) -> [HookGroup] {
        groups.sorted { lhs, rhs in
            if lhs.managed != rhs.managed { return lhs.managed && !rhs.managed }
            return hookWorkbenchTitle(lhs.representative)
                .localizedCaseInsensitiveCompare(hookWorkbenchTitle(rhs.representative)) == .orderedAscending
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .agentToolsPage()
        .overlay(alignment: .top) { AgentToolsNoticeBanner(text: store.hookNotice) { store.hookNotice = nil } }
        .sheet(isPresented: $showAddSheet) { addSheet }
        .sheet(item: $editingHookSource) { source in
            AgentToolsJSONEditorSheet(
                title: L("编辑 %@ 的 Hooks", source.displayName),
                subtitle: source.configURL.path,
                hint: L("直接编辑 hooks：形如 { \"Stop\": [ { \"hooks\": [ { \"type\": \"command\", \"command\": \"…\" } ] } ] }。保存即写入，文件里其它键保留。"),
                initialText: store.hooksJSON(for: source),
                onSave: { store.saveHooksJSON($0, for: source) },
                onClose: { editingHookSource = nil })
        }
        .confirmationDialog(
            L("移除 hook？"),
            isPresented: Binding(
                get: { entryPendingDelete != nil },
                set: { if !$0 { entryPendingDelete = nil } }),
            titleVisibility: .visible,
            presenting: entryPendingDelete
        ) { entry in
            Button(L("从 %@ 移除", entry.source.displayName), role: .destructive) {
                if editingEntry?.id == entry.id { cancelEditing() }
                store.removeHookEntry(entry)
                entryPendingDelete = nil
            }
            Button(L("取消"), role: .cancel) { entryPendingDelete = nil }
        } message: { entry in
            Text(L("将从 %@ 的 %@ 事件删除该 hook，不可撤销。只想临时关闭就用「停用」。", entry.source.displayName, entry.event))
        }
        .onAppear {
            if store.hookEntries.isEmpty { store.refreshHooks() }
        }
    }

    // MARK: 顶部

    private var header: some View {
        VStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Hooks")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(AppStyle.textPrimary)
                Text(summaryLine)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(AppStyle.textTertiary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                ToolActionButton(title: L("新建自动化"), systemImage: "plus", role: .primary,
                                 height: 30, fontSize: 11.5, horizontalPadding: 12) { beginAdd() }
                IconOnlyButton(systemName: store.isLoadingHooks ? "arrow.triangle.2.circlepath" : "arrow.clockwise",
                               help: L("刷新"), size: 30, symbolSize: 12) { store.refreshHooks() }
                    .disabled(store.isLoadingHooks)
            }
            HStack(spacing: 8) {
                AgentToolsSearchField(placeholder: L("搜索事件 / 命令"), text: $query)
                AgentToolsMenuButton(title: filter == .all ? L("筛选") : filter.title, icon: "line.3.horizontal.decrease") {
                    ForEach(AgentToolsHooksFilter.allCases) { option in
                        Button { withAnimation(AgentToolsMotion.selection) { filter = option } } label: {
                            Label(option.title, systemImage: filter == option ? "checkmark" : "")
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
        guard !groups.isEmpty else { return L("还没有自动化") }
        let managed = groups.filter(\.managed).count
        var parts = [L("%ld 个自动化", groups.count)]
        if managed > 0 { parts.append(L("%ld 托管", managed)) }
        return parts.joined(separator: " · ")
    }

    // MARK: 内容（事件时间线）

    private var content: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if eventSections.isEmpty {
                    emptyState
                } else {
                    ForEach(eventSections, id: \.meta.id) { section in
                        eventSection(section.meta, groups: section.groups)
                    }
                }
                Spacer(minLength: 18)
                configFilesFooter
                if let error = store.hookError {
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

    private func eventSection(_ meta: HookLifecycleMeta, groups: [HookGroup]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                Text(meta.event)
                    .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(AppStyle.textSecondary)
                Text("· " + meta.when)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(AppStyle.textTertiary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.top, 16)
            .padding(.bottom, 8)

            ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                if index > 0 {
                    Rectangle().fill(AppStyle.separator.opacity(0.4)).frame(height: 1).padding(.leading, 14)
                }
                groupRow(group)
            }
        }
    }

    // MARK: 单行 hook

    private func groupRow(_ group: HookGroup) -> some View {
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

    private func collapsedRow(_ group: HookGroup, expanded: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(hookWorkbenchTitle(group.representative))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppStyle.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if group.managed {
                    Text(L("托管"))
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(AppStyle.accent)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(AppStyle.textTertiary)
                    .rotationEffect(.degrees(expanded ? 90 : 0))
            }
            Text(group.command)
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

    private func presenceLine(_ group: HookGroup) -> some View {
        let active = HookSource.allCases.filter { group.entry(for: $0)?.enabled == true }
        let parked = HookSource.allCases.filter { s in
            if let e = group.entry(for: s) { return !e.enabled }
            return false
        }
        return HStack(spacing: 6) {
            Circle()
                .fill(active.isEmpty ? AppStyle.textTertiary.opacity(0.5) : AppStyle.accent)
                .frame(width: 5, height: 5)
            if active.isEmpty {
                Text(L("未启用")).font(.system(size: 11, weight: .medium)).foregroundStyle(AppStyle.textTertiary)
            } else {
                Text(active.map(\.displayName).joined(separator: " · "))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppStyle.textSecondary)
                    .lineLimit(1)
            }
            if !parked.isEmpty {
                Text(L("· %ld 停用", parked.count))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppStyle.waitAmber)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: 展开详情（每个 agent 一行）

    private func expandedDetail(_ group: HookGroup) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(HookSource.allCases) { source in
                agentControlRow(group, source)
                if source.id != HookSource.allCases.last?.id {
                    Rectangle().fill(AppStyle.separator.opacity(0.25)).frame(height: 1)
                }
            }
            HStack(spacing: 14) {
                AgentToolsLinkButton(title: L("编辑 hook"), icon: "square.and.pencil", tint: AppStyle.accent) {
                    beginEditing(group.representative)
                }
                if let timeout = group.timeout {
                    Text(L("超时 %ldms", timeout)).font(.system(size: 10.5, weight: .medium)).foregroundStyle(AppStyle.textTertiary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 4)
        }
        .padding(.bottom, 8)
    }

    private func agentControlRow(_ group: HookGroup, _ source: HookSource) -> some View {
        let entry = group.entry(for: source)
        let state: HookLightState = entry == nil ? .absent : (entry!.enabled ? .active : .parked)
        return HStack(spacing: 8) {
            Circle().fill(state.dotColor(source)).frame(width: 6, height: 6)
            Text(source.displayName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(state == .absent ? AppStyle.textTertiary : AppStyle.textPrimary)
            Spacer(minLength: 8)
            switch state {
            case .absent:
                AgentToolsLinkButton(title: L("安装"), tint: AppStyle.accent) {
                    store.installCustomHook(sources: [source], event: group.event,
                                            command: group.command, timeout: group.timeout ?? 5000)
                }
            case .active:
                Text(L("已启用")).font(.system(size: 11, weight: .medium)).foregroundStyle(AppStyle.textTertiary)
                AgentToolsLinkButton(title: L("停用")) { if let entry { store.setHookEntryEnabled(entry, enabled: false) } }
                AgentToolsLinkButton(title: L("移除"), tint: AppStyle.errorRed) { entryPendingDelete = entry }
            case .parked:
                Text(L("已停用")).font(.system(size: 11, weight: .medium)).foregroundStyle(AppStyle.waitAmber)
                AgentToolsLinkButton(title: L("启用"), tint: AppStyle.doneGreen) { if let entry { store.setHookEntryEnabled(entry, enabled: true) } }
                AgentToolsLinkButton(title: L("移除"), tint: AppStyle.errorRed) { entryPendingDelete = entry }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    // MARK: 配置文件页脚

    private var configFilesFooter: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(AppStyle.separator.opacity(0.4)).frame(height: 1).padding(.leading, 14)
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
                    ForEach(HookSource.allCases) { source in
                        configFileRow(source)
                    }
                    HStack(spacing: 14) {
                        AgentToolsLinkButton(title: L("复制摘要"), icon: "doc.on.doc") { store.copyText(hookSummaryText) }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                }
                .transition(AgentToolsMotion.revealTransition)
            }
        }
    }

    private func configFileRow(_ source: HookSource) -> some View {
        let exists = FileManager.default.fileExists(atPath: source.configURL.path)
        return HStack(spacing: 8) {
            Circle()
                .fill(exists ? AppStyle.doneGreen : AppStyle.textTertiary.opacity(0.5))
                .frame(width: 5, height: 5)
            VStack(alignment: .leading, spacing: 1) {
                Text(source.displayName)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(AppStyle.textSecondary)
                Text(source.configURL.path)
                    .font(.system(size: 9.5, weight: .regular, design: .monospaced))
                    .foregroundStyle(AppStyle.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
            AgentToolsLinkButton(title: L("编辑"), icon: "curlybraces") { editingHookSource = source }
            IconOnlyButton(systemName: "folder", help: L("在 Finder 中显示"), size: 22, symbolSize: 10) {
                NSWorkspace.shared.activateFileViewerSelecting([source.configURL])
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
    }

    private var hookSummaryText: String {
        var lines = [
            "Conductor Hook Summary",
            "automations: \(allGroups.count)",
            "records: \(store.hookEntries.count)",
            "managed: \(allGroups.filter(\.managed).count)",
        ]
        for entry in store.hookEntries {
            let flag = entry.enabled ? "" : " (disabled)"
            lines.append("- \(entry.source.displayName) / \(entry.event) / \(entry.command)\(flag)")
        }
        if let error = store.hookError { lines.append("error: \(error)") }
        return lines.joined(separator: "\n")
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "bolt.horizontal.circle")
                .font(.system(size: 26, weight: .regular))
                .foregroundStyle(AppStyle.textTertiary)
            Text(query.isEmpty && filter == .all ? L("还没有任何自动化") : L("没有匹配的 hook"))
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(AppStyle.textPrimary)
            Text(L("从配方库装一个，或自己挑触发事件 + 写命令。"))
                .font(.system(size: 11.5, weight: .regular))
                .foregroundStyle(AppStyle.textTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
            ToolActionButton(title: L("新建自动化"), systemImage: "plus", role: .primary,
                             height: 30, fontSize: 11.5, horizontalPadding: 14) { beginAdd() }
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 56)
    }

    // MARK: 添加 / 编辑

    private func beginAdd() {
        editingEntry = nil
        resetComposer()
        addTab = .recipe
        selectedSources = []
        showAddSheet = true
    }

    private func beginEditing(_ entry: HookEntry) {
        editingEntry = entry
        editEvent = entry.event
        customCommand = entry.command
        customTimeout = entry.timeout.map(String.init) ?? "5000"
        addTab = .custom
        showAddSheet = true
    }

    private func saveEdit() {
        guard let editingEntry else { return }
        store.updateHookEntry(editingEntry, newEvent: editEvent, newCommand: customCommand, newTimeout: Int(customTimeout) ?? 5000)
        cancelEditing()
    }

    private func cancelEditing() {
        editingEntry = nil
        resetComposer()
        showAddSheet = false
    }

    private func resetComposer() {
        customEvents = [HookEventName.stop]
        editEvent = HookEventName.stop
        customCommand = ""
        customTimeout = "5000"
    }

    private var addSheet: some View {
        VStack(spacing: 0) {
            HStack {
                Text(editingEntry == nil ? L("新建自动化") : L("编辑 Hook"))
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

            if editingEntry == nil {
                Picker("", selection: $addTab) {
                    ForEach(AgentToolsHooksAddTab.allCases) { tab in Text(tab.title).tag(tab) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 18)
                .padding(.bottom, 12)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if editingEntry == nil { targetPicker }
                    if editingEntry == nil && addTab == .recipe {
                        recipeLibrary
                    } else {
                        customComposer
                    }
                }
                .padding(18)
            }
            .scrollIndicators(.never)
        }
        .frame(width: 620, height: 620)
        .background(AppStyle.windowBackground)
    }

    private var targetPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            AgentToolsFormLabel(L("装到哪些 agent")) {
                AgentToolsLinkButton(title: L("全选")) { selectedSources = Set(HookSource.allCases) }
                AgentToolsLinkButton(title: L("清空")) { selectedSources.removeAll() }
            }
            AgentToolsFormGroup {
                ForEach(Array(HookSource.allCases.enumerated()), id: \.element.id) { index, source in
                    if index > 0 { AgentToolsFormDivider() }
                    AgentToolsCheckRow(
                        title: source.displayName,
                        subtitle: source.configURL.path,
                        isOn: selectedSources.contains(source)) {
                            if selectedSources.contains(source) { selectedSources.remove(source) }
                            else { selectedSources.insert(source) }
                        }
                }
            }
        }
    }

    // MARK: 配方库

    private var recipeLibrary: some View {
        VStack(alignment: .leading, spacing: 8) {
            AgentToolsFormLabel(L("配方库"))
            AgentToolsFormGroup {
                ForEach(Array(filteredRecipes.enumerated()), id: \.element.id) { index, recipe in
                    if index > 0 { AgentToolsFormDivider() }
                    recipeRow(recipe)
                }
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

    private func recipeRow(_ recipe: HookRecipe) -> some View {
        let sources = store.hookRecipeStates[recipe.id] ?? []
        let installed = !sources.isEmpty
        return HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(recipe.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppStyle.textPrimary)
                    Text(recipe.id == HookInstaller.recipeID ? L("多事件") : L("Stop"))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(AppStyle.textTertiary)
                }
                Text(recipe.detail)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(AppStyle.textTertiary)
                    .lineLimit(2)
                if installed {
                    Text(L("已装：%@", sources.map(\.displayName).sorted().joined(separator: " · ")))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(AppStyle.accent)
                }
            }
            Spacer(minLength: 8)
            if installed {
                ToolActionButton(title: L("全部移除"), height: 26, fontSize: 11, horizontalPadding: 11) {
                    store.uninstallHookRecipe(recipe)
                }
            } else {
                ToolActionButton(
                    title: selectedSources.isEmpty ? L("先选 agent") : L("安装"),
                    systemImage: "arrow.down.circle", role: .primary,
                    height: 26, fontSize: 11, horizontalPadding: 11) {
                        store.installHookRecipe(recipe, to: selectedSources)
                    }
                    .disabled(selectedSources.isEmpty)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: 自定义构建器

    private var customComposer: some View {
        let editing = editingEntry != nil
        return VStack(alignment: .leading, spacing: 14) {
            if let editingEntry {
                Text(L("正在编辑 %@ · %@", editingEntry.source.displayName, editingEntry.event))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppStyle.accent)
            }

            if editing {
                VStack(alignment: .leading, spacing: 8) {
                    AgentToolsFormLabel(L("触发事件"))
                    AgentToolsMenuButton(title: editEvent, icon: "bolt") {
                        ForEach(Self.lifecycle) { meta in
                            Button("\(meta.event) · \(meta.when)") { editEvent = meta.event }
                        }
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    AgentToolsFormLabel(L("触发时机（可多选）"))
                    AgentToolsFormGroup {
                        ForEach(Array(Self.lifecycle.enumerated()), id: \.element.id) { index, meta in
                            if index > 0 { AgentToolsFormDivider() }
                            AgentToolsCheckRow(
                                title: meta.event,
                                subtitle: meta.when,
                                isOn: customEvents.contains(meta.event)) {
                                    if customEvents.contains(meta.event) { customEvents.remove(meta.event) }
                                    else { customEvents.insert(meta.event) }
                                }
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                AgentToolsFormLabel(L("命令"))
                AgentToolsFormGroup {
                    fieldRow {
                        TextField(L("shell 命令，例如 afplay /System/Library/Sounds/Glass.aiff"), text: $customCommand)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12, weight: .regular, design: .monospaced))
                            .foregroundStyle(AppStyle.textPrimary)
                    }
                    AgentToolsFormDivider()
                    fieldRow {
                        HStack(spacing: 8) {
                            Text(L("超时"))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(AppStyle.textSecondary)
                            Spacer(minLength: 0)
                            TextField("5000", text: $customTimeout)
                                .textFieldStyle(.plain)
                                .multilineTextAlignment(.trailing)
                                .font(.system(size: 12, weight: .regular, design: .monospaced))
                                .foregroundStyle(AppStyle.textPrimary)
                                .frame(width: 70)
                            Text("ms")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(AppStyle.textTertiary)
                        }
                    }
                }
            }

            HStack(spacing: 10) {
                if !editing {
                    Text(L("%ld 事件 · %ld agent", customEvents.count, selectedSources.count))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle((customEvents.isEmpty || selectedSources.isEmpty) ? AppStyle.waitAmber : AppStyle.textTertiary)
                }
                Spacer(minLength: 0)
                if editing {
                    ToolActionButton(title: L("取消"), height: 28, fontSize: 11, horizontalPadding: 12) { cancelEditing() }
                    ToolActionButton(title: L("保存修改"), systemImage: "checkmark", role: .primary,
                                     height: 28, fontSize: 11, horizontalPadding: 12) { saveEdit() }
                        .disabled(!canSaveEdit)
                } else {
                    ToolActionButton(title: L("创建"), systemImage: "plus", role: .primary,
                                     height: 28, fontSize: 11, horizontalPadding: 12) { createCustom() }
                        .disabled(!canCreate)
                }
            }
        }
    }

    private func fieldRow<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 12)
            .frame(height: 38)
    }

    private var canSaveEdit: Bool {
        !customCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !editEvent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canCreate: Bool {
        !selectedSources.isEmpty && !customEvents.isEmpty
            && !customCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func createCustom() {
        let timeout = Int(customTimeout) ?? 5000
        for event in customEvents.sorted() {
            store.installCustomHook(sources: selectedSources, event: event, command: customCommand, timeout: timeout)
        }
        resetComposer()
        showAddSheet = false
    }

}

/// agent 在某 hook 上的三态。
private enum HookLightState {
    case absent, active, parked
    @MainActor func dotColor(_ source: HookSource) -> Color {
        switch self {
        case .absent: return AppStyle.textTertiary.opacity(0.5)
        case .active: return hookWorkbenchSourceColor(source)
        case .parked: return AppStyle.waitAmber
        }
    }
}

private func hookWorkbenchTitle(_ entry: HookEntry) -> String {
    if entry.command.contains("#conductor:notify") { return L("完成通知") }
    if entry.command.contains("#conductor:approve") { return L("工具审批") }
    if entry.command.contains("#conductor:sound") { return L("完成提示音") }
    if entry.command.contains("#conductor:banner") { return L("系统横幅") }
    if entry.command.contains("#conductor:log") { return L("完成日志") }
    if entry.managedByConductor { return L("Conductor 管理的 Hook") }
    return L("自定义命令")
}

@MainActor private func hookWorkbenchSourceColor(_ source: HookSource) -> Color {
    switch source {
    case .claude: return .orange
    case .codex: return AppStyle.doneGreen
    }
}
