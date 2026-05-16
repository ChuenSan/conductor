import AppKit
import Foundation
import GhosttyKit
import QuartzCore

@MainActor
final class TerminalSurfaceOwner {
    let id = UUID()

    private(set) lazy var hostView = TerminalHostView(owner: self)
    private var surface: ghostty_surface_t?
    private var lastPixelSize = CGSize(width: -1, height: -1)
    private var lastScale = CGSize(width: -1, height: -1)
    private var lastDisplayID: UInt32 = 0
    private var focused = false
    private var sizeChangeCount = 0
    private var currentTheme: TerminalTheme = .flexoki
    private var appliedSurfaceTheme: TerminalTheme?
    private var surfaceThemeConfig: ghostty_config_t?

    func attachIfPossible() {
        guard surface == nil else {
            syncGeometry()
            return
        }
        guard hostView.window != nil else {
            ValidationLogger.info("surface create skipped id=\(id.uuidString) reason=no-window")
            return
        }
        GhosttyRuntime.shared.start(theme: currentTheme)
        guard let app = GhosttyRuntime.shared.app else {
            ValidationLogger.error("surface create failed id=\(id.uuidString) reason=no-runtime")
            return
        }

        var surfaceConfig = ghostty_surface_config_new()
        surfaceConfig.platform_tag = GHOSTTY_PLATFORM_MACOS
        surfaceConfig.platform = ghostty_platform_u(
            macos: ghostty_platform_macos_s(
                nsview: Unmanaged.passUnretained(hostView).toOpaque()
            )
        )
        surfaceConfig.userdata = Unmanaged.passUnretained(self).toOpaque()
        surfaceConfig.scale_factor = Double(hostView.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2)
        surfaceConfig.font_size = 13
        surfaceConfig.context = GHOSTTY_SURFACE_CONTEXT_WINDOW
        surfaceConfig.wait_after_command = false

        let command = "/bin/zsh"
        let workingDirectory = FileManager.default.homeDirectoryForCurrentUser.path

        command.withCString { commandPtr in
            workingDirectory.withCString { workingDirectoryPtr in
                surfaceConfig.command = commandPtr
                surfaceConfig.working_directory = workingDirectoryPtr
                surfaceConfig.initial_input = nil
                surface = ghostty_surface_new(app, &surfaceConfig)
            }
        }

        guard let surface else {
            ValidationLogger.error("ghostty_surface_new returned nil id=\(id.uuidString)")
            return
        }

        ValidationLogger.info("surface created id=\(id.uuidString)")
        syncGeometry(force: true)
        hostView.window?.makeFirstResponder(hostView)
        setFocused(hostView.window?.firstResponder === hostView)
        appliedSurfaceTheme = currentTheme
        ghostty_surface_refresh(surface)
    }

    func applyTheme(_ theme: TerminalTheme) {
        currentTheme = theme
        hostView.layer?.backgroundColor = NSColor(theme.shellBackground).cgColor
        guard let surface else { return }
        guard appliedSurfaceTheme != theme else { return }
        guard let config = GhosttyRuntime.shared.makeConfig(theme: theme) else {
            ValidationLogger.error("theme config failed id=\(id.uuidString) theme=\(theme.title)")
            return
        }
        if let previous = surfaceThemeConfig {
            ghostty_config_free(previous)
        }
        surfaceThemeConfig = config
        ghostty_surface_update_config(surface, config)
        ghostty_surface_refresh(surface)
        appliedSurfaceTheme = theme
        ValidationLogger.info("surface theme id=\(id.uuidString) theme=\(theme.title)")
    }

    func syncGeometry(force: Bool = false) {
        guard let surface else { return }

        let scaleX = hostView.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let scaleY = scaleX
        let scale = CGSize(width: scaleX, height: scaleY)
        if force || scale != lastScale {
            ghostty_surface_set_content_scale(surface, Double(scaleX), Double(scaleY))
            lastScale = scale
            ValidationLogger.info("surface scale id=\(id.uuidString) x=\(scaleX) y=\(scaleY)")
        }

        if let displayID = hostView.window?.screen?.validationDisplayID, displayID != 0, force || displayID != lastDisplayID {
            ghostty_surface_set_display_id(surface, displayID)
            lastDisplayID = displayID
            ValidationLogger.info("surface display id=\(id.uuidString) displayID=\(displayID)")
        }

        let backingSize = hostView.convertToBacking(NSRect(origin: .zero, size: hostView.bounds.size)).size
        let pixelWidth = max(1, UInt32(backingSize.width.rounded(.toNearestOrAwayFromZero)))
        let pixelHeight = max(1, UInt32(backingSize.height.rounded(.toNearestOrAwayFromZero)))
        let pixelSize = CGSize(width: CGFloat(pixelWidth), height: CGFloat(pixelHeight))
        if force || pixelSize != lastPixelSize {
            ghostty_surface_set_size(surface, pixelWidth, pixelHeight)
            lastPixelSize = pixelSize
            sizeChangeCount += 1
            if force || sizeChangeCount <= 4 || sizeChangeCount.isMultiple(of: 20) {
                ValidationLogger.info("surface size id=\(id.uuidString) width=\(pixelWidth) height=\(pixelHeight) count=\(sizeChangeCount)")
            }
        }
    }

    func setFocused(_ value: Bool) {
        guard focused != value else { return }
        focused = value
        guard let surface else { return }
        ghostty_surface_set_focus(surface, value)
        ValidationLogger.info("surface focus id=\(id.uuidString) focused=\(value)")
    }

    func refresh() {
        guard let surface else { return }
        ghostty_surface_refresh(surface)
    }

    func sendAutomationText(_ text: String) {
        guard let surface, !text.isEmpty else { return }
        text.withCString { ptr in
            ghostty_surface_text(surface, ptr, UInt(text.utf8.count))
        }
    }

    func sendPreedit(_ text: String?) {
        guard let surface else { return }
        guard let text, !text.isEmpty else {
            ghostty_surface_preedit(surface, nil, 0)
            return
        }
        text.withCString { ptr in
            ghostty_surface_preedit(surface, ptr, UInt(text.utf8.count))
        }
    }

    func imeRect() -> NSRect {
        guard let surface else {
            return NSRect(x: hostView.bounds.midX, y: hostView.bounds.midY, width: 0, height: 18)
        }
        var x: Double = 0
        var y: Double = 0
        var width: Double = 0
        var height: Double = 18
        ghostty_surface_ime_point(surface, &x, &y, &width, &height)
        return NSRect(
            x: x,
            y: hostView.bounds.height - y,
            width: width,
            height: max(height, 18)
        )
    }

    func sendTypedText(_ text: String, preserveLiteralEscape: Bool = false) {
        guard let surface, !text.isEmpty else { return }

        var bufferedText = ""
        var previousWasCarriageReturn = false

        func flushBufferedText() {
            guard !bufferedText.isEmpty else { return }
            var keyEvent = ghostty_input_key_s()
            keyEvent.action = GHOSTTY_ACTION_PRESS
            keyEvent.keycode = 0
            keyEvent.mods = GHOSTTY_MODS_NONE
            keyEvent.consumed_mods = GHOSTTY_MODS_NONE
            keyEvent.unshifted_codepoint = 0
            keyEvent.composing = false
            bufferedText.withCString { ptr in
                keyEvent.text = ptr
                _ = ghostty_surface_key(surface, keyEvent)
            }
            bufferedText.removeAll(keepingCapacity: true)
        }

        func sendControlKey(_ keycode: UInt32) {
            var keyEvent = ghostty_input_key_s()
            keyEvent.action = GHOSTTY_ACTION_PRESS
            keyEvent.keycode = keycode
            keyEvent.mods = GHOSTTY_MODS_NONE
            keyEvent.consumed_mods = GHOSTTY_MODS_NONE
            keyEvent.unshifted_codepoint = 0
            keyEvent.composing = false
            keyEvent.text = nil
            _ = ghostty_surface_key(surface, keyEvent)
        }

        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x0A:
                if !previousWasCarriageReturn {
                    flushBufferedText()
                    sendControlKey(0x24)
                }
                previousWasCarriageReturn = false
            case 0x0D:
                flushBufferedText()
                sendControlKey(0x24)
                previousWasCarriageReturn = true
            case 0x09:
                flushBufferedText()
                sendControlKey(0x30)
                previousWasCarriageReturn = false
            case 0x1B:
                if preserveLiteralEscape {
                    bufferedText.unicodeScalars.append(scalar)
                } else {
                    flushBufferedText()
                    sendControlKey(0x35)
                }
                previousWasCarriageReturn = false
            default:
                bufferedText.unicodeScalars.append(scalar)
                previousWasCarriageReturn = false
            }
        }
        flushBufferedText()
    }

    @discardableResult
    func forwardKeyEvent(_ event: NSEvent, action: ghostty_input_action_e) -> Bool {
        forwardKeyEvent(event, action: action, textOverride: nil, composing: false)
    }

    @discardableResult
    func forwardKeyEvent(
        _ event: NSEvent,
        action: ghostty_input_action_e,
        textOverride: String?,
        composing: Bool
    ) -> Bool {
        guard let surface else { return false }
        var keyEvent = ghosttyKeyEvent(for: event, surface: surface)
        keyEvent.action = action
        keyEvent.composing = composing

        if action == GHOSTTY_ACTION_RELEASE {
            keyEvent.text = nil
        }

        let candidateText = textOverride ?? textForKeyEvent(event)
        guard action != GHOSTTY_ACTION_RELEASE, !composing, let text = candidateText else {
            keyEvent.text = nil
            keyEvent.consumed_mods = GHOSTTY_MODS_NONE
            return ghostty_surface_key(surface, keyEvent)
        }

        return text.withCString { ptr in
            keyEvent.text = ptr
            return ghostty_surface_key(surface, keyEvent)
        }
    }

    func forwardModifierEvent(_ event: NSEvent) {
        guard let surface, let action = modifierAction(for: event) else { return }
        var keyEvent = ghostty_input_key_s()
        keyEvent.action = action
        keyEvent.mods = event.modifierFlags.ghosttyMods
        keyEvent.consumed_mods = GHOSTTY_MODS_NONE
        keyEvent.keycode = UInt32(event.keyCode)
        keyEvent.text = nil
        keyEvent.unshifted_codepoint = 0
        keyEvent.composing = false
        _ = ghostty_surface_key(surface, keyEvent)
    }

    func isGhosttyBinding(_ event: NSEvent) -> Bool {
        guard let surface else { return false }
        var keyEvent = ghosttyKeyEvent(for: event, surface: surface)
        var flags = ghostty_binding_flags_e(0)
        let text = textForKeyEvent(event) ?? ""
        return text.withCString { ptr in
            keyEvent.text = ptr
            return ghostty_surface_key_is_binding(surface, keyEvent, &flags)
        }
    }

    func sendStressCommand() {
        ValidationLogger.info("sending stress command id=\(id.uuidString)")
        sendSyntheticKey(macKeyCode: 32, mods: GHOSTTY_MODS_CTRL, text: "u")
        sendAutomationText("yes 'validation-output-line' | head -100000")
        sendSyntheticKey(macKeyCode: 36, mods: GHOSTTY_MODS_NONE, text: "\r")
    }

    func sendControlDForValidation() {
        ValidationLogger.info("sending ctrl-d id=\(id.uuidString)")
        sendSyntheticKey(macKeyCode: 2, mods: GHOSTTY_MODS_CTRL, text: "d")
    }

    func scroll(deltaX: CGFloat, deltaY: CGFloat, modifiers: NSEvent.ModifierFlags) {
        guard let surface else { return }
        ghostty_surface_mouse_scroll(surface, Double(deltaX), Double(deltaY), modifiers.ghosttyScrollMods)
    }

    func updateMousePosition(_ point: NSPoint, modifiers: NSEvent.ModifierFlags) {
        guard let surface else { return }
        ghostty_surface_mouse_pos(surface, Double(point.x), Double(hostView.bounds.height - point.y), modifiers.ghosttyMods)
    }

    func sendMouseButton(_ button: ghostty_input_mouse_button_e, state: ghostty_input_mouse_state_e, event: NSEvent) {
        guard let surface else { return }
        updateMousePosition(hostView.convert(event.locationInWindow, from: nil), modifiers: event.modifierFlags)
        _ = ghostty_surface_mouse_button(surface, state, button, event.modifierFlags.ghosttyMods)
    }

    func completeClipboardRequest(location: ghostty_clipboard_e, state: UnsafeMutableRawPointer) {
        guard let surface else { return }
        let text = NSPasteboard.general.string(forType: .string) ?? ""
        text.withCString { ptr in
            ghostty_surface_complete_clipboard_request(surface, ptr, state, false)
        }
    }

    func closeFromGhostty(needsConfirmation: Bool) {
        ValidationLogger.info("close requested id=\(id.uuidString) needsConfirmation=\(needsConfirmation)")
    }

    func close() {
        guard let surface else { return }
        self.surface = nil
        if let surfaceThemeConfig {
            ghostty_config_free(surfaceThemeConfig)
            self.surfaceThemeConfig = nil
        }
        ghostty_surface_free(surface)
        ValidationLogger.info("surface freed id=\(id.uuidString)")
    }

    @discardableResult
    private func sendSyntheticKey(macKeyCode: UInt32, mods: ghostty_input_mods_e, text: String?) -> Bool {
        guard let surface else { return false }
        var keyEvent = ghostty_input_key_s()
        keyEvent.action = GHOSTTY_ACTION_PRESS
        keyEvent.mods = mods
        keyEvent.consumed_mods = GHOSTTY_MODS_NONE
        keyEvent.keycode = macKeyCode
        keyEvent.unshifted_codepoint = text?.unicodeScalars.first?.value ?? 0
        keyEvent.composing = false

        let handled: Bool
        if let text {
            handled = text.withCString { ptr in
                keyEvent.text = ptr
                return ghostty_surface_key(surface, keyEvent)
            }
        } else {
            keyEvent.text = nil
            handled = ghostty_surface_key(surface, keyEvent)
        }

        keyEvent.action = GHOSTTY_ACTION_RELEASE
        keyEvent.text = nil
        _ = ghostty_surface_key(surface, keyEvent)
        return handled
    }

    private func ghosttyKeyEvent(for event: NSEvent, surface: ghostty_surface_t) -> ghostty_input_key_s {
        var keyEvent = ghostty_input_key_s()
        keyEvent.action = event.isARepeat ? GHOSTTY_ACTION_REPEAT : GHOSTTY_ACTION_PRESS
        keyEvent.mods = event.modifierFlags.ghosttyMods
        keyEvent.keycode = UInt32(event.keyCode)
        keyEvent.unshifted_codepoint = unshiftedCodepoint(from: event)
        keyEvent.composing = false

        let translatedMods = ghostty_surface_key_translation_mods(surface, event.modifierFlags.ghosttyMods)
        keyEvent.consumed_mods = consumedMods(from: translatedMods)

        keyEvent.text = nil
        return keyEvent
    }

    private func textForKeyEvent(_ event: NSEvent) -> String? {
        guard let characters = event.characters, !characters.isEmpty else { return nil }
        guard let scalar = characters.unicodeScalars.first else { return nil }

        if scalar.value >= 0xF700, scalar.value <= 0xF8FF {
            return nil
        }

        if scalar.value < 0x20, event.modifierFlags.contains(.control) {
            return event.charactersIgnoringModifiers ?? characters
        }

        if event.modifierFlags.contains(.command), !event.modifierFlags.contains(.option) {
            return nil
        }

        return characters
    }

    private func unshiftedCodepoint(from event: NSEvent) -> UInt32 {
        guard let characters = event.charactersIgnoringModifiers ?? event.characters,
              let scalar = characters.unicodeScalars.first,
              !(scalar.value >= 0xF700 && scalar.value <= 0xF8FF) else {
            return 0
        }
        return scalar.value
    }

    private func consumedMods(from mods: ghostty_input_mods_e) -> ghostty_input_mods_e {
        var raw: UInt32 = 0
        if mods.rawValue & GHOSTTY_MODS_SHIFT.rawValue != 0 {
            raw |= GHOSTTY_MODS_SHIFT.rawValue
        }
        if mods.rawValue & GHOSTTY_MODS_ALT.rawValue != 0 {
            raw |= GHOSTTY_MODS_ALT.rawValue
        }
        return ghostty_input_mods_e(rawValue: raw)
    }

    private func modifierAction(for event: NSEvent) -> ghostty_input_action_e? {
        switch event.keyCode {
        case 0x39:
            return event.modifierFlags.contains(.capsLock) ? GHOSTTY_ACTION_PRESS : GHOSTTY_ACTION_RELEASE
        case 0x38, 0x3C:
            return event.modifierFlags.contains(.shift) ? GHOSTTY_ACTION_PRESS : GHOSTTY_ACTION_RELEASE
        case 0x3B, 0x3E:
            return event.modifierFlags.contains(.control) ? GHOSTTY_ACTION_PRESS : GHOSTTY_ACTION_RELEASE
        case 0x3A, 0x3D:
            return event.modifierFlags.contains(.option) ? GHOSTTY_ACTION_PRESS : GHOSTTY_ACTION_RELEASE
        case 0x37, 0x36:
            return event.modifierFlags.contains(.command) ? GHOSTTY_ACTION_PRESS : GHOSTTY_ACTION_RELEASE
        default:
            return nil
        }
    }
}

final class TerminalHostView: NSView, @preconcurrency NSTextInputClient {
    private weak var owner: TerminalSurfaceOwner?
    private var keyTextAccumulator: [String]?
    private var markedText = NSMutableAttributedString()
    private var markedSelectedRange = NSRange(location: NSNotFound, length: 0)

    init(owner: TerminalSurfaceOwner) {
        self.owner = owner
        super.init(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        wantsLayer = true
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
        return layer
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        owner?.attachIfPossible()
        if window?.firstResponder == nil || window?.firstResponder === window {
            window?.makeFirstResponder(self)
        }
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        owner?.syncGeometry(force: true)
    }

    override func layout() {
        super.layout()
        owner?.syncGeometry()
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        owner?.setFocused(true)
        owner?.sendMouseButton(GHOSTTY_MOUSE_LEFT, state: GHOSTTY_MOUSE_PRESS, event: event)
    }

    override func mouseUp(with event: NSEvent) {
        owner?.sendMouseButton(GHOSTTY_MOUSE_LEFT, state: GHOSTTY_MOUSE_RELEASE, event: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        owner?.setFocused(true)
        owner?.sendMouseButton(GHOSTTY_MOUSE_RIGHT, state: GHOSTTY_MOUSE_PRESS, event: event)
    }

    override func rightMouseUp(with event: NSEvent) {
        owner?.sendMouseButton(GHOSTTY_MOUSE_RIGHT, state: GHOSTTY_MOUSE_RELEASE, event: event)
    }

    override func otherMouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        owner?.setFocused(true)
        owner?.sendMouseButton(GHOSTTY_MOUSE_MIDDLE, state: GHOSTTY_MOUSE_PRESS, event: event)
    }

    override func otherMouseUp(with event: NSEvent) {
        owner?.sendMouseButton(GHOSTTY_MOUSE_MIDDLE, state: GHOSTTY_MOUSE_RELEASE, event: event)
    }

    override func mouseMoved(with event: NSEvent) {
        owner?.updateMousePosition(convert(event.locationInWindow, from: nil), modifiers: event.modifierFlags)
    }

    override func mouseDragged(with event: NSEvent) {
        owner?.updateMousePosition(convert(event.locationInWindow, from: nil), modifiers: event.modifierFlags)
    }

    override func scrollWheel(with event: NSEvent) {
        owner?.scroll(deltaX: event.scrollingDeltaX, deltaY: event.scrollingDeltaY, modifiers: event.modifierFlags)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return false }
        guard window?.firstResponder === self else { return false }

        let flags = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting([.numericPad, .function, .capsLock])

        if !flags.contains(.command),
           !flags.contains(.control),
           let text = textForKeyEquivalent(event),
           shouldSendText(text) {
            return false
        }

        guard owner?.isGhosttyBinding(event) == true else { return false }
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
           owner?.forwardKeyEvent(event, action: action) == true {
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
                _ = owner?.forwardKeyEvent(
                    event,
                    action: action,
                    textOverride: text,
                    composing: false
                )
            }
            return
        }

        _ = owner?.forwardKeyEvent(
            event,
            action: action,
            textOverride: nil,
            composing: markedBefore || hasMarkedText()
        )
    }

    override func keyUp(with event: NSEvent) {
        _ = owner?.forwardKeyEvent(event, action: GHOSTTY_ACTION_RELEASE)
    }

    override func flagsChanged(with event: NSEvent) {
        owner?.forwardModifierEvent(event)
    }

    override func becomeFirstResponder() -> Bool {
        owner?.setFocused(true)
        return true
    }

    override func resignFirstResponder() -> Bool {
        owner?.setFocused(false)
        return true
    }

    override func doCommand(by selector: Selector) {
        // AppKit calls this for unhandled text-system commands during
        // interpretKeyEvents. The fallback Ghostty key path handles them.
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

        owner?.sendTypedText(text)
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
        let viewRect = owner?.imeRect() ?? NSRect(x: bounds.midX, y: bounds.midY, width: 0, height: 18)
        let windowRect = convert(viewRect, to: nil)
        return window?.convertToScreen(windowRect) ?? windowRect
    }

    func characterIndex(for point: NSPoint) -> Int {
        selectedRange().location
    }

    private func syncPreedit(clearIfNeeded: Bool = true) {
        if markedText.length > 0 {
            owner?.sendPreedit(markedText.string)
        } else if clearIfNeeded {
            owner?.sendPreedit(nil)
        }
    }

    private func normalizedMarkedSelectionRange(_ range: NSRange, markedLength: Int) -> NSRange {
        guard markedLength > 0 else { return NSRange(location: NSNotFound, length: 0) }
        if range.location == NSNotFound {
            return NSRange(location: markedLength, length: 0)
        }
        let location = min(max(0, range.location), markedLength)
        let maxLength = markedLength - location
        return NSRange(location: location, length: min(max(0, range.length), maxLength))
    }

    private func clampedMarkedTextRange(_ range: NSRange, markedLength: Int) -> NSRange? {
        guard markedLength > 0 else { return nil }
        let lower = range.location == NSNotFound ? 0 : max(0, min(range.location, markedLength))
        let upper = max(lower, min(lower + max(0, range.length), markedLength))
        return NSRange(location: lower, length: upper - lower)
    }

    private func textForKeyEquivalent(_ event: NSEvent) -> String? {
        guard let characters = event.characters, !characters.isEmpty else { return nil }
        guard let scalar = characters.unicodeScalars.first else { return nil }
        if scalar.value >= 0xF700, scalar.value <= 0xF8FF {
            return nil
        }
        return characters
    }

    private func shouldSendText(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        guard text.count == 1, let scalar = text.unicodeScalars.first else { return true }
        return scalar.value >= 0x20 && scalar.value != 0x7F
    }
}

private extension NSScreen {
    var validationDisplayID: UInt32 {
        guard let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return 0
        }
        return number.uint32Value
    }
}

private extension NSEvent.ModifierFlags {
    var ghosttyMods: ghostty_input_mods_e {
        var mods = GHOSTTY_MODS_NONE
        if contains(.shift) { mods = ghostty_input_mods_e(UInt32(mods.rawValue) | UInt32(GHOSTTY_MODS_SHIFT.rawValue)) }
        if contains(.control) { mods = ghostty_input_mods_e(UInt32(mods.rawValue) | UInt32(GHOSTTY_MODS_CTRL.rawValue)) }
        if contains(.option) { mods = ghostty_input_mods_e(UInt32(mods.rawValue) | UInt32(GHOSTTY_MODS_ALT.rawValue)) }
        if contains(.command) { mods = ghostty_input_mods_e(UInt32(mods.rawValue) | UInt32(GHOSTTY_MODS_SUPER.rawValue)) }
        if contains(.capsLock) { mods = ghostty_input_mods_e(UInt32(mods.rawValue) | UInt32(GHOSTTY_MODS_CAPS.rawValue)) }
        return mods
    }

    var ghosttyScrollMods: ghostty_input_scroll_mods_t {
        ghostty_input_scroll_mods_t(ghosttyMods.rawValue)
    }
}
