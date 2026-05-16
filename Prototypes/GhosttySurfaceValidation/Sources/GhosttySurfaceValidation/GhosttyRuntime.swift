import AppKit
import Foundation
import GhosttyKit

@MainActor
final class GhosttyRuntime {
    static let shared = GhosttyRuntime()

    private(set) var app: ghostty_app_t?
    private var config: ghostty_config_t?
    private var tickScheduled = false

    private init() {}

    func start(theme: TerminalTheme) {
        guard app == nil else { return }

        if getenv("NO_COLOR") != nil {
            unsetenv("NO_COLOR")
        }

        let result = ghostty_init(UInt(CommandLine.argc), CommandLine.unsafeArgv)
        guard result == GHOSTTY_SUCCESS else {
            ValidationLogger.error("ghostty_init failed result=\(result)")
            return
        }

        guard let config = makeConfig(theme: theme) else {
            ValidationLogger.error("makeConfig failed")
            return
        }

        var runtimeConfig = ghostty_runtime_config_s()
        runtimeConfig.userdata = Unmanaged.passUnretained(self).toOpaque()
        runtimeConfig.supports_selection_clipboard = true
        runtimeConfig.wakeup_cb = { userdata in
            guard let userdata else { return }
            let runtime = Unmanaged<GhosttyRuntime>.fromOpaque(userdata).takeUnretainedValue()
            Task { @MainActor in
                runtime.scheduleTick()
            }
        }
        runtimeConfig.action_cb = { _, target, action in
            ValidationLogger.info("action tag=\(action.tag.rawValue) target=\(target.tag.rawValue)")
            return false
        }
        runtimeConfig.read_clipboard_cb = { userdata, location, state in
            guard let userdata, let state else { return false }
            let owner = Unmanaged<TerminalSurfaceOwner>.fromOpaque(userdata).takeUnretainedValue()
            Task { @MainActor in
                owner.completeClipboardRequest(location: location, state: state)
            }
            return true
        }
        runtimeConfig.write_clipboard_cb = { _, _, content, count, _ in
            guard let content, count > 0 else { return }
            let buffer = UnsafeBufferPointer(start: content, count: count)
            for item in buffer {
                guard let data = item.data else { continue }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(String(cString: data), forType: .string)
                return
            }
        }
        runtimeConfig.close_surface_cb = { userdata, needsConfirmClose in
            guard let userdata else { return }
            let owner = Unmanaged<TerminalSurfaceOwner>.fromOpaque(userdata).takeUnretainedValue()
            Task { @MainActor in
                owner.closeFromGhostty(needsConfirmation: needsConfirmClose)
            }
        }

        guard let created = ghostty_app_new(&runtimeConfig, config) else {
            ValidationLogger.error("ghostty_app_new failed")
            dumpDiagnostics(config)
            ghostty_config_free(config)
            return
        }

        self.app = created
        self.config = config
        ghostty_app_set_focus(created, NSApp.isActive)
        ValidationLogger.info("Ghostty runtime initialized")
    }

    func makeConfig(theme: TerminalTheme) -> ghostty_config_t? {
        guard let config = ghostty_config_new() else { return nil }
        loadValidationConfig(into: config, theme: theme)
        ghostty_config_finalize(config)
        return config
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

    private func loadValidationConfig(into config: ghostty_config_t, theme: TerminalTheme) {
        let configText = """
        macos-background-from-layer = true
        macos-titlebar-proxy-icon = hidden
        shell-integration = none
        font-size = 13
        \(theme.ghosttyConfig)
        """
        configText.withCString { ptr in
            ghostty_config_load_string(config, ptr, UInt(configText.utf8.count), "validation-config")
        }
    }

    private func dumpDiagnostics(_ config: ghostty_config_t) {
        let count = ghostty_config_diagnostics_count(config)
        guard count > 0 else { return }
        for index in 0..<count {
            let diagnostic = ghostty_config_get_diagnostic(config, index)
            let message = diagnostic.message.map { String(cString: $0) } ?? "(null)"
            ValidationLogger.error("config diagnostic[\(index)]: \(message)")
        }
    }
}
