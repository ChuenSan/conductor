import AppKit
import QuartzCore
@preconcurrency import GhosttyKit

/// 承载一个 libghostty surface 的 NSView：CAMetalLayer 背衬。
/// 自身不直接调 libghostty——把生命周期/几何/输入都委托给 `owner`（GhosttySurface）。
@MainActor
final class TerminalHostView: NSView {
    weak var owner: GhosttySurface?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        clipsToBounds = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        configureLayer(layer)
        // 右键菜单由 PaneContainerView 统一构建（复制/粘贴/分屏/路径/清屏…），这里不再各自维护。
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not implemented") }

    override var acceptsFirstResponder: Bool { true }

    override func makeBackingLayer() -> CALayer {
        let layer = CAMetalLayer()
        layer.framebufferOnly = false
        layer.isOpaque = true
        layer.backgroundColor = AppStyle.cardBackground.cgColor
        layer.masksToBounds = true
        layer.cornerRadius = 12              // 与卡片圆角一致
        layer.cornerCurve = .continuous
        configureLayer(layer)
        return layer
    }

    /// 禁用图层隐式动画：resize 时 Metal 层立即呈现，不被动画过渡。
    private func configureLayer(_ layer: CALayer?) {
        layer?.actions = [
            "bounds": NSNull(), "position": NSNull(), "frame": NSNull(),
            "contentsScale": NSNull(), "backgroundColor": NSNull(),
        ]
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        owner?.attachIfPossible()
        owner?.syncGeometry(force: true)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        owner?.syncGeometry()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        owner?.syncGeometry(force: true)
    }

    // MARK: - First responder

    override func becomeFirstResponder() -> Bool {
        owner?.setFocused(true)
        return true
    }

    override func resignFirstResponder() -> Bool {
        owner?.setFocused(false)
        return true
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        owner?.forwardKey(event, action: event.isARepeat ? GHOSTTY_ACTION_REPEAT : GHOSTTY_ACTION_PRESS)
    }

    override func keyUp(with event: NSEvent) {
        owner?.forwardKey(event, action: GHOSTTY_ACTION_RELEASE)
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        owner?.requestFocus()
        owner?.setFocused(true)
        owner?.sendMouseButton(GHOSTTY_MOUSE_LEFT, state: GHOSTTY_MOUSE_PRESS, event: event)
    }

    override func mouseUp(with event: NSEvent) {
        owner?.sendMouseButton(GHOSTTY_MOUSE_LEFT, state: GHOSTTY_MOUSE_RELEASE, event: event)
    }

    override func mouseDragged(with event: NSEvent) {
        owner?.updateMouse(event)
    }

    override func scrollWheel(with event: NSEvent) {
        owner?.scroll(event)
    }
}
