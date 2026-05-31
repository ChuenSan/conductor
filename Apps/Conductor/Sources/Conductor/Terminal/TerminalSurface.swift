import AppKit
import ConductorCore
import Foundation
@preconcurrency import GhosttyKit

struct TerminalScrollbarState: Equatable, Sendable {
    let total: UInt64
    let offset: UInt64
    let len: UInt64

    var hasScrollback: Bool {
        total > len
    }
}

extension Notification.Name {
    static let terminalSurfaceDidUpdateScrollbar = Notification.Name("terminalSurfaceDidUpdateScrollbar")
    static let terminalSurfaceDidUpdateCellSize = Notification.Name("terminalSurfaceDidUpdateCellSize")
    static let terminalSurfaceDidReceiveWheelScroll = Notification.Name("terminalSurfaceDidReceiveWheelScroll")
}

@MainActor
final class TerminalSurface {
    private struct RetainedCString {
        let pointer: UnsafeMutablePointer<CChar>
        let bytes: Int
    }

    let id: TerminalID
    let hostView: TerminalHostView
    var onFocusRequest: (@MainActor (TerminalID) -> Void)?
    var onUserActivity: (@MainActor (TerminalID) -> Void)?
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
    private var appliedRendererPreferences: TerminalRendererPreferences?
    private var surfaceConfig: ghostty_config_t?
    private var pendingText: [String] = []
    private var pendingSnapshotReplay: String?
    private let workingDirectory: String?
    private var lifecycle: TerminalSurfaceLifecycle = .initialized
    private var retainedUserdata: Unmanaged<TerminalSurface>?
    private var retainedInputCStrings: [RetainedCString] = []
    private var retainedInputBytes = 0
    private var inputEventCount = 0
    private let maxRetainedInputCStrings = 4096
    private let maxRetainedInputBytes = 8 * 1024 * 1024
    private(set) var scrollbarState: TerminalScrollbarState?
    private(set) var cellSize: CGSize = .zero
    private var pendingScrollbarState: TerminalScrollbarState?
    private var scrollbarFlushScheduled = false

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

        let rendererPreferences = TerminalAppearanceRuntime.renderer
        let command = rendererPreferences.activeGhosttyOverrideValue(for: "initial-command") ?? "/bin/zsh"
        let configuredDirectory = rendererPreferences.activeGhosttyOverrideValue(for: "working-directory")
        let directory = Self.validWorkingDirectory(configuredDirectory)
            ?? workingDirectory
            ?? FileManager.default.homeDirectoryForCurrentUser.path
        let terminalID = id.description
        let hookBridgePath = Bundle.main.executablePath ?? CommandLine.arguments.first ?? "Conductor"
        let terminalIDKey = "CONDUCTOR_TERMINAL_ID"
        let hookBridgeKey = "CONDUCTOR_HOOK_BRIDGE"
        let proxyEnvironment = rendererPreferences.proxy.environment
        command.withCString { commandPointer in
            directory.withCString { directoryPointer in
                terminalID.withCString { terminalIDPointer in
                    hookBridgePath.withCString { hookBridgePathPointer in
                        terminalIDKey.withCString { terminalIDKeyPointer in
                            hookBridgeKey.withCString { hookBridgeKeyPointer in
                                var envVars: [ghostty_env_var_s] = [
                                    ghostty_env_var_s(key: terminalIDKeyPointer, value: terminalIDPointer),
                                    ghostty_env_var_s(key: hookBridgeKeyPointer, value: hookBridgePathPointer)
                                ]
                                var proxyStorage: [(UnsafeMutablePointer<CChar>, UnsafeMutablePointer<CChar>)] = []
                                proxyStorage.reserveCapacity(proxyEnvironment.count)
                                for (key, value) in proxyEnvironment.sorted(by: { $0.key < $1.key }) {
                                    guard let keyPointer = strdup(key),
                                          let valuePointer = strdup(value) else {
                                        continue
                                    }
                                    proxyStorage.append((keyPointer, valuePointer))
                                    envVars.append(ghostty_env_var_s(key: keyPointer, value: valuePointer))
                                }
                                defer {
                                    for (keyPointer, valuePointer) in proxyStorage {
                                        free(keyPointer)
                                        free(valuePointer)
                                    }
                                }
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
        replayPendingSnapshot(into: surface)
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
        let rendererPreferences = TerminalAppearanceRuntime.renderer
        let backgroundColor = NSColor(theme.terminalBackground)
            .usingColorSpace(.sRGB)?
            .withAlphaComponent(rendererPreferences.backgroundOpacity)
            .cgColor ?? NSColor(theme.terminalBackground).cgColor
        hostView.layer?.backgroundColor = backgroundColor
        guard let surface,
              appliedTheme != theme ||
              appliedTerminalFontSize != currentTerminalFontSize ||
              appliedRendererPreferences != rendererPreferences else { return }
        guard let config = GhosttyAppRuntime.shared.makeConfig(theme: theme, terminalFontSize: currentTerminalFontSize) else { return }
        if let surfaceConfig {
            ghostty_config_free(surfaceConfig)
        }
        surfaceConfig = config
        ghostty_surface_update_config(surface, config)
        ghostty_surface_refresh(surface)
        appliedTheme = theme
        appliedTerminalFontSize = currentTerminalFontSize
        appliedRendererPreferences = rendererPreferences
    }

    @discardableResult
    func syncGeometry(force: Bool = false) -> Bool {
        guard let surface,
              let window = hostView.window else {
            return false
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
        return didUpdateGeometry
    }

    private static func validWorkingDirectory(_ path: String?) -> String? {
        guard let path, !path.isEmpty else { return nil }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return nil
        }
        return path
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
        onUserActivity?(id)
    }

    func recordUserActivity() {
        onUserActivity?(id)
    }

    func enqueueScrollbarUpdate(_ scrollbar: TerminalScrollbarState) {
        pendingScrollbarState = scrollbar
        guard !scrollbarFlushScheduled else { return }
        scrollbarFlushScheduled = true
        Task { @MainActor [weak self] in
            self?.flushPendingScrollbar()
        }
    }

    private func flushPendingScrollbar() {
        scrollbarFlushScheduled = false
        guard let scrollbar = pendingScrollbarState else { return }
        pendingScrollbarState = nil
        guard scrollbarState != scrollbar else { return }
        scrollbarState = scrollbar
        NotificationCenter.default.post(
            name: .terminalSurfaceDidUpdateScrollbar,
            object: self,
            userInfo: ["scrollbar": scrollbar]
        )
    }

    func updateCellSize(width: UInt32, height: UInt32) {
        let next = CGSize(width: CGFloat(width), height: CGFloat(height))
        guard cellSize != next else { return }
        cellSize = next
        NotificationCenter.default.post(name: .terminalSurfaceDidUpdateCellSize, object: self)
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

    /// Reads only the visible viewport (not the full scrollback buffer). This is
    /// cheap even when the session has tens of thousands of lines of history,
    /// which matters because agent-state polling calls it twice a second per
    /// terminal. `GHOSTTY_POINT_SCREEN` would instead pin to the extremes of the
    /// entire history and stall the main thread on large buffers.
    func visibleText() -> String? {
        guard let surface else { return nil }
        let size = ghostty_surface_size(surface)
        guard size.columns > 0, size.rows > 0 else { return nil }

        let selection = ghostty_selection_s(
            top_left: ghostty_point_s(
                tag: GHOSTTY_POINT_VIEWPORT,
                coord: GHOSTTY_POINT_COORD_TOP_LEFT,
                x: 0,
                y: 0
            ),
            bottom_right: ghostty_point_s(
                tag: GHOSTTY_POINT_VIEWPORT,
                coord: GHOSTTY_POINT_COORD_BOTTOM_RIGHT,
                x: UInt32(size.columns - 1),
                y: UInt32(size.rows - 1)
            ),
            rectangle: false
        )
        var text = ghostty_text_s()
        guard ghostty_surface_read_text(surface, selection, &text) else { return nil }
        defer { ghostty_surface_free_text(surface, &text) }
        guard let pointer = text.text, text.text_len > 0 else { return "" }
        return String(decoding: UnsafeRawBufferPointer(start: pointer, count: Int(text.text_len)), as: UTF8.self)
    }

    /// Captures the on-screen scrollback text for a session snapshot, trimmed to
    /// the last `maxLines` lines / `maxBytes` bytes so persistence stays small.
    /// Reads the full history buffer (`GHOSTTY_POINT_SCREEN`); only called at quit,
    /// never on the polling path.
    func capturedScrollbackText(maxLines: Int = 400, maxBytes: Int = 128 * 1024) -> String? {
        guard let surface else { return nil }
        let size = ghostty_surface_size(surface)
        guard size.columns > 0, size.rows > 0 else { return nil }

        let selection = ghostty_selection_s(
            top_left: ghostty_point_s(
                tag: GHOSTTY_POINT_SCREEN,
                coord: GHOSTTY_POINT_COORD_TOP_LEFT,
                x: 0,
                y: 0
            ),
            bottom_right: ghostty_point_s(
                tag: GHOSTTY_POINT_SCREEN,
                coord: GHOSTTY_POINT_COORD_BOTTOM_RIGHT,
                x: UInt32(size.columns - 1),
                y: UInt32(size.rows - 1)
            ),
            rectangle: false
        )
        var text = ghostty_text_s()
        guard ghostty_surface_read_text(surface, selection, &text) else { return nil }
        defer { ghostty_surface_free_text(surface, &text) }
        guard let pointer = text.text, text.text_len > 0 else { return nil }
        let raw = String(decoding: UnsafeRawBufferPointer(start: pointer, count: Int(text.text_len)), as: UTF8.self)
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var lines = trimmed.components(separatedBy: "\n")
        if lines.count > maxLines {
            lines = Array(lines.suffix(maxLines))
        }
        var result = lines.joined(separator: "\n")
        if result.utf8.count > maxBytes {
            result = String(decoding: result.utf8.suffix(maxBytes), as: UTF8.self)
        }
        return result
    }

    /// Captures the on-screen scrollback as a VT/ANSI byte stream (colors, cursor,
    /// wide-char layout preserved) via libghostty's `write_screen_file:copy,vt`
    /// action, which writes a temp file and puts its path on the pasteboard. The
    /// user's pasteboard is saved and restored around the call. Returns nil on any
    /// failure so the caller can fall back to plain-text capture.
    func capturedScrollbackVT(maxLines: Int = 400, maxBytes: Int = 128 * 1024) -> String? {
        guard surface != nil else { return nil }
        let pasteboard = NSPasteboard.general

        let savedItems: [NSPasteboardItem] = (pasteboard.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    copy.setData(data, forType: type)
                }
            }
            return copy
        }
        defer {
            pasteboard.clearContents()
            if !savedItems.isEmpty {
                pasteboard.writeObjects(savedItems)
            }
        }

        pasteboard.clearContents()
        guard performBindingAction("write_screen_file:copy,vt") else { return nil }
        guard let raw = pasteboard.string(forType: .string),
              let path = ExportedScreenPath.normalized(raw) else { return nil }

        let fileURL = URL(fileURLWithPath: path)
        defer {
            if ExportedScreenPath.isUnderTemporaryDirectory(fileURL) {
                try? FileManager.default.removeItem(at: fileURL)
            }
        }
        guard let data = try? Data(contentsOf: fileURL), !data.isEmpty else { return nil }

        let text = TerminalScrollbackSanitizer.truncate(
            String(decoding: data, as: UTF8.self),
            maxLines: maxLines,
            maxBytes: maxBytes
        )
        return text.isEmpty ? nil : text
    }

    /// Queues prior-session output to be painted onto the screen once the surface
    /// attaches. This writes to the display via the program-output path, NOT the
    /// shell input path, so nothing is ever executed.
    func setSnapshotReplay(_ text: String?) {
        guard let text, !text.isEmpty else { return }
        pendingSnapshotReplay = text
    }

    private func replayPendingSnapshot(into surface: ghostty_surface_t) {
        guard let snapshot = pendingSnapshotReplay else { return }
        pendingSnapshotReplay = nil
        // Replay the prior session's VT bytes through ghostty's own parser
        // (process_output is the program-output path: inert, never executed).
        // No marker lines are injected — the restored history keeps its original
        // colors and reads as real scrollback. See spec decision D2.
        let payload = TerminalScrollbackSanitizer.prepareForReplay(snapshot)
        replayOutput(payload, into: surface)
    }

    private func replayOutput(_ text: String, into surface: ghostty_surface_t) {
        guard !text.isEmpty else { return }
        let bytes = Array(text.utf8)
        bytes.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            base.withMemoryRebound(to: CChar.self, capacity: buffer.count) { pointer in
                ghostty_surface_process_output(surface, pointer, UInt(buffer.count))
            }
        }
    }

    @discardableResult
    func performBindingAction(_ action: String) -> Bool {
        guard let surface else { return false }
        guard let retained = retainedCString(for: action) else { return false }
        return ghostty_surface_binding_action(surface, UnsafePointer(retained.pointer), UInt(action.utf8.count))
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
        guard let retained = retainedCString(for: text) else { return }
        recordInputEvent(kind: "text", bytes: text.utf8.count)
        ghostty_surface_text(surface, UnsafePointer(retained.pointer), UInt(text.utf8.count))
    }

    func sendPreedit(_ text: String?) {
        guard let surface else { return }
        guard let text, !text.isEmpty else {
            ghostty_surface_preedit(surface, nil, 0)
            return
        }
        guard let retained = retainedCString(for: text) else { return }
        ghostty_surface_preedit(surface, UnsafePointer(retained.pointer), UInt(text.utf8.count))
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
        guard let retained = retainedCString(for: text) else { return }
        ghostty_surface_complete_clipboard_request(surface, UnsafePointer(retained.pointer), state, false)
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
        onUserActivity = nil
        onContextMenuRequest = nil
        onTerminalTabDropRequest = nil
        onTerminalTabDropTargetChange = nil
        hasActiveTerminalTabDrag = nil
        hostView.removeFromSuperview()
        guard let surface else {
            hostView.surface = nil
            releaseRetainedInputCStrings()
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
        releaseRetainedInputCStrings()
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

        guard let retained = retainedCString(for: text) else { return false }
        recordInputEvent(kind: "key", bytes: text.utf8.count)
        keyEvent.text = UnsafePointer(retained.pointer)
        return ghostty_surface_key(surface, keyEvent)
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

    func scroll(deltaX: CGFloat, deltaY: CGFloat, precise: Bool, momentumPhase: NSEvent.Phase) {
        guard let surface else { return }
        NotificationCenter.default.post(name: .terminalSurfaceDidReceiveWheelScroll, object: self)
        var x = Double(deltaX)
        var y = Double(deltaY)
        if precise {
            x *= 2
            y *= 2
        }
        ghostty_surface_mouse_scroll(surface, x, y, Self.scrollMods(precise: precise, momentumPhase: momentumPhase))
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

    private func retainedCString(for text: String) -> RetainedCString? {
        guard let pointer = strdup(text) else { return nil }
        let retained = RetainedCString(pointer: pointer, bytes: text.utf8.count + 1)
        retainedInputCStrings.append(retained)
        retainedInputBytes += retained.bytes
        pruneRetainedInputCStrings()
        return retained
    }

    private func pruneRetainedInputCStrings() {
        while retainedInputCStrings.count > maxRetainedInputCStrings ||
            (retainedInputBytes > maxRetainedInputBytes && retainedInputCStrings.count > 1) {
            let removed = retainedInputCStrings.removeFirst()
            retainedInputBytes -= removed.bytes
            free(removed.pointer)
        }
    }

    private func releaseRetainedInputCStrings() {
        for retained in retainedInputCStrings {
            free(retained.pointer)
        }
        retainedInputCStrings.removeAll(keepingCapacity: false)
        retainedInputBytes = 0
    }

    private func recordInputEvent(kind: String, bytes: Int) {
        inputEventCount &+= 1
        guard inputEventCount == 1 || inputEventCount.isMultiple(of: 128) else { return }
        ConductorDiagnostics.record(
            "terminal-input",
            fields: [
                "terminal": id.description,
                "kind": kind,
                "events": inputEventCount,
                "bytes": bytes,
                "retained": retainedInputCStrings.count,
                "retainedBytes": retainedInputBytes
            ]
        )
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

    private static func scrollMods(precise: Bool, momentumPhase: NSEvent.Phase) -> ghostty_input_scroll_mods_t {
        var raw: Int32 = precise ? 1 : 0
        raw |= momentumRawValue(for: momentumPhase) << 1
        return ghostty_input_scroll_mods_t(raw)
    }

    private static func momentumRawValue(for phase: NSEvent.Phase) -> Int32 {
        switch phase {
        case .began:
            return Int32(GHOSTTY_MOUSE_MOMENTUM_BEGAN.rawValue)
        case .stationary:
            return Int32(GHOSTTY_MOUSE_MOMENTUM_STATIONARY.rawValue)
        case .changed:
            return Int32(GHOSTTY_MOUSE_MOMENTUM_CHANGED.rawValue)
        case .ended:
            return Int32(GHOSTTY_MOUSE_MOMENTUM_ENDED.rawValue)
        case .cancelled:
            return Int32(GHOSTTY_MOUSE_MOMENTUM_CANCELLED.rawValue)
        case .mayBegin:
            return Int32(GHOSTTY_MOUSE_MOMENTUM_MAY_BEGIN.rawValue)
        default:
            return Int32(GHOSTTY_MOUSE_MOMENTUM_NONE.rawValue)
        }
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

}
