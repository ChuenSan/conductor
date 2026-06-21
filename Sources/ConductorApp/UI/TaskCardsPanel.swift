import AppKit
import ConductorCore
import SwiftUI

// MARK: - 任务卡片（甩进终端就跑）
//
// 灵魂：任务是一张「牌」，抓起来甩进哪个终端 pane，就在那跑。
// 静息：一叠可抓的任务牌（悬停微抬，暗示可抓）。点一下牌 = 在当前终端跑（最快）。
// 抓起拖动 = 系统级拖拽，牌影跟手；拖到主窗里任意终端 pane，那个 pane 整卡高亮，松手 = 在那跑。
// 带 {{变量}} 的，落到 pane 后面板弹填值条，填完在那 pane 跑。创建仍是搜索框写命令 ↵。

private struct TaskRunRequest {
    let card: TaskCard
    var workspaceID: String?
    var inCurrentPane: Bool
    var paneID: PaneID?
}

/// 只让标题栏移动窗口：mouseDown 时发起 performDrag。背景拖动整体关掉，
/// 这样拖任务牌（系统拖拽）绝不会误移窗口，两者物理隔离。
private struct WindowDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { Handle() }
    func updateNSView(_ nsView: NSView, context: Context) {}
    final class Handle: NSView {
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }
}

/// 任务牌的拖拽源 + 点击。垫在卡片 `.background`：卡片正文非交互，鼠标会透下来到这。
/// 用 AppKit 原生拖拽 + 饿汉式 `NSPasteboardItem.setString`（落点 `string(forType:)` 同步读得到，
/// 这是 pane 重排已验证可行的路子；SwiftUI .onDrag 的数据在 AppKit 落点读不到，故弃用）。
private struct CardDragSource: NSViewRepresentable {
    let cardID: String
    let title: String
    let onTap: () -> Void

    func makeNSView(context: Context) -> NSView {
        let v = SourceView()
        v.cardID = cardID
        v.title = title
        v.onTap = onTap
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        guard let v = nsView as? SourceView else { return }
        v.cardID = cardID
        v.title = title
        v.onTap = onTap
    }

    final class SourceView: NSView, NSDraggingSource {
        var cardID = ""
        var title = ""
        var onTap: (() -> Void)?
        private var downAt: NSPoint?
        private var dragging = false

        override func mouseDown(with event: NSEvent) {
            downAt = event.locationInWindow
            dragging = false
        }

        override func mouseDragged(with event: NSEvent) {
            guard !dragging, let downAt else { return }
            let p = event.locationInWindow
            guard abs(p.x - downAt.x) > 6 || abs(p.y - downAt.y) > 6 else { return }
            dragging = true
            let item = NSPasteboardItem()
            item.setString(cardID, forType: PaneContainerView.taskType)
            let dragItem = NSDraggingItem(pasteboardWriter: item)
            let image = dragImage()
            dragItem.setDraggingFrame(NSRect(origin: .zero, size: image.size), contents: image)
            beginDraggingSession(with: [dragItem], event: event, source: self)
        }

        override func mouseUp(with event: NSEvent) {
            if !dragging { onTap?() }
            downAt = nil
            dragging = false
        }

        func draggingSession(_ session: NSDraggingSession,
                             sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }

        /// 拖拽影：AppKit 画一张卡片样子（SwiftUI 层 cacheDisplay 抓不到，故手绘）。
        private func dragImage() -> NSImage {
            let size = NSSize(width: max(bounds.width, 200), height: max(bounds.height, 44))
            let img = NSImage(size: size)
            img.lockFocus()
            let rect = NSRect(origin: .zero, size: size).insetBy(dx: 1.5, dy: 1.5)
            let path = NSBezierPath(roundedRect: rect, xRadius: 12, yRadius: 12)
            NSColor(AppStyle.accent).withAlphaComponent(0.14).setFill()
            path.fill()
            NSColor(AppStyle.accent).withAlphaComponent(0.85).setStroke()
            path.lineWidth = 1.5
            path.stroke()
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
                .foregroundColor: NSColor(AppStyle.textPrimary),
            ]
            let text = title.isEmpty ? L("任务") : title
            let textSize = (text as NSString).size(withAttributes: attrs)
            (text as NSString).draw(at: NSPoint(x: 14, y: (size.height - textSize.height) / 2),
                                    withAttributes: attrs)
            img.unlockFocus()
            return img
        }
    }
}

struct TaskCardsPanelView: View {
    @ObservedObject var coordinator: AppCoordinator
    @ObservedObject var store: TaskCardStore
    let onClose: () -> Void

    @State private var query = ""
    @FocusState private var searchFocused: Bool
    @State private var hoverCardID: String?

    @State private var expandedEditID: String?
    @State private var draftTitle = ""
    @State private var draftPrompt = ""

    @State private var fillRequest: TaskRunRequest?
    @State private var fillValues: [String: String] = [:]

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var visibleCards: [TaskCard] {
        let q = trimmedQuery.lowercased()
        return store.cards
            .filter { card in
                q.isEmpty
                    || card.displayTitle.lowercased().contains(q)
                    || card.prompt.lowercased().contains(q)
            }
            .sorted { a, b in
                if a.pinned != b.pinned { return a.pinned }
                return (a.lastRunAt ?? a.updatedAt) > (b.lastRunAt ?? b.updatedAt)
            }
    }

    var body: some View {
        ZStack {
            launcher
            if let request = fillRequest {
                fillOverlay(request).transition(.opacity)
            }
        }
        .frame(width: 600, height: 560)
        .taskCardPanelSurface(cornerRadius: Radius.xl)
        .animation(Motion.snappy, value: fillRequest != nil)
        .animation(Motion.snappy, value: expandedEditID)
        .onChange(of: store.pendingDropFill) { _, request in
            guard let request, let card = store.cards.first(where: { $0.id == request.cardID }) else { return }
            store.pendingDropFill = nil
            fillValues = Dictionary(uniqueKeysWithValues: card.variableNames.map { ($0, "") })
            fillRequest = TaskRunRequest(card: card, workspaceID: nil, inCurrentPane: false, paneID: PaneID(request.paneID))
        }
        .onAppear {
            DispatchQueue.main.async {
                searchFocused = true
                #if DEBUG
                switch ProcessInfo.processInfo.environment["CDR_DEBUG_TC"] {
                case "edit": if let c = store.cards.first { startInlineEdit(c) }
                case "fill": if let c = store.cards.first(where: { !$0.variableNames.isEmpty }) { requestRun(c, inCurrentPane: true) }
                default: break
                }
                #endif
            }
        }
    }

    // MARK: 启动器

    private var launcher: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppStyle.accent)
                Text(L("任务卡片"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppStyle.textPrimary)
                Spacer()
                IconOnlyButton(systemName: "xmark", help: L("关闭 (Esc)"), size: 26, symbolSize: 11, weight: .bold) {
                    onClose()
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 10)
            .background(WindowDragHandle())

            searchField
                .padding(.horizontal, 14)
                .padding(.bottom, 12)

            if visibleCards.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 9) {
                        ForEach(visibleCards) { card in
                            if expandedEditID == card.id {
                                inlineEditor(card)
                            } else {
                                taskCard(card)
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 16)
                }
                .scrollIndicators(.never)
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppStyle.textTertiary)
            TextField(L("搜索任务，或写命令 ↵ 存为新任务"), text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(AppStyle.textPrimary)
                .focused($searchFocused)
                .onSubmit(submitSearch)
            if !query.isEmpty {
                IconOnlyButton(systemName: "xmark.circle.fill", help: L("清空"), size: 18, symbolSize: 10, tint: AppStyle.textTertiary) {
                    query = ""
                }
            }
        }
        .padding(.horizontal, 11)
        .frame(height: 36)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(AppStyle.hoverFill.opacity(0.9)))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(AppStyle.separator.opacity(0.18), lineWidth: 1))
    }

    private func submitSearch() {
        if let first = visibleCards.first {
            runHere(first)
        } else if !trimmedQuery.isEmpty {
            createFromQuery()
        }
    }

    private func createFromQuery() {
        let now = Date()
        let card = TaskCard(
            id: "task-\(UUID().uuidString)",
            title: "", prompt: trimmedQuery,
            workspaceID: nil, executor: .shell,
            createdAt: now, updatedAt: now, lastRunAt: nil, runCount: 0)
        store.upsert(card)
        query = ""
    }

    // MARK: 任务牌（点=当前终端跑；拖=甩进某个终端）

    private func taskCard(_ card: TaskCard) -> some View {
        let hover = hoverCardID == card.id
        let variables = card.variableNames
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Button { store.togglePin(card.id) } label: {
                    Image(systemName: card.pinned ? "star.fill" : "star")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(card.pinned ? AppStyle.waitAmber : AppStyle.textTertiary.opacity(0.55))
                }
                .buttonStyle(.plain)
                .help(card.pinned ? L("取消置顶") : L("置顶"))

                Text(card.displayTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppStyle.textPrimary)
                    .lineLimit(1)
                if !variables.isEmpty {
                    Text(L("%ld 变量", variables.count))
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(AppStyle.accent)
                }
                Spacer(minLength: 6)
                if hover {
                    IconOnlyButton(systemName: "square.and.pencil", help: L("编辑"), size: 22, symbolSize: 10.5) {
                        startInlineEdit(card)
                    }
                    .transition(.opacity)
                }
            }
            if !card.title.isEmpty {
                Text(card.prompt)
                    .font(.system(size: 10.5, weight: .regular, design: .monospaced))
                    .foregroundStyle(AppStyle.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Text(metaLine(card))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(AppStyle.textTertiary)
                .lineLimit(1)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        // 拖拽源夹在正文与填充之间：正文非交互 → 鼠标落到它；填充 Shape 在它身后只做视觉。
        .background(CardDragSource(cardID: card.id, title: card.displayTitle) { runHere(card) })
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(hover ? AppStyle.elevated : (AppStyle.theme.isDark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(AppStyle.separator.opacity(hover ? 0.28 : 0.14), lineWidth: 1))
        .shadow(color: .black.opacity(hover ? (AppStyle.theme.isDark ? 0.4 : 0.12) : 0), radius: hover ? 8 : 0, y: hover ? 4 : 0)
        .offset(y: hover ? -2 : 0)
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onHover { inside in
            if inside { hoverCardID = card.id }
            else if hoverCardID == card.id { hoverCardID = nil }
        }
        .help(L("点=当前终端 · 拖进终端=在那跑 · 右键=分配到…"))
        .animation(Motion.hover, value: hover)
        .contextMenu { cardMenu(card) }
    }

    /// 右键菜单：显式「分配到某终端 / 某工作区」+ 编辑/置顶/删除（不靠拖也能指派）。
    @ViewBuilder
    private func cardMenu(_ card: TaskCard) -> some View {
        Button {
            runHere(card)
        } label: { Label(L("在当前终端运行"), systemImage: "play.fill") }

        let targets = coordinator.taskDispatchTargets()
        if !targets.isEmpty {
            Menu(L("分配到终端")) {
                ForEach(targets, id: \.pane) { target in
                    Button(target.label) { requestRun(card, paneID: target.pane) }
                }
            }
        }
        Menu(L("新标签运行于")) {
            ForEach(coordinator.visibleWorkspaces, id: \.id) { ws in
                Button(ws.name) { requestRun(card, workspaceID: ws.id.value) }
            }
        }

        Divider()
        Button { store.togglePin(card.id) } label: {
            Label(card.pinned ? L("取消置顶") : L("置顶"), systemImage: card.pinned ? "star.slash" : "star")
        }
        Button { startInlineEdit(card) } label: { Label(L("编辑"), systemImage: "square.and.pencil") }
        Button(role: .destructive) { store.delete(card.id) } label: { Label(L("删除"), systemImage: "trash") }
    }

    // MARK: 行内编辑

    private func inlineEditor(_ card: TaskCard) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(L("标题（可选）"), text: $draftTitle)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(AppStyle.textPrimary)
                .padding(.horizontal, 10)
                .frame(height: 32)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(AppStyle.hoverFill.opacity(0.7)))

            TextEditor(text: $draftPrompt)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundStyle(AppStyle.textPrimary)
                .scrollContentBackground(.hidden)
                .frame(height: 72)
                .padding(7)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(AppStyle.hoverFill.opacity(0.7)))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(AppStyle.separator.opacity(0.16), lineWidth: 1))

            HStack(spacing: 8) {
                Text(L("甩进哪个终端 = 谁执行"))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(AppStyle.textTertiary)
                Spacer(minLength: 0)
                AgentToolsLinkButton(title: L("删除"), tint: AppStyle.errorRed) {
                    store.delete(card.id)
                    expandedEditID = nil
                }
                ToolActionButton(title: L("完成"), systemImage: "checkmark", role: .primary, height: 26, fontSize: 11, horizontalPadding: 12) {
                    commitInlineEdit(card.id)
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(AppStyle.elevated))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(AppStyle.accent.opacity(0.3), lineWidth: 1))
    }

    private func startInlineEdit(_ card: TaskCard) {
        draftTitle = card.title
        draftPrompt = card.prompt
        expandedEditID = card.id
    }

    private func commitInlineEdit(_ id: String) {
        if var card = store.cards.first(where: { $0.id == id }) {
            card.title = draftTitle
            card.prompt = draftPrompt
            store.upsert(card)
        }
        expandedEditID = nil
    }

    // MARK: 空状态

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "bolt")
                .font(.system(size: 26, weight: .regular))
                .foregroundStyle(AppStyle.textTertiary)
            if trimmedQuery.isEmpty {
                Text(L("还没有任务卡片"))
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(AppStyle.textPrimary)
                Text(L("在上面写一条命令按 ↵ 就存成任务。点牌在当前终端跑，或把牌拖进某个终端在那跑。"))
                    .font(.system(size: 11.5, weight: .regular))
                    .foregroundStyle(AppStyle.textTertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
            } else {
                Button(action: createFromQuery) {
                    HStack(spacing: 6) {
                        Image(systemName: "return").font(.system(size: 11, weight: .bold))
                        Text(L("新建任务：%@", trimmedQuery))
                            .font(.system(size: 12.5, weight: .semibold))
                            .lineLimit(1).truncationMode(.middle)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .frame(height: 32)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(AppStyle.accent))
                }
                .buttonStyle(.plain)
                Text(L("没有匹配的任务 · 按 ↵ 直接存成新任务"))
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(AppStyle.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    // MARK: 运行

    private func runHere(_ card: TaskCard) {
        requestRun(card, inCurrentPane: true)
    }

    private func requestRun(_ card: TaskCard, workspaceID: String? = nil, inCurrentPane: Bool = false, paneID: PaneID? = nil) {
        let request = TaskRunRequest(card: card, workspaceID: workspaceID, inCurrentPane: inCurrentPane, paneID: paneID)
        if card.variableNames.isEmpty {
            fire(request, resolvedPrompt: nil)
        } else {
            fillValues = Dictionary(uniqueKeysWithValues: card.variableNames.map { ($0, "") })
            fillRequest = request
        }
    }

    private func fire(_ request: TaskRunRequest, resolvedPrompt: String?) {
        coordinator.runTaskCard(
            request.card,
            resolvedPrompt: resolvedPrompt,
            workspaceID: request.workspaceID,
            inCurrentPane: request.inCurrentPane,
            paneID: request.paneID)
        onClose()
    }

    // MARK: 变量填值

    private func fillOverlay(_ request: TaskRunRequest) -> some View {
        let variables = request.card.variableNames
        let ready = variables.allSatisfy { !(fillValues[$0] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return VStack(spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("填入变量"))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(AppStyle.textPrimary)
                    Text(request.card.displayTitle)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(AppStyle.textTertiary)
                        .lineLimit(1)
                }
                Spacer()
                IconOnlyButton(systemName: "xmark", help: L("返回"), size: 26, symbolSize: 11, weight: .bold) { fillRequest = nil }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    AgentToolsFormGroup {
                        ForEach(Array(variables.enumerated()), id: \.element) { index, name in
                            if index > 0 { AgentToolsFormDivider() }
                            HStack(spacing: 10) {
                                Text(name)
                                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(AppStyle.accent)
                                    .frame(minWidth: 80, alignment: .leading)
                                TextField(L("值"), text: Binding(
                                    get: { fillValues[name] ?? "" },
                                    set: { fillValues[name] = $0 }))
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 12))
                                    .foregroundStyle(AppStyle.textPrimary)
                            }
                            .padding(.horizontal, 12)
                            .frame(height: 38)
                        }
                    }
                    Text(TaskCardTemplate.substitute(request.card.prompt, values: fillValues))
                        .font(.system(size: 10.5, weight: .regular, design: .monospaced))
                        .foregroundStyle(AppStyle.textTertiary)
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(16)
            }
            .scrollIndicators(.never)

            VStack(spacing: 0) {
                Rectangle().fill(AppStyle.separator.opacity(0.4)).frame(height: 1)
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    ToolActionButton(title: L("取消"), height: 28, fontSize: 11, horizontalPadding: 12) { fillRequest = nil }
                    ToolActionButton(title: L("运行"), systemImage: "play.fill", role: .primary, height: 28, fontSize: 11, horizontalPadding: 14) {
                        let resolved = TaskCardTemplate.substitute(request.card.prompt, values: fillValues)
                        fillRequest = nil
                        fire(request, resolvedPrompt: resolved)
                    }
                    .disabled(!ready)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        .background(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
            .fill(AppStyle.theme.isDark ? Color(nsColor: AppStyle.cardBackground) : Color(red: 0.965, green: 0.967, blue: 0.972)))
    }

    // MARK: 小工具

    private func metaLine(_ card: TaskCard) -> String {
        guard let lastRunAt = card.lastRunAt else { return L("未运行") }
        return L("%ld× · %@", card.runCount, Self.relativeFormatter.localizedString(for: lastRunAt, relativeTo: Date()))
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()
}

private struct TaskCardPanelSurface: ViewModifier {
    @ObservedObject private var configStore = ConfigStore.shared
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background(shape.fill(surfaceColor))
            .overlay(shape.strokeBorder(borderColor, lineWidth: 1))
            .clipShape(shape)
    }

    @MainActor
    private var surfaceColor: Color {
        AppStyle.theme.isDark
            ? Color(nsColor: AppStyle.cardBackground)
            : Color(red: 0.965, green: 0.967, blue: 0.972)
    }

    @MainActor
    private var borderColor: Color {
        AppStyle.theme.isDark ? Color.white.opacity(0.10) : Color.black.opacity(0.08)
    }
}

private extension View {
    func taskCardPanelSurface(cornerRadius: CGFloat) -> some View {
        modifier(TaskCardPanelSurface(cornerRadius: cornerRadius))
    }
}

@MainActor
final class TaskCardsPanelController: NSObject, NSWindowDelegate {
    private var panel: KeyPanel?
    private var escMonitor: Any?

    func toggle(coordinator: AppCoordinator, over parent: NSWindow?) {
        if let panel, panel.isVisible {
            hide()
            return
        }
        show(coordinator: coordinator, over: parent)
    }

    func show(coordinator: AppCoordinator, over parent: NSWindow?) {
        let view = TaskCardsPanelView(
            coordinator: coordinator,
            store: coordinator.taskCardStore,
            onClose: { [weak self] in self?.hide() })
        let host = NSHostingView(rootView: view)
        let size = NSSize(width: 600, height: 560)
        let p = panel ?? makePanel(size: size)
        p.contentView = host
        p.setContentSize(size)

        let mousePoint = NSEvent.mouseLocation
        let mouseScreen = NSScreen.screens.first { NSMouseInRect(mousePoint, $0.frame, false) }
        let targetScreen = mouseScreen ?? parent?.screen ?? NSScreen.main
        let screenFrame = targetScreen?.visibleFrame ?? parent?.frame ?? .zero
        let parentFrame: NSRect = if parent?.screen === targetScreen {
            parent?.frame ?? screenFrame
        } else {
            screenFrame
        }
        let preferredX = parentFrame.maxX - size.width - 42
        let preferredY = parentFrame.maxY - size.height - 70
        let x = min(max(preferredX, screenFrame.minX + 20), screenFrame.maxX - size.width - 20)
        let y = min(max(preferredY, screenFrame.minY + 20), screenFrame.maxY - size.height - 20)
        p.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)

        p.alphaValue = 0
        p.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.14
            p.animator().alphaValue = 1
        }
        if escMonitor == nil {
            escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard event.keyCode == 53, event.window === self?.panel else { return event }
                self?.hide()
                return nil
            }
        }
    }

    func hide() {
        if let escMonitor {
            NSEvent.removeMonitor(escMonitor)
            self.escMonitor = nil
        }
        guard let panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.1
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak panel] in panel?.orderOut(nil) })
    }

    func automationSnapshot() -> JSONValue {
        guard let panel else {
            return .object(["visible": .bool(false)])
        }
        return .object([
            "visible": .bool(panel.isVisible),
            "title": .string(panel.title),
            "frame": .object([
                "x": .double(panel.frame.origin.x),
                "y": .double(panel.frame.origin.y),
                "width": .double(panel.frame.width),
                "height": .double(panel.frame.height),
            ]),
        ])
    }

    private func makePanel(size: NSSize) -> KeyPanel {
        let panel = KeyPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: true)
        panel.title = "Task Cards"
        panel.identifier = NSUserInterfaceItemIdentifier("TaskCardsPanel")
        panel.setAccessibilityTitle("Task Cards")
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        // 背景拖动整体关掉：移窗只走标题栏的 WindowDragHandle，拖牌只走系统拖拽，互不干扰。
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.delegate = self
        self.panel = panel
        return panel
    }
}
