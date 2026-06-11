import AppKit
import ConductorCore
import Foundation
@preconcurrency import GhosttyKit

/// 最小 libghostty 运行时（单例，C 回调里只能引用全局）。
/// 相比 spike，action_cb 升级为按 surface 路由 title/pwd/child-exited 到对应 GhosttySurface。
@MainActor
final class GhosttyRuntime {
    static let shared = GhosttyRuntime()

    private(set) var app: ghostty_app_t?
    private(set) var config: ghostty_config_t?
    private var tickScheduled = false

    private init() {}

    func ensureStarted() {
        guard app == nil else { return }

        let resources = "/Applications/Ghostty.app/Contents/Resources/ghostty"
        if FileManager.default.fileExists(atPath: resources + "/shell-integration/zsh/.zshenv") {
            setenv("GHOSTTY_RESOURCES_DIR", resources, 1)
        }

        guard ghostty_init(UInt(CommandLine.argc), CommandLine.unsafeArgv) == GHOSTTY_SUCCESS else {
            NSLog("[conductor] ghostty_init failed")
            return
        }
        // 终端外观全部从用户配置(config.yaml)生成，不再硬编码。
        guard let config = Self.makeConfig(from: ConfigStore.shared.config) else {
            NSLog("[conductor] ghostty_config_new failed")
            return
        }

        var rc = ghostty_runtime_config_s()
        rc.userdata = nil
        rc.supports_selection_clipboard = true
        rc.wakeup_cb = { _ in
            Task { @MainActor in GhosttyRuntime.shared.scheduleTick() }
        }
        rc.action_cb = { _, target, action in
            GhosttyRuntime.routeAction(target: target, action: action)
        }
        // 剪贴板回调：缺这两个，libghostty 在「选中→复制」时会调空指针而崩溃。
        rc.write_clipboard_cb = { _, _, content, count, _ in
            guard let content, count > 0 else { return }
            let items = UnsafeBufferPointer(start: content, count: count)
            for item in items {
                guard let data = item.data else { continue }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(String(cString: data), forType: .string)
                return
            }
        }
        rc.read_clipboard_cb = { userdata, _, state in
            guard let userdata, let state else { return false }
            let surface = Unmanaged<GhosttySurface>.fromOpaque(userdata).takeUnretainedValue()
            let retained = Unmanaged.passRetained(surface)
            Task { @MainActor in
                retained.takeRetainedValue().completeClipboardRequest(state: state)
            }
            return true
        }

        guard let created = ghostty_app_new(&rc, config) else {
            NSLog("[conductor] ghostty_app_new failed")
            ghostty_config_free(config)
            return
        }
        self.app = created
        self.config = config
        ghostty_app_set_focus(created, true)
        syncColorScheme(ConfigStore.shared.config)
        NSLog("[conductor] ghostty runtime started")
    }

    /// 用 AppConfig 造一个 ghostty 配置对象(load string + finalize)。
    static func makeConfig(from appConfig: AppConfig) -> ghostty_config_t? {
        guard let config = ghostty_config_new() else { return nil }
        let text = ghosttyConfigText(from: appConfig)
        text.withCString {
            ghostty_config_load_string(config, $0, UInt(text.utf8.count), "conductor")
        }
        ghostty_config_finalize(config)
        return config
    }

    /// 热更新:用新配置重建 ghostty 配置并应用到 app(各 surface 由 GhosttySurface.reloadConfig 各自更新)。
    func applyConfig(_ appConfig: AppConfig) {
        guard let app, let newConfig = Self.makeConfig(from: appConfig) else { return }
        ghostty_app_update_config(app, newConfig)
        let old = config
        config = newConfig
        if let old { ghostty_config_free(old) }
        // 告知各 surface 里运行中的 TUI 配色方案变了(DEC mode 2031)：
        // codex/claude 等启动时探测一次深浅色，不通知的话切主题后它们仍按旧方案画(深底上出白块)。
        syncColorScheme(appConfig)
    }

    private func syncColorScheme(_ appConfig: AppConfig) {
        guard let app else { return }
        let dark = ThemePalette.resolve(appConfig.appearance).isDark
        ghostty_app_set_color_scheme(
            app, dark ? GHOSTTY_COLOR_SCHEME_DARK : GHOSTTY_COLOR_SCHEME_LIGHT)
    }

    /// 把 `AppConfig` 翻译成 libghostty 的 `key = value` 配置串(高扩展:数据驱动)。
    static func ghosttyConfigText(from config: AppConfig) -> String {
        let a = config.appearance
        let theme = ThemePalette.resolve(a)
        var keys: [String] = []
        var values: [String: String] = [:]
        func set(_ key: String, _ value: String) {
            if values[key] == nil { keys.append(key) }
            values[key] = value
        }
        // libghostty 默认 TERM=xterm-ghostty，其 terminfo 只有装了 Ghostty.app 的机器才有；
        // 缺失时 ls/TUI 都探测不到颜色能力，输出全灰。改用系统自带的 xterm-256color。
        // （用户仍可在 ghosttyOverrides 里改回 xterm-ghostty。）
        set("term", "xterm-256color")
        set("background", theme.background)
        set("foreground", theme.foreground)
        set("cursor-color", theme.cursor)
        set("selection-background", theme.selection)
        set("selection-foreground", theme.selectionForeground)
        set("font-size", "\(a.font.size)")
        set("adjust-cell-height", "12%")
        set("window-padding-x", "\(a.padding.x)")
        set("window-padding-y", "\(a.padding.y)")
        set("window-padding-balance", "true")
        set("cursor-style", a.cursorStyle)
        // ghostty 的 scrollback-limit 单位是字节（按需分配，设大无固定开销）。
        // 行数 → 字节按 512B/行 保守折算（约 160 列 × UTF-8 中文 3B），确保至少能存下配置的行数。
        set("scrollback-limit", "\(config.terminal.scrollback * 512)")
        let family = a.font.family.trimmingCharacters(in: .whitespaces)
        if !family.isEmpty { set("font-family", family) }
        for (key, rawValue) in config.ghosttyOverrides.sorted(by: { $0.key < $1.key }) {
            let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard ConductorGhosttyConfigCatalog.knownKeySet.contains(key), !value.isEmpty else { continue }
            set(key, value)
        }
        return keys.compactMap { key in
            values[key].map { "\(key) = \($0)" }
        }
        .joined(separator: "\n")
    }

    private func scheduleTick() {
        guard !tickScheduled else { return }
        tickScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.tickScheduled = false
            if let app = self.app { ghostty_app_tick(app) }
        }
    }

    // C 回调是 nonisolated；取出原始值后跳回主线程分派。
    private nonisolated static func routeAction(
        target: ghostty_target_s,
        action: ghostty_action_s
    ) -> Bool {
        guard target.tag == GHOSTTY_TARGET_SURFACE else { return false }
        let surfaceHandle = target.target.surface

        switch action.tag {
        case GHOSTTY_ACTION_SET_TITLE:
            guard let titlePointer = action.action.set_title.title else { return false }
            let title = String(cString: titlePointer)
            Task { @MainActor in
                GhosttySurface.fromGhosttySurface(surfaceHandle)?.handleSetTitle(title)
            }
            return true
        case GHOSTTY_ACTION_SCROLLBAR:
            let sb = action.action.scrollbar
            Task { @MainActor in
                GhosttySurface.fromGhosttySurface(surfaceHandle)?
                    .handleScrollbar(total: sb.total, offset: sb.offset, len: sb.len)
            }
            return true
        case GHOSTTY_ACTION_PWD:
            guard let pwdPointer = action.action.pwd.pwd else { return true }
            let pwd = String(cString: pwdPointer)
            Task { @MainActor in
                GhosttySurface.fromGhosttySurface(surfaceHandle)?.handlePwd(pwd)
            }
            return true
        case GHOSTTY_ACTION_START_SEARCH:
            let needle = action.action.start_search.needle.map { String(cString: $0) } ?? ""
            Task { @MainActor in GhosttySurface.fromGhosttySurface(surfaceHandle)?.handleSearchStart(needle) }
            return true
        case GHOSTTY_ACTION_END_SEARCH:
            Task { @MainActor in GhosttySurface.fromGhosttySurface(surfaceHandle)?.handleSearchEnd() }
            return true
        case GHOSTTY_ACTION_SEARCH_TOTAL:
            let total = Int(action.action.search_total.total)
            Task { @MainActor in GhosttySurface.fromGhosttySurface(surfaceHandle)?.handleSearchTotal(total) }
            return true
        case GHOSTTY_ACTION_SEARCH_SELECTED:
            let sel = Int(action.action.search_selected.selected)
            Task { @MainActor in GhosttySurface.fromGhosttySurface(surfaceHandle)?.handleSearchSelected(sel) }
            return true
        case GHOSTTY_ACTION_OPEN_URL:
            guard let urlPointer = action.action.open_url.url else { return false }
            let urlString = String(cString: urlPointer)
            Task { @MainActor in
                if let url = URL(string: urlString) { NSWorkspace.shared.open(url) }
            }
            return true
        case GHOSTTY_ACTION_SHOW_CHILD_EXITED:
            Task { @MainActor in
                GhosttySurface.fromGhosttySurface(surfaceHandle)?.handleChildExited()
            }
            return true
        default:
            return false
        }
    }
}
