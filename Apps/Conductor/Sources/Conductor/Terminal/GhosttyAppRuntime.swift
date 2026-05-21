import AppKit
import ConductorCore
import Foundation
@preconcurrency import GhosttyKit

@MainActor
protocol GhosttyAppRuntimeActionDelegate: AnyObject {
    func ghosttyRuntimeDidRequestNewTab(terminalID: TerminalID) -> Bool
    func ghosttyRuntimeDidRequestMoveTab(terminalID: TerminalID, amount: Int) -> Bool
    func ghosttyRuntimeDidRequestSelectTab(terminalID: TerminalID, offset: Int?, last: Bool) -> Bool
    func ghosttyRuntimeDidRequestCommandPalette(terminalID: TerminalID) -> Bool
    func ghosttyRuntimeDidRequestSplit(terminalID: TerminalID, direction: SplitDirection) -> Bool
    func ghosttyRuntimeDidRequestFocus(terminalID: TerminalID, direction: FocusDirection) -> Bool
    func ghosttyRuntimeDidRequestResize(terminalID: TerminalID, direction: ResizeSplitDirection, amount: UInt16) -> Bool
    func ghosttyRuntimeDidRequestEqualize(terminalID: TerminalID) -> Bool
    func ghosttyRuntimeDidRequestToggleZoom(terminalID: TerminalID) -> Bool
    func ghosttyRuntimeDidSetTitle(terminalID: TerminalID, title: String) -> Bool
    func ghosttyRuntimeDidSetWorkingDirectory(terminalID: TerminalID, workingDirectory: String) -> Bool
    func ghosttyRuntimeDidReceiveNotification(terminalID: TerminalID, title: String, body: String) -> Bool
    func ghosttyRuntimeDidRingBell(terminalID: TerminalID) -> Bool
    func ghosttyRuntimeDidUpdateProgress(terminalID: TerminalID, kind: TerminalProgressKind, progress: Int?) -> Bool
    func ghosttyRuntimeDidFinishCommand(terminalID: TerminalID, exitCode: Int?, durationNanoseconds: UInt64) -> Bool
    func ghosttyRuntimeDidUpdateCellSize(terminalID: TerminalID, width: UInt32, height: UInt32) -> Bool
    func ghosttyRuntimeDidUpdateSearch(terminalID: TerminalID, active: Bool, needle: String?, total: Int?, selected: Int?) -> Bool
    func ghosttyRuntimeDidSetReadonly(terminalID: TerminalID, readonly: Bool) -> Bool
    func ghosttyRuntimeDidRequestClose(terminalID: TerminalID) -> Bool
    func ghosttyRuntimeDidRequestCloseTabs(terminalID: TerminalID, scope: TabCloseScope) -> Bool
    func ghosttyRuntimeDidRequestOpenURL(terminalID: TerminalID?, url: URL) -> Bool
}

@MainActor
final class GhosttyAppRuntime {
    static let shared = GhosttyAppRuntime()

    private(set) var app: ghostty_app_t?
    var actionDelegate: GhosttyAppRuntimeActionDelegate?
    private var config: ghostty_config_t?
    private var tickScheduled = false

    private init() {}

    func ensureStarted(theme: TerminalTheme, terminalFontSize: CGFloat) {
        guard app == nil else { return }

        if getenv("NO_COLOR") != nil {
            unsetenv("NO_COLOR")
        }
        let resourcesDir = Self.configureGhosttyResourcesEnvironment()

        let initResult = ghostty_init(UInt(CommandLine.argc), CommandLine.unsafeArgv)
        guard initResult == GHOSTTY_SUCCESS else {
            ConductorLog.terminal.error("ghostty_init failed: \(initResult)")
            return
        }

        guard let config = makeConfig(theme: theme, terminalFontSize: terminalFontSize) else {
            ConductorLog.terminal.error("Ghostty config allocation failed")
            return
        }

        var runtimeConfig = ghostty_runtime_config_s()
        runtimeConfig.userdata = Unmanaged.passUnretained(self).toOpaque()
        runtimeConfig.supports_selection_clipboard = true
        runtimeConfig.wakeup_cb = { userdata in
            guard let userdata else { return }
            let runtime = Unmanaged<GhosttyAppRuntime>.fromOpaque(userdata).takeUnretainedValue()
            Task { @MainActor in
                runtime.scheduleTick()
            }
        }
        runtimeConfig.action_cb = { userdata, target, action in
            guard let userdata else { return false }
            let runtime = Unmanaged<GhosttyAppRuntime>.fromOpaque(userdata).takeUnretainedValue()
            return runtime.handleAction(target: target, action: action)
        }
        runtimeConfig.read_clipboard_cb = { userdata, location, state in
            guard let userdata, let state else { return false }
            let surface = Unmanaged<TerminalSurface>.fromOpaque(userdata).takeUnretainedValue()
            let retainedSurface = Unmanaged.passRetained(surface)
            Task { @MainActor in
                let surface = retainedSurface.takeRetainedValue()
                surface.completeClipboardRequest(location: location, state: state)
            }
            return true
        }
        runtimeConfig.write_clipboard_cb = { _, _, content, count, _ in
            guard let content, count > 0 else { return }
            let items = UnsafeBufferPointer(start: content, count: count)
            for item in items {
                guard let data = item.data else { continue }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(String(cString: data), forType: .string)
                return
            }
        }
        runtimeConfig.close_surface_cb = { userdata, needsConfirmClose in
            guard let userdata else { return }
            let surface = Unmanaged<TerminalSurface>.fromOpaque(userdata).takeUnretainedValue()
            let terminalID = surface.id
            Task { @MainActor in
                ConductorLog.terminal.info(
                    "Ghostty requested close for \(terminalID.description), confirm=\(needsConfirmClose)"
                )
                _ = GhosttyAppRuntime.shared.actionDelegate?.ghosttyRuntimeDidRequestClose(terminalID: terminalID)
            }
        }

        guard let created = ghostty_app_new(&runtimeConfig, config) else {
            ConductorLog.terminal.error("ghostty_app_new failed")
            logDiagnostics(config)
            ghostty_config_free(config)
            return
        }

        self.app = created
        self.config = config
        ghostty_app_set_focus(created, NSApp.isActive)
        ConductorLog.terminal.info("Ghostty runtime started resources=\(resourcesDir ?? "(unavailable)")")
    }

    func makeConfig(theme: TerminalTheme, terminalFontSize: CGFloat) -> ghostty_config_t? {
        guard let config = ghostty_config_new() else { return nil }
        let text = TerminalGhosttyConfigBuilder.configText(
            theme: theme,
            terminalFontSize: terminalFontSize,
            renderer: TerminalAppearanceRuntime.renderer
        )
        text.withCString { pointer in
            ghostty_config_load_string(config, pointer, UInt(text.utf8.count), "conductor-config")
        }
        ghostty_config_finalize(config)
        return config
    }

    private static func configureGhosttyResourcesEnvironment() -> String? {
        let key = "GHOSTTY_RESOURCES_DIR"
        let lockedResourcesPath = lockedGhosttyResourcesPath()
        if let existing = getenv(key).map({ String(cString: $0) }),
           !existing.isEmpty,
           existing != lockedResourcesPath {
            ConductorLog.terminal.info(
                "Ignoring external GHOSTTY_RESOURCES_DIR=\(existing); locked to \(lockedResourcesPath ?? "(unavailable)")"
            )
        }

        guard let lockedResourcesPath else {
            unsetenv(key)
            ConductorLog.terminal.error("Locked Ghostty resources path is unavailable; shell integration cannot be injected")
            return nil
        }

        setenv(key, lockedResourcesPath, 1)
        return lockedResourcesPath
    }

    private static func lockedGhosttyResourcesPath() -> String? {
        let bundlePath = Bundle.main.resourceURL?
            .appendingPathComponent("ghostty")
            .path(percentEncoded: false)
        if let bundlePath, hasGhosttyShellIntegration(at: bundlePath) {
            return bundlePath
        }

        let developmentPath = "/Applications/Ghostty.app/Contents/Resources/ghostty"
        if hasGhosttyShellIntegration(at: developmentPath) {
            return developmentPath
        }

        return nil
    }

    private static func hasGhosttyShellIntegration(at path: String) -> Bool {
        var isDirectory: ObjCBool = false
        let zshPath = URL(fileURLWithPath: path)
            .appendingPathComponent("shell-integration/zsh/.zshenv")
            .path
        return FileManager.default.fileExists(atPath: zshPath, isDirectory: &isDirectory) && !isDirectory.boolValue
    }

    func setAppFocus(_ focused: Bool) {
        guard let app else { return }
        ghostty_app_set_focus(app, focused)
    }

    private func scheduleTick() {
        guard !tickScheduled else { return }
        tickScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.tickScheduled = false
            if let app = self.app {
                ghostty_app_tick(app)
            }
        }
    }

    private nonisolated func dispatchToDelegate(
        _ operation: @escaping @MainActor (GhosttyAppRuntimeActionDelegate?) -> Void
    ) {
        Task { @MainActor in
            operation(GhosttyAppRuntime.shared.actionDelegate)
        }
    }

    private nonisolated func openURL(_ url: URL, terminalID: TerminalID?) {
        Task { @MainActor in
            let handled = GhosttyAppRuntime.shared.actionDelegate?
                .ghosttyRuntimeDidRequestOpenURL(terminalID: terminalID, url: url) ?? false
            guard !handled else { return }
            guard !url.isFileURL else {
                let fileURL = url.standardizedFileURL
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    NSWorkspace.shared.activateFileViewerSelecting([fileURL])
                } else {
                    ConductorLog.terminal.warning("Ignoring unhandled local file URL: \(fileURL.path)")
                }
                return
            }
            NSWorkspace.shared.open(url)
        }
    }

    private nonisolated func handleAction(target: ghostty_target_s, action: ghostty_action_s) -> Bool {
        guard target.tag == GHOSTTY_TARGET_SURFACE else {
            if action.tag == GHOSTTY_ACTION_OPEN_URL,
               let url = URL(ghosttyOpenURL: action.action.open_url) {
                openURL(url, terminalID: nil)
                return true
            }
            ConductorLog.terminal.debug("Unhandled Ghostty app action=\(action.tag.rawValue)")
            return false
        }

        switch action.tag {
        case GHOSTTY_ACTION_OPEN_URL:
            guard let url = URL(ghosttyOpenURL: action.action.open_url) else { return false }
            let terminalID = TerminalSurface.fromGhosttySurface(target.target.surface)?.id
            openURL(url, terminalID: terminalID)
            return true
        case GHOSTTY_ACTION_NEW_WINDOW, GHOSTTY_ACTION_NEW_TAB:
            guard let terminal = TerminalSurface.fromGhosttySurface(target.target.surface) else { return false }
            let terminalID = terminal.id
            dispatchToDelegate { delegate in
                _ = delegate?.ghosttyRuntimeDidRequestNewTab(terminalID: terminalID)
            }
            return true
        case GHOSTTY_ACTION_MOVE_TAB:
            guard let terminal = TerminalSurface.fromGhosttySurface(target.target.surface) else { return false }
            let terminalID = terminal.id
            let amount = Int(action.action.move_tab.amount)
            dispatchToDelegate { delegate in
                _ = delegate?.ghosttyRuntimeDidRequestMoveTab(terminalID: terminalID, amount: amount)
            }
            return true
        case GHOSTTY_ACTION_GOTO_TAB:
            guard let terminal = TerminalSurface.fromGhosttySurface(target.target.surface) else { return false }
            let terminalID = terminal.id
            let gotoTab = action.action.goto_tab
            let offset: Int?
            let last: Bool
            switch gotoTab {
            case GHOSTTY_GOTO_TAB_PREVIOUS:
                offset = -1
                last = false
            case GHOSTTY_GOTO_TAB_NEXT:
                offset = 1
                last = false
            case GHOSTTY_GOTO_TAB_LAST:
                offset = nil
                last = true
            default:
                offset = Int(gotoTab.rawValue)
                last = false
            }
            dispatchToDelegate { delegate in
                _ = delegate?.ghosttyRuntimeDidRequestSelectTab(terminalID: terminalID, offset: offset, last: last)
            }
            return true
        case GHOSTTY_ACTION_TOGGLE_COMMAND_PALETTE:
            guard let terminal = TerminalSurface.fromGhosttySurface(target.target.surface) else { return false }
            let terminalID = terminal.id
            dispatchToDelegate { delegate in
                _ = delegate?.ghosttyRuntimeDidRequestCommandPalette(terminalID: terminalID)
            }
            return true
        case GHOSTTY_ACTION_NEW_SPLIT:
            guard let terminal = TerminalSurface.fromGhosttySurface(target.target.surface),
                  let direction = SplitDirection(ghosttyDirection: action.action.new_split) else {
                return false
            }
            let terminalID = terminal.id
            dispatchToDelegate { delegate in
                _ = delegate?.ghosttyRuntimeDidRequestSplit(terminalID: terminalID, direction: direction)
            }
            return true
        case GHOSTTY_ACTION_GOTO_SPLIT:
            guard let terminal = TerminalSurface.fromGhosttySurface(target.target.surface),
                  let direction = FocusDirection(ghosttyDirection: action.action.goto_split) else {
                return false
            }
            let terminalID = terminal.id
            dispatchToDelegate { delegate in
                _ = delegate?.ghosttyRuntimeDidRequestFocus(terminalID: terminalID, direction: direction)
            }
            return true
        case GHOSTTY_ACTION_RESIZE_SPLIT:
            guard let terminal = TerminalSurface.fromGhosttySurface(target.target.surface),
                  let direction = ResizeSplitDirection(ghosttyDirection: action.action.resize_split.direction) else {
                return false
            }
            let terminalID = terminal.id
            let amount = action.action.resize_split.amount
            dispatchToDelegate { delegate in
                _ = delegate?.ghosttyRuntimeDidRequestResize(terminalID: terminalID, direction: direction, amount: amount)
            }
            return true
        case GHOSTTY_ACTION_EQUALIZE_SPLITS:
            guard let terminal = TerminalSurface.fromGhosttySurface(target.target.surface) else { return false }
            let terminalID = terminal.id
            dispatchToDelegate { delegate in
                _ = delegate?.ghosttyRuntimeDidRequestEqualize(terminalID: terminalID)
            }
            return true
        case GHOSTTY_ACTION_TOGGLE_SPLIT_ZOOM:
            guard let terminal = TerminalSurface.fromGhosttySurface(target.target.surface) else { return false }
            let terminalID = terminal.id
            dispatchToDelegate { delegate in
                _ = delegate?.ghosttyRuntimeDidRequestToggleZoom(terminalID: terminalID)
            }
            return true
        case GHOSTTY_ACTION_SET_TITLE:
            guard let terminal = TerminalSurface.fromGhosttySurface(target.target.surface),
                  let titlePointer = action.action.set_title.title else {
                return false
            }
            let terminalID = terminal.id
            let title = String(cString: titlePointer)
            dispatchToDelegate { delegate in
                _ = delegate?.ghosttyRuntimeDidSetTitle(terminalID: terminalID, title: title)
            }
            return true
        case GHOSTTY_ACTION_SET_TAB_TITLE:
            guard let terminal = TerminalSurface.fromGhosttySurface(target.target.surface),
                  let titlePointer = action.action.set_tab_title.title else {
                return false
            }
            let terminalID = terminal.id
            let title = String(cString: titlePointer)
            dispatchToDelegate { delegate in
                _ = delegate?.ghosttyRuntimeDidSetTitle(terminalID: terminalID, title: title)
            }
            return true
        case GHOSTTY_ACTION_PWD:
            guard let terminal = TerminalSurface.fromGhosttySurface(target.target.surface),
                  let pwdPointer = action.action.pwd.pwd else {
                return true
            }
            let terminalID = terminal.id
            let workingDirectory = String(cString: pwdPointer)
            dispatchToDelegate { delegate in
                _ = delegate?.ghosttyRuntimeDidSetWorkingDirectory(
                    terminalID: terminalID,
                    workingDirectory: workingDirectory
                )
            }
            return true
        case GHOSTTY_ACTION_DESKTOP_NOTIFICATION:
            guard let terminal = TerminalSurface.fromGhosttySurface(target.target.surface) else { return true }
            let terminalID = terminal.id
            let title = action.action.desktop_notification.title.map { String(cString: $0) } ?? ""
            let body = action.action.desktop_notification.body.map { String(cString: $0) } ?? ""
            dispatchToDelegate { delegate in
                _ = delegate?.ghosttyRuntimeDidReceiveNotification(terminalID: terminalID, title: title, body: body)
            }
            return true
        case GHOSTTY_ACTION_PROGRESS_REPORT:
            guard let terminal = TerminalSurface.fromGhosttySurface(target.target.surface),
                  let kind = TerminalProgressKind(ghosttyState: action.action.progress_report.state) else {
                return true
            }
            let terminalID = terminal.id
            let rawProgress = action.action.progress_report.progress
            let progress = rawProgress >= 0 ? Int(rawProgress) : nil
            dispatchToDelegate { delegate in
                _ = delegate?.ghosttyRuntimeDidUpdateProgress(terminalID: terminalID, kind: kind, progress: progress)
            }
            return true
        case GHOSTTY_ACTION_COMMAND_FINISHED:
            guard let terminal = TerminalSurface.fromGhosttySurface(target.target.surface) else { return true }
            let terminalID = terminal.id
            let rawExitCode = action.action.command_finished.exit_code
            let exitCode = rawExitCode >= 0 ? Int(rawExitCode) : nil
            let duration = action.action.command_finished.duration
            dispatchToDelegate { delegate in
                _ = delegate?.ghosttyRuntimeDidFinishCommand(
                    terminalID: terminalID,
                    exitCode: exitCode,
                    durationNanoseconds: duration
                )
            }
            return true
        case GHOSTTY_ACTION_START_SEARCH:
            guard let terminal = TerminalSurface.fromGhosttySurface(target.target.surface) else { return true }
            let terminalID = terminal.id
            let needle = action.action.start_search.needle.map { String(cString: $0) }
            dispatchToDelegate { delegate in
                _ = delegate?.ghosttyRuntimeDidUpdateSearch(
                    terminalID: terminalID,
                    active: true,
                    needle: needle,
                    total: nil,
                    selected: nil
                )
            }
            return true
        case GHOSTTY_ACTION_END_SEARCH:
            guard let terminal = TerminalSurface.fromGhosttySurface(target.target.surface) else { return true }
            let terminalID = terminal.id
            dispatchToDelegate { delegate in
                _ = delegate?.ghosttyRuntimeDidUpdateSearch(
                    terminalID: terminalID,
                    active: false,
                    needle: nil,
                    total: nil,
                    selected: nil
                )
            }
            return true
        case GHOSTTY_ACTION_SEARCH_TOTAL:
            guard let terminal = TerminalSurface.fromGhosttySurface(target.target.surface) else { return true }
            let terminalID = terminal.id
            let rawTotal = action.action.search_total.total
            let total = rawTotal >= 0 ? Int(rawTotal) : nil
            dispatchToDelegate { delegate in
                _ = delegate?.ghosttyRuntimeDidUpdateSearch(
                    terminalID: terminalID,
                    active: true,
                    needle: nil,
                    total: total,
                    selected: nil
                )
            }
            return true
        case GHOSTTY_ACTION_SEARCH_SELECTED:
            guard let terminal = TerminalSurface.fromGhosttySurface(target.target.surface) else { return true }
            let terminalID = terminal.id
            let rawSelected = action.action.search_selected.selected
            let selected = rawSelected >= 0 ? Int(rawSelected) : nil
            dispatchToDelegate { delegate in
                _ = delegate?.ghosttyRuntimeDidUpdateSearch(
                    terminalID: terminalID,
                    active: true,
                    needle: nil,
                    total: nil,
                    selected: selected
                )
            }
            return true
        case GHOSTTY_ACTION_READONLY:
            guard let terminal = TerminalSurface.fromGhosttySurface(target.target.surface) else { return true }
            let terminalID = terminal.id
            let readonly = action.action.readonly == GHOSTTY_READONLY_ON
            dispatchToDelegate { delegate in
                _ = delegate?.ghosttyRuntimeDidSetReadonly(terminalID: terminalID, readonly: readonly)
            }
            return true
        case GHOSTTY_ACTION_CLOSE_TAB:
            guard let terminal = TerminalSurface.fromGhosttySurface(target.target.surface) else { return false }
            let terminalID = terminal.id
            let scope = TabCloseScope(ghosttyMode: action.action.close_tab_mode)
            dispatchToDelegate { delegate in
                _ = delegate?.ghosttyRuntimeDidRequestCloseTabs(terminalID: terminalID, scope: scope)
            }
            return true
        case GHOSTTY_ACTION_SHOW_CHILD_EXITED:
            guard let terminal = TerminalSurface.fromGhosttySurface(target.target.surface) else { return false }
            let terminalID = terminal.id
            dispatchToDelegate { delegate in
                _ = delegate?.ghosttyRuntimeDidRequestClose(terminalID: terminalID)
            }
            return true
        default:
            ConductorLog.terminal.debug("Unhandled Ghostty surface action=\(action.tag.rawValue)")
            return false
        }
    }

    private func logDiagnostics(_ config: ghostty_config_t) {
        let count = ghostty_config_diagnostics_count(config)
        guard count > 0 else { return }
        for index in 0..<count {
            let diagnostic = ghostty_config_get_diagnostic(config, index)
            let message = diagnostic.message.map { String(cString: $0) } ?? "(null)"
            ConductorLog.terminal.error("Ghostty config diagnostic \(index): \(message)")
        }
    }
}

private extension TerminalProgressKind {
    init?(ghosttyState: ghostty_action_progress_report_state_e) {
        switch ghosttyState {
        case GHOSTTY_PROGRESS_STATE_REMOVE:
            self = .removed
        case GHOSTTY_PROGRESS_STATE_SET:
            self = .set
        case GHOSTTY_PROGRESS_STATE_ERROR:
            self = .error
        case GHOSTTY_PROGRESS_STATE_INDETERMINATE:
            self = .indeterminate
        case GHOSTTY_PROGRESS_STATE_PAUSE:
            self = .paused
        default:
            return nil
        }
    }
}

private extension TabCloseScope {
    init(ghosttyMode: ghostty_action_close_tab_mode_e) {
        switch ghosttyMode {
        case GHOSTTY_ACTION_CLOSE_TAB_MODE_OTHER:
            self = .others
        case GHOSTTY_ACTION_CLOSE_TAB_MODE_RIGHT:
            self = .toRight
        default:
            self = .selected
        }
    }
}

private extension URL {
    init?(ghosttyOpenURL: ghostty_action_open_url_s) {
        guard let pointer = ghosttyOpenURL.url, ghosttyOpenURL.len > 0 else { return nil }
        let buffer = UnsafeBufferPointer(start: UnsafeRawPointer(pointer).assumingMemoryBound(to: UInt8.self), count: Int(ghosttyOpenURL.len))
        let string = String(decoding: buffer, as: UTF8.self)
        self.init(string: string)
    }
}

private extension SplitDirection {
    init?(ghosttyDirection: ghostty_action_split_direction_e) {
        switch ghosttyDirection {
        case GHOSTTY_SPLIT_DIRECTION_LEFT:
            self = .left
        case GHOSTTY_SPLIT_DIRECTION_RIGHT:
            self = .right
        case GHOSTTY_SPLIT_DIRECTION_UP:
            self = .up
        case GHOSTTY_SPLIT_DIRECTION_DOWN:
            self = .down
        default:
            return nil
        }
    }
}

private extension FocusDirection {
    init?(ghosttyDirection: ghostty_action_goto_split_e) {
        switch ghosttyDirection {
        case GHOSTTY_GOTO_SPLIT_PREVIOUS:
            self = .previous
        case GHOSTTY_GOTO_SPLIT_NEXT:
            self = .next
        case GHOSTTY_GOTO_SPLIT_LEFT:
            self = .left
        case GHOSTTY_GOTO_SPLIT_RIGHT:
            self = .right
        case GHOSTTY_GOTO_SPLIT_UP:
            self = .up
        case GHOSTTY_GOTO_SPLIT_DOWN:
            self = .down
        default:
            return nil
        }
    }
}

private extension ResizeSplitDirection {
    init?(ghosttyDirection: ghostty_action_resize_split_direction_e) {
        switch ghosttyDirection {
        case GHOSTTY_RESIZE_SPLIT_LEFT:
            self = .left
        case GHOSTTY_RESIZE_SPLIT_RIGHT:
            self = .right
        case GHOSTTY_RESIZE_SPLIT_UP:
            self = .up
        case GHOSTTY_RESIZE_SPLIT_DOWN:
            self = .down
        default:
            return nil
        }
    }
}
