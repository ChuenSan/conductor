import AppKit
import ConductorCore
import SwiftUI

/// 任务队列面板（⌘⇧⏎ / pane 右键）：给一个 pane 排队多条指令，
/// agent 每次 Stop 后自动发出下一条——流水线 / 夜间挂机。
struct QueuePanelView: View {
    let pane: PaneID
    let paneTitle: String
    @ObservedObject var coordinator: AppCoordinator
    let onClose: () -> Void

    @State private var draft = ""
    @FocusState private var fieldFocused: Bool

    private var queue: [String] { coordinator.paneQueues[pane] ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "text.badge.plus")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppStyle.accent)
                Text(L("任务队列 · %@", paneTitle))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppStyle.textPrimary)
                    .lineLimit(1)
                Spacer()
                Text(L("Esc 关闭"))
                    .font(.system(size: 10.5))
                    .foregroundStyle(AppStyle.textTertiary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            TextField(L("排给这个终端的下一条指令…"), text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(AppStyle.textPrimary)
                .lineLimit(1...4)
                .focused($fieldFocused)
                .onSubmit { append() }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(AppStyle.activeFill))
                .padding(.horizontal, 16)

            Text(L("回车加入队列；当前任务完成（Stop）后自动逐条发出"))
                .font(.system(size: 10))
                .foregroundStyle(AppStyle.textTertiary)
                .padding(.horizontal, 18)
                .padding(.top, 6)
                .padding(.bottom, 8)

            Rectangle().fill(AppStyle.separator).frame(height: 1)
            ScrollView {
                VStack(spacing: 3) {
                    if queue.isEmpty {
                        Text(L("队列为空。先排几条，让 Agent 一条接一条干。"))
                            .font(.system(size: 11))
                            .foregroundStyle(AppStyle.textTertiary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 56)
                    } else {
                        ForEach(Array(queue.enumerated()), id: \.offset) { index, item in
                            QueueRow(index: index, text: item) {
                                coordinator.removeQueuedPrompt(at: index, for: pane)
                            }
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
            .scrollIndicators(.never)
            .frame(height: 176)

            Rectangle().fill(AppStyle.separator).frame(height: 1)
            HStack {
                Text(L("%ld 条排队中", queue.count))
                    .font(.system(size: 10.5))
                    .monospacedDigit()
                    .foregroundStyle(AppStyle.textTertiary)
                Spacer()
                if !queue.isEmpty {
                    Button(L("清空")) { coordinator.clearQueue(for: pane) }
                        .buttonStyle(.plain)
                        .font(.system(size: 10.5))
                        .foregroundStyle(AppStyle.textTertiary)
                    Button {
                        coordinator.sendNextQueuedNow(for: pane)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 9, weight: .semibold))
                            Text(L("立即发队首"))
                                .font(.system(size: 10.5, weight: .medium))
                        }
                        .foregroundStyle(AppStyle.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3.5)
                        .background(Capsule().fill(AppStyle.accent.opacity(0.13)))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help(L("不等 Stop，现在就发出第一条"))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
        }
        .frame(width: 460)
        .conductorFloatingPanel(cornerRadius: Radius.xl)
        .padding(Space.xl)
        .onAppear { fieldFocused = true }
    }

    private func append() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        coordinator.enqueuePrompt(text, for: pane)
        draft = ""
        fieldFocused = true
    }
}

private struct QueueRow: View {
    let index: Int
    let text: String
    let onDelete: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            Text("\(index + 1)")
                .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(AppStyle.textTertiary)
                .frame(width: 16, height: 16)
                .background(Circle().fill(AppStyle.hoverFill))
            Text(text)
                .font(.system(size: 11.5))
                .foregroundStyle(AppStyle.textSecondary)
                .lineLimit(2)
            Spacer(minLength: 0)
            if hovering {
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(AppStyle.textTertiary)
                }
                .buttonStyle(.plain)
                .help(L("移出队列"))
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(hovering ? AppStyle.hoverFill : Color.clear))
        .onHover { hovering = $0 }
    }
}

/// 队列面板窗口：复用浮动 KeyPanel 形态；Esc / 失焦 / 再按一次 ⌘⇧⏎ 关闭。
@MainActor
final class QueuePanelController: NSObject, NSWindowDelegate {
    private var panel: KeyPanel?
    private var escMonitor: Any?

    func toggle(pane: PaneID, title: String, coordinator: AppCoordinator, over parent: NSWindow?) {
        if let panel, panel.isVisible { hide(); return }
        show(pane: pane, title: title, coordinator: coordinator, over: parent)
    }

    func show(pane: PaneID, title: String, coordinator: AppCoordinator, over parent: NSWindow?) {
        let view = QueuePanelView(pane: pane, paneTitle: title, coordinator: coordinator,
                                  onClose: { [weak self] in self?.hide() })
        let host = NSHostingView(rootView: view)
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
