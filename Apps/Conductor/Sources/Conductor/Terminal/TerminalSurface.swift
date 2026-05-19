import AppKit
import ConductorCore
import Foundation
@preconcurrency import GhosttyKit

@MainActor
final class TerminalSurface {
    let id: TerminalID
    let hostView: TerminalHostView
    var onFocusRequest: (@MainActor (TerminalID) -> Void)?
    var onContextMenuRequest: (@MainActor (TerminalID, NSEvent, NSView) -> Bool)?
    var onTerminalTabDropRequest: (@MainActor (TerminalID, TerminalID, TerminalTabDropTarget) -> Bool)?
    var onTerminalTabDropTargetChange: (@MainActor (TerminalID, TerminalTabDropTarget?) -> Void)?
    var hasActiveTerminalTabDrag: (@MainActor () -> Bool)?

    private var surface: ghostty_surface_t?
    private var lastPixelSize = CGSize(width: -1, height: -1)
    private var lastScale = CGSize(width: -1, height: -1)
    private var lastDisplayID: UInt32 = 0
    private var isFocused = false
    private var currentTheme: TerminalTheme
    private var currentTerminalFontSize: CGFloat
    private var appliedTheme: TerminalTheme?
    private var appliedTerminalFontSize: CGFloat?
    private var surfaceConfig: ghostty_config_t?
    private var pendingText: [String] = []
    private let workingDirectory: String?
    private var lifecycle: TerminalSurfaceLifecycle = .initialized
    private var retainedUserdata: Unmanaged<TerminalSurface>?

    init(id: TerminalID, theme: TerminalTheme, terminalFontSize: CGFloat, workingDirectory: String?) {
        self.id = id
        self.currentTheme = theme
        self.currentTerminalFontSize = AppearancePreferences.clampedTerminalFontSize(terminalFontSize)
        self.workingDirectory = workingDirectory
        self.hostView = TerminalHostView()
        self.hostView.surface = self
    }

    var isReadyForInput: Bool {
        lifecycle == .attached && surface != nil && hostView.window != nil
    }

    var terminalTabDropAccentColor: NSColor {
        NSColor(currentTheme.accent)
    }

    nonisolated static func fromGhosttySurface(_ surface: ghostty_surface_t?) -> TerminalSurface? {
        guard let surface,
              let userdata = ghostty_surface_userdata(surface) else {
            return nil
        }
        return Unmanaged<TerminalSurface>.fromOpaque(userdata).takeUnretainedValue()
    }

    deinit {
        MainActor.assumeIsolated {
            close()
        }
    }

    func attachIfPossible() {
        guard lifecycle != .closing && lifecycle != .closed else { return }
        guard surface == nil else {
            syncGeometry()
            return
        }
        guard hostView.window != nil else { return }
        let signpost = ConductorSignpost.begin("surface-attach")
        defer { ConductorSignpost.end("surface-attach", signpost) }
        GhosttyAppRuntime.shared.ensureStarted(theme: currentTheme, terminalFontSize: currentTerminalFontSize)
        guard let app = GhosttyAppRuntime.shared.app else { return }

        var config = ghostty_surface_config_new()
        config.platform_tag = GHOSTTY_PLATFORM_MACOS
        config.platform = ghostty_platform_u(
            macos: ghostty_platform_macos_s(
                nsview: Unmanaged.passUnretained(hostView).toOpaque()
            )
        )
        let userdata = Unmanaged.passRetained(self)
        config.userdata = userdata.toOpaque()
        config.context = GHOSTTY_SURFACE_CONTEXT_WINDOW
        config.font_size = Float(currentTerminalFontSize)
        config.wait_after_command = false
        config.scale_factor = Double(hostView.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2)

        let command = "/bin/zsh"
        let directory = workingDirectory ?? FileManager.default.homeDirectoryForCurrentUser.path
        let terminalID = id.description
        let hookBridgePath = Bundle.main.executablePath ?? CommandLine.arguments.first ?? "Conductor"
        let terminalIDKey = "CONDUCTOR_TERMINAL_ID"
        let hookBridgeKey = "CONDUCTOR_HOOK_BRIDGE"
        command.withCString { commandPointer in
            directory.withCString { directoryPointer in
                terminalID.withCString { terminalIDPointer in
                    hookBridgePath.withCString { hookBridgePathPointer in
                        terminalIDKey.withCString { terminalIDKeyPointer in
                            hookBridgeKey.withCString { hookBridgeKeyPointer in
                                var envVars = [
                                    ghostty_env_var_s(key: terminalIDKeyPointer, value: terminalIDPointer),
                                    ghostty_env_var_s(key: hookBridgeKeyPointer, value: hookBridgePathPointer)
                                ]
                                envVars.withUnsafeMutableBufferPointer { envBuffer in
                                    config.command = commandPointer
                                    config.working_directory = directoryPointer
                                    config.env_vars = envBuffer.baseAddress
                                    config.env_var_count = envBuffer.count
                                    surface = ghostty_surface_new(app, &config)
                                }
                            }
                        }
                    }
                }
            }
        }

        guard let surface else {
            userdata.release()
            ConductorLog.terminal.error("Ghostty surface creation failed for \(self.id.description)")
            return
        }
        retainedUserdata = userdata

        syncGeometry(force: true)
        applyAppearance(theme: currentTheme, terminalFontSize: currentTerminalFontSize)
        setFocused(false, force: true)
        pendingText.forEach { sendText($0) }
        pendingText.removeAll(keepingCapacity: false)
        ghostty_surface_refresh(surface)
        lifecycle = .attached
        ConductorLog.terminal.info("Ghostty surface created for \(self.id.description)")
    }

    func applyTheme(_ theme: TerminalTheme) {
        applyAppearance(theme: theme, terminalFontSize: currentTerminalFontSize)
    }

    func applyTerminalFontSize(_ terminalFontSize: CGFloat) {
        applyAppearance(theme: currentTheme, terminalFontSize: terminalFontSize)
    }

    func applyAppearance(theme: TerminalTheme, terminalFontSize: CGFloat) {
        currentTheme = theme
        currentTerminalFontSize = AppearancePreferences.clampedTerminalFontSize(terminalFontSize)
        hostView.layer?.backgroundColor = NSColor(theme.terminalBackground).cgColor
        guard let surface,
              appliedTheme != theme || appliedTerminalFontSize != currentTerminalFontSize else { return }
        guard let config = GhosttyAppRuntime.shared.makeConfig(theme: theme, terminalFontSize: currentTerminalFontSize) else { return }
        if let surfaceConfig {
            ghostty_config_free(surfaceConfig)
        }
        surfaceConfig = config
        ghostty_surface_update_config(surface, config)
        ghostty_surface_refresh(surface)
        appliedTheme = theme
        appliedTerminalFontSize = currentTerminalFontSize
    }

    func syncGeometry(force: Bool = false) {
        guard let surface,
              let window = hostView.window else {
            return
        }

        let signpost = force ? ConductorSignpost.begin("surface-geometry-force") : nil
        defer {
            if let signpost {
                ConductorSignpost.end("surface-geometry-force", signpost)
            }
        }

        let backingScale = window.backingScaleFactor
        var didUpdateGeometry = false
        let scale = CGSize(width: backingScale, height: backingScale)
        if force || scale != lastScale {
            ghostty_surface_set_content_scale(surface, Double(backingScale), Double(backingScale))
            lastScale = scale
            didUpdateGeometry = true
        }

        if let displayID = window.screen?.conductorDisplayID,
           displayID != 0,
           force || displayID != lastDisplayID {
            ghostty_surface_set_display_id(surface, displayID)
            lastDisplayID = displayID
            didUpdateGeometry = true
        }

        let backingSize = hostView.convertToBacking(NSRect(origin: .zero, size: hostView.bounds.size)).size
        let width = max(1, UInt32(backingSize.width.rounded(.toNearestOrAwayFromZero)))
        let height = max(1, UInt32(backingSize.height.rounded(.toNearestOrAwayFromZero)))
        let pixelSize = CGSize(width: CGFloat(width), height: CGFloat(height))
        if force || pixelSize != lastPixelSize {
            ghostty_surface_set_size(surface, width, height)
            lastPixelSize = pixelSize
            didUpdateGeometry = true
        }

        if didUpdateGeometry {
            ghostty_surface_refresh(surface)
        }
    }

    func setFocused(_ focused: Bool, force: Bool = false) {
        guard force || focused != isFocused else { return }
        isFocused = focused
        guard let surface else { return }
        ghostty_surface_set_focus(surface, focused)
        ghostty_surface_refresh(surface)
    }

    func requestWorkspaceFocus() {
        onFocusRequest?(id)
    }

    @discardableResult
    func requestContextMenu(event: NSEvent, in view: NSView) -> Bool {
        onContextMenuRequest?(id, event, view) ?? false
    }

    @discardableResult
    func performTerminalTabDrop(draggedTerminalID: TerminalID, target: TerminalTabDropTarget) -> Bool {
        onTerminalTabDropRequest?(id, draggedTerminalID, target) ?? false
    }

    func canAcceptTerminalTabDrop() -> Bool {
        hasActiveTerminalTabDrag?() ?? false
    }

    func updateTerminalTabDropTarget(_ target: TerminalTabDropTarget?) {
        onTerminalTabDropTargetChange?(id, target)
    }

    func refresh() {
        guard let surface else { return }
        ghostty_surface_refresh(surface)
    }

    @discardableResult
    func performBindingAction(_ action: String) -> Bool {
        guard let surface else { return false }
        return action.withCString { pointer in
            ghostty_surface_binding_action(surface, pointer, UInt(action.utf8.count))
        }
    }

    @discardableResult
    func startSearchPrompt() -> Bool {
        performBindingAction("start_search")
    }

    @discardableResult
    func search(_ query: String) -> Bool {
        performBindingAction("search:\(Self.searchNeedle(from: query))")
    }

    @discardableResult
    func navigateSearch(previous: Bool) -> Bool {
        performBindingAction(previous ? "navigate_search:previous" : "navigate_search:next")
    }

    @discardableResult
    func endSearch() -> Bool {
        performBindingAction("end_search")
    }

    func sendText(_ text: String) {
        guard !text.isEmpty else { return }
        guard let surface else {
            pendingText.append(text)
            if pendingText.reduce(0, { $0 + $1.utf8.count }) > 1_048_576 {
                pendingText.removeAll(keepingCapacity: false)
            }
            return
        }
        text.withCString { pointer in
            ghostty_surface_text(surface, pointer, UInt(text.utf8.count))
        }
    }

    func sendPreedit(_ text: String?) {
        guard let surface else { return }
        guard let text, !text.isEmpty else {
            ghostty_surface_preedit(surface, nil, 0)
            return
        }
        text.withCString { pointer in
            ghostty_surface_preedit(surface, pointer, UInt(text.utf8.count))
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
        return NSRect(x: x, y: hostView.bounds.height - y, width: width, height: max(height, 18))
    }

    func completeClipboardRequest(location: ghostty_clipboard_e, state: UnsafeMutableRawPointer) {
        guard let surface else { return }
        let text = NSPasteboard.general.string(forType: .string) ?? ""
        text.withCString { pointer in
            ghostty_surface_complete_clipboard_request(surface, pointer, state, false)
        }
    }

    func closeFromGhostty(needsConfirmation: Bool) {
        ConductorLog.terminal.info("Ghostty requested close for \(self.id.description), confirm=\(needsConfirmation)")
        _ = GhosttyAppRuntime.shared.actionDelegate?.ghosttyRuntimeDidRequestClose(terminalID: id)
    }

    func close() {
        guard lifecycle != .closing && lifecycle != .closed else { return }
        lifecycle = .closing
        pendingText.removeAll(keepingCapacity: false)
        onFocusRequest = nil
        onContextMenuRequest = nil
        hostView.removeFromSuperview()
        guard let surface else {
            hostView.surface = nil
            lifecycle = .closed
            return
        }
        self.surface = nil
        hostView.surface = nil
        if let surfaceConfig {
            ghostty_config_free(surfaceConfig)
            self.surfaceConfig = nil
        }
        ghostty_surface_free(surface)
        retainedUserdata?.release()
        retainedUserdata = nil
        lifecycle = .closed
        ConductorLog.terminal.info("Ghostty surface freed for \(self.id.description)")
    }

    @discardableResult
    func forwardKeyEvent(
        _ event: NSEvent,
        action: ghostty_input_action_e,
        textOverride: String? = nil,
        composing: Bool = false
    ) -> Bool {
        guard let surface else { return false }
        var keyEvent = makeGhosttyKeyEvent(event, surface: surface)
        keyEvent.action = action
        keyEvent.composing = composing

        if action == GHOSTTY_ACTION_RELEASE {
            keyEvent.text = nil
            return ghostty_surface_key(surface, keyEvent)
        }

        guard !composing, let text = textOverride ?? printableText(for: event) else {
            keyEvent.text = nil
            return ghostty_surface_key(surface, keyEvent)
        }

        return text.withCString { pointer in
            keyEvent.text = pointer
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
        guard event.type == .keyDown, isReadyForInput, let surface else { return false }
        var keyEvent = makeGhosttyKeyEvent(event, surface: surface)
        var flags = ghostty_binding_flags_e(0)
        let text = printableText(for: event) ?? ""
        return text.withCString { pointer in
            keyEvent.text = pointer
            return ghostty_surface_key_is_binding(surface, keyEvent, &flags)
        }
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

    private func makeGhosttyKeyEvent(_ event: NSEvent, surface: ghostty_surface_t) -> ghostty_input_key_s {
        var keyEvent = ghostty_input_key_s()
        keyEvent.action = event.isARepeat ? GHOSTTY_ACTION_REPEAT : GHOSTTY_ACTION_PRESS
        keyEvent.mods = event.modifierFlags.ghosttyMods
        keyEvent.keycode = UInt32(event.keyCode)
        keyEvent.unshifted_codepoint = unshiftedCodepoint(from: event)
        keyEvent.composing = false
        keyEvent.text = nil
        let translatedMods = ghostty_surface_key_translation_mods(surface, event.modifierFlags.ghosttyMods)
        keyEvent.consumed_mods = consumedMods(from: translatedMods)
        return keyEvent
    }

    private func printableText(for event: NSEvent) -> String? {
        guard let characters = event.characters, !characters.isEmpty else { return nil }
        guard let scalar = characters.unicodeScalars.first else { return nil }
        if scalar.value >= 0xF700, scalar.value <= 0xF8FF { return nil }
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
        if mods.rawValue & GHOSTTY_MODS_SHIFT.rawValue != 0 { raw |= GHOSTTY_MODS_SHIFT.rawValue }
        if mods.rawValue & GHOSTTY_MODS_ALT.rawValue != 0 { raw |= GHOSTTY_MODS_ALT.rawValue }
        return ghostty_input_mods_e(rawValue: raw)
    }

    private func modifierAction(for event: NSEvent) -> ghostty_input_action_e? {
        switch event.keyCode {
        case 0x39:
            event.modifierFlags.contains(.capsLock) ? GHOSTTY_ACTION_PRESS : GHOSTTY_ACTION_RELEASE
        case 0x38, 0x3C:
            event.modifierFlags.contains(.shift) ? GHOSTTY_ACTION_PRESS : GHOSTTY_ACTION_RELEASE
        case 0x3B, 0x3E:
            event.modifierFlags.contains(.control) ? GHOSTTY_ACTION_PRESS : GHOSTTY_ACTION_RELEASE
        case 0x3A, 0x3D:
            event.modifierFlags.contains(.option) ? GHOSTTY_ACTION_PRESS : GHOSTTY_ACTION_RELEASE
        case 0x37, 0x36:
            event.modifierFlags.contains(.command) ? GHOSTTY_ACTION_PRESS : GHOSTTY_ACTION_RELEASE
        default:
            nil
        }
    }

    private static func searchNeedle(from query: String) -> String {
        query
            .replacingOccurrences(of: "\u{0}", with: "")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }
}

private enum TerminalSurfaceLifecycle {
    case initialized
    case attached
    case closing
    case closed
}

private extension NSScreen {
    var conductorDisplayID: UInt32 {
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
