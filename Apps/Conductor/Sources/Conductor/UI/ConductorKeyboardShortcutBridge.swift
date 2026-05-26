import AppKit
import SwiftUI

struct ConductorKeyboardShortcutBridge: NSViewRepresentable {
    var autofocus = true
    var forceAutofocus = false
    let handler: (NSEvent) -> Bool

    func makeNSView(context: Context) -> ConductorKeyboardShortcutBridgeView {
        let view = ConductorKeyboardShortcutBridgeView()
        view.autofocus = autofocus
        view.forceAutofocus = forceAutofocus
        view.handler = handler
        return view
    }

    func updateNSView(_ view: ConductorKeyboardShortcutBridgeView, context: Context) {
        view.autofocus = autofocus
        view.forceAutofocus = forceAutofocus
        view.handler = handler
        view.applyAutofocusPolicy()
    }
}

final class ConductorKeyboardShortcutBridgeView: NSView {
    var autofocus = true
    var forceAutofocus = false
    var handler: (NSEvent) -> Bool = { _ in false }

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyAutofocusPolicy()
    }

    func applyAutofocusPolicy() {
        if !autofocus {
            if window?.firstResponder === self {
                window?.makeFirstResponder(nil)
            }
            return
        }
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  self.autofocus else { return }
            guard self.forceAutofocus ||
                self.window?.firstResponder == nil ||
                self.window?.firstResponder === self else { return }
            self.window?.makeFirstResponder(self)
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        handler(event) || super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if handler(event) {
            return
        }
        super.keyDown(with: event)
    }
}
