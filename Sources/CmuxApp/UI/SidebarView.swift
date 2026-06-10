import AppKit
import CmuxCore
import SwiftUI

/// 左侧工作区栏（自绘，深色 Craft 风）：列出工作区；点击切换，`+` 选目录新建，active 高亮。
/// 右键菜单可重命名（行内编辑）/ 删除工作区。
struct SidebarView: View {
    @ObservedObject var coordinator: AppCoordinator
    @ObservedObject private var configStore = ConfigStore.shared   // 主题变 → 重渲染（AppStyle 跟随）
    @ObservedObject private var sessionStore = SessionManagerStore.shared
    @State private var editingWorkspace: WorkspaceID?
    @State private var draftName: String = ""
    @FocusState private var renameFocused: Bool
    @State private var hoverRecord: AgentSessionRecord?
    @State private var hoverPanelPinned = false
    @State private var rowFrames: [String: CGRect] = [:]
    @State private var hoverTask: Task<Void, Never>?

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                sidebarContent
                hoverPreviewLayer(sidebarWidth: geo.size.width)
            }
        }
        .coordinateSpace(name: "sidebarRoot")
        .onPreferenceChange(SidebarRowFrameKey.self) { rowFrames = $0 }
    }

    private var sidebarContent: some View {
        VStack(alignment: isCollapsed ? .center : .leading, spacing: 0) {
            header
            ScrollView {
                VStack(alignment: isCollapsed ? .center : .leading, spacing: 3) {
                    let workspaces = coordinator.store.workspaces
                    ForEach(Array(workspaces.enumerated()), id: \.element.id) { index, ws in
                        let selected = ws.id == coordinator.store.activeWorkspace
                        let summary = SidebarWorkspaceSummary(
                            workspace: ws,
                            isSelected: selected,
                            paneTitles: coordinator.paneTitles,
                            paneCwds: coordinator.paneCwds
                        )
                        let row = WorkspaceRow(
                            name: ws.name,
                            summary: summary,
                            selected: selected,
                            isEditing: editingWorkspace == ws.id,
                            isCollapsed: isCollapsed,
                            draft: $draftName,
                            focused: $renameFocused,
                            onSelect: { if editingWorkspace == nil { coordinator.selectWorkspace(ws.id) } },
                            onCommit: { commitRename() }
                        )
                        .contextMenu {
                            Button { beginRename(ws) } label: { Label("重命名", systemImage: "pencil") }
                            Button { coordinator.revealInFinder(ws.path) } label: {
                                Label("在 Finder 中显示", systemImage: "folder")
                            }
                            Button { coordinator.copyToClipboard(ws.path) } label: {
                                Label("复制路径", systemImage: "doc.on.doc")
                            }
                            Divider()
                            Button(role: .destructive) { coordinator.removeWorkspace(ws.id) } label: {
                                Label("删除工作区", systemImage: "trash")
                            }
                            .disabled(workspaces.count <= 1)
                        }

                        // 仅多个工作区时才挂拖拽重排（单个无处可排，且避免与点击争手势）
                        if workspaces.count > 1, editingWorkspace == nil {
                            row
                                .draggable(ws.id.value)
                                .dropDestination(for: String.self) { dropped, _ in
                                    guard let s = dropped.first else { return false }
                                    coordinator.moveWorkspace(WorkspaceID(s), toIndex: index)
                                    return true
                                }
                        } else {
                            row
                        }
                    }
                }
                .padding(.horizontal, isCollapsed ? 8 : 10)
                .padding(.top, 2)

                if !isCollapsed {
                    sessionsSection
                        .padding(.horizontal, 10)
                        .padding(.top, 14)
                }
            }
            .scrollIndicators(.hidden)
            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity)
        .background(AppStyle.sidebarBackground)
        // 点走输入框即提交重命名
        .onChange(of: renameFocused) { _, focused in
            if !focused, editingWorkspace != nil { commitRename() }
        }
        .onChange(of: coordinator.sidebarPresentation.isCollapsed) { _, collapsed in
            if collapsed, editingWorkspace != nil { commitRename() }
        }
        .clipShape(Rectangle())
    }

    @ViewBuilder
    private func hoverPreviewLayer(sidebarWidth: CGFloat) -> some View {
        if !isCollapsed, let record = hoverRecord, let frame = rowFrames[record.id] {
            SessionHoverPreviewPanel(record: record) {
                coordinator.resumeSession(record, inPane: nil)
                hoverRecord = nil
            }
            .offset(x: sidebarWidth + 10, y: max(8, frame.minY - 4))
            .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .leading)))
            .zIndex(100)
            .onHover { pinned in
                hoverPanelPinned = pinned
                if !pinned { scheduleClearHover(after: 0.15) }
            }
        }
    }

    private func handleSessionHover(_ record: AgentSessionRecord, inside: Bool) {
        hoverTask?.cancel()
        if inside {
            SessionPreviewCache.shared.prefetch(record)
            hoverTask = Task {
                try? await Task.sleep(nanoseconds: 280_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    withAnimation(.easeOut(duration: 0.16)) { hoverRecord = record }
                }
            }
        } else if !hoverPanelPinned {
            scheduleClearHover(after: 0.12)
        }
    }

    private func scheduleClearHover(after seconds: Double) {
        hoverTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                if !hoverPanelPinned {
                    withAnimation(.easeOut(duration: 0.12)) { hoverRecord = nil }
                }
            }
        }
    }

    private var isCollapsed: Bool { coordinator.sidebarPresentation.isCollapsed }

    private var header: some View {
        VStack(alignment: isCollapsed ? .center : .leading, spacing: 0) {
            // 品牌头：应用名（无 logo）
            HStack(spacing: 0) {
                if !isCollapsed {
                    Text("conductor")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(AppStyle.textPrimary)
                    Spacer()
                }
                Button(action: coordinator.toggleSidebar) {
                    Image(systemName: isCollapsed ? "sidebar.right" : "sidebar.left")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AppStyle.textSecondary)
                }
                .buttonStyle(IconButtonStyle(size: 28))
                .help(isCollapsed ? "展开侧边栏" : "收起侧边栏")
                .accessibilityLabel(isCollapsed ? "展开侧边栏" : "收起侧边栏")
            }
            .frame(maxWidth: .infinity, alignment: isCollapsed ? .center : .leading)
            .padding(.horizontal, isCollapsed ? 0 : 16)
            .padding(.top, 24)
            .padding(.bottom, 12)

            // 工作区分区头
            if isCollapsed {
                Button {
                    let path = coordinator.store.workspaces
                        .first(where: { $0.id == coordinator.store.activeWorkspace })?.path
                    coordinator.openSessionManager(scopePath: path)
                } label: {
                    Image(systemName: "bubble.left.and.text.bubble.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppStyle.textSecondary)
                }
                .buttonStyle(IconButtonStyle(size: 30))
                .help("Agent 会话")
                .accessibilityLabel("Agent 会话")
                Button(action: addWorkspace) {
                    Image(systemName: "plus").font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppStyle.textSecondary)
                }
                .buttonStyle(IconButtonStyle(size: 30))
                .help("新增工作区")
                .accessibilityLabel("新增工作区")
                .padding(.bottom, 6)
            } else {
                HStack {
                    Text("工作区")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppStyle.textTertiary)
                        .textCase(.uppercase)
                        .tracking(0.5)
                    Spacer()
                    Button(action: addWorkspace) {
                        Image(systemName: "plus").font(.system(size: 12, weight: .medium))
                            .foregroundStyle(AppStyle.textSecondary)
                    }
                    .buttonStyle(IconButtonStyle(size: 22))
                    .help("新增工作区")
                    .accessibilityLabel("新增工作区")
                }
                .padding(.leading, 14)
                .padding(.trailing, 10)
                .padding(.bottom, 6)
            }
        }
    }

    private func beginRename(_ ws: Workspace) {
        draftName = ws.name
        editingWorkspace = ws.id
        coordinator.expandSidebar()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { renameFocused = true }
    }

    private func commitRename() {
        if let id = editingWorkspace { coordinator.renameWorkspace(id, to: draftName) }
        editingWorkspace = nil
        renameFocused = false
    }

    private var sessionsSection: some View {
        let workspacePath = coordinator.store.workspaces
            .first(where: { $0.id == coordinator.store.activeWorkspace })?.path ?? ""
        let sessions = sessionStore.recordsForWorkspace(workspacePath, limit: 500)

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("会话")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppStyle.textTertiary)
                    .textCase(.uppercase)
                    .tracking(0.5)
                Spacer()
                Button("全部") {
                    coordinator.openSessionManager(scopePath: workspacePath.isEmpty ? nil : workspacePath)
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppStyle.textSecondary)
                .buttonStyle(.plain)
            }
            .padding(.leading, 4)

            if sessionStore.isLoading, sessions.isEmpty {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small).scaleEffect(0.65)
                    Text("扫描中…")
                        .font(.system(size: 11))
                        .foregroundStyle(AppStyle.textTertiary)
                }
                .padding(.leading, 4)
            } else if sessions.isEmpty {
                Text("暂无 Agent 会话")
                    .font(.system(size: 11))
                    .foregroundStyle(AppStyle.textTertiary)
                    .padding(.leading, 4)
            } else {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(sessions) { record in
                        SidebarSessionRow(
                            record: record,
                            onResume: { coordinator.resumeSession(record, inPane: nil) },
                            onHover: { handleSessionHover(record, inside: $0) }
                        )
                    }
                }
            }
        }
    }

    private func addWorkspace() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "选为工作区"
        if panel.runModal() == .OK, let url = panel.url {
            coordinator.addWorkspace(path: url.path)
        }
    }
}

private struct SidebarSessionRow: View {
    let record: AgentSessionRecord
    let onResume: () -> Void
    let onHover: (Bool) -> Void
    @State private var hovering = false

    private var logoName: String { record.agent == "claude" ? "claude" : "codex" }

    var body: some View {
        Button(action: onResume) {
            HStack(spacing: 8) {
                sessionLogo
                VStack(alignment: .leading, spacing: 2) {
                    Text(record.title)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(hovering ? AppStyle.textPrimary : AppStyle.textSecondary)
                        .lineLimit(1)
                    Text("\(record.agent.capitalized) · \(record.shortID)")
                        .font(.system(size: 10))
                        .foregroundStyle(AppStyle.textTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(hovering ? AppStyle.hoverFill : Color.clear))
        }
        .buttonStyle(.plain)
        .background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: SidebarRowFrameKey.self,
                    value: [record.id: geo.frame(in: .named("sidebarRoot"))])
            }
        )
        .onHover { inside in
            hovering = inside
            onHover(inside)
        }
    }

    @ViewBuilder
    private var sessionLogo: some View {
        if let image = CLIToolLogo.image(named: logoName) {
            Image(nsImage: image)
                .resizable().scaledToFit()
                .frame(width: 14, height: 14)
        } else {
            Image(systemName: "bubble.left")
                .font(.system(size: 11))
                .foregroundStyle(AppStyle.textTertiary)
                .frame(width: 14, height: 14)
        }
    }
}

private struct WorkspaceRow: View {
    let name: String
    let summary: SidebarWorkspaceSummary
    let selected: Bool
    let isEditing: Bool
    let isCollapsed: Bool
    @Binding var draft: String
    var focused: FocusState<Bool>.Binding
    let onSelect: () -> Void
    let onCommit: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: isCollapsed ? 0 : 8) {
            workspaceGlyph
                .padding(.top, isCollapsed ? 0 : 2)
            if !isCollapsed {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        if isEditing {
                            TextField("", text: $draft)
                                .textFieldStyle(.plain)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(AppStyle.textPrimary)
                                .focused(focused)
                                .onSubmit { onCommit() }
                        } else {
                            Text(name)
                                .font(.system(size: 13, weight: selected ? .semibold : .regular))
                                .foregroundStyle(selected ? AppStyle.textPrimary : AppStyle.textSecondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        metricsBadge
                    }

                    Text(summary.pathText)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(AppStyle.textTertiary)
                        .lineLimit(1)

                    if let activeDetail = summary.activeDetailText {
                        HStack(spacing: 5) {
                            Image(systemName: "terminal")
                                .font(.system(size: 10, weight: .semibold))
                            Text(activeDetail)
                                .font(.system(size: 11, weight: .medium))
                                .lineLimit(1)
                        }
                        .foregroundStyle(AppStyle.accent)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: isCollapsed ? .center : .leading)
        .padding(.horizontal, isCollapsed ? 0 : 9)
        .padding(.vertical, isCollapsed ? 7 : 7)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(selected ? AppStyle.activeFill : (hovering ? AppStyle.hoverFill : Color.clear))
        )
        .contentShape(Rectangle())
        .animation(.easeOut(duration: 0.15), value: hovering)
        .animation(.easeInOut(duration: 0.22), value: selected)
        .animation(.spring(response: 0.34, dampingFraction: 0.82), value: isCollapsed)
        .animation(.easeInOut(duration: 0.20), value: summary.activeDetailText)
        .onTapGesture { if !isEditing { onSelect() } }
        .onHover { hovering = $0 }
        .help(summary.tooltipText)
        .accessibilityLabel("\(name), \(summary.pathText), \(summary.metricsText)")
    }

    private var workspaceGlyph: some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: "folder")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(selected ? AppStyle.textPrimary : AppStyle.textSecondary)
                .frame(width: isCollapsed ? 22 : 18, height: 20)
            if isCollapsed, summary.paneCount > 1 {
                Text("\(min(summary.paneCount, 99))")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(AppStyle.accent)
                    .padding(.horizontal, 3)
                    .frame(height: 11)
                    .background(Capsule().fill(AppStyle.accent.opacity(0.12)))
                    .offset(x: 7, y: -4)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(width: isCollapsed ? 22 : 18, height: 20)
    }

    private var metricsBadge: some View {
        Text(summary.metricsText)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(selected ? AppStyle.textSecondary : AppStyle.textTertiary)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 7)
            .frame(height: 18)
            .background(Capsule().fill(selected ? AppStyle.hoverFill : AppStyle.activeFill))
    }
}
