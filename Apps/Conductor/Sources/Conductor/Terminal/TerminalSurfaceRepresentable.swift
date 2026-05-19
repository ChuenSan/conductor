import AppKit
import QuartzCore
import SwiftUI

struct TerminalSurfaceRepresentable: NSViewRepresentable {
    let surface: TerminalSurface
    let theme: TerminalTheme
    let isFocused: Bool
    var suspendsGeometrySync = false

    func makeNSView(context: Context) -> TerminalSurfaceContainerView {
        let container = TerminalSurfaceContainerView()
        container.setSurface(surface, theme: theme, focused: isFocused, suspendsGeometrySync: suspendsGeometrySync)
        return container
    }

    func updateNSView(_ nsView: TerminalSurfaceContainerView, context: Context) {
        nsView.setSurface(surface, theme: theme, focused: isFocused, suspendsGeometrySync: suspendsGeometrySync)
    }
}

@MainActor
final class TerminalSurfaceContainerView: NSView {
    private var currentSurface: TerminalSurface?
    private var currentTheme: TerminalTheme?
    private var currentFocused = false
    private var currentSuspendsGeometrySync = false
    private var wantsTerminalFocus = false
    private var pendingGeometrySync = false
    private var pendingGeometryForce = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        clipsToBounds = true
        layer?.masksToBounds = true
        configureLayerForTerminalHosting(layer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setSurface(_ surface: TerminalSurface, theme: TerminalTheme, focused: Bool, suspendsGeometrySync: Bool) {
        let surfaceChanged = currentSurface !== surface
        let focusChanged = currentFocused != focused
        let geometrySyncResumed = currentSuspendsGeometrySync && !suspendsGeometrySync
        wantsTerminalFocus = focused
        currentFocused = focused
        currentSuspendsGeometrySync = suspendsGeometrySync
        if surfaceChanged {
            let signpost = ConductorSignpost.begin("surface-host-swap")
            defer { ConductorSignpost.end("surface-host-swap", signpost) }
            currentSurface?.setFocused(false)
            currentSurface?.hostView.removeFromSuperview()
            currentSurface = surface
            currentTheme = nil
            installHostView(surface.hostView)
            ConductorLog.terminal.info("Visible terminal host swapped to \(surface.id.description)")
        }
        surface.hostView.suspendsGeometrySync = suspendsGeometrySync
        synchronizeHostedViewFrame(force: surfaceChanged)

        let themeChanged = currentTheme != theme
        if surfaceChanged || themeChanged {
            surface.applyTheme(theme)
        }
        currentTheme = theme
        if !suspendsGeometrySync {
            surface.attachIfPossible()
        }
        surface.setFocused(focused)
        resignFocusIfNeeded(for: surface)
        restoreFocusIfNeeded()
        if geometrySyncResumed {
            syncCurrentSurface(force: false)
        } else if !suspendsGeometrySync && (surfaceChanged || themeChanged || focusChanged) {
            schedulePostLayoutGeometrySync(for: surface, force: surfaceChanged || themeChanged)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        synchronizeHostedViewFrame(force: true)
        syncCurrentSurface(force: true)
        if !currentSuspendsGeometrySync {
            currentSurface?.attachIfPossible()
        }
        restoreFocusIfNeeded()
    }

    override func layout() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        super.layout()
        synchronizeHostedViewFrame(force: false)
        CATransaction.commit()
    }

    override func setFrameSize(_ newSize: NSSize) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        super.setFrameSize(newSize)
        synchronizeHostedViewFrame(force: false)
        CATransaction.commit()
    }

    override func setBoundsSize(_ newSize: NSSize) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        super.setBoundsSize(newSize)
        synchronizeHostedViewFrame(force: false)
        CATransaction.commit()
    }

    private func installHostView(_ hostView: TerminalHostView) {
        hostView.removeFromSuperview()
        hostView.translatesAutoresizingMaskIntoConstraints = true
        hostView.autoresizingMask = [.width, .height]
        hostView.clipsToBounds = true
        hostView.frame = bounds
        hostView.bounds = NSRect(origin: .zero, size: bounds.size)
        addSubview(hostView)
        hostView.suspendsGeometrySync = currentSuspendsGeometrySync
    }

    @discardableResult
    private func synchronizeHostedViewFrame(force: Bool) -> Bool {
        guard let currentSurface else { return false }
        let targetFrame = NSRect(origin: .zero, size: bounds.size)
        let targetBounds = NSRect(origin: .zero, size: targetFrame.size)
        var geometryChanged = false
        if force || !rectApproximatelyEqual(currentSurface.hostView.frame, targetFrame) {
            currentSurface.hostView.frame = targetFrame
            geometryChanged = true
        }
        if force || !rectApproximatelyEqual(currentSurface.hostView.bounds, targetBounds) {
            currentSurface.hostView.bounds = targetBounds
            geometryChanged = true
        }
        if geometryChanged, !currentSuspendsGeometrySync {
            currentSurface.syncGeometry(force: force)
        }
        return geometryChanged
    }

    private func syncCurrentSurface(force: Bool, layoutNow: Bool = true) {
        guard let currentSurface else { return }
        guard !currentSuspendsGeometrySync else { return }
        if layoutNow {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            _ = synchronizeHostedViewFrame(force: false)
            CATransaction.commit()
        }
        currentSurface.syncGeometry(force: force)
        if force {
            currentSurface.refresh()
        }
    }

    private func schedulePostLayoutGeometrySync(for surface: TerminalSurface, force: Bool) {
        pendingGeometryForce = pendingGeometryForce || force
        guard !pendingGeometrySync else { return }
        pendingGeometrySync = true
        Task { @MainActor [weak self, weak surface] in
            guard let self else {
                return
            }
            let shouldForce = self.pendingGeometryForce
            self.pendingGeometrySync = false
            self.pendingGeometryForce = false
            guard let surface,
                  self.currentSurface === surface else {
                return
            }
            self.syncCurrentSurface(force: shouldForce)
            self.restoreFocusIfNeeded()
        }
    }

    private func restoreFocusIfNeeded() {
        guard wantsTerminalFocus,
              let surface = currentSurface,
              window?.firstResponder !== surface.hostView else {
            return
        }
        window?.makeFirstResponder(surface.hostView)
    }

    private func resignFocusIfNeeded(for surface: TerminalSurface) {
        guard !wantsTerminalFocus,
              window?.firstResponder === surface.hostView else {
            return
        }
        window?.makeFirstResponder(nil)
    }

    private func configureLayerForTerminalHosting(_ layer: CALayer?) {
        layer?.actions = [
            "bounds": NSNull(),
            "position": NSNull(),
            "frame": NSNull(),
            "contentsScale": NSNull(),
            "backgroundColor": NSNull()
        ]
    }

    private func rectApproximatelyEqual(_ lhs: CGRect, _ rhs: CGRect, epsilon: CGFloat = 0.25) -> Bool {
        abs(lhs.origin.x - rhs.origin.x) <= epsilon &&
            abs(lhs.origin.y - rhs.origin.y) <= epsilon &&
            abs(lhs.size.width - rhs.size.width) <= epsilon &&
            abs(lhs.size.height - rhs.size.height) <= epsilon
    }
}
