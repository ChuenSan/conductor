import AppKit
import ConductorCore
import SwiftUI

/// 侧栏列表模式：固定的工作区列表，或从家目录开始的文件夹树。
enum SidebarListMode: String {
    case workspaces
    case folders
}

/// 左侧工作区栏（自绘，深色 Craft 风）：列出工作区；点击切换，`+` 选目录新建，active 高亮。
/// 分区头可切到「文件夹」模式：家目录文件夹树，点击展开下级、右键/悬停按钮在该目录开终端。
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
    @State private var hoverTask: Task<Void, Never>?
    /// 一次性引导：用户首次触发悬停预览后永久隐藏提示。
    @AppStorage("sidebar.sessionHoverHintSeen") private var hoverHintSeen = false
    /// Finder 文件夹正悬在侧栏上方（释放即新建工作区）→ 整栏亮接收态。
    @State private var folderDropTargeted = false
    /// 文件夹树状态（展开集合 + 懒加载缓存），与侧栏同生命周期。
    @StateObject private var folderTree = FolderTreeModel()
    /// 分段控件选中底块的滑动动画命名空间。
    @Namespace private var modeTabNamespace

    /// 列表模式由 coordinator 持有：切模式时右侧整套标签/分屏跟着换上下文。
    private var listMode: SidebarListMode {
        coordinator.sidebarListMode
    }

    var body: some View {
        sidebarContent
    }

    private var sidebarContent: some View {
        VStack(alignment: isCollapsed ? .center : .leading, spacing: 0) {
            header
            ScrollViewReader { proxy in
                ScrollView {
                    if !isCollapsed, listMode == .folders {
                        SidebarFolderTree(coordinator: coordinator, model: folderTree)
                            .padding(.horizontal, 10)
                            .padding(.top, 2)
                    } else {
                        workspaceList
                    }

                    if !isCollapsed {
                        sessionsSection
                            .padding(.horizontal, 10)
                            .padding(.top, 14)
                    }
                }
                .scrollIndicators(.never)   // `.hidden` 在系统“始终显示滚动条”下仍会画 legacy 滚动条
                // 「定位当前目录」：等展开后的行上树再滚（Lazy 容器需要一拍布局）
                .onChange(of: folderTree.revealRequest) { _, request in
                    guard let request else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                        withAnimation(Motion.panel) {
                            proxy.scrollTo(request.path, anchor: .center)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity)
        .background(AppStyle.sidebarBackground)
        // 从 Finder 拖文件夹进来 → 新建工作区（同路径已存在则直接切过去）
        .dropDestination(for: URL.self) { urls, _ in
            handleFolderDrop(urls)
        } isTargeted: { folderDropTargeted = $0 }
        .overlay {
            if folderDropTargeted {
                ZStack {
                    Rectangle().fill(AppStyle.accent.opacity(0.07))
                    Rectangle().strokeBorder(AppStyle.accent.opacity(0.6), lineWidth: 2)
                }
                .allowsHitTesting(false)
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: folderDropTargeted)
        // 点走输入框即提交重命名
        .onChange(of: renameFocused) { _, focused in
            if !focused, editingWorkspace != nil { commitRename() }
        }
        .onChange(of: coordinator.sidebarPresentation.isCollapsed) { _, collapsed in
            if collapsed, editingWorkspace != nil { commitRename() }
        }
        .clipShape(Rectangle())
    }

    private var workspaceList: some View {
        VStack(alignment: isCollapsed ? .center : .leading, spacing: 3) {
            let workspaces = coordinator.visibleWorkspaces
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
                    isThinking: coordinator.isWorkspaceThinking(ws),
                    unseenDoneCount: coordinator.workspaceUnseenDoneCount(ws),
                    isEditing: editingWorkspace == ws.id,
                    isCollapsed: isCollapsed,
                    draft: $draftName,
                    focused: $renameFocused,
                    onSelect: { if editingWorkspace == nil { coordinator.selectWorkspace(ws.id) } },
                    onCommit: { commitRename() }
                )
                .contextMenu {
                    ForEach(coordinator.launchableAgents) { agent in
                        Button {
                            coordinator.launchAIAgentSession(agent, workspaceID: ws.id, cwd: ws.path)
                        } label: {
                            Label {
                                Text(AIAgentMenuPresentation.sessionTitle(for: agent))
                            } icon: {
                                LaunchableAgentIcon(agent: agent, size: 13)
                            }
                        }
                    }
                    if !coordinator.launchableAgents.isEmpty {
                        Divider()
                    }
                    Button { beginRename(ws) } label: { Label(L("重命名"), systemImage: "pencil") }
                    Button { coordinator.revealInFinder(ws.path) } label: {
                        Label(L("在 Finder 中显示"), systemImage: "folder")
                    }
                    Button { coordinator.copyToClipboard(ws.path) } label: {
                        Label(L("复制路径"), systemImage: "doc.on.doc")
                    }
                    Divider()
                    Button(role: .destructive) { confirmRemoveWorkspace(ws) } label: {
                        Label(L("删除工作区"), systemImage: "trash")
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
    }

    /// 悬停预览绑定：popover 是独立 NSWindow，能浮在终端区的 Metal 视图之上
    /// （SwiftUI 越界 overlay 会被 ghostty 的 AppKit 视图盖住，所以不能画在侧栏内）。
    private func hoverPreviewBinding(for record: AgentSessionRecord) -> Binding<Bool> {
        Binding(
            get: { hoverRecord?.id == record.id },
            set: { presented in
                if !presented, hoverRecord?.id == record.id { hoverRecord = nil }
            }
        )
    }

    private func handleSessionHover(_ record: AgentSessionRecord, inside: Bool) {
        hoverTask?.cancel()
        if inside {
            SessionPreviewCache.shared.prefetch(record)
            hoverTask = Task {
                try? await Task.sleep(nanoseconds: 280_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    hoverRecord = record
                    // 预览已出现，引导完成使命
                    if !hoverHintSeen {
                        withAnimation(.easeOut(duration: 0.3)) { hoverHintSeen = true }
                    }
                }
            }
        } else if !hoverPanelPinned {
            // 留出从行移入 popover 的时间，否则中途就被关掉
            scheduleClearHover(after: 0.25)
        }
    }

    private func scheduleClearHover(after seconds: Double) {
        hoverTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                if !hoverPanelPinned { hoverRecord = nil }
            }
        }
    }

    private var isCollapsed: Bool { coordinator.sidebarPresentation.isCollapsed }

    private var header: some View {
        VStack(alignment: isCollapsed ? .center : .leading, spacing: 0) {
            // 品牌头：应用名（无 logo）
            HStack(spacing: 0) {
                if !isCollapsed {
                    Text("Conductor")
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
                .help(isCollapsed ? L("展开侧边栏") : L("收起侧边栏"))
                .accessibilityLabel(isCollapsed ? L("展开侧边栏") : L("收起侧边栏"))
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
                .help(L("Agent 会话"))
                .accessibilityLabel(L("Agent 会话"))
                Button(action: addWorkspace) {
                    Image(systemName: "plus").font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppStyle.textSecondary)
                }
                .buttonStyle(IconButtonStyle(size: 30))
                .help(L("新增工作区"))
                .accessibilityLabel(L("新增工作区"))
                .padding(.bottom, 6)
            } else {
                HStack(spacing: 8) {
                    listModeSwitcher
                    Spacer(minLength: 4)
                    if listMode == .workspaces {
                        Button(action: addWorkspace) {
                            Image(systemName: "plus").font(.system(size: 12, weight: .medium))
                                .foregroundStyle(AppStyle.textSecondary)
                        }
                        .buttonStyle(IconButtonStyle(size: 24))
                        .help(L("新增工作区"))
                        .accessibilityLabel(L("新增工作区"))
                        .transition(.scale.combined(with: .opacity))
                    } else {
                        Button(action: locateActiveDirectory) {
                            Image(systemName: "scope").font(.system(size: 12, weight: .medium))
                                .foregroundStyle(AppStyle.textSecondary)
                        }
                        .buttonStyle(IconButtonStyle(size: 24))
                        .help(L("在树中定位当前终端目录"))
                        .accessibilityLabel(L("在树中定位当前终端目录"))
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(.leading, 12)
                .padding(.trailing, 10)
                .padding(.bottom, 8)
                .animation(Motion.panel, value: listMode)
            }
        }
    }

    /// 分区头的「工作区 / 文件夹」胶囊分段控件：选中底块滑动跟随。
    private var listModeSwitcher: some View {
        HStack(spacing: 2) {
            modeSegment(L("工作区"), icon: "square.grid.2x2", mode: .workspaces)
            modeSegment(L("文件夹"), icon: "folder", mode: .folders)
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(AppStyle.activeFill.opacity(0.7))
        )
        // 模式也可能被外部切换（命令面板跳工作区、通知跳进文件夹上下文），同样要有滑动
        .animation(Motion.panel, value: listMode)
    }

    private func modeSegment(_ title: String, icon: String, mode: SidebarListMode) -> some View {
        let selected = listMode == mode
        return Button {
            withAnimation(Motion.panel) {
                coordinator.setSidebarListMode(mode)
            }
        } label: {
            HStack(spacing: 4.5) {
                Image(systemName: selected ? icon + ".fill" : icon)
                    .font(.system(size: 9.5, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                Text(title)
                    .font(.system(size: 11, weight: selected ? .semibold : .medium))
            }
            .foregroundStyle(selected ? AppStyle.textPrimary : AppStyle.textTertiary)
            .padding(.horizontal, 9)
            .frame(height: 21)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 6.5, style: .continuous)
                        .fill(AppStyle.elevated)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6.5, style: .continuous)
                                .strokeBorder(AppStyle.textPrimary.opacity(0.08), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.28), radius: 2.5, y: 1)
                        .matchedGeometryEffect(id: "modeTabSelection", in: modeTabNamespace)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 6.5, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
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
                Text(L("会话"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppStyle.textTertiary)
                    .textCase(.uppercase)
                    .tracking(0.5)
                Spacer()
                Button(L("全部")) {
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
                    Text(L("扫描中…"))
                        .font(.system(size: 11))
                        .foregroundStyle(AppStyle.textTertiary)
                }
                .padding(.leading, 4)
            } else if sessions.isEmpty {
                Text(L("暂无 Agent 会话"))
                    .font(.system(size: 11))
                    .foregroundStyle(AppStyle.textTertiary)
                    .padding(.leading, 4)
            } else {
                if !hoverHintSeen {
                    HStack(spacing: 5) {
                        Image(systemName: "cursorarrow.rays")
                            .font(.system(size: 10, weight: .medium))
                        Text(L("鼠标悬停可预览对话"))
                            .font(.system(size: 10.5))
                    }
                    .foregroundStyle(AppStyle.textTertiary)
                    .padding(.leading, 4)
                    .padding(.bottom, 2)
                    .transition(.opacity)
                }
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(sessions) { record in
                        SidebarSessionRow(
                            record: record,
                            onResume: { coordinator.resumeSession(record, inPane: nil) },
                            onHover: { handleSessionHover(record, inside: $0) }
                        )
                        .popover(isPresented: hoverPreviewBinding(for: record), arrowEdge: .trailing) {
                            SessionHoverPreviewPanel(record: record) {
                                coordinator.resumeSession(record, inPane: nil)
                                hoverRecord = nil
                            }
                            .onHover { pinned in
                                hoverPanelPinned = pinned
                                if pinned {
                                    hoverTask?.cancel()
                                } else {
                                    scheduleClearHover(after: 0.15)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    /// 删除工作区是不可撤销的破坏性操作（会关掉其中所有终端），先确认再动手。
    private func confirmRemoveWorkspace(_ ws: Workspace) {
        let paneCount = ws.tabs.flatMap { $0.rootSplit.leaves() }.count
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L("删除工作区「%@」？", ws.name)
        alert.informativeText = paneCount > 0
            ? L("其中 %ld 个终端会被关闭，此操作无法撤销。", paneCount)
            : L("此操作无法撤销。")
        alert.addButton(withTitle: L("删除"))
        alert.addButton(withTitle: L("取消"))
        if let deleteButton = alert.buttons.first { deleteButton.hasDestructiveAction = true }
        if alert.runModal() == .alertFirstButtonReturn {
            coordinator.removeWorkspace(ws.id)
        }
    }

    /// 「定位当前终端目录」：在文件夹树里展开、滚动并高亮活动 pane 的 cwd。
    private func locateActiveDirectory() {
        let active = coordinator.store.workspaces
            .first(where: { $0.id == coordinator.store.activeWorkspace })?.path
        guard let cwd = coordinator.activeCwd ?? active else { return }
        let found = withAnimation(Motion.expand) { folderTree.reveal(cwd) }
        if !found {
            ToastHUD.shared.show(L("该目录不在家目录下，树里看不到"),
                                 icon: "exclamationmark.circle.fill", over: coordinator.window)
        }
    }

    /// Finder 拖入的目录 → 逐个建工作区；同路径已有的不重复建，直接切过去。
    /// 返回 false 表示拖进来的不含目录（如纯文件），让系统显示拒收。
    private func handleFolderDrop(_ urls: [URL]) -> Bool {
        let dirs = urls.map(\.standardizedFileURL).filter { url in
            var isDir: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
        }
        guard !dirs.isEmpty else { return false }

        var created = 0
        var lastCreated: URL?
        var lastExisting: Workspace?
        for dir in dirs {
            if let existing = coordinator.visibleWorkspaces.first(where: { $0.path == dir.path }) {
                lastExisting = existing
            } else {
                coordinator.addWorkspace(path: dir.path)
                created += 1
                lastCreated = dir
            }
        }
        switch (created, lastCreated, lastExisting) {
        case (0, _, let existing?):
            // 全是已有的 → 切到最后一个并提示
            coordinator.selectWorkspace(existing.id)
            ToastHUD.shared.show(L("已切到工作区「%@」", existing.name),
                                 icon: "folder.fill", over: coordinator.window)
        case (1, let dir?, _):
            ToastHUD.shared.show(L("已新建工作区「%@」", dir.lastPathComponent),
                                 icon: "folder.fill.badge.plus", over: coordinator.window)
        default:
            ToastHUD.shared.show(L("已新建 %ld 个工作区", created),
                                 icon: "folder.fill.badge.plus", over: coordinator.window)
        }
        return true
    }

    private func addWorkspace() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = L("选为工作区")
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
    let isThinking: Bool
    /// 这个工作区里「后台跑完还没看」的 pane 数（绿点 + 数字角标）。
    let unseenDoneCount: Int
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
                        if isThinking {
                            ThinkingIndicator(size: 8)
                                .transition(.scale.combined(with: .opacity))
                        }
                        if unseenDoneCount > 0 {
                            unseenDoneBadge
                                .transition(.scale.combined(with: .opacity))
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
        .animation(Motion.hover, value: hovering)
        .animation(.easeInOut(duration: 0.2), value: selected)
        .animation(Motion.panel, value: isCollapsed)
        .animation(.easeInOut(duration: 0.2), value: summary.activeDetailText)
        .onTapGesture { if !isEditing { onSelect() } }
        .onHover { hovering = $0 }
        .help(unseenDoneCount > 0
            ? summary.tooltipText + "\n" + L("%ld 个 Agent 已完成，等你来看", unseenDoneCount)
            : summary.tooltipText)
        .accessibilityLabel("\(name), \(summary.pathText), \(summary.metricsText)")
        .animation(.easeOut(duration: 0.2), value: unseenDoneCount > 0)
    }

    /// 「完成未读」绿点：>1 时带数字。
    private var unseenDoneBadge: some View {
        HStack(spacing: 3) {
            Circle()
                .fill(AppStyle.doneGreen)
                .frame(width: 7, height: 7)
                .shadow(color: AppStyle.doneGreen.opacity(0.55), radius: 2.5)
            if unseenDoneCount > 1 {
                Text("\(unseenDoneCount)")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(AppStyle.doneGreen)
            }
        }
    }

    private var workspaceGlyph: some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: "folder")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(selected ? AppStyle.textPrimary : AppStyle.textSecondary)
                .frame(width: isCollapsed ? 22 : 18, height: 20)
            // 收起态没有名字行，思考动效挂在图标右下角（右上角留给 pane 数角标）
            if isCollapsed, isThinking {
                ThinkingIndicator(size: 7)
                    .offset(x: 5, y: 16)
                    .transition(.scale.combined(with: .opacity))
            }
            // 收起态的完成未读绿点：挂图标左上角（右上角是 pane 数、右下角是思考动效）
            if isCollapsed, unseenDoneCount > 0 {
                Circle()
                    .fill(AppStyle.doneGreen)
                    .frame(width: 6.5, height: 6.5)
                    .shadow(color: AppStyle.doneGreen.opacity(0.55), radius: 2.5)
                    .offset(x: -14, y: -3)
                    .transition(.scale.combined(with: .opacity))
            }
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
