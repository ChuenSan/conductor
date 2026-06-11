import AppKit
import ConductorCore
import SwiftUI

/// 广播目标：一个正在跑 agent 的 pane。
struct BroadcastTarget: Identifiable {
    let pane: PaneID
    let agentID: String
    let title: String

    var id: String { pane.value }
}

/// 最近广播过的指令（去重置顶，最多 10 条），UserDefaults 持久化。
enum BroadcastHistory {
    private static let key = "conductor.broadcastHistory"
    private static let limit = 10

    static func load() -> [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    static func record(_ text: String) {
        var items = load()
        items.removeAll { $0 == text }
        items.insert(text, at: 0)
        UserDefaults.standard.set(Array(items.prefix(limit)), forKey: key)
    }
}

/// 广播输入面板：一条指令同时发给当前工作区所有（勾选的）agent pane。
/// 多 agent 并行开工时，「都试试这个思路」一句话就能下发。
struct BroadcastPanelView: View {
    let targets: [BroadcastTarget]
    /// 观察 coordinator 拿 thinkingPanes：面板开着时目标 chip 的思考转圈实时变。
    @ObservedObject var coordinator: AppCoordinator
    let onSend: (_ panes: [PaneID], _ text: String, _ execute: Bool) -> Void
    let onClose: () -> Void

    @State private var text = ""
    @State private var enabled: Set<String>
    /// 回车后是否自动提交；关掉则只把文字摆进各 agent 的输入框（可再人工补充后回车）。
    @State private var executeAfterSend = true
    @State private var history = BroadcastHistory.load()
    /// ↑ 键在历史里回翻的位置（-1 = 没在翻）。
    @State private var historyCursor = -1
    @FocusState private var fieldFocused: Bool

    init(targets: [BroadcastTarget],
         coordinator: AppCoordinator,
         onSend: @escaping (_ panes: [PaneID], _ text: String, _ execute: Bool) -> Void,
         onClose: @escaping () -> Void) {
        self.targets = targets
        _coordinator = ObservedObject(wrappedValue: coordinator)
        self.onSend = onSend
        self.onClose = onClose
        _enabled = State(initialValue: Set(targets.map(\.id)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppStyle.accent)
                Text(L("广播到 Agent"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppStyle.textPrimary)
                Spacer()
                executeToggle
                Text(executeAfterSend ? L("回车发送 · Esc 关闭") : L("回车仅填入 · Esc 关闭"))
                    .font(.system(size: 10.5))
                    .foregroundStyle(AppStyle.textTertiary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            TextField(L("输入要发给所有 Agent 的指令…"), text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 13.5))
                .foregroundStyle(AppStyle.textPrimary)
                .lineLimit(1...5)
                .focused($fieldFocused)
                .onSubmit { send() }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(AppStyle.activeFill))
                .padding(.horizontal, 16)

            // 目标勾选：默认全选，点击排除个别 pane
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(targets) { target in
                        targetChip(target)
                    }
                }
                .padding(.horizontal, 16)
            }
            .scrollIndicators(.never)
            .padding(.top, 10)
            .padding(.bottom, history.isEmpty ? 14 : 10)

            if !history.isEmpty {
                Rectangle().fill(AppStyle.separator).frame(height: 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("最近广播（↑ 回翻）"))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(AppStyle.textTertiary)
                        .padding(.horizontal, 6)
                        .padding(.bottom, 2)
                    ForEach(Array(history.prefix(4).enumerated()), id: \.offset) { _, item in
                        historyRow(item)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
            }
        }
        .frame(width: 480)
        .conductorFloatingPanel(cornerRadius: Radius.xl)
        .padding(Space.xl)
        .onKeyPress(.escape) { onClose(); return .handled }
        .onKeyPress(.upArrow) { recallHistory(1); return .handled }
        .onKeyPress(.downArrow) { recallHistory(-1); return .handled }
        .onAppear { fieldFocused = true }
    }

    /// 「发送后执行」开关：关掉后广播只把文字摆进输入框，各 agent 由人工确认提交。
    private var executeToggle: some View {
        Button {
            executeAfterSend.toggle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: executeAfterSend ? "bolt.fill" : "text.cursor")
                    .font(.system(size: 9, weight: .semibold))
                Text(L("发送后执行"))
                    .font(.system(size: 10.5, weight: .medium))
            }
            .foregroundStyle(executeAfterSend ? AppStyle.accent : AppStyle.textTertiary)
            .padding(.horizontal, 8)
            .frame(height: 21)
            .background(
                Capsule().fill(executeAfterSend ? AppStyle.accent.opacity(0.13) : AppStyle.hoverFill))
            .overlay(
                Capsule().strokeBorder(
                    executeAfterSend ? AppStyle.accent.opacity(0.4) : AppStyle.textPrimary.opacity(0.1),
                    lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help(L("关闭后只把文字填入各 Agent 输入框，不自动回车"))
    }

    private func historyRow(_ item: String) -> some View {
        HistoryRow(item: item) {
            text = item
            fieldFocused = true
        } onSend: {
            sendDirect(item)
        } onSaveSnippet: {
            // 常用的广播语收藏成片段，下次去片段库或 ⌘K 里直接发
            SnippetStore.shared.add(Snippet(name: snippetName(for: item), command: item))
        }
    }

    /// 从命令文本生成片段名：取首行，过长截断。
    private func snippetName(for command: String) -> String {
        let firstLine = command.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? command
        return firstLine.count > 32 ? String(firstLine.prefix(32)) + "…" : firstLine
    }

    /// 历史条目上的「直接发送」：不经输入框，按当前勾选目标立刻广播。
    private func sendDirect(_ item: String) {
        let selected = targets.filter { enabled.contains($0.id) }.map(\.pane)
        guard !selected.isEmpty else { return }
        BroadcastHistory.record(item)
        onClose()
        onSend(selected, item, executeAfterSend)
    }

    /// ↑/↓ 在历史里回翻：↑ 往更早翻，↓ 往回翻到空。
    private func recallHistory(_ direction: Int) {
        guard !history.isEmpty else { return }
        let next = historyCursor + direction
        if next < 0 {
            historyCursor = -1
            text = ""
            return
        }
        guard next < history.count else { return }
        historyCursor = next
        text = history[next]
    }

    private func targetChip(_ target: BroadcastTarget) -> some View {
        let on = enabled.contains(target.id)
        let thinking = coordinator.thinkingPanes.contains(target.pane)
        return Button {
            if on { enabled.remove(target.id) } else { enabled.insert(target.id) }
        } label: {
            HStack(spacing: 5) {
                if let logo = CLIToolLogo.image(named: target.agentID) {
                    Image(nsImage: logo).resizable().interpolation(.high).scaledToFit()
                        .frame(width: 12, height: 12)
                        .opacity(on ? 1 : 0.4)
                }
                Text(target.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(on ? AppStyle.textPrimary : AppStyle.textTertiary)
                    .lineLimit(1)
                if thinking {
                    ThinkingIndicator(size: 9)
                }
                if on {
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(AppStyle.accent)
                }
            }
            .padding(.horizontal, 9)
            .frame(height: 24)
            .background(
                Capsule().fill(on ? AppStyle.accent.opacity(0.14) : AppStyle.hoverFill))
            .overlay(
                Capsule().strokeBorder(on ? AppStyle.accent.opacity(0.45) : Color.clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help(on ? L("点击排除该 Agent") : L("点击加入广播"))
    }

    private func send() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let selected = targets.filter { enabled.contains($0.id) }.map(\.pane)
        guard !trimmed.isEmpty, !selected.isEmpty else { return }
        BroadcastHistory.record(trimmed)
        onClose()
        onSend(selected, trimmed, executeAfterSend)
    }
}

/// 历史行：点击填回输入框；hover 浮现「直接发送」「收藏为片段」按钮。
private struct HistoryRow: View {
    let item: String
    let onFill: () -> Void
    let onSend: () -> Void
    let onSaveSnippet: () -> Void

    @State private var hovered = false
    /// 已点过收藏：星标变实心并停手，避免重复收藏同一条。
    @State private var saved = false

    var body: some View {
        HStack(spacing: 7) {
            Button(action: onFill) {
                HStack(spacing: 7) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(AppStyle.textTertiary)
                    Text(item)
                        .font(.system(size: 11.5))
                        .foregroundStyle(AppStyle.textSecondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(L("点击填入输入框"))

            if hovered || saved {
                Button {
                    guard !saved else { return }
                    saved = true
                    onSaveSnippet()
                } label: {
                    Image(systemName: saved ? "star.fill" : "star")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(saved ? Color.yellow.opacity(0.85) : AppStyle.textSecondary)
                        .frame(width: 22, height: 20)
                        .background(RoundedRectangle(cornerRadius: 5).fill(AppStyle.hoverFill))
                }
                .buttonStyle(.plain)
                .help(saved ? L("已收藏为片段") : L("收藏为命令片段"))
                .transition(.opacity)
            }
            if hovered {
                Button(action: onSend) {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(AppStyle.accent)
                        .frame(width: 22, height: 20)
                        .background(RoundedRectangle(cornerRadius: 5).fill(AppStyle.accent.opacity(0.13)))
                }
                .buttonStyle(.plain)
                .help(L("按当前勾选目标直接发送"))
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 6).fill(hovered ? AppStyle.hoverFill : .clear))
        .onHover { inside in
            withAnimation(.easeOut(duration: 0.12)) { hovered = inside }
        }
    }
}

/// 广播面板窗口：复用命令面板的浮动 KeyPanel 形态。
@MainActor
final class BroadcastPanelController: NSObject, NSWindowDelegate {
    private var panel: KeyPanel?

    func toggle(targets: [BroadcastTarget],
                coordinator: AppCoordinator,
                over parent: NSWindow?,
                onSend: @escaping (_ panes: [PaneID], _ text: String, _ execute: Bool) -> Void) {
        if let panel, panel.isVisible { hide(); return }
        show(targets: targets, coordinator: coordinator, over: parent, onSend: onSend)
    }

    func show(targets: [BroadcastTarget],
              coordinator: AppCoordinator,
              over parent: NSWindow?,
              onSend: @escaping (_ panes: [PaneID], _ text: String, _ execute: Bool) -> Void) {
        let view = BroadcastPanelView(
            targets: targets,
            coordinator: coordinator,
            onSend: onSend,
            onClose: { [weak self] in self?.hide() })
        let host = NSHostingView(rootView: view)
        // 高度随内容自适应（有无历史区高度不同），宽度由视图自身固定
        let size = host.fittingSize
        let p = panel ?? makePanel(size: size)
        p.contentView = host

        let frame = parent?.frame ?? NSScreen.main?.visibleFrame ?? .zero
        let x = frame.midX - size.width / 2
        let y = frame.maxY - size.height - max(80, frame.height * 0.16)
        p.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)

        p.alphaValue = 0
        p.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.14
            p.animator().alphaValue = 1
        }
    }

    func hide() {
        guard let panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.1
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak panel] in panel?.orderOut(nil) })
    }

    private func makePanel(size: NSSize) -> KeyPanel {
        let p = KeyPanel(contentRect: NSRect(origin: .zero, size: size),
                         styleMask: [.borderless, .titled, .fullSizeContentView],
                         backing: .buffered, defer: true)
        p.titleVisibility = .hidden
        p.titlebarAppearsTransparent = true
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.level = .floating
        p.isMovableByWindowBackground = false
        p.hidesOnDeactivate = true
        p.delegate = self
        panel = p
        return p
    }

    func windowDidResignKey(_ notification: Notification) { hide() }
}
