import Foundation

/// 用户配置（来自 `~/.config/conductor/config.yaml`）。纯 Codable 模型，不含 YAML 解析（那在 App 层用 Yams）。
///
/// **容错**：每个结构都自定义 `init(from:)`，缺字段用默认、未知字段忽略——
/// 保证旧/新配置文件都能加载，单个坏字段不至于整份失效（高商用）。
/// `validated()` 进一步夹紧非法值（字号范围、枚举回退）。
public struct AppConfig: Codable, Equatable, Sendable {
    public var appearance: Appearance
    public var terminal: TerminalConfig
    public var behavior: Behavior
    public var keybindings: [String: String]
    public var ghosttyOverrides: [String: String]
    public var workspaceDefaults: WorkspaceDefaults

    public init(appearance: Appearance = .init(),
                terminal: TerminalConfig = .init(),
                behavior: Behavior = .init(),
                keybindings: [String: String] = [:],
                ghosttyOverrides: [String: String] = [:],
                workspaceDefaults: WorkspaceDefaults = .init()) {
        self.appearance = appearance
        self.terminal = terminal
        self.behavior = behavior
        self.keybindings = keybindings
        self.ghosttyOverrides = ghosttyOverrides
        self.workspaceDefaults = workspaceDefaults
    }

    public static let `default` = AppConfig()

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        appearance = c.value(.appearance, AppConfig.default.appearance)
        terminal = c.value(.terminal, AppConfig.default.terminal)
        behavior = c.value(.behavior, AppConfig.default.behavior)
        keybindings = c.value(.keybindings, [:])
        ghosttyOverrides = c.value(.ghosttyOverrides, [:])
        workspaceDefaults = c.value(.workspaceDefaults, .init())
    }

    /// 夹紧非法值，返回修正后的副本。
    public func validated() -> AppConfig {
        var copy = self
        copy.appearance = appearance.validated()
        copy.terminal = terminal.validated()
        copy.behavior = behavior.validated()
        copy.ghosttyOverrides = ghosttyOverrides.compactMapValues { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        return copy
    }
}

// MARK: - appearance

public struct Appearance: Codable, Equatable, Sendable {
    public var theme: String
    public var font: FontConfig
    public var padding: Padding
    public var cursorStyle: String       // bar | block | underline
    public var colors: Colors?

    public init(theme: String = "dark", font: FontConfig = .init(),
                padding: Padding = .init(), cursorStyle: String = "bar",
                colors: Colors? = nil) {
        self.theme = theme
        self.font = font
        self.padding = padding
        self.cursorStyle = cursorStyle
        self.colors = colors
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Appearance()
        theme = c.value(.theme, d.theme)
        font = c.value(.font, d.font)
        padding = c.value(.padding, d.padding)
        cursorStyle = c.value(.cursorStyle, d.cursorStyle)
        colors = (try? c.decodeIfPresent(Colors.self, forKey: .colors)) ?? nil
    }

    static let validCursorStyles: Set<String> = ["bar", "block", "underline"]

    func validated() -> Appearance {
        var copy = self
        copy.font = font.validated()
        if !Appearance.validCursorStyles.contains(cursorStyle) { copy.cursorStyle = "bar" }
        return copy
    }
}

public struct FontConfig: Codable, Equatable, Sendable {
    public var family: String
    public var size: Int

    public init(family: String = "SF Mono", size: Int = 13) {
        self.family = family
        self.size = size
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = FontConfig()
        family = c.value(.family, d.family)
        size = c.value(.size, d.size)
    }

    func validated() -> FontConfig {
        var copy = self
        copy.size = min(max(size, 6), 72)     // 字号夹到 6...72
        if family.trimmingCharacters(in: .whitespaces).isEmpty { copy.family = "SF Mono" }
        return copy
    }
}

public struct Padding: Codable, Equatable, Sendable {
    public var x: Int
    public var y: Int

    public init(x: Int = 14, y: Int = 12) {
        self.x = x
        self.y = y
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Padding()
        x = c.value(.x, d.x)
        y = c.value(.y, d.y)
    }
}

public struct Colors: Codable, Equatable, Sendable {
    public var background: String?
    public var foreground: String?
    public var cursor: String?
    public var selection: String?
    public var ansi: [String]?

    public init(background: String? = nil, foreground: String? = nil,
                cursor: String? = nil, selection: String? = nil, ansi: [String]? = nil) {
        self.background = background
        self.foreground = foreground
        self.cursor = cursor
        self.selection = selection
        self.ansi = ansi
    }
}

// MARK: - terminal

public struct TerminalConfig: Codable, Equatable, Sendable {
    public var shell: String?           // nil = 用户登录 shell
    public var scrollback: Int
    public var copyOnSelect: Bool
    public var confirmCloseRunning: Bool

    public init(shell: String? = nil, scrollback: Int = 10000,
                copyOnSelect: Bool = false, confirmCloseRunning: Bool = true) {
        self.shell = shell
        self.scrollback = scrollback
        self.copyOnSelect = copyOnSelect
        self.confirmCloseRunning = confirmCloseRunning
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = TerminalConfig()
        shell = (try? c.decodeIfPresent(String.self, forKey: .shell)) ?? nil
        scrollback = c.value(.scrollback, d.scrollback)
        copyOnSelect = c.value(.copyOnSelect, d.copyOnSelect)
        confirmCloseRunning = c.value(.confirmCloseRunning, d.confirmCloseRunning)
    }

    func validated() -> TerminalConfig {
        var copy = self
        copy.scrollback = min(max(scrollback, 0), 1_000_000)
        return copy
    }
}

// MARK: - behavior

public struct Behavior: Codable, Equatable, Sendable {
    public var restoreLayoutOnLaunch: Bool
    public var newTabCwd: String        // workspace | activePane | home

    public init(restoreLayoutOnLaunch: Bool = true, newTabCwd: String = "workspace") {
        self.restoreLayoutOnLaunch = restoreLayoutOnLaunch
        self.newTabCwd = newTabCwd
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Behavior()
        restoreLayoutOnLaunch = c.value(.restoreLayoutOnLaunch, d.restoreLayoutOnLaunch)
        newTabCwd = c.value(.newTabCwd, d.newTabCwd)
    }

    static let validNewTabCwd: Set<String> = ["workspace", "activePane", "home"]

    func validated() -> Behavior {
        var copy = self
        if !Behavior.validNewTabCwd.contains(newTabCwd) { copy.newTabCwd = "workspace" }
        return copy
    }
}

// MARK: - workspace defaults

public struct WorkspaceDefaults: Codable, Equatable, Sendable {
    public var shell: String?
    public var startupCommand: String?

    public init(shell: String? = nil, startupCommand: String? = nil) {
        self.shell = shell
        self.startupCommand = startupCommand
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        shell = (try? c.decodeIfPresent(String.self, forKey: .shell)) ?? nil
        startupCommand = (try? c.decodeIfPresent(String.self, forKey: .startupCommand)) ?? nil
    }
}

// MARK: - 容错解码助手

extension KeyedDecodingContainer {
    /// 取 key 的值，缺失/类型错都回退到 `def`（不抛）。
    func value<T: Decodable>(_ key: Key, _ def: T) -> T {
        ((try? decodeIfPresent(T.self, forKey: key)) ?? nil) ?? def
    }
}
