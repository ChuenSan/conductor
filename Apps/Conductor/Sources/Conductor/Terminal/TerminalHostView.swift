import AppKit
import QuartzCore
@preconcurrency import GhosttyKit

@MainActor
final class TerminalHostView: NSView, @preconcurrency NSTextInputClient {
    weak var surface: TerminalSurface?
    private var keyTextAccumulator: [String]?
    private var markedText = NSMutableAttributedString()
    private var markedSelectedRange = NSRange(location: NSNotFound, length: 0)

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 900, height: 620))
        wantsLayer = true
        clipsToBounds = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    override func makeBackingLayer() -> CALayer {
        let layer = CAMetalLayer()
        layer.framebufferOnly = false
        layer.isOpaque = true
        layer.backgroundColor = NSColor.black.cgColor
        layer.masksToBounds = true
        return layer
    }

    override func setFrameSize(_ newSize: NSSize) {
        let changed = bounds.size != newSize
        super.setFrameSize(newSize)
        guard changed else { return }
        surface?.syncGeometry()
        surface?.refresh()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        surface?.attachIfPossible()
        surface?.syncGeometry(force: true)
        surface?.refresh()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        surface?.syncGeometry(force: true)
    }

    override func layout() {
        super.layout()
        surface?.syncGeometry()
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        surface?.requestWorkspaceFocus()
        surface?.setFocused(true)
        surface?.sendMouseButton(GHOSTTY_MOUSE_LEFT, state: GHOSTTY_MOUSE_PRESS, event: event)
    }

    override func mouseUp(with event: NSEvent) {
        surface?.sendMouseButton(GHOSTTY_MOUSE_LEFT, state: GHOSTTY_MOUSE_RELEASE, event: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        surface?.requestWorkspaceFocus()
        surface?.setFocused(true)
        surface?.sendMouseButton(GHOSTTY_MOUSE_RIGHT, state: GHOSTTY_MOUSE_PRESS, event: event)
    }

    override func rightMouseUp(with event: NSEvent) {
        surface?.sendMouseButton(GHOSTTY_MOUSE_RIGHT, state: GHOSTTY_MOUSE_RELEASE, event: event)
    }

    override func otherMouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        surface?.requestWorkspaceFocus()
        surface?.setFocused(true)
        surface?.sendMouseButton(GHOSTTY_MOUSE_MIDDLE, state: GHOSTTY_MOUSE_PRESS, event: event)
    }

    override func otherMouseUp(with event: NSEvent) {
        surface?.sendMouseButton(GHOSTTY_MOUSE_MIDDLE, state: GHOSTTY_MOUSE_RELEASE, event: event)
    }

    override func mouseMoved(with event: NSEvent) {
        surface?.updateMousePosition(convert(event.locationInWindow, from: nil), modifiers: event.modifierFlags)
    }

    override func mouseDragged(with event: NSEvent) {
        surface?.updateMousePosition(convert(event.locationInWindow, from: nil), modifiers: event.modifierFlags)
    }

    override func scrollWheel(with event: NSEvent) {
        surface?.scroll(deltaX: event.scrollingDeltaX, deltaY: event.scrollingDeltaY, modifiers: event.modifierFlags)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown, window?.firstResponder === self else { return false }
        let flags = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting([.numericPad, .function, .capsLock])
        if hasMarkedText(), !flags.contains(.command) {
            return false
        }
        if !flags.contains(.command),
           !flags.contains(.control),
           let text = event.characters,
           shouldSendText(text) {
            return false
        }
        guard surface?.isReadyForInput == true,
              surface?.isGhosttyBinding(event) == true else {
            return false
        }
        keyDown(with: event)
        return true
    }

    override func keyDown(with event: NSEvent) {
        let action = event.isARepeat ? GHOSTTY_ACTION_REPEAT : GHOSTTY_ACTION_PRESS
        let flags = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting([.numericPad, .function, .capsLock])

        if flags.contains(.control),
           !flags.contains(.command),
           !flags.contains(.option),
           !hasMarkedText(),
           surface?.forwardKeyEvent(event, action: action) == true {
            return
        }

        keyTextAccumulator = []
        let markedBefore = hasMarkedText()
        interpretKeyEvents([event])
        let accumulatedText = keyTextAccumulator ?? []
        keyTextAccumulator = nil
        syncPreedit(clearIfNeeded: markedBefore)

        if !accumulatedText.isEmpty {
            for text in accumulatedText where shouldSendText(text) {
                _ = surface?.forwardKeyEvent(event, action: action, textOverride: text, composing: false)
            }
            return
        }

        _ = surface?.forwardKeyEvent(
            event,
            action: action,
            textOverride: nil,
            composing: markedBefore || hasMarkedText()
        )
    }

    override func keyUp(with event: NSEvent) {
        _ = surface?.forwardKeyEvent(event, action: GHOSTTY_ACTION_RELEASE)
    }

    override func flagsChanged(with event: NSEvent) {
        surface?.forwardModifierEvent(event)
    }

    override func becomeFirstResponder() -> Bool {
        surface?.requestWorkspaceFocus()
        surface?.setFocused(true)
        return true
    }

    override func resignFirstResponder() -> Bool {
        surface?.setFocused(false)
        return true
    }

    override func doCommand(by selector: Selector) {
        // The fallback Ghostty key path handles text-system commands.
    }

    override func insertText(_ insertString: Any) {
        insertText(insertString, replacementRange: NSRange(location: NSNotFound, length: 0))
    }

    func insertText(_ string: Any, replacementRange: NSRange) {
        let text: String
        switch string {
        case let attributed as NSAttributedString:
            text = attributed.string
        case let plain as String:
            text = plain
        default:
            return
        }

        unmarkText()
        guard !text.isEmpty else { return }

        if keyTextAccumulator != nil {
            keyTextAccumulator?.append(text)
            return
        }

        surface?.sendText(text)
    }

    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        switch string {
        case let attributed as NSAttributedString:
            markedText = NSMutableAttributedString(attributedString: attributed)
        case let plain as String:
            markedText = NSMutableAttributedString(string: plain)
        default:
            return
        }
        markedSelectedRange = normalizedMarkedSelectionRange(selectedRange, markedLength: markedText.length)

        if keyTextAccumulator == nil {
            syncPreedit()
        }
    }

    func unmarkText() {
        guard markedText.length > 0 else { return }
        markedText.mutableString.setString("")
        markedSelectedRange = NSRange(location: NSNotFound, length: 0)
        syncPreedit()
    }

    func selectedRange() -> NSRange {
        if markedText.length > 0 {
            return markedSelectedRange
        }
        return NSRange(location: 0, length: 0)
    }

    func markedRange() -> NSRange {
        guard markedText.length > 0 else { return NSRange(location: NSNotFound, length: 0) }
        return NSRange(location: 0, length: markedText.length)
    }

    func hasMarkedText() -> Bool {
        markedText.length > 0
    }

    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? {
        guard markedText.length > 0 else { return nil }
        guard let substringRange = clampedMarkedTextRange(range, markedLength: markedText.length) else { return nil }
        actualRange?.pointee = substringRange
        return markedText.attributedSubstring(from: substringRange)
    }

    func validAttributesForMarkedText() -> [NSAttributedString.Key] {
        []
    }

    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        actualRange?.pointee = range
        let viewRect = surface?.imeRect() ?? NSRect(x: bounds.midX, y: bounds.midY, width: 0, height: 18)
        let windowRect = convert(viewRect, to: nil)
        return window?.convertToScreen(windowRect) ?? windowRect
    }

    func characterIndex(for point: NSPoint) -> Int {
        selectedRange().location
    }

    private func syncPreedit(clearIfNeeded: Bool = true) {
        if markedText.length > 0 {
            surface?.sendPreedit(markedText.string)
        } else if clearIfNeeded {
            surface?.sendPreedit(nil)
        }
    }

    private func normalizedMarkedSelectionRange(_ range: NSRange, markedLength: Int) -> NSRange {
        guard markedLength > 0 else { return NSRange(location: NSNotFound, length: 0) }
        if range.location == NSNotFound {
            return NSRange(location: markedLength, length: 0)
        }
        let location = min(max(0, range.location), markedLength)
        return NSRange(location: location, length: min(max(0, range.length), markedLength - location))
    }

    private func clampedMarkedTextRange(_ range: NSRange, markedLength: Int) -> NSRange? {
        guard markedLength > 0 else { return nil }
        let lower = range.location == NSNotFound ? 0 : max(0, min(range.location, markedLength))
        let upper = max(lower, min(lower + max(0, range.length), markedLength))
        return NSRange(location: lower, length: upper - lower)
    }

    private func shouldSendText(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        guard text.count == 1, let scalar = text.unicodeScalars.first else { return true }
        return scalar.value >= 0x20 && scalar.value != 0x7F
    }
}
