import AppKit
import CmuxCore
import SwiftUI

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

    static func resolve(_ appearance: Appearance) -> Theme {
        switch appearance.theme {
        case "light": return .light
        default: return .dark   // custom: 外壳暂用深色(终端用自定义色)
        }
    }

    @MainActor static var current: Theme { resolve(ConfigStore.shared.config.appearance) }
}
