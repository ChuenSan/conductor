/// 一个归一化的键位组合（修饰键 + 主键），用于命令分发与配置键位匹配。
/// 解析人写的键位串如 `"cmd+shift+d"`；App 层把 `NSEvent` 也归一成 `KeyChord` 来查表。
public struct KeyChord: Hashable, Sendable {
    public struct Modifiers: OptionSet, Hashable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let command = Modifiers(rawValue: 1 << 0)
        public static let shift = Modifiers(rawValue: 1 << 1)
        public static let option = Modifiers(rawValue: 1 << 2)
        public static let control = Modifiers(rawValue: 1 << 3)
    }

    public var modifiers: Modifiers
    public var key: String   // 归一化主键：单字符小写，或 left/right/up/down/enter/esc/space/tab/delete

    public init(modifiers: Modifiers, key: String) {
        self.modifiers = modifiers
        self.key = key
    }

    /// 解析 `"cmd+shift+d"` / `"⌘D"` / `"ctrl+alt+left"`。无主键或多个主键 → nil。
    public init?(parsing string: String) {
        var mods: Modifiers = []
        var parsedKey: String?
        // 只用 "+" 分隔（"-" 是合法主键，如 cmd+- 缩小字号）。
        for raw in string.split(separator: "+", omittingEmptySubsequences: true) {
            let token = raw.trimmingCharacters(in: .whitespaces).lowercased()
            if token.isEmpty { continue }
            switch token {
            case "cmd", "command", "⌘", "super", "meta":
                mods.insert(.command)
            case "shift", "⇧":
                mods.insert(.shift)
            case "alt", "opt", "option", "⌥":
                mods.insert(.option)
            case "ctrl", "control", "⌃":
                mods.insert(.control)
            default:
                guard parsedKey == nil else { return nil }   // 出现第二个主键 → 非法
                parsedKey = KeyChord.normalizeKey(token)
            }
        }
        guard let key = parsedKey, !key.isEmpty else { return nil }
        self.modifiers = mods
        self.key = key
    }

    /// 主键别名归一：方向键/回车/退出等统一写法；其余取首字符。
    public static func normalizeKey(_ raw: String) -> String {
        switch raw {
        case "return", "enter": return "enter"
        case "escape", "esc": return "esc"
        case "delete", "del", "backspace": return "delete"
        case "space", "spacebar", " ": return "space"
        case "tab": return "tab"
        case "left", "arrowleft": return "left"
        case "right", "arrowright": return "right"
        case "up", "arrowup": return "up"
        case "down", "arrowdown": return "down"
        // 花括号归一成字面字符：NSEvent 侧 ⇧[ / ⇧] 产生 "{" / "}"；
        // 否则 "rightbrace" 走默认分支被取首字符成 "r"，⌘⇧} 永远无法命中。
        case "leftbrace", "lbrace": return "{"
        case "rightbrace", "rbrace": return "}"
        default:
            // 普通键取第一个字符（小写）
            return String(raw.prefix(1))
        }
    }
}
