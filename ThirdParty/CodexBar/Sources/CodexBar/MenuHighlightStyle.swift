import SwiftUI

private struct MenuItemHighlightedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var menuItemHighlighted: Bool {
        get { self[MenuItemHighlightedKey.self] }
        set { self[MenuItemHighlightedKey.self] = newValue }
    }
}

enum MenuHighlightStyle {
    static let selectionText = Color(nsColor: .selectedMenuItemTextColor)
    static let normalPrimaryText = Color(nsColor: .controlTextColor)
    static let normalSecondaryText = Color(nsColor: .secondaryLabelColor)

    static func primary(_ highlighted: Bool) -> Color {
        if let style = ConductorUsageMenuStyle.current {
            return highlighted ? style.primaryText : style.primaryText
        }
        return highlighted ? self.selectionText : self.normalPrimaryText
    }

    static func secondary(_ highlighted: Bool) -> Color {
        if let style = ConductorUsageMenuStyle.current {
            return highlighted ? style.primaryText.opacity(0.94) : style.secondaryText
        }
        return highlighted ? self.selectionText : self.normalSecondaryText
    }

    static func error(_ highlighted: Bool) -> Color {
        if ConductorUsageMenuStyle.current != nil {
            return highlighted ? .primary : Color(nsColor: .systemRed)
        }
        return highlighted ? self.selectionText : Color(nsColor: .systemRed)
    }

    static func progressTrack(_ highlighted: Bool) -> Color {
        if let style = ConductorUsageMenuStyle.current {
            return highlighted
                ? style.primaryText.opacity(0.18)
                : style.controlFill.opacity(style.usesDarkChrome ? 0.40 : 0.46)
        }
        return highlighted ? self.selectionText.opacity(0.22) : Color(nsColor: .tertiaryLabelColor).opacity(0.22)
    }

    static func progressTint(_ highlighted: Bool, fallback: Color) -> Color {
        if let style = ConductorUsageMenuStyle.current, highlighted {
            return style.emphasis
        }
        return highlighted ? self.selectionText : fallback
    }

    static func selectionBackground(_ highlighted: Bool) -> Color {
        if let style = ConductorUsageMenuStyle.current {
            return highlighted ? ConductorUsageMenuStyle.plateFill(highlighted: true, style: style) : .clear
        }
        return highlighted ? Color(nsColor: .selectedContentBackgroundColor) : .clear
    }
}
