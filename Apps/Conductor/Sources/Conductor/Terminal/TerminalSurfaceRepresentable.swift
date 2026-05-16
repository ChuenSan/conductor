import AppKit
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
    private var currentConstraints: [NSLayoutConstraint] = []
    private var wantsTerminalFocus = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        clipsToBounds = true
        layer?.masksToBounds = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setSurface(_ surface: TerminalSurface, theme: TerminalTheme, focused: Bool) {
        wantsTerminalFocus = focused
        if currentSurface !== surface {
            let signpost = ConductorSignpost.begin("surface-host-swap")
            defer { ConductorSignpost.end("surface-host-swap", signpost) }
            NSLayoutConstraint.deactivate(currentConstraints)
            currentConstraints.removeAll(keepingCapacity: true)
            currentSurface?.setFocused(false)
            currentSurface?.hostView.removeFromSuperview()
            currentSurface = surface
            installHostView(surface.hostView)
            ConductorLog.terminal.info("Visible terminal host swapped to \(surface.id.description)")
        }

        surface.applyTheme(theme)
        syncCurrentSurface(force: true)
        surface.attachIfPossible()
        surface.setFocused(focused)
        restoreFocusIfNeeded()
        schedulePostLayoutGeometrySync(for: surface, repeatCount: 3)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        syncCurrentSurface(force: true)
        currentSurface?.attachIfPossible()
        restoreFocusIfNeeded()
    }

    override func layout() {
        super.layout()
        syncCurrentSurface(force: false)
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

    private func syncCurrentSurface(force: Bool) {
        guard let currentSurface else { return }
        layoutSubtreeIfNeeded()
        currentSurface.hostView.layoutSubtreeIfNeeded()
        currentSurface.syncGeometry(force: force)
        currentSurface.refresh()
    }

    private func schedulePostLayoutGeometrySync(for surface: TerminalSurface, repeatCount: Int) {
        guard repeatCount > 0 else { return }
        DispatchQueue.main.async { [weak self, weak surface] in
            guard let self,
                  let surface,
                  self.currentSurface === surface else {
                return
            }
            self.syncCurrentSurface(force: true)
            self.schedulePostLayoutGeometrySync(for: surface, repeatCount: repeatCount - 1)
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
}
