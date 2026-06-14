import AppKit
import ConductorCore
import SwiftUI

/// Hook 管理 + 市场：查看 Claude / Codex 已配置的 hooks（按事件分组），
/// 并从精选目录一键安装/移除（带双端安装状态）。
struct HooksManagerView: View {
    /// 主题变 → 重渲染（AppStyle 跟随）。不观察的话切主题后停在旧配色。
    @ObservedObject private var configStore = ConfigStore.shared
    @State private var entries: [HookEntry] = []
    @State private var recipeStates: [String: Set<HookSource>] = [:]
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                marketSection
                configuredSection
                configFilesSection
                if let error {
                    ToolStatusLine(icon: "exclamationmark.triangle.fill", text: error, color: AppStyle.errorRed)
                }
                footnote
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
        }
        .onAppear { if entries.isEmpty { reload() } }
    }

    // MARK: - 市场

    private var marketSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle(L("Hook 市场"), trailing: nil)
            ForEach(HookRecipes.all) { recipe in
                recipeRow(recipe)
            }
        }
    }

    private func recipeRow(_ recipe: HookRecipe) -> some View {
        let sources = recipeStates[recipe.id] ?? []
        let installed = !sources.isEmpty
        return HStack(spacing: 10) {
            Image(systemName: recipe.icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(installed ? AppStyle.accent : AppStyle.textSecondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(recipe.title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(AppStyle.textPrimary)
                    ForEach(HookSource.allCases, id: \.self) { src in
                        if sources.contains(src) {
                            ToolBadge(
                                text: src.displayName,
                                color: src == .claude ? .orange : AppStyle.doneGreen,
                                style: .solid,
                                height: 17)
                        }
                    }
                }
                Text(recipe.detail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(AppStyle.textSecondary)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 6)
            ToolActionButton(
                title: installed ? L("移除") : L("安装"),
                role: installed ? .secondary : .primary,
                height: 25,
                fontSize: 11,
                horizontalPadding: 11) {
                    installed ? uninstall(recipe) : install(recipe)
                }
        }
        .padding(.horizontal, 11).padding(.vertical, 9)
        .toolsCard(cornerRadius: Radius.sm + 2)
        .help(recipe.detail)
    }

    // MARK: - 已配置（按事件分组）

    private var groupedEntries: [(event: String, items: [HookEntry])] {
        let groups = Dictionary(grouping: entries, by: \.event)
        return groups.keys.sorted().map { (event: $0, items: groups[$0] ?? []) }
    }

    private var configuredSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle(L("已配置 hooks"), trailing: "\(entries.count)")
            if loading && entries.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(L("读取中…")).font(.system(size: 12)).foregroundStyle(AppStyle.textSecondary)
                    Spacer()
                }.padding(.vertical, 12)
            } else if entries.isEmpty {
                ToolEmptyState(icon: "link", title: L("还没有任何 hook"), compact: true)
            } else {
                ForEach(groupedEntries, id: \.event) { group in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 5) {
                            Image(systemName: eventIcon(group.event))
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundStyle(AppStyle.textTertiary)
                            Text(group.event)
                                .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                                .foregroundStyle(AppStyle.textSecondary)
                            Text("\(group.items.count)")
                                .font(.system(size: 9.5))
                                .foregroundStyle(AppStyle.textTertiary)
                        }
                        ForEach(group.items) { entry in
                            HookEntryRow(entry: entry) { remove(entry) }
                        }
                    }
                    .padding(.bottom, 2)
                }
            }
        }
    }

    private func eventIcon(_ event: String) -> String {
        switch event {
        case "Stop": return "stop.circle"
        case "SessionStart": return "play.circle"
        case "UserPromptSubmit": return "paperplane"
        case "SubagentStop": return "person.2"
        default: return "link"
        }
    }

    // MARK: - 配置文件入口

    private var configFilesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle(L("配置文件"), trailing: nil)
            HStack(spacing: 8) {
                ForEach(HookSource.allCases, id: \.self) { src in
                    ToolActionButton(
                        title: L("%@ 配置", src.displayName),
                        systemImage: "doc.text",
                        role: .secondary,
                        height: 26,
                        fontSize: 10.5,
                        horizontalPadding: 9,
                        help: L("用默认编辑器打开配置文件")) {
                            NSWorkspace.shared.open(src.configURL)
                        }
                }
            }
        }
    }

    private func sectionTitle(_ title: String, trailing: String?) -> some View {
        HStack {
            ToolsSectionLabel(title)
            if let trailing {
                Text(trailing).font(.system(size: 10.5, weight: .medium)).foregroundStyle(AppStyle.textTertiary)
            }
            Spacer()
            if title == L("Hook 市场") {
                IconOnlyButton(
                    systemName: "arrow.clockwise",
                    help: L("刷新 Hook 市场"),
                    size: 24,
                    symbolSize: 10.5,
                    weight: .bold,
                    tint: AppStyle.textSecondary,
                    action: reload)
                .disabled(loading)
            }
        }
    }

    private var footnote: some View {
        Text(L("仅管理 Conductor 安装的 hook；已有配置会保留。通知只作用于从 Conductor 启动的 Agent。"))
            .font(.system(size: 9.5)).foregroundStyle(AppStyle.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - 操作

    private func reload() {
        loading = true
        Task {
            let result = await Task.detached(priority: .userInitiated) { () -> ([HookEntry], [String: Set<HookSource>]) in
                let entries = HookConfigDocument(source: .claude).entries()
                    + HookConfigDocument(source: .codex).entries()
                var states: [String: Set<HookSource>] = [:]
                for recipe in HookRecipes.all {
                    states[recipe.id] = HookRecipes.installedSources(recipe)
                }
                return (entries, states)
            }.value
            await MainActor.run {
                entries = result.0
                recipeStates = result.1
                loading = false
            }
        }
    }

    private func install(_ recipe: HookRecipe) {
        error = nil
        do { try HookRecipes.install(recipe); reload() }
        catch { self.error = L("安装失败：%@", error.localizedDescription) }
    }

    private func uninstall(_ recipe: HookRecipe) {
        error = nil
        do { try HookRecipes.uninstall(recipe); reload() }
        catch { self.error = L("移除失败：%@", error.localizedDescription) }
    }

    private func remove(_ entry: HookEntry) {
        error = nil
        do {
            try HookConfigDocument(source: entry.source).removeCommands(containing: entry.command)
            reload()
        } catch { self.error = L("移除失败：%@", error.localizedDescription) }
    }
}

private struct HookEntryRow: View {
    let entry: HookEntry
    let onRemove: () -> Void
    @State private var expanded = false

    private var entryTitle: String {
        if entry.command.contains("#conductor:notify") { return L("完成通知") }
        if entry.command.contains("#conductor:sound") { return L("完成提示音") }
        if entry.command.contains("#conductor:banner") { return L("系统横幅") }
        if entry.command.contains("#conductor:log") { return L("完成日志") }
        if entry.managedByConductor { return L("Conductor hook") }
        return L("自定义命令")
    }

    private var entryDetail: String {
        entry.managedByConductor
            ? L("由 Conductor 管理，可一键移除。")
            : L("来自现有 Agent 配置。")
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    ToolBadge(
                        text: entry.source.displayName,
                        color: entry.source == .claude ? .orange : AppStyle.doneGreen,
                        style: .solid,
                        height: 17)
                    if entry.managedByConductor {
                        ToolBadge(
                            text: "Conductor",
                            color: AppStyle.accent,
                            style: .soft,
                            height: 17)
                    }
                    if let timeout = entry.timeout {
                        ToolBadge(
                            text: L("%ld ms", timeout),
                            color: AppStyle.textTertiary,
                            style: .muted,
                            height: 17)
                    }
                }
                Text(entryTitle)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(AppStyle.textPrimary)
                    .lineLimit(1)
                if expanded {
                    Text(entry.command)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(AppStyle.textTertiary)
                        .lineLimit(nil)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                } else {
                    Text(entryDetail)
                        .font(.system(size: 10.5))
                        .foregroundStyle(AppStyle.textSecondary)
                        .lineLimit(1)
                        .transition(.opacity)
                }
            }
            Spacer(minLength: 4)
            IconOnlyButton(
                systemName: expanded ? "chevron.up" : "chevron.down",
                help: expanded ? L("收起命令") : L("查看命令"),
                size: 24,
                symbolSize: 10.5,
                weight: .semibold,
                tint: AppStyle.textSecondary) {
                    withAnimation(Motion.snappy) { expanded.toggle() }
                }
            if entry.managedByConductor {
                IconOnlyButton(
                    systemName: "trash",
                    help: L("移除该 conductor hook"),
                    size: 24,
                    symbolSize: 10.5,
                    weight: .semibold,
                    tint: AppStyle.errorRed,
                    action: onRemove)
            }
        }
        .padding(.horizontal, 11).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).fill(AppStyle.hoverFill.opacity(0.5)))
        .contentShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
    }
}
