import AppKit
import SwiftUI

/// 占位符填值面板：片段命令里有 `{{变量}}` 时弹出，逐项填完回车发送。
/// 例：`git commit -m "{{message}}"` → 弹一个 message 输入框。
struct SnippetFillPanelView: View {
    let snippet: Snippet
    let names: [String]
    let onConfirm: (_ filledCommand: String) -> Void
    let onClose: () -> Void

    @State private var values: [String: String] = [:]
    @FocusState private var focusedName: String?

    /// 占位符记忆：按变量名全局记住上次填的值（`{{branch}}` 这类常量型变量重复用最频繁）。
    private static let memoryKey = "snippets.placeholderMemory"

    /// 实时预览：当前已填的值代入后的完整命令。
    private var preview: String {
        Snippet.fill(snippet.command, values: values.filter { !$0.value.isEmpty })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "curlybraces")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppStyle.accent)
                Text(snippet.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppStyle.textPrimary)
                    .lineLimit(1)
                Spacer()
                Text(L("回车发送 · Esc 关闭"))
                    .font(.system(size: 10.5))
                    .foregroundStyle(AppStyle.textTertiary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            VStack(spacing: 8) {
                ForEach(names, id: \.self) { name in
                    HStack(spacing: 8) {
                        Text(name)
                            .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(AppStyle.textSecondary)
                            .frame(width: 110, alignment: .trailing)
                            .lineLimit(1)
                        TextField("", text: binding(for: name))
                            .textFieldStyle(.plain)
                            .font(.system(size: 12.5, design: .monospaced))
                            .foregroundStyle(AppStyle.textPrimary)
                            .focused($focusedName, equals: name)
                            .onSubmit(advanceOrSend)
                            .padding(.horizontal, 9)
                            .frame(height: 28)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(AppStyle.activeFill))
                    }
                }
            }
            .padding(.horizontal, 16)

            // 代入预览：填之前先看到最终要发出去的命令长什么样
            Text(preview)
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(AppStyle.textTertiary)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 14)
        }
        .frame(width: 440)
        .conductorFloatingPanel(cornerRadius: Radius.xl)
        .padding(Space.xl)
        .onKeyPress(.escape) { onClose(); return .handled }
        .onAppear {
            // 预填上次的值：直接回车即可重发；想改的字段已聚焦可改
            let memory = Self.loadMemory()
            for name in names where values[name] == nil {
                if let remembered = memory[name] { values[name] = remembered }
            }
            // 聚焦第一个还空着的字段；全有记忆值就停在第一个（回车直发）
            focusedName = names.first(where: { (values[$0] ?? "").isEmpty }) ?? names.first
        }
    }

    private func binding(for name: String) -> Binding<String> {
        Binding(get: { values[name] ?? "" }, set: { values[name] = $0 })
    }

    /// 回车：还有空着的字段就跳过去，全填完才发送。
    private func advanceOrSend() {
        if let next = names.first(where: { (values[$0] ?? "").isEmpty }) {
            focusedName = next
            return
        }
        saveMemory()
        onClose()
        onConfirm(Snippet.fill(snippet.command, values: values))
    }

    private static func loadMemory() -> [String: String] {
        (UserDefaults.standard.dictionary(forKey: memoryKey) ?? [:])
            .compactMapValues { $0 as? String }
    }

    /// 发送成功才记：半途 Esc 掉的不污染记忆。
    private func saveMemory() {
        var memory = Self.loadMemory()
        for (name, value) in values where !value.isEmpty { memory[name] = value }
        UserDefaults.standard.set(memory, forKey: Self.memoryKey)
    }
}

/// 占位符面板窗口：复用命令面板的浮动 KeyPanel 形态。
@MainActor
final class SnippetFillPanelController: NSObject, NSWindowDelegate {
    private var panel: KeyPanel?

    func show(snippet: Snippet,
              over parent: NSWindow?,
              onConfirm: @escaping (_ filledCommand: String) -> Void) {
        let view = SnippetFillPanelView(
            snippet: snippet,
            names: snippet.placeholders,
            onConfirm: onConfirm,
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
