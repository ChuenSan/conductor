import AppKit
import SwiftUI

/// 设计令牌：现在从当前 `Theme`(主题派生)取色，外壳随 config.yaml 的主题切换。
/// 用法不变(`AppStyle.windowBackground` 等)，但值是计算属性、跟随主题。
enum AppStyle {
    @MainActor static var theme: Theme { Theme.current }

    // 面
    @MainActor static var windowBackground: Color { theme.windowBackground }
    @MainActor static var sidebarBackground: Color { theme.sidebarBackground }
    @MainActor static var chromeBackground: Color { theme.windowBackground }   // tab 栏=画布
    @MainActor static var cardBackground: NSColor { theme.cardBackground }
    @MainActor static var elevated: Color { theme.elevated }
    @MainActor static var activeFill: Color { theme.activeFill }
    @MainActor static var separator: Color { theme.separator }
    @MainActor static var hoverFill: Color { theme.hoverFill }

    // 文字
    @MainActor static var textPrimary: Color { theme.textPrimary }
    @MainActor static var textSecondary: Color { theme.textSecondary }
    @MainActor static var textTertiary: Color { theme.textTertiary }

    // 强调
    @MainActor static var accent: Color { theme.accent }

    // 尺寸(与主题无关)
    static let sidebarWidth: CGFloat = 224
    static let sidebarCollapsedWidth: CGFloat = 56
    static let tabBarHeight: CGFloat = 34
}

/// 侧栏/工具栏图标按钮：hover 高亮 + 按下弹簧缩放（微交互）。
struct IconButtonStyle: ButtonStyle {
    var size: CGFloat = 26
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(hovering ? AppStyle.hoverFill : Color.clear)
            )
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed ? 0.86 : 1)
            .opacity(configuration.isPressed ? 0.6 : 1)
            .animation(.spring(response: 0.26, dampingFraction: 0.6), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.14), value: hovering)
            .onHover { hovering = $0 }
    }
}
