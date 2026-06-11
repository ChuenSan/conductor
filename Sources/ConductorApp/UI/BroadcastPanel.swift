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
    let onSend: ([PaneID], String) -> Void
    let onClose: () -> Void

    @State private var text = ""
    @State private var enabled: Set<String>
    @State private var history = BroadcastHistory.load()
    /// ↑ 键在历史里回翻的位置（-1 = 没在翻）。
    @State private var historyCursor = -1
    @FocusState private var fieldFocused: Bool

    init(targets: [BroadcastTarget],
         onSend: @escaping ([PaneID], String) -> Void,
         onClose: @escaping () -> Void) {
        self.targets = targets
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
                Text(L("回车发送 · Esc 关闭"))
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

    private func historyRow(_ item: String) -> some View {
        Button {
            text = item
            fieldFocused = true
        } label: {
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
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(item)
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
        onSend(selected, trimmed)
    }
}

/// 广播面板窗口：复用命令面板的浮动 KeyPanel 形态。
@MainActor
final class BroadcastPanelController: NSObject, NSWindowDelegate {
    private var panel: KeyPanel?

    func toggle(targets: [BroadcastTarget],
                over parent: NSWindow?,
                onSend: @escaping ([PaneID], String) -> Void) {
        if let panel, panel.isVisible { hide(); return }
        show(targets: targets, over: parent, onSend: onSend)
    }

    func show(targets: [BroadcastTarget],
              over parent: NSWindow?,
              onSend: @escaping ([PaneID], String) -> Void) {
        let view = BroadcastPanelView(
            targets: targets,
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
