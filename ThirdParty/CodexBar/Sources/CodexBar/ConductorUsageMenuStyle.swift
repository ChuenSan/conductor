import AppKit
import CodexBarCore
import SwiftUI

enum ConductorUsageMenuStyle {
    nonisolated(unsafe) private static var hostStyle: ConductorUsagePanelStyle?

    static func configure(_ style: ConductorUsagePanelStyle) {
        self.hostStyle = style
    }

    static var current: ConductorUsagePanelStyle? {
        guard CodexBarDisplayBrand.isRunningInsideConductor else { return nil }
        return self.hostStyle ?? .fallback
    }

    static var isEnabled: Bool {
        self.current != nil
    }

    static func nsColor(_ color: Color) -> NSColor {
        NSColor(color)
    }

    static func plateFill(highlighted: Bool, style: ConductorUsagePanelStyle) -> Color {
        if highlighted {
            return style.emphasis.opacity(style.usesDarkChrome ? 0.22 : 0.14)
        }
        return style.controlFill.opacity(style.usesDarkChrome ? 0.18 : 0.22)
    }

    static func selectedControlFill(style: ConductorUsagePanelStyle) -> Color {
        style.emphasis.opacity(style.usesDarkChrome ? 0.46 : 0.34)
    }

    static func hoverControlFill(style: ConductorUsagePanelStyle) -> Color {
        style.controlStrongFill.opacity(style.usesDarkChrome ? 0.36 : 0.44)
    }
}

struct ConductorUsageMenuActionRow: View {
    let title: String
    let subtitle: String?
    let systemImageName: String?
    let shortcutText: String?
    let showsChevron: Bool
    let isEnabled: Bool
    let width: CGFloat

    @Environment(\.menuItemHighlighted) private var isHighlighted

    var body: some View {
        let style = ConductorUsageMenuStyle.current ?? .fallback
        HStack(spacing: 9) {
            icon(style: style)

            VStack(alignment: .leading, spacing: 1) {
                Text(codexBarLocalizedDisplayText(title))
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(primaryColor(style: style))
                    .lineLimit(1)
                if let subtitle, !subtitle.isEmpty {
                    Text(codexBarLocalizedDisplayText(subtitle))
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(secondaryColor(style: style))
                        .lineLimit(2)
                }
            }
            .layoutPriority(1)

            Spacer(minLength: 8)

            if let shortcutText, !shortcutText.isEmpty {
                Text(shortcutText)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(secondaryColor(style: style))
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(secondaryColor(style: style))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, subtitle == nil ? 7 : 8)
        .frame(width: width, alignment: .leading)
        .opacity(isEnabled ? 1 : 0.54)
    }

    private func icon(style: ConductorUsagePanelStyle) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(iconFill(style: style))
            if let systemImageName,
               !systemImageName.isEmpty
            {
                Image(systemName: systemImageName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(iconColor(style: style))
            }
        }
        .frame(width: 23, height: 23)
    }

    private func primaryColor(style: ConductorUsagePanelStyle) -> Color {
        isHighlighted ? style.primaryText : style.primaryText
    }

    private func secondaryColor(style: ConductorUsagePanelStyle) -> Color {
        isHighlighted ? style.primaryText.opacity(0.72) : style.secondaryText
    }

    private func iconColor(style: ConductorUsagePanelStyle) -> Color {
        isHighlighted ? style.primaryText : style.emphasis
    }

    private func iconFill(style: ConductorUsagePanelStyle) -> Color {
        if isHighlighted {
            return style.emphasis.opacity(style.usesDarkChrome ? 0.22 : 0.16)
        }
        return style.controlStrongFill.opacity(style.usesDarkChrome ? 0.22 : 0.32)
    }
}
