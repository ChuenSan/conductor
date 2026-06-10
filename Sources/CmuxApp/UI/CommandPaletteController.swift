import AppKit
import SwiftUI

/// 命令面板窗口：可成为 key 的无边框浮动面板（接管键盘）；居中靠上；失焦/Esc 关闭。
@MainActor
final class CommandPaletteController: NSObject, NSWindowDelegate {
    private var panel: KeyPanel?
    private weak var coordinator: AppCoordinator?

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        super.init()
    }

    func toggle(items: [PaletteItem], over parent: NSWindow?) {
        if let panel, panel.isVisible { hide(); return }
        show(items: items, over: parent)
    }

    func show(items: [PaletteItem], over parent: NSWindow?) {
        // 内容 540×420 + 四周 24pt 透明边给柔阴影扩散（见 CommandPaletteView 的 padding）。
        let size = NSSize(width: 540 + 48, height: 420 + 48)
        let p = panel ?? makePanel(size: size)
        let view = CommandPaletteView(items: items, onClose: { [weak self] in self?.hide() })
        p.contentView = NSHostingView(rootView: view)

        // 居中靠上（相对父窗口，否则主屏）
        let frame = parent?.frame ?? NSScreen.main?.visibleFrame ?? .zero
        let x = frame.midX - size.width / 2
        let y = frame.maxY - size.height - max(80, frame.height * 0.14)
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
        p.hasShadow = false   // 用 SwiftUI 自绘的双层柔阴影，关掉系统硬阴影
        p.level = .floating
        p.isMovableByWindowBackground = false
        p.hidesOnDeactivate = true
        p.delegate = self
        panel = p
        return p
    }

    func windowDidResignKey(_ notification: Notification) { hide() }
}

/// 无边框但能成为 key 的面板（接管键盘输入）。
final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
