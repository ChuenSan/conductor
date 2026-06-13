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
                    Text(error).font(.system(size: 10.5)).foregroundStyle(.red)
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
                    // 双端安装状态徽标
                    ForEach(HookSource.allCases, id: \.self) { src in
                        if sources.contains(src) {
                            Text(src.displayName)
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 4).padding(.vertical, 1)
                                .background(Capsule().fill(src == .claude ? Color.orange : Color.green))
                        }
                    }
                }
                Text(recipe.detail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(AppStyle.textSecondary)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 6)
            Button {
                installed ? uninstall(recipe) : install(recipe)
            } label: {
                Text(installed ? L("移除") : L("安装"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(installed ? AppStyle.textSecondary : AppStyle.theme.primarySolidText)
                    .padding(.horizontal, 11).frame(height: 25)
                    .background(Capsule().fill(installed ? AppStyle.hoverFill : AppStyle.theme.primarySolid))
                    .contentShape(Capsule())
            }
            .buttonStyle(PressScaleStyle())
        }
        .padding(.horizontal, 11).padding(.vertical, 9)
        .toolsCard(cornerRadius: Radius.sm + 2)
        .help(recipe.command)
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
                Text(L("还没有任何 hook")).font(.system(size: 12)).foregroundStyle(AppStyle.textTertiary)
                    .padding(.vertical, 12)
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
                    Button {
                        NSWorkspace.shared.open(src.configURL)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "doc.text")
                                .font(.system(size: 10, weight: .semibold))
                            Text(shortConfigPath(src))
                                .font(.system(size: 10, design: .monospaced))
                                .lineLimit(1).truncationMode(.middle)
                        }
                        .foregroundStyle(AppStyle.textSecondary)
                        .padding(.horizontal, 9).frame(height: 26)
                        .frame(maxWidth: .infinity)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(AppStyle.hoverFill))
                    }
                    .buttonStyle(PressScaleStyle())
                    .help(L("用默认编辑器打开 %@", src.configURL.path))
                }
            }
        }
    }

    private func shortConfigPath(_ src: HookSource) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let p = src.configURL.path
        return p.hasPrefix(home) ? "~" + p.dropFirst(home.count) : p
    }

    private func sectionTitle(_ title: String, trailing: String?) -> some View {
        HStack {
            ToolsSectionLabel(title)
            if let trailing {
                Text(trailing).font(.system(size: 10.5, weight: .medium)).foregroundStyle(AppStyle.textTertiary)
            }
            Spacer()
            if title == L("Hook 市场") {
                Button(action: reload) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundStyle(AppStyle.textSecondary)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(AppStyle.hoverFill))
                }
                .buttonStyle(PressScaleStyle())
                .help(L("刷新 Hook 市场"))
                .disabled(loading)
            }
        }
    }

    private var footnote: some View {
        Text(L("安装写入 Claude（~/.claude/settings.json）与 Codex（~/.codex/hooks.json）的 Stop 事件；命令带 $CONDUCTOR_PANE_ID 网关，只对 conductor 启动的 agent 生效。其它配置项原样保留，移除只删 conductor 自己安装的条目。"))
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

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(entry.source.displayName)
                        .font(.system(size: 8.5, weight: .bold)).foregroundStyle(.white)
                        .padding(.horizontal, 5).padding(.vertical, 1.5)
                        .background(Capsule().fill(entry.source == .claude ? Color.orange : Color.green))
                    if entry.managedByConductor {
                        Text("Conductor")
                            .font(.system(size: 8.5, weight: .bold)).foregroundStyle(AppStyle.accent)
                            .padding(.horizontal, 5).padding(.vertical, 1.5)
                            .background(Capsule().fill(AppStyle.accent.opacity(0.18)))
                    }
                    if let timeout = entry.timeout {
                        Text("timeout \(timeout)")
                            .font(.system(size: 8.5)).foregroundStyle(AppStyle.textTertiary)
                    }
                }
                Text(entry.command)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(AppStyle.textTertiary)
                    .lineLimit(expanded ? nil : 2)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentShape(Rectangle())
                    .onTapGesture { withAnimation(.easeOut(duration: 0.15)) { expanded.toggle() } }
            }
            Spacer(minLength: 4)
            if entry.managedByConductor {
                Button(action: onRemove) {
                    Image(systemName: "trash")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.red.opacity(0.85))
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(AppStyle.hoverFill))
                }
                .buttonStyle(PressScaleStyle())
                .help(L("移除该 conductor hook"))
            }
        }
        .padding(.horizontal, 11).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(AppStyle.hoverFill.opacity(0.5)))
    }
}
