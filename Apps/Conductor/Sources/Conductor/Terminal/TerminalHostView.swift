import AppKit
import ConductorCore
import QuartzCore
@preconcurrency import GhosttyKit

@MainActor
final class TerminalHostView: NSView, @preconcurrency NSTextInputClient {
    private static let legacyFilenamesPboardType = NSPasteboard.PasteboardType("NSFilenamesPboardType")
    private static let internalTerminalTabDragType = NSPasteboard.PasteboardType("app.conductor.terminal-tab")
    private static let dropTypes: Set<NSPasteboard.PasteboardType> = [
        internalTerminalTabDragType,
        .string,
        .fileURL,
        .URL,
        legacyFilenamesPboardType
    ]
    private static let externalFileDropTypes: Set<NSPasteboard.PasteboardType> = [
        .fileURL,
        .URL,
        legacyFilenamesPboardType
    ]

    weak var surface: TerminalSurface?
    var suspendsGeometrySync = false
    private var keyTextAccumulator: [String]?
    private var markedText = NSMutableAttributedString()
    private var markedSelectedRange = NSRange(location: NSNotFound, length: 0)
    private var consumedRightMouseForMenu = false

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 900, height: 620))
        wantsLayer = true
        clipsToBounds = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        configureLayerForTerminalHosting(layer)
        registerForDraggedTypes(Array(Self.dropTypes))
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
        configureLayerForTerminalHosting(layer)
        return layer
    }

    override func setFrameSize(_ newSize: NSSize) {
        let changed = bounds.size != newSize
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        super.setFrameSize(newSize)
        CATransaction.commit()
        guard changed else { return }
        syncGeometryIfWindowAttached()
    }

    override func setBoundsSize(_ newSize: NSSize) {
        let changed = bounds.size != newSize
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        super.setBoundsSize(newSize)
        CATransaction.commit()
        guard changed else { return }
        syncGeometryIfWindowAttached()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        if !suspendsGeometrySync {
            surface?.attachIfPossible()
        }
        syncGeometryIfWindowAttached(force: true)
        surface?.refresh()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        syncGeometryIfWindowAttached(force: true)
        surface?.refresh()
    }

    override func layout() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        super.layout()
        CATransaction.commit()
        syncGeometryIfWindowAttached()
    }

    private func syncGeometryIfWindowAttached(force: Bool = false) {
        guard window != nil,
              !suspendsGeometrySync else { return }
        surface?.syncGeometry(force: force)
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
        if surface?.requestContextMenu(event: event, in: self) == true {
            consumedRightMouseForMenu = true
            return
        }
        surface?.sendMouseButton(GHOSTTY_MOUSE_RIGHT, state: GHOSTTY_MOUSE_PRESS, event: event)
    }

    override func rightMouseUp(with event: NSEvent) {
        if consumedRightMouseForMenu {
            consumedRightMouseForMenu = false
            return
        }
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

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let operation = dropOperation(for: sender.draggingPasteboard)
        if operation == .move,
           terminalTabID(from: sender.draggingPasteboard) != nil {
            updateTerminalTabDropOverlay(for: sender)
        } else {
            hideTerminalTabDropOverlay()
        }
        return operation
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        let operation = dropOperation(for: sender.draggingPasteboard)
        if operation == .move,
           terminalTabID(from: sender.draggingPasteboard) != nil {
            updateTerminalTabDropOverlay(for: sender)
        } else {
            hideTerminalTabDropOverlay()
        }
        return operation
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        hideTerminalTabDropOverlay()
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        hideTerminalTabDropOverlay()
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        if surface?.canAcceptTerminalTabDrop() == true,
           let draggedTerminalID = terminalTabID(from: sender.draggingPasteboard) {
            let target = terminalTabDropTarget(for: convert(sender.draggingLocation, from: nil), size: bounds.size)
            hideTerminalTabDropOverlay()
            return surface?.performTerminalTabDrop(draggedTerminalID: draggedTerminalID, target: target) ?? false
        }

        guard let text = droppedTerminalText(from: sender.draggingPasteboard) else { return false }
        window?.makeFirstResponder(self)
        surface?.requestWorkspaceFocus()
        surface?.setFocused(true)
        insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
        return true
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

    private func dropOperation(for pasteboard: NSPasteboard) -> NSDragOperation {
        if surface?.canAcceptTerminalTabDrop() == true,
           terminalTabID(from: pasteboard) != nil {
            return .move
        }

        guard let types = pasteboard.types,
              !types.contains(Self.internalTerminalTabDragType),
              !Set(types).isDisjoint(with: Self.externalFileDropTypes),
              droppedTerminalText(from: pasteboard) != nil else {
            return []
        }
        return .copy
    }

    private func updateTerminalTabDropOverlay(for sender: NSDraggingInfo) {
        let location = convert(sender.draggingLocation, from: nil)
        let target = terminalTabDropTarget(for: location, size: bounds.size)
        surface?.updateTerminalTabDropTarget(target)
    }

    private func hideTerminalTabDropOverlay() {
        surface?.updateTerminalTabDropTarget(nil)
    }

    private func terminalTabID(from pasteboard: NSPasteboard) -> TerminalID? {
        guard surface?.canAcceptTerminalTabDrop() == true else { return nil }

        if let data = pasteboard.data(forType: Self.internalTerminalTabDragType),
           let text = String(data: data, encoding: .utf8),
           let terminalID = terminalID(fromDroppedText: text) {
            return terminalID
        }

        if let text = pasteboard.string(forType: Self.internalTerminalTabDragType),
           let terminalID = terminalID(fromDroppedText: text) {
            return terminalID
        }

        if let text = pasteboard.string(forType: .string),
           let terminalID = terminalID(fromDroppedText: text) {
            return terminalID
        }

        return nil
    }

    private func terminalID(fromDroppedText text: String) -> TerminalID? {
        let prefix = "terminal:"
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawID = trimmed.hasPrefix(prefix)
            ? String(trimmed.dropFirst(prefix.count))
            : trimmed
        guard let uuid = UUID(uuidString: rawID) else { return nil }
        return TerminalID(uuid)
    }

    private func terminalTabDropTarget(for location: CGPoint, size: CGSize) -> TerminalTabDropTarget {
        let width = max(1, size.width)
        let height = max(1, size.height)
        let topOriginY = height - location.y
        let horizontalEdge = max(80, width * 0.25)
        let verticalEdge = max(80, height * 0.25)
        if location.x < horizontalEdge {
            return .left
        }
        if location.x > width - horizontalEdge {
            return .right
        }
        if topOriginY < verticalEdge {
            return .up
        }
        if topOriginY > height - verticalEdge {
            return .down
        }
        return .center
    }

    private func droppedTerminalText(from pasteboard: NSPasteboard) -> String? {
        guard let types = pasteboard.types,
              !types.contains(Self.internalTerminalTabDragType) else {
            return nil
        }

        let urls = fileURLs(from: pasteboard)
        if !urls.isEmpty {
            return urls
                .map { shellEscapedText($0.path) }
                .joined(separator: " ") + " "
        }

        if let rawURL = pasteboard.string(forType: .URL),
           !rawURL.isEmpty {
            return shellEscapedText(rawURL) + " "
        }

        if let string = pasteboard.string(forType: .string),
           !string.isEmpty {
            return string
        }

        return nil
    }

    private func fileURLs(from pasteboard: NSPasteboard) -> [URL] {
        var fileURLs: [URL] = []

        let objects = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) ?? []
        for object in objects {
            if let url = object as? URL, url.isFileURL {
                fileURLs.append(url.standardizedFileURL)
            }
        }

        if let filePaths = pasteboard.propertyList(forType: Self.legacyFilenamesPboardType) as? [String] {
            fileURLs.append(
                contentsOf: filePaths
                    .filter { !$0.isEmpty }
                    .map { URL(fileURLWithPath: $0).standardizedFileURL }
            )
        }

        if let value = pasteboard.string(forType: .fileURL),
           let url = URL(string: value),
           url.isFileURL {
            fileURLs.append(url.standardizedFileURL)
        }

        var seen: Set<String> = []
        return fileURLs.filter { url in
            seen.insert(url.path).inserted
        }
    }

    private func shellEscapedText(_ value: String) -> String {
        if value.contains(where: { $0 == "\n" || $0 == "\r" }) {
            return shellSingleQuoted(value)
        }

        var result = value
        for character in "\\ ()[]{}<>\"'`!#$&;|*?\t" {
            result = result.replacingOccurrences(of: String(character), with: "\\\(character)")
        }
        return result
    }

    private func shellSingleQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}

enum TerminalTabDropTarget: Equatable {
    case center
    case left
    case right
    case up
    case down

    var direction: SplitDirection {
        switch self {
        case .center, .right:
            return .right
        case .left:
            return .left
        case .up:
            return .up
        case .down:
            return .down
        }
    }

    var isHorizontalSplit: Bool {
        switch self {
        case .left, .right:
            return true
        case .center, .up, .down:
            return false
        }
    }
}
