import SwiftUI

enum ConductorIconButtonVariant {
    case toolbar
    case sidebarDock
    case sidebarRail
    case settingsIcon
    case fileManagerPanel(
        iconColor: Color,
        opacity: CGFloat,
        disabledOpacity: CGFloat,
        fontScale: AppearanceFontScale,
        fontFamily: AppearanceFontFamily
    )
}

struct ConductorIconButton: View {
    let state: ConductorControlState
    let variant: ConductorIconButtonVariant
    let action: () -> Void

    @State private var hovering = false
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorFontFamily) private var fontFamily
    @Environment(\.conductorTheme) private var theme

    init(
        state: ConductorControlState,
        variant: ConductorIconButtonVariant = .toolbar,
        action: @escaping () -> Void
    ) {
        self.state = state
        self.variant = variant
        self.action = action
    }

    init(
        systemImage: String,
        help: String,
        title: String? = nil,
        disabled: Bool = false,
        active: Bool = false,
        action: @escaping () -> Void
    ) {
        self.state = ConductorControlState(
            id: "\(systemImage)-\(title ?? help)",
            title: title,
            systemImage: systemImage,
            isEnabled: !disabled,
            isActive: active,
            tooltip: help,
            accessibilityLabel: title ?? help
        )
        self.variant = .toolbar
        self.action = action
    }

    var body: some View {
        Button {
            guard state.isEnabled else { return }
            action()
        } label: {
            label
                .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
        .buttonStyle(ConductorPressButtonStyle(pressedScale: 0.985, pressedOpacity: 0.96))
        .disabled(!state.isEnabled)
        .macNativeTooltip(state.tooltip)
        .accessibilityLabel(Text(state.accessibilityLabel))
        .opacity(opacity)
        .scaleEffect(hovering && state.isEnabled ? hoverScale : 1)
        .animation(ConductorMotion.selection, value: state.isActive)
        .animation(ConductorMotion.micro, value: state.isEnabled)
        .animation(ConductorMotion.hover, value: hovering)
        .conductorHover($hovering)
        .fixedSize(horizontal: true, vertical: false)
        .layoutPriority(2)
    }

    private var label: some View {
        HStack(spacing: state.title == nil ? 0 : 5) {
            Image(systemName: state.systemImage)
                .renderingMode(.template)
                .symbolRenderingMode(.monochrome)
                .font(iconFont)
            if let title = state.title {
                Text(title)
                    .font(titleFont)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, horizontalPadding)
        .frame(width: fixedWidth, height: height)
        .background(background)
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(buttonStroke, lineWidth: strokeWidth)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private var iconFont: Font {
        switch variant {
        case .toolbar:
            .conductorSystem(size: 11.4, weight: .semibold, family: fontFamily, scale: fontScale)
        case .sidebarDock:
            .conductorSystem(size: 12.5, weight: .semibold, scale: fontScale)
        case .sidebarRail:
            .conductorSystem(size: 13, weight: .semibold, scale: fontScale)
        case .settingsIcon:
            .system(size: 10, weight: .bold)
        case let .fileManagerPanel(_, _, _, scale, family):
            .conductorSystem(size: 12.5, weight: .semibold, family: family, scale: scale)
        }
    }

    private var titleFont: Font {
        .conductorSystem(size: 10.5, weight: .semibold, family: fontFamily, scale: fontScale)
    }

    private var foreground: Color {
        switch variant {
        case .toolbar:
            state.isActive ? theme.shellChromeText : theme.shellChromeText.opacity(hovering ? 0.82 : 0.64)
        case .sidebarDock:
            state.isEnabled ? theme.shellChromeText.opacity(0.86) : theme.shellChromeTextMuted.opacity(0.50)
        case .sidebarRail:
            state.isActive ? theme.floatingEmphasis : ConductorDesign.secondaryText
        case .settingsIcon:
            state.isEnabled ? theme.floatingEmphasis : ConductorDesign.tertiaryText
        case let .fileManagerPanel(iconColor, opacity, disabledOpacity, _, _):
            iconColor.opacity(state.isEnabled ? opacity : disabledOpacity)
        }
    }

    private var background: Color {
        switch variant {
        case .toolbar:
            if theme.usesDarkChrome {
                return Color.white.opacity(state.isActive ? 0.052 : (hovering ? 0.030 : 0.0))
            }
            return state.isActive ? theme.shellSelectedFill.opacity(0.52) : (hovering ? theme.shellHoverFill.opacity(0.42) : theme.shellControlFill.opacity(0.28))
        case .sidebarDock:
            return hovering && state.isEnabled ? theme.shellHoverFill.opacity(0.52) : theme.shellControlFill.opacity(0.20)
        case .sidebarRail:
            return state.isActive ? theme.shellSelectedFill.opacity(0.66) : (hovering ? theme.shellHoverFill.opacity(0.56) : Color.clear)
        case .settingsIcon:
            return hovering && state.isEnabled ? theme.floatingHoverFill : theme.floatingControlFill
        case .fileManagerPanel:
            return Color.clear
        }
    }

    private var buttonStroke: Color {
        switch variant {
        case .toolbar:
            if theme.usesDarkChrome {
                return Color.white.opacity(state.isActive ? 0.075 : (hovering ? 0.044 : 0.0))
            }
            return theme.shellStroke.opacity(state.isActive ? 0.38 : (hovering ? 0.28 : 0.16))
        case .sidebarDock, .sidebarRail, .settingsIcon, .fileManagerPanel:
            return Color.clear
        }
    }

    private var strokeWidth: CGFloat {
        switch variant {
        case .toolbar:
            0.6
        case .sidebarDock, .sidebarRail, .settingsIcon, .fileManagerPanel:
            0
        }
    }

    private var horizontalPadding: CGFloat {
        switch variant {
        case .toolbar:
            state.title == nil ? 0 : 8
        case .sidebarDock, .sidebarRail, .settingsIcon, .fileManagerPanel:
            0
        }
    }

    private var fixedWidth: CGFloat? {
        switch variant {
        case .toolbar:
            state.title == nil ? 26 : nil
        case .sidebarDock:
            28
        case .sidebarRail:
            34
        case .settingsIcon:
            24
        case .fileManagerPanel:
            28
        }
    }

    private var height: CGFloat {
        switch variant {
        case .toolbar:
            26
        case .sidebarDock:
            27
        case .sidebarRail:
            34
        case .settingsIcon:
            24
        case .fileManagerPanel:
            28
        }
    }

    private var cornerRadius: CGFloat {
        switch variant {
        case .toolbar:
            ConductorTokens.Radius.control
        case .sidebarDock:
            8
        case .sidebarRail:
            11
        case .settingsIcon:
            6
        case .fileManagerPanel:
            7
        }
    }

    private var opacity: CGFloat {
        guard state.isEnabled else {
            switch variant {
            case .toolbar:
                return 0.34
            case .sidebarDock:
                return 0.42
            case .sidebarRail:
                return 0.35
            case .settingsIcon:
                return 1
            case .fileManagerPanel:
                return 1
            }
        }
        return 1
    }

    private var hoverScale: CGFloat {
        switch variant {
        case .toolbar:
            1
        case .sidebarDock, .sidebarRail:
            1.002
        case .settingsIcon, .fileManagerPanel:
            1
        }
    }
}
