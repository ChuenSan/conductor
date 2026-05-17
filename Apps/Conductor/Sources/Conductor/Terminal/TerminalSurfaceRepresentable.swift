import AppKit
import QuartzCore
import SwiftUI

struct TerminalSurfaceRepresentable: NSViewRepresentable {
    let surface: TerminalSurface
    let theme: TerminalTheme
    let isFocused: Bool

    func makeNSView(context: Context) -> TerminalSurfaceContainerView {
        let container = TerminalSurfaceContainerView()
        container.setSurface(surface, theme: theme, focused: isFocused)
        return container
    }

    func updateNSView(_ nsView: TerminalSurfaceContainerView, context: Context) {
        nsView.setSurface(surface, theme: theme, focused: isFocused)
    }
}

@MainActor
final class TerminalSurfaceContainerView: NSView {
    private var currentSurface: TerminalSurface?
    private var currentTheme: TerminalTheme?
    private var currentFocused = false
    private var currentConstraints: [NSLayoutConstraint] = []
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

    func setSurface(_ surface: TerminalSurface, theme: TerminalTheme, focused: Bool) {
        let surfaceChanged = currentSurface !== surface
        let focusChanged = currentFocused != focused
        wantsTerminalFocus = focused
        currentFocused = focused
        if surfaceChanged {
            let signpost = ConductorSignpost.begin("surface-host-swap")
            defer { ConductorSignpost.end("surface-host-swap", signpost) }
            NSLayoutConstraint.deactivate(currentConstraints)
            currentConstraints.removeAll(keepingCapacity: true)
            currentSurface?.setFocused(false)
            currentSurface?.hostView.removeFromSuperview()
            currentSurface = surface
            currentTheme = nil
            installHostView(surface.hostView)
            ConductorLog.terminal.info("Visible terminal host swapped to \(surface.id.description)")
        }

        let themeChanged = currentTheme != theme
        if surfaceChanged || themeChanged {
            surface.applyTheme(theme)
        }
        currentTheme = theme
        surface.attachIfPossible()
        surface.setFocused(focused)
        if surfaceChanged || themeChanged {
            syncCurrentSurface(force: true)
        }
        restoreFocusIfNeeded()
        if surfaceChanged || themeChanged || focusChanged {
            schedulePostLayoutGeometrySync(for: surface, force: surfaceChanged || themeChanged)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        syncCurrentSurface(force: true)
        currentSurface?.attachIfPossible()
        restoreFocusIfNeeded()
    }

    override func layout() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        super.layout()
        CATransaction.commit()
        syncCurrentSurface(force: false, layoutNow: false)
    }

    private func installHostView(_ hostView: TerminalHostView) {
        hostView.removeFromSuperview()
        hostView.translatesAutoresizingMaskIntoConstraints = false
        hostView.clipsToBounds = true
        addSubview(hostView)
        currentConstraints = [
            hostView.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostView.trailingAnchor.constraint(equalTo: trailingAnchor),
            hostView.topAnchor.constraint(equalTo: topAnchor),
            hostView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ]
        NSLayoutConstraint.activate(currentConstraints)
    }

    private func syncCurrentSurface(force: Bool, layoutNow: Bool = true) {
        guard let currentSurface else { return }
        if layoutNow {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layoutSubtreeIfNeeded()
            currentSurface.hostView.layoutSubtreeIfNeeded()
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

    private func configureLayerForTerminalHosting(_ layer: CALayer?) {
        layer?.actions = [
            "bounds": NSNull(),
            "position": NSNull(),
            "frame": NSNull(),
            "contentsScale": NSNull(),
            "backgroundColor": NSNull()
        ]
    }
}
