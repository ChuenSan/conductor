@preconcurrency import AppKit
import SwiftUI

private struct ConductorFontScaleKey: EnvironmentKey {
    static let defaultValue = AppearanceFontScale.standard
}

private struct ConductorThemeKey: EnvironmentKey {
    static let defaultValue = TerminalTheme.codexDark
}

private struct ConductorSplitResizeActiveKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var conductorFontScale: AppearanceFontScale {
        get { self[ConductorFontScaleKey.self] }
        set { self[ConductorFontScaleKey.self] = newValue }
    }

    var conductorTheme: TerminalTheme {
        get { self[ConductorThemeKey.self] }
        set { self[ConductorThemeKey.self] = newValue }
    }

    var conductorSplitResizeActive: Bool {
        get { self[ConductorSplitResizeActiveKey.self] }
        set { self[ConductorSplitResizeActiveKey.self] = newValue }
    }
}

extension Font {
    static func conductorSystem(
        size: CGFloat,
        weight: Font.Weight = .regular,
        design: Font.Design = .default,
        scale: AppearanceFontScale
    ) -> Font {
        .system(size: scale.size(size), weight: weight, design: design)
    }
}

extension NSFont {
    static func conductorSystemFont(
        ofSize size: CGFloat,
        weight: NSFont.Weight = .regular,
        scale: AppearanceFontScale
    ) -> NSFont {
        .systemFont(ofSize: scale.size(size), weight: weight)
    }

    static func conductorMonospacedSystemFont(
        ofSize size: CGFloat,
        weight: NSFont.Weight = .regular,
        scale: AppearanceFontScale
    ) -> NSFont {
        .monospacedSystemFont(ofSize: scale.size(size), weight: weight)
    }
}

enum ConductorTokens {
    enum Palette {
        static let window = Color(red: 0.933, green: 0.949, blue: 0.969)
        static let canvas = Color(red: 0.933, green: 0.949, blue: 0.969)
        static let floatingPanelFallback = Color.white.opacity(0.62)
        static let floatingPanelStrong = Color.white.opacity(0.82)
        static let glassTint = Color.white.opacity(0.30)
        static let glassTintStrong = Color.white.opacity(0.48)
        static let glassTintOnDark = Color.white.opacity(0.035)
        static let glassStroke = Color.white.opacity(0.60)
        static let glassStrokeSubtle = Color.white.opacity(0.34)
        static let glassShadow = Color.clear
        static let terminalRaised = Color(red: 0.024, green: 0.035, blue: 0.052)
        static let terminalChrome = Color(red: 0.047, green: 0.071, blue: 0.106)
        static let terminalChromeSelected = Color.clear
        static let terminalText = Color(red: 0.894, green: 0.918, blue: 0.953)
        static let terminalTextMuted = Color(red: 0.494, green: 0.537, blue: 0.612)
        static let splitGutter = Color(red: 0.063, green: 0.090, blue: 0.125)

        static let textPrimary = Color(red: 0.110, green: 0.130, blue: 0.170)
        static let textSecondary = Color(red: 0.405, green: 0.443, blue: 0.505)
        static let textTertiary = Color(red: 0.604, green: 0.631, blue: 0.678)

        static let selectedFill = Color.black.opacity(0.042)
        static let inactiveFill = Color.white.opacity(0.58)
        static let subtleFill = Color.white.opacity(0.36)
        static let hoverFill = Color.black.opacity(0.040)

        static let strokeSubtle = Color.black.opacity(0.075)
        static let strokeMedium = Color.black.opacity(0.120)
        static let strokeOnDark = Color.white.opacity(0.12)
        static let warmAccent = Color(red: 0.850, green: 0.470, blue: 0.020)
    }

    enum Radius {
        static let sidebar: CGFloat = 22
        static let panel: CGFloat = 26
        static let commandPalette: CGFloat = 24
        static let card: CGFloat = 16
        static let controlGroup: CGFloat = 14
        static let control: CGFloat = 9
        static let workspaceTab: CGFloat = 12
        static let terminalPane: CGFloat = 12
        static let terminalTab: CGFloat = 7
        static let row: CGFloat = 10
    }

    enum Space {
        static let shellX: CGFloat = 8
        static let shellTop: CGFloat = 8
        static let shellBottom: CGFloat = 8
        static let shellGap: CGFloat = 8
        static let sidebarWidth: CGFloat = 230
        static let sidebarCollapsedWidth: CGFloat = 88
        static let sidebarX: CGFloat = 8
        static let sidebarTop: CGFloat = 0
        static let sidebarBottom: CGFloat = 0
        static let toolbarHeight: CGFloat = 34
        static let toolbarX: CGFloat = 0
        static let toolbarGap: CGFloat = 5
        static let terminalInset: CGFloat = 0
        static let splitGutter: CGFloat = 4
        static let paneTabRailHeight: CGFloat = 26
        static let paneTabHeight: CGFloat = 21
        static let paneTabWidth: CGFloat = 118
        static let statusHeight: CGFloat = 18
        static let notificationPanelWidth: CGFloat = 300
        static let notificationPanelHeight: CGFloat = 360
        static let notificationPanelMinWidth: CGFloat = 280
        static let notificationPanelMinHeight: CGFloat = 300
    }

    enum Typography {
        static let appTitle = Font.system(size: 13.5, weight: .bold)
        static let appSubtitle = Font.system(size: 11)
        static let section = Font.system(size: 10, weight: .semibold)
        static let row = Font.system(size: 12, weight: .medium)
        static let rowSelected = Font.system(size: 12, weight: .semibold)
        static let toolbar = Font.system(size: 11, weight: .semibold)
        static let workspaceTab = Font.system(size: 11.5, weight: .semibold)
        static let workspaceTabSelected = Font.system(size: 11.5, weight: .bold)
        static let terminalTab = Font.system(size: 10.5, weight: .medium)
        static let terminalTabSelected = Font.system(size: 10.5, weight: .semibold)
        static let status = Font.system(size: 10.5, weight: .medium)
    }

    enum Shadow {
        static let panelOpacity = 0.0
        static let panelRadius: CGFloat = 0
        static let panelY: CGFloat = 0
        static let controlOpacity = 0.0
        static let controlRadius: CGFloat = 0
        static let controlY: CGFloat = 2
        static let selectedOpacity = 0.0
        static let selectedRadius: CGFloat = 0
        static let selectedY: CGFloat = 0
    }
}

enum ConductorGlassSurfaceStyle: Equatable {
    case sidebar
    case settings
    case palette
    case panel
    case card
    case controlGroup
    case terminalToolbar

    var radius: CGFloat {
        switch self {
        case .sidebar, .settings:
            ConductorTokens.Radius.sidebar
        case .palette:
            ConductorTokens.Radius.commandPalette
        case .panel:
            ConductorTokens.Radius.panel
        case .card:
            ConductorTokens.Radius.card
        case .controlGroup:
            ConductorTokens.Radius.controlGroup
        case .terminalToolbar:
            ConductorTokens.Radius.terminalPane
        }
    }

    var fallbackMaterial: Material {
        switch self {
        case .sidebar, .settings, .palette, .panel:
            .regularMaterial
        case .card, .controlGroup:
            .thinMaterial
        case .terminalToolbar:
            .ultraThinMaterial
        }
    }

    var tint: Color {
        switch self {
        case .sidebar:
            ConductorTokens.Palette.glassTintStrong
        case .settings:
            Color.white.opacity(0.12)
        case .palette, .panel:
            ConductorTokens.Palette.glassTint
        case .card:
            Color.white.opacity(0.20)
        case .controlGroup:
            ConductorTokens.Palette.glassTintOnDark
        case .terminalToolbar:
            Color.white.opacity(0.045)
        }
    }

    var stroke: Color {
        switch self {
        case .sidebar, .settings, .palette, .panel:
            ConductorTokens.Palette.glassStroke
        case .card:
            ConductorTokens.Palette.glassStrokeSubtle
        case .controlGroup, .terminalToolbar:
            ConductorTokens.Palette.strokeOnDark.opacity(0.50)
        }
    }

    var shadow: Color {
        switch self {
        case .controlGroup, .terminalToolbar:
            ConductorDesign.shadow(ConductorTokens.Shadow.controlOpacity)
        case .card:
            ConductorDesign.shadow(0.085)
        case .sidebar, .settings, .palette, .panel:
            ConductorTokens.Palette.glassShadow
        }
    }

    var shadowRadius: CGFloat {
        switch self {
        case .controlGroup, .terminalToolbar:
            ConductorTokens.Shadow.controlRadius
        case .card:
            12
        case .sidebar, .settings, .palette, .panel:
            ConductorTokens.Shadow.panelRadius
        }
    }

    var shadowY: CGFloat {
        switch self {
        case .controlGroup, .terminalToolbar:
            ConductorTokens.Shadow.controlY
        case .card:
            7
        case .sidebar, .settings, .palette, .panel:
            ConductorTokens.Shadow.panelY
        }
    }
}

struct ConductorGlassSurface<Content: View>: View {
    let style: ConductorGlassSurfaceStyle
    var clarity = ChromeClarity.balanced
    var interactive = false
    @ViewBuilder var content: Content
    @Environment(\.conductorTheme) private var theme

    var body: some View {
        content
            .background {
                surfaceFill
            }
            .clipShape(surfaceShape)
            .overlay {
                surfaceShape
                    .strokeBorder(resolvedStroke, lineWidth: clarity == .crisp ? 1.15 : 1)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .topLeading) {
                LinearGradient(
                    colors: [
                        Color.white.opacity((style == .terminalToolbar ? 0.08 : 0.34) * clarity.highlightMultiplier),
                        Color.white.opacity(0.04 * clarity.highlightMultiplier),
                        Color.clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .clipShape(surfaceShape)
                .allowsHitTesting(false)
            }
    }

    private var surfaceShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: style.radius, style: .continuous)
    }

    private var resolvedTint: Color {
        switch style {
        case .sidebar, .palette, .panel:
            theme.shellPanelBackground.opacity(clarity.glassTintMultiplier)
        case .settings:
            theme.settingsPanelWash.opacity(clarity.glassTintMultiplier)
        case .card, .controlGroup, .terminalToolbar:
            style.tint.opacity(clarity.glassTintMultiplier)
        }
    }

    private var resolvedStroke: Color {
        switch style {
        case .sidebar, .palette, .panel:
            theme.shellStroke.opacity(clarity.strokeMultiplier)
        case .settings:
            theme.settingsStroke.opacity(clarity.strokeMultiplier)
        case .card, .controlGroup, .terminalToolbar:
            style.stroke.opacity(clarity.strokeMultiplier)
        }
    }

    @ViewBuilder
    private var surfaceFill: some View {
        if style == .settings {
            surfaceShape
                .fill(theme.settingsPanelBase)
                .overlay {
                    surfaceShape
                        .fill(resolvedTint)
                }
                .overlay {
                    surfaceShape
                        .fill(Color.white.opacity(0.04 * clarity.highlightMultiplier))
                }
        } else if #available(macOS 26.0, *) {
            Color.clear
                .glassEffect(
                    Glass.regular.tint(resolvedTint).interactive(interactive),
                    in: surfaceShape
                )
        } else {
            surfaceShape
                .fill(style.fallbackMaterial)
                .overlay {
                    surfaceShape
                        .fill(resolvedTint)
                }
        }
    }
}

struct ConductorWindowBackdrop: View {
    let theme: TerminalTheme

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.regularMaterial)
            theme.windowBackdropStops[1]
                .opacity(0.42)
            LinearGradient(
                colors: theme.windowBackdropStops.map { $0.opacity(0.58) },
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [
                    theme.windowBackdropWash,
                    Color.clear
                ],
                center: .topTrailing,
                startRadius: 40,
                endRadius: 620
            )
            LinearGradient(
                colors: [
                    Color.white.opacity(0.26),
                    Color.clear,
                    Color.black.opacity(0.035)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

enum ConductorDesign {
    static let windowBackground = ConductorTokens.Palette.window
    static let canvasBackground = ConductorTokens.Palette.canvas
    static let sidebarBackground = ConductorTokens.Palette.floatingPanelFallback
    static let sidebarBackgroundStrong = ConductorTokens.Palette.floatingPanelStrong
    static let sidebarStroke = ConductorTokens.Palette.strokeSubtle
    static let toolbarStroke = ConductorTokens.Palette.strokeSubtle
    static let selectedFill = ConductorTokens.Palette.selectedFill
    static let inactiveFill = ConductorTokens.Palette.inactiveFill
    static let subtleFill = ConductorTokens.Palette.subtleFill
    static let hoverFill = ConductorTokens.Palette.hoverFill
    static let primaryText = ConductorTokens.Palette.textPrimary
    static let secondaryText = ConductorTokens.Palette.textSecondary
    static let tertiaryText = ConductorTokens.Palette.textTertiary
    static let terminalChrome = ConductorTokens.Palette.terminalChrome
    static let terminalChromeSelected = ConductorTokens.Palette.terminalChromeSelected
    static let terminalText = ConductorTokens.Palette.terminalText
    static let terminalTextMuted = ConductorTokens.Palette.terminalTextMuted
    static let divider = ConductorTokens.Palette.strokeMedium
    static let splitGutter = ConductorTokens.Palette.splitGutter
    static let warmAccent = ConductorTokens.Palette.warmAccent

    static let shellHorizontalPadding = ConductorTokens.Space.shellX
    static let shellTopPadding = ConductorTokens.Space.shellTop
    static let shellBottomPadding = ConductorTokens.Space.shellBottom
    static let shellGap = ConductorTokens.Space.shellGap
    static let sidebarWidth = ConductorTokens.Space.sidebarWidth
    static let sidebarCollapsedWidth = ConductorTokens.Space.sidebarCollapsedWidth
    static let sidebarCornerRadius = ConductorTokens.Radius.sidebar
    static let toolbarHeight = ConductorTokens.Space.toolbarHeight
    static let statusBarHeight = ConductorTokens.Space.statusHeight
    static let terminalCanvasInset = ConductorTokens.Space.terminalInset

    static func sidebarWidth(for appearance: AppearancePreferences) -> CGFloat {
        appearance.density.sidebarWidth
    }

    static func toolbarHeight(for appearance: AppearancePreferences) -> CGFloat {
        appearance.density.toolbarHeight
    }

    static func shadow(_ opacity: Double = 0.10, radius: CGFloat = 16, y: CGFloat = 8) -> Color {
        Color.black.opacity(opacity)
    }
}

enum ConductorMotion {
    static let micro = Animation.easeOut(duration: 0.12)
    static let standard = Animation.spring(response: 0.24, dampingFraction: 0.86, blendDuration: 0)
    static let layout = Animation.spring(response: 0.32, dampingFraction: 0.88, blendDuration: 0)
    static let emphasized = Animation.spring(response: 0.38, dampingFraction: 0.78, blendDuration: 0)

    static func perform(_ action: () -> Void) {
        withAnimation(standard, action)
    }

    static func perform(_ animation: Animation = ConductorMotion.standard, _ action: () -> Void) {
        withAnimation(animation, action)
    }
}

struct ConductorPressButtonStyle: ButtonStyle {
    var pressedScale: CGFloat = 0.96

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? pressedScale : 1)
            .animation(ConductorMotion.micro, value: configuration.isPressed)
    }
}

struct ConductorIconButton: View {
    let systemImage: String
    let help: String
    var title: String? = nil
    var disabled = false
    var active = false
    let action: () -> Void
    @Environment(\.conductorFontScale) private var fontScale

    var body: some View {
        HStack(spacing: title == nil ? 0 : 5) {
            Image(systemName: systemImage)
                .font(.conductorSystem(size: 10.5, weight: .medium, scale: fontScale))
            if let title {
                Text(title)
                    .font(.conductorSystem(size: 11, weight: .semibold, scale: fontScale))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .foregroundStyle(active ? ConductorDesign.terminalText : ConductorDesign.terminalTextMuted)
        .padding(.horizontal, title == nil ? 0 : 9)
        .frame(width: title == nil ? 24 : nil, height: 24)
        .background(active ? Color.white.opacity(0.060) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: ConductorTokens.Radius.control))
        .contentShape(RoundedRectangle(cornerRadius: ConductorTokens.Radius.control))
        .opacity(disabled ? 0.38 : 1)
        .onTapGesture {
            guard !disabled else { return }
            ConductorMotion.perform(.easeOut(duration: 0.10), action)
        }
        .accessibilityAddTraits(.isButton)
        .animation(ConductorMotion.standard, value: active)
        .animation(ConductorMotion.micro, value: disabled)
        .fixedSize(horizontal: true, vertical: false)
        .layoutPriority(2)
        .help(help)
    }
}

struct ConductorHorizontalFadeMask: View {
    var edgeWidth: CGFloat = 18

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let stop = min(edgeWidth / width, 0.45)
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: stop),
                    .init(color: .black, location: 1 - stop),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
    }
}

struct ConductorVerticalFadeMask: View {
    var edgeHeight: CGFloat = 16

    var body: some View {
        GeometryReader { proxy in
            let height = max(proxy.size.height, 1)
            let stop = min(edgeHeight / height, 0.45)
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: stop),
                    .init(color: .black, location: 1 - stop),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

struct ConductorPillGroup<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 1) {
            content
        }
        .padding(3)
        .background(Color.white.opacity(0.040))
        .clipShape(RoundedRectangle(cornerRadius: ConductorTokens.Radius.controlGroup, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ConductorTokens.Radius.controlGroup, style: .continuous)
                .stroke(ConductorTokens.Palette.strokeOnDark.opacity(0.34), lineWidth: 1)
        }
        .fixedSize(horizontal: true, vertical: false)
        .layoutPriority(2)
    }
}

struct ConductorSegmentDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.075))
            .frame(width: 1, height: 15)
    }
}

struct ConductorTerminalToolbarSurface<Content: View>: View {
    let theme: TerminalTheme
    @ViewBuilder var content: Content

    var body: some View {
        content
            .background {
                ZStack {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                    LinearGradient(
                        colors: [
                            theme.terminalChrome.opacity(0.82),
                            theme.terminalRaisedBackground.opacity(0.72)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.070),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
            }
    }
}

struct RenameTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var font: NSFont
    var textColor: NSColor
    var onCommit: () -> Void
    var onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onCommit: onCommit, onCancel: onCancel)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.placeholderString = placeholder
        field.font = font
        field.textColor = textColor
        field.delegate = context.coordinator
        field.lineBreakMode = .byTruncatingTail
        field.usesSingleLineMode = true
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        context.coordinator.attach(field)
        DispatchQueue.main.async {
            field.window?.makeFirstResponder(field)
            field.currentEditor()?.selectAll(nil)
        }
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        if field.stringValue != text {
            field.stringValue = text
        }
        field.placeholderString = placeholder
        field.font = font
        field.textColor = textColor
        context.coordinator.text = $text
        context.coordinator.onCommit = onCommit
        context.coordinator.onCancel = onCancel
        context.coordinator.attach(field)
    }

    static func dismantleNSView(_ field: NSTextField, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class Coordinator: NSObject, NSTextFieldDelegate, @unchecked Sendable {
        var text: Binding<String>
        var onCommit: () -> Void
        var onCancel: () -> Void
        private var handledEndEditing = false
        private weak var field: NSTextField?
        private var mouseMonitor: Any?

        init(text: Binding<String>, onCommit: @escaping () -> Void, onCancel: @escaping () -> Void) {
            self.text = text
            self.onCommit = onCommit
            self.onCancel = onCancel
        }

        deinit {
            detach()
        }

        func attach(_ field: NSTextField) {
            self.field = field
            installMouseMonitorIfNeeded()
        }

        func detach() {
            if let mouseMonitor {
                NSEvent.removeMonitor(mouseMonitor)
                self.mouseMonitor = nil
            }
            field = nil
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            text.wrappedValue = field.stringValue
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            guard !handledEndEditing else { return }
            if let field = notification.object as? NSTextField {
                text.wrappedValue = field.stringValue
            }
            handledEndEditing = true
            onCommit()
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.insertNewline(_:)):
                handledEndEditing = true
                text.wrappedValue = textView.string
                onCommit()
                control.window?.makeFirstResponder(nil)
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                handledEndEditing = true
                onCancel()
                control.window?.makeFirstResponder(nil)
                return true
            default:
                return false
            }
        }

        private func installMouseMonitorIfNeeded() {
            guard mouseMonitor == nil else { return }
            mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
                let windowNumber = event.windowNumber
                let locationInWindow = event.locationInWindow
                DispatchQueue.main.async { [weak self] in
                    self?.commitIfClickWasOutsideField(windowNumber: windowNumber, locationInWindow: locationInWindow)
                }
                return event
            }
        }

        @MainActor
        private func commitIfClickWasOutsideField(windowNumber: Int, locationInWindow: NSPoint) {
            guard let field,
                  !handledEndEditing else {
                return
            }

            if field.window?.windowNumber == windowNumber {
                let location = field.convert(locationInWindow, from: nil)
                if field.bounds.contains(location) {
                    return
                }
            }

            commitFromOutsideClick(field)
        }

        @MainActor
        private func commitFromOutsideClick(_ field: NSTextField) {
            guard !handledEndEditing else { return }
            handledEndEditing = true
            text.wrappedValue = field.stringValue
            onCommit()
            field.window?.makeFirstResponder(nil)
        }
    }
}
