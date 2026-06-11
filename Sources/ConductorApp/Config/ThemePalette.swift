import ConductorCore

/// 由配置(主题名/自定义色)解析出一组终端配色(hex，不带 #)。
/// 数据驱动:dark/light 内置，custom 用用户 colors，缺项回退 dark。给 ghostty 配置串与(将来)AppStyle 共用。
struct ThemePalette: Equatable {
    let background: String
    let foreground: String
    let cursor: String
    let selection: String
    let selectionForeground: String

    static let dark = ThemePalette(
        background: "1b1c22", foreground: "d7d8e0", cursor: "8aa9ff",
        selection: "33406b", selectionForeground: "ffffff")

    static let light = ThemePalette(
        background: "f8f8f8", foreground: "26272c", cursor: "2b6cff",
        selection: "d4e2ff", selectionForeground: "15161a")

    static func resolve(_ appearance: Appearance) -> ThemePalette {
        switch appearance.theme {
        case "light":
            return .light
        case "custom":
            let d = ThemePalette.dark
            let c = appearance.colors
            return ThemePalette(
                background: hex(c?.background) ?? d.background,
                foreground: hex(c?.foreground) ?? d.foreground,
                cursor: hex(c?.cursor) ?? d.cursor,
                selection: hex(c?.selection) ?? d.selection,
                selectionForeground: "ffffff")
        default:
            return .dark
        }
    }

    /// 终端底色是否偏深。custom 主题也按实际背景亮度判断，
    /// 用于告知 TUI（mode 2031）当前是深色还是浅色方案。
    var isDark: Bool {
        guard background.count >= 6,
              let r = UInt8(background.prefix(2), radix: 16),
              let g = UInt8(background.dropFirst(2).prefix(2), radix: 16),
              let b = UInt8(background.dropFirst(4).prefix(2), radix: 16)
        else { return true }
        // ITU-R BT.601 亮度
        let luma = 0.299 * Double(r) + 0.587 * Double(g) + 0.114 * Double(b)
        return luma < 128
    }

    /// "#1b1c22" / "1b1c22" → "1b1c22"；nil/空 → nil。
    private static func hex(_ s: String?) -> String? {
        guard let s, !s.isEmpty else { return nil }
        return s.hasPrefix("#") ? String(s.dropFirst()) : s
    }
}
