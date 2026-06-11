import AppKit
import ConductorCore
import SwiftUI

/// Skill 管理：扫描 Claude / Codex / Cursor 的 SKILL.md，列出并可启用/禁用（重命名 .disabled）。
/// 行可展开：看完整描述 / 路径 / 版本 / 作者，并可在 Finder 显示或用默认编辑器打开。
struct SkillsManagerView: View {
    /// 主题变 → 重渲染（AppStyle 跟随）。不观察的话切主题后停在旧配色。
    @ObservedObject private var configStore = ConfigStore.shared
    @State private var skills: [SkillEntry] = []
    @State private var loading = false
    @State private var query = ""
    @State private var sourceFilter: SkillSource?
    @State private var expandedID: String?
    @State private var error: String?

    private var filtered: [SkillEntry] {
        var list = skills
        if let f = sourceFilter { list = list.filter { $0.source == f } }
        guard !query.isEmpty else { return list }
        let q = query.lowercased()
        return list.filter {
            $0.name.lowercased().contains(q) || $0.description.lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            filterBar
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if loading && skills.isEmpty {
                        loadingRow
                    } else if filtered.isEmpty {
                        emptyRow
                    } else {
                        ForEach(filtered) { skill in
                            SkillRow(
                                skill: skill,
                                expanded: expandedID == skill.id,
                                onToggle: { on in toggle(skill, on) },
                                onExpand: {
                                    withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                                        expandedID = expandedID == skill.id ? nil : skill.id
                                    }
                                })
                        }
                    }
                    if let error {
                        Text(error).font(.system(size: 10.5)).foregroundStyle(.red)
                    }
                    footnote
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        .onAppear { if skills.isEmpty { reload() } }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10.5)).foregroundStyle(AppStyle.textTertiary)
                TextField(L("搜索 skill 名称或描述"), text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
            }
            .padding(.horizontal, 9).frame(height: 28)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(AppStyle.hoverFill))

            Button(action: reload) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(AppStyle.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(AppStyle.hoverFill))
            }
            .buttonStyle(PressScaleStyle())
            .disabled(loading)
        }
        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 8)
    }

    /// 来源筛选（全部 / Claude / Codex / Cursor，带各自数量）。
    private var filterBar: some View {
        HStack(spacing: 5) {
            filterChip(nil, label: L("全部"), count: skills.count)
            ForEach([SkillSource.claude, .codex, .cursor], id: \.self) { src in
                let count = skills.filter { $0.source == src }.count
                if count > 0 {
                    filterChip(src, label: src.displayName, count: count)
                }
            }
            Spacer()
            Text(L("启用 %ld", skills.filter(\.enabled).count))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(AppStyle.textTertiary)
        }
        .padding(.horizontal, 16).padding(.bottom, 8)
    }

    private func filterChip(_ src: SkillSource?, label: String, count: Int) -> some View {
        let selected = sourceFilter == src
        return Button {
            sourceFilter = src
        } label: {
            Text("\(label) \(count)")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(selected ? .white : AppStyle.textSecondary)
                .padding(.horizontal, 8)
                .frame(height: 22)
                .background(Capsule().fill(selected ? AppStyle.accent : AppStyle.hoverFill))
        }
        .buttonStyle(PressScaleStyle())
    }

    private var loadingRow: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(L("正在扫描 skills…")).font(.system(size: 12)).foregroundStyle(AppStyle.textSecondary)
            Spacer()
        }.padding(.vertical, 20)
    }

    private var emptyRow: some View {
        Text(query.isEmpty ? L("没有找到 skill") : L("无匹配结果"))
            .font(.system(size: 12)).foregroundStyle(AppStyle.textTertiary)
            .padding(.vertical, 20)
    }

    private var footnote: some View {
        Text(L("扫描 ~/.claude、~/.codex、~/.cursor 下的 SKILL.md。禁用 = 把文件重命名为 SKILL.md.disabled（可逆，agent 即不再加载）。同名副本只显示一份。"))
            .font(.system(size: 9.5)).foregroundStyle(AppStyle.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 4)
    }

    private func reload() {
        loading = true
        Task {
            let result = await Task.detached(priority: .userInitiated) { () -> [SkillEntry] in
                SkillCatalog().scan()
            }.value
            await MainActor.run { skills = result; loading = false }
        }
    }

    private func toggle(_ skill: SkillEntry, _ on: Bool) {
        do {
            try SkillCatalog.setEnabled(skill, on)
            reload()
        } catch {
            self.error = L("切换失败：%@", error.localizedDescription)
        }
    }
}

private struct SkillRow: View {
    let skill: SkillEntry
    let expanded: Bool
    let onToggle: (Bool) -> Void
    let onExpand: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 头部行（点击展开/收起）
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(skill.name)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(skill.enabled ? AppStyle.textPrimary : AppStyle.textTertiary)
                            .lineLimit(1)
                        sourceBadge
                        if let v = skill.version {
                            Text("v\(v)").font(.system(size: 9.5)).foregroundStyle(AppStyle.textTertiary)
                        }
                        if !skill.enabled {
                            Text(L("已禁用"))
                                .font(.system(size: 8.5, weight: .bold))
                                .foregroundStyle(AppStyle.textTertiary)
                                .padding(.horizontal, 5).padding(.vertical, 1.5)
                                .background(Capsule().stroke(AppStyle.separator, lineWidth: 1))
                        }
                    }
                    Text(skill.description.isEmpty ? L("（无描述）") : skill.description)
                        .font(.system(size: 10.5))
                        .foregroundStyle(AppStyle.textSecondary)
                        .lineLimit(expanded ? nil : 2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .contentShape(Rectangle())
                .onTapGesture(perform: onExpand)
                Spacer(minLength: 6)
                VStack(alignment: .trailing, spacing: 6) {
                    Toggle("", isOn: Binding(get: { skill.enabled }, set: { onToggle($0) }))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(AppStyle.textTertiary)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                        .contentShape(Rectangle().inset(by: -6))
                        .onTapGesture(perform: onExpand)
                }
            }

            // 展开区：元信息 + 操作
            if expanded {
                VStack(alignment: .leading, spacing: 6) {
                    Divider().overlay(AppStyle.separator).padding(.vertical, 6)
                    if let author = skill.author {
                        metaRow(L("作者"), author)
                    }
                    metaRow(L("路径"), collapsedPath)
                    HStack(spacing: 6) {
                        actionButton(L("在 Finder 显示"), icon: "folder") {
                            NSWorkspace.shared.activateFileViewerSelecting(
                                [URL(fileURLWithPath: skill.markdownPath)])
                        }
                        actionButton(L("打开 SKILL.md"), icon: "doc.text") {
                            NSWorkspace.shared.open(URL(fileURLWithPath: skill.markdownPath))
                        }
                        actionButton(L("拷贝路径"), icon: "doc.on.doc") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(skill.directory, forType: .string)
                        }
                    }
                    .padding(.top, 2)
                }
            }
        }
        .padding(.horizontal, 11).padding(.vertical, 9)
        .opacity(skill.enabled ? 1 : 0.62)
        .toolsCard(cornerRadius: Radius.sm + 2)
    }

    private var collapsedPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return skill.directory.hasPrefix(home)
            ? "~" + skill.directory.dropFirst(home.count)
            : skill.directory
    }

    private func metaRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(label)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(AppStyle.textTertiary)
                .frame(width: 28, alignment: .leading)
            Text(value)
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundStyle(AppStyle.textSecondary)
                .textSelection(.enabled)
                .lineLimit(2).truncationMode(.middle)
        }
    }

    private func actionButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 9, weight: .semibold))
                Text(title).font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(AppStyle.textSecondary)
            .padding(.horizontal, 8).frame(height: 22)
            .background(Capsule().fill(AppStyle.hoverFill))
        }
        .buttonStyle(PressScaleStyle())
    }

    private var sourceBadge: some View {
        Text(skill.source.displayName)
            .font(.system(size: 8.5, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 5).padding(.vertical, 1.5)
            .background(Capsule().fill(badgeColor))
    }

    private var badgeColor: Color {
        switch skill.source {
        case .claude: return .orange
        case .codex: return .green
        case .cursor: return .blue
        case .other: return .gray
        }
    }
}
