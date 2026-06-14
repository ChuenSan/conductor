import AppKit
import ConductorCore
import SwiftUI

/// "1e1e2e" → Color；非法值回落近黑（仅用于内置主题字面量，恒合法）。
private func gc(_ hex: String) -> Color { Color(hex: hex) ?? .black }

/// 外壳(侧栏/Tab栏/卡片/文字/强调)的一整套色，按主题数据驱动。对标 Craft：柔和、暖、卡片浮起无硬线。
/// 与 `ThemePalette`(终端配色，喂 ghostty)互补:这套给 SwiftUI/AppKit 外壳用。
struct Theme {
    let windowBackground: Color      // 画布（比卡片略深，卡片浮其上）
    let sidebarBackground: Color
    let cardBackground: NSColor      // 终端卡片底（与终端配色一致）
    let elevated: Color
    let activeFill: Color
    let separator: Color
    let hoverFill: Color
    let textPrimary: Color
    let textSecondary: Color
    let textTertiary: Color
    let accent: Color
    let isDark: Bool
    // 卡片立体感：浅色用柔阴影，深色用极淡边框 + 弱阴影
    let cardShadowColor: NSColor
    let cardShadowOpacity: Float
    let cardShadowRadius: CGFloat
    let cardBorder: NSColor           // 静态卡片的细边（可近乎透明）

    // 浮层质感（毛玻璃面板 + 高光/边框）与主操作（石墨实心，收敛蓝色）。
    let primarySolid: Color           // 主按钮底（高对比、近黑/近白）
    let primarySolidText: Color       // 主按钮文字
    let panelTint: Color              // 压在毛玻璃上的半透明色调
    let panelHairline: Color          // 浮层细边
    let panelHighlight: Color         // 浮层顶部 1px 高光

    static let dark = Theme(
        windowBackground: Color(red: 0.055, green: 0.057, blue: 0.066),
        sidebarBackground: Color(red: 0.055, green: 0.057, blue: 0.066),
        cardBackground: NSColor(red: 0.106, green: 0.110, blue: 0.133, alpha: 1),
        elevated: Color(red: 0.16, green: 0.16, blue: 0.185),
        activeFill: Color.white.opacity(0.09),
        separator: Color.white.opacity(0.06),
        hoverFill: Color.white.opacity(0.05),
        textPrimary: .white,
        textSecondary: Color.white.opacity(0.62),
        textTertiary: Color.white.opacity(0.38),
        accent: Color(red: 0.45, green: 0.58, blue: 0.86),   // 收敛：去掉霓虹蓝的廉价感
        isDark: true,
        cardShadowColor: .black,
        cardShadowOpacity: 0.38,
        cardShadowRadius: 11,
        cardBorder: NSColor.white.withAlphaComponent(0.05),
        primarySolid: Color(red: 0.95, green: 0.95, blue: 0.96),
        primarySolidText: Color(red: 0.08, green: 0.08, blue: 0.10),
        panelTint: Color.white.opacity(0.04),
        panelHairline: Color.white.opacity(0.10),
        panelHighlight: Color.white.opacity(0.22))

    // 中性浅主题（不带暖色：略偏冷的中性灰白）
    static let light = Theme(
        windowBackground: Color(red: 248.0 / 255.0, green: 248.0 / 255.0, blue: 248.0 / 255.0),
        sidebarBackground: Color(red: 248.0 / 255.0, green: 248.0 / 255.0, blue: 248.0 / 255.0),
        cardBackground: NSColor(red: 0.987, green: 0.989, blue: 0.994, alpha: 1),  // 中性近白
        elevated: Color(red: 1.0, green: 1.0, blue: 1.0),       // 纯白抬起胶囊
        activeFill: Color.black.opacity(0.05),
        separator: Color.black.opacity(0.065),
        hoverFill: Color.black.opacity(0.042),
        textPrimary: Color(red: 0.12, green: 0.13, blue: 0.15),
        textSecondary: Color.black.opacity(0.55),
        textTertiary: Color.black.opacity(0.38),
        accent: Color(red: 0.20, green: 0.40, blue: 0.78),   // 收敛：略去饱和，更克制
        isDark: false,
        cardShadowColor: NSColor(red: 0.13, green: 0.15, blue: 0.20, alpha: 1),    // 中性冷灰阴影
        cardShadowOpacity: 0.11,
        cardShadowRadius: 15,                                                        // 柔阴影（收紧一点）
        cardBorder: NSColor.black.withAlphaComponent(0.035),
        primarySolid: Color(red: 0.12, green: 0.12, blue: 0.13),                     // 近黑主操作（对标 Craft 黑胶囊）
        primarySolidText: .white,
        panelTint: Color.white.opacity(0.55),                                        // 毛玻璃上压一层近白，定调亮净
        panelHairline: Color.black.opacity(0.06),
        panelHighlight: Color.white.opacity(0.75))

    /// 由一组深色配色派生整套外壳主题：沿用深色主题成熟的层级/高光规则，
    /// 只替换底色、文字与强调色。让加新主题=填几个 hex，不再手调二十个字段。
    /// 画布、终端卡底、侧栏/状态栏统一用同一个 `base`——终端不再是一块浮起的异色卡，
    /// 与四周完全融为一色（这些配色本就是为单底色设计的）。
    /// - base:    全局底色（= 该主题终端配色的 background，整窗一色）
    /// - surface: 抬起表面（选中胶囊/分段指示器底）
    /// - text:    主文字（次/三级文字按其透明度派生）
    /// - accent:  强调色（链接/选中描边/开关）
    private static func darkVariant(
        base: String, surface: String, text: String, accent: String
    ) -> Theme {
        Theme(
            windowBackground: gc(base),
            sidebarBackground: gc(base),
            cardBackground: NSColor(gc(base)),
            elevated: gc(surface),
            activeFill: Color.white.opacity(0.09),
            separator: Color.white.opacity(0.07),
            hoverFill: Color.white.opacity(0.05),
            textPrimary: gc(text),
            textSecondary: gc(text).opacity(0.64),
            textTertiary: gc(text).opacity(0.40),
            accent: gc(accent),
            isDark: true,
            cardShadowColor: .black,
            cardShadowOpacity: 0,               // 整窗一色，终端不再浮起 → 无阴影、无异色块
            cardShadowRadius: 0,
            cardBorder: NSColor.white.withAlphaComponent(0.05),
            primarySolid: gc(text),            // 主按钮：近白前景实心
            primarySolidText: gc(base),        // 文字：取底色深色
            panelTint: Color.white.opacity(0.04),
            panelHairline: Color.white.opacity(0.10),
            panelHighlight: Color.white.opacity(0.20))
    }

    // 以下四款为社区公认耐看的配色，hex 取自各自官方调色板（整窗单底色）。
    static let tokyoNight = darkVariant(
        base: "1a1b26", surface: "292e42", text: "c0caf5", accent: "7aa2f7")
    static let catppuccin = darkVariant(   // Mocha
        base: "1e1e2e", surface: "313244", text: "cdd6f4", accent: "cba6f7")
    static let nord = darkVariant(
        base: "2e3440", surface: "3b4252", text: "d8dee9", accent: "88c0d0")
    static let rosePine = darkVariant(
        base: "191724", surface: "26233a", text: "e0def4", accent: "c4a7e7")

    static func resolve(_ appearance: Appearance) -> Theme {
        switch appearance.theme {
        case "light": return .light
        case "tokyo-night": return .tokyoNight
        case "catppuccin": return .catppuccin
        case "nord": return .nord
        case "rose-pine": return .rosePine
        default: return .dark   // dark / custom: 外壳走深色(custom 仅终端用自定义色)
        }
    }

    @MainActor static var current: Theme { resolve(ConfigStore.shared.config.appearance) }
}
