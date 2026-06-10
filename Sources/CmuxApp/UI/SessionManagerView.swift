import CmuxCore
import SwiftUI

/// Agent 会话管理面板：浏览 / 筛选 / 续聊 claude & codex 会话。
struct SessionManagerView: View {
    let coordinator: AppCoordinator
    var onClose: () -> Void = {}

    @ObservedObject private var configStore = ConfigStore.shared
    @ObservedObject private var store = SessionManagerStore.shared
    @State private var agentFilter: String? = nil
    @State private var query = ""

    private var scopePath: String? { coordinator.sessionScopePath }
    private var scopeLabel: String {
        if let path = scopePath {
            return (path as NSString).abbreviatingWithTildeInPath
        }
        return "全部目录"
    }

    private var filtered: [AgentSessionRecord] {
        var list = store.records
        if let scopePath {
            list = list.filter { $0.belongsToWorkspace(scopePath) || $0.belongsToDirectory(scopePath) }
        }
        if let agentFilter { list = list.filter { $0.agent == agentFilter } }
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !q.isEmpty {
            list = list.filter {
                $0.title.lowercased().contains(q)
                    || $0.sessionID.lowercased().contains(q)
                    || ($0.cwd?.lowercased().contains(q) ?? false)
            }
        }
        return list
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(AppStyle.separator)
            filterBar
            Divider().overlay(AppStyle.separator)
            content
        }
        .frame(maxHeight: .infinity)
        .background(AppStyle.windowBackground)
        .overlay(alignment: .leading) {
            Rectangle().fill(AppStyle.separator).frame(width: 1).allowsHitTesting(false)
        }
        .onAppear { store.refresh() }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Agent 会话")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppStyle.textPrimary)
                Text(scopeLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(AppStyle.textTertiary)
                    .lineLimit(1)
                if let scanned = store.lastScannedAt {
                    Text("更新于 \(scanned, style: .relative)前")
                        .font(.system(size: 10))
                        .foregroundStyle(AppStyle.textTertiary)
                }
            }
            Spacer(minLength: 8)
            Button(action: { store.refresh(force: true) }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppStyle.textSecondary)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(AppStyle.hoverFill))
            }
            .buttonStyle(PressScaleStyle())
            .disabled(store.isLoading)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(AppStyle.textSecondary)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(AppStyle.hoverFill))
            }
            .buttonStyle(PressScaleStyle())
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private var filterBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                filterChip("全部", agent: nil)
                filterChip("Claude", agent: "claude")
                filterChip("Codex", agent: "codex")
                Spacer()
            }
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(AppStyle.textTertiary)
                TextField("搜索标题、目录或 ID", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(AppStyle.textPrimary)
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(AppStyle.hoverFill))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func filterChip(_ label: String, agent: String?) -> some View {
        let selected = agentFilter == agent
        return Button {
            withAnimation(.easeOut(duration: 0.15)) { agentFilter = agent }
        } label: {
            Text(label)
                .font(.system(size: 11, weight: selected ? .semibold : .medium))
                .foregroundStyle(selected ? AppStyle.accent : AppStyle.textSecondary)
                .padding(.horizontal, 10)
                .frame(height: 24)
                .background(
                    Capsule().fill(selected ? AppStyle.accent.opacity(0.12) : AppStyle.hoverFill))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var content: some View {
        if store.isLoading, store.records.isEmpty {
            VStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("正在扫描会话…")
                    .font(.system(size: 12))
                    .foregroundStyle(AppStyle.textTertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = store.scanError {
            emptyState("扫描失败", err)
        } else if filtered.isEmpty {
            emptyState("暂无会话", store.records.isEmpty
                ? "本机还没找到 Claude / Codex 会话记录"
                : "当前筛选条件下没有匹配的会话")
        } else {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(filtered) { record in
                        SessionRow(record: record, coordinator: coordinator)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func emptyState(_ title: String, _ detail: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.system(size: 28))
                .foregroundStyle(AppStyle.textTertiary)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppStyle.textSecondary)
            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(AppStyle.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct SessionRow: View {
    let record: AgentSessionRecord
    let coordinator: AppCoordinator
    @State private var hovering = false
    @State private var expanded = false
    @State private var preview: [AgentSessionMessage]?
    @State private var loadingPreview = false

    private var logoName: String {
        record.agent == "claude" ? "claude" : "codex"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: toggleExpanded) {
                HStack(alignment: .top, spacing: 8) {
                    logo
                    VStack(alignment: .leading, spacing: 3) {
                        Text(record.title)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(AppStyle.textPrimary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        if let cwd = record.cwd {
                            Text((cwd as NSString).abbreviatingWithTildeInPath)
                                .font(.system(size: 10.5))
                                .foregroundStyle(AppStyle.textTertiary)
                                .lineLimit(1)
                        }
                        HStack(spacing: 6) {
                            Text(record.agent.capitalized)
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundStyle(AppStyle.accent)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(AppStyle.accent.opacity(0.10)))
                            Text(record.shortID)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(AppStyle.textTertiary)
                            Text(record.modifiedAt, style: .relative)
                                .font(.system(size: 10))
                                .foregroundStyle(AppStyle.textTertiary)
                        }
                    }
                    Spacer(minLength: 0)
                    if record.filePath != nil {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(AppStyle.textTertiary)
                            .rotationEffect(.degrees(expanded ? 180 : 0))
                            .padding(.top, 3)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded { previewSection }

            HStack(spacing: 8) {
                Button("当前面板") { coordinator.resumeSession(record, inPane: coordinator.sessionTargetPane) }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(coordinator.sessionTargetPane == nil)
                Button("新标签") { coordinator.resumeSession(record, inPane: nil) }
                    .buttonStyle(PrimaryButtonStyle())
                Menu {
                    Button("复制会话 ID") { coordinator.copyToClipboard(record.sessionID) }
                    if let cmd = record.resumeCommand {
                        Button("复制续聊命令") { coordinator.copyToClipboard(cmd) }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppStyle.textSecondary)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(AppStyle.hoverFill))
                }
                .menuStyle(.borderlessButton)
            }
        }
        .padding(12)
        .toolsCard()
        .onHover { hovering = $0 }
    }

    private func toggleExpanded() {
        guard record.filePath != nil else { return }
        withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) { expanded.toggle() }
        if expanded, preview == nil, !loadingPreview { loadPreview() }
    }

    private func loadPreview() {
        guard record.filePath != nil else { return }
        loadingPreview = true
        Task {
            let messages = await SessionPreviewCache.shared.messages(for: record)
            preview = messages
            loadingPreview = false
        }
    }

    @ViewBuilder
    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            if loadingPreview, preview == nil {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small).scaleEffect(0.65)
                    Text("读取完整对话…")
                        .font(.system(size: 10.5))
                        .foregroundStyle(AppStyle.textTertiary)
                }
                .frame(maxWidth: .infinity, minHeight: 120)
            } else if let preview, !preview.isEmpty {
                HStack {
                    Text("\(preview.count) 条消息")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(AppStyle.textTertiary)
                    Spacer()
                }
                SessionTranscriptView(messages: preview, maxHeight: 420)
            } else {
                Text("没有可预览的对话内容")
                    .font(.system(size: 10.5))
                    .foregroundStyle(AppStyle.textTertiary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(AppStyle.theme.isDark ? Color.white.opacity(0.04) : Color.black.opacity(0.03)))
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    @ViewBuilder
    private var logo: some View {
        if let image = CLIToolLogo.image(named: logoName) {
            if CLIToolLogo.isMonochrome(logoName) {
                Image(nsImage: image)
                    .resizable().scaledToFit()
                    .frame(width: 18, height: 18)
                    .foregroundStyle(AppStyle.textSecondary)
            } else {
                Image(nsImage: image)
                    .resizable().scaledToFit()
                    .frame(width: 18, height: 18)
            }
        } else {
            Image(systemName: record.agent == "claude" ? "sparkles" : "chevron.left.forwardslash.chevron.right")
                .font(.system(size: 12))
                .foregroundStyle(AppStyle.textSecondary)
                .frame(width: 18, height: 18)
        }
    }
}
