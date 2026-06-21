import AppKit
import ConductorCore
import SwiftUI

/// ② 命令记录面板（pane 右键「命令记录…」）：列出这个终端最近每条命令的
/// 退出码 / 耗时 / 时刻 / 目录；失败的可一键「甩给 agent」（把最近输出交给 agent 诊断）。
/// 数据来自 OSC 133 命令完成信号——只含硬事实，命令原文 ghostty 没暴露给嵌入方。
struct CommandLogPanelView: View {
    let pane: PaneID
    let paneTitle: String
    @ObservedObject var coordinator: AppCoordinator
    let onClose: () -> Void

    private var records: [PaneCommandRecord] { coordinator.paneCommands(pane).reversed() }
    private var hasAgentTarget: Bool { coordinator.hasAgentForDiagnosis(near: pane) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "list.bullet.rectangle.portrait")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppStyle.accent)
                Text(L("命令记录 · %@", paneTitle))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppStyle.textPrimary)
                    .lineLimit(1)
                Spacer()
                if let last = records.first, last.failed {
                    Text(L("上条失败"))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(AppStyle.errorRed)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Capsule().fill(AppStyle.errorRed.opacity(0.14)))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            ToolSoftGroup {
                ScrollView {
                    VStack(spacing: 2) {
                        if records.isEmpty {
                            ToolEmptyState(
                                icon: "terminal",
                                title: L("还没有命令记录"),
                                detail: L("在这个终端跑一条命令，完成后就会出现在这里。"),
                                compact: true)
                                .padding(.top, 22)
                        } else {
                            ForEach(records) { record in
                                CommandLogRow(record: record)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.never)
                .frame(height: 232)
            }
            .padding(.horizontal, 16)

            HStack(spacing: 8) {
                let total = coordinator.paneCommands(pane).count
                let failed = coordinator.paneCommands(pane).filter(\.failed).count
                Text(failed > 0 ? L("%ld 条 · %ld 失败", total, failed) : L("%ld 条", total))
                    .font(.system(size: 10.5))
                    .monospacedDigit()
                    .foregroundStyle(failed > 0 ? AppStyle.errorRed : AppStyle.textTertiary)
                Spacer()
                if total > 0 {
                    ToolActionButton(
                        title: L("清空"),
                        role: .secondary,
                        height: 24, fontSize: 10.5, horizontalPadding: 9) {
                            coordinator.clearPaneCommandLog(pane)
                        }
                    ToolActionButton(
                        title: L("复制最近输出"),
                        systemImage: "doc.on.doc",
                        role: .secondary,
                        height: 24, fontSize: 10.5, horizontalPadding: 9,
                        help: L("把这个终端当前可见的输出复制到剪贴板")) {
                            coordinator.copyRecentOutput(from: pane)
                        }
                    ToolActionButton(
                        title: hasAgentTarget ? L("甩给 agent") : L("复制给 agent"),
                        systemImage: "sparkles",
                        role: .tinted(AppStyle.accent),
                        height: 24, fontSize: 10.5, horizontalPadding: 9,
                        help: hasAgentTarget
                            ? L("把最近输出交给 agent 帮你诊断")
                            : L("没有正在跑的 agent，先复制到剪贴板")) {
                            coordinator.askAgentAboutLastCommand(from: pane)
                            onClose()
                        }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
        .frame(width: 460)
        .conductorFloatingPanel(cornerRadius: Radius.xl)
        .padding(Space.xl)
    }
}

private struct CommandLogRow: View {
    let record: PaneCommandRecord
    @State private var hovering = false

    private var glyph: String { record.exitCode == nil ? "minus.circle" : (record.failed ? "xmark.circle.fill" : "checkmark.circle.fill") }
    private var tint: Color { record.exitCode == nil ? AppStyle.textTertiary : (record.failed ? AppStyle.errorRed : AppStyle.doneGreen) }

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: glyph)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(record.exitCode.map { $0 == 0 ? L("成功") : L("退出码 %ld", $0) } ?? L("已完成"))
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(record.failed ? AppStyle.errorRed : AppStyle.textPrimary)
                    Text(record.durationText)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(AppStyle.textTertiary)
                }
                if let cwd = record.cwd, !cwd.isEmpty {
                    Text(PathDisplay.lastComponent(cwd))
                        .font(.system(size: 9.5))
                        .foregroundStyle(AppStyle.textTertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Text(Self.relativeTime(from: record.finishedAt, to: Date()))
                .font(.system(size: 9.5))
                .monospacedDigit()
                .foregroundStyle(AppStyle.textTertiary)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(hovering ? AppStyle.hoverFill : Color.clear))
        .onHover { hovering = $0 }
    }

    /// "刚刚" / "23s" / "4m" / "1h"
    static func relativeTime(from date: Date, to now: Date) -> String {
        let s = Int(max(0, now.timeIntervalSince(date)))
        if s < 3 { return L("刚刚") }
        if s < 60 { return "\(s)s" }
        if s < 3600 { return "\(s / 60)m" }
        return "\(s / 3600)h"
    }
}

/// 命令记录面板窗口：复用浮动 KeyPanel 形态；Esc / 失焦关闭。
@MainActor
final class CommandLogPanelController: NSObject, NSWindowDelegate {
    private var panel: KeyPanel?
    private var escMonitor: Any?

    func toggle(pane: PaneID, title: String, coordinator: AppCoordinator, over parent: NSWindow?) {
        if let panel, panel.isVisible { hide(); return }
        show(pane: pane, title: title, coordinator: coordinator, over: parent)
    }

    func show(pane: PaneID, title: String, coordinator: AppCoordinator, over parent: NSWindow?) {
        let view = CommandLogPanelView(pane: pane, paneTitle: title, coordinator: coordinator,
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
