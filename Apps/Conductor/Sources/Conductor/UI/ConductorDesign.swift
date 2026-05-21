@preconcurrency import AppKit
import SwiftUI

private struct ConductorFontScaleKey: EnvironmentKey {
    static let defaultValue = AppearanceFontScale.standard
}

private struct ConductorFontFamilyKey: EnvironmentKey {
    static let defaultValue = AppearanceFontFamily.system
}

private struct ConductorThemeKey: EnvironmentKey {
    static let defaultValue = TerminalTheme.graphite
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

    var conductorFontFamily: AppearanceFontFamily {
        get { self[ConductorFontFamilyKey.self] }
        set { self[ConductorFontFamilyKey.self] = newValue }
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
        family: AppearanceFontFamily = ConductorAppearanceRuntime.fontFamily,
        scale: AppearanceFontScale
    ) -> Font {
        .system(size: scale.size(size), weight: weight, design: family.fontDesign(fallback: design))
    }
}

extension NSFont {
    static func conductorSystemFont(
        ofSize size: CGFloat,
        weight: NSFont.Weight = .regular,
        family: AppearanceFontFamily = ConductorAppearanceRuntime.fontFamily,
        scale: AppearanceFontScale
    ) -> NSFont {
        family.systemFont(ofSize: scale.size(size), weight: weight)
    }

    static func conductorMonospacedSystemFont(
        ofSize size: CGFloat,
        weight: NSFont.Weight = .regular,
        scale: AppearanceFontScale
    ) -> NSFont {
        .monospacedSystemFont(ofSize: scale.size(size), weight: weight)
    }
}

extension AppearanceFontFamily {
    func fontDesign(fallback: Font.Design = .default) -> Font.Design {
        switch self {
        case .system:
            fallback
        case .rounded:
            .rounded
        case .serif:
            .serif
        case .monospaced:
            .monospaced
        }
    }

    func systemFont(ofSize size: CGFloat, weight: NSFont.Weight) -> NSFont {
        switch self {
        case .system:
            return .systemFont(ofSize: size, weight: weight)
        case .monospaced:
            return .monospacedSystemFont(ofSize: size, weight: weight)
        case .rounded, .serif:
            let base = NSFont.systemFont(ofSize: size, weight: weight)
            let design: NSFontDescriptor.SystemDesign = self == .rounded ? .rounded : .serif
            guard let descriptor = base.fontDescriptor.withDesign(design) else {
                return base
            }
            return NSFont(descriptor: descriptor, size: size) ?? base
        }
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

        static let textPrimary = Color.primary
        static let textSecondary = Color.secondary
        static let textTertiary = Color.secondary.opacity(0.68)

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
        static let sidebar: CGFloat = 20
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
        static let shellLeading: CGFloat = 2
        static let shellTrailing: CGFloat = 0
        static let shellTop: CGFloat = 0
        static let shellBottom: CGFloat = 0
        static let shellGap: CGFloat = 0
        static let shellJoinerWidth: CGFloat = 0
        static let sidebarWidth: CGFloat = 230
        static let sidebarCollapsedWidth: CGFloat = 88
        static let sidebarX: CGFloat = 8
        static let sidebarTop: CGFloat = 0
        static let sidebarBottom: CGFloat = 0
        static let toolbarHeight: CGFloat = 34
        static let toolbarX: CGFloat = 0
        static let toolbarGap: CGFloat = 5
        static let terminalInset: CGFloat = 0
        static let splitGutter: CGFloat = 10
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
                        Color.white.opacity(topHighlightOpacity * clarity.highlightMultiplier),
                        Color.white.opacity(midHighlightOpacity * clarity.highlightMultiplier),
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
        case .sidebar:
            theme.shellPanelBackground.opacity(clarity.glassTintMultiplier)
        case .settings, .palette, .panel:
            theme.floatingPanelWash.opacity(clarity.glassTintMultiplier)
        case .card, .controlGroup, .terminalToolbar:
            style.tint.opacity(clarity.glassTintMultiplier)
        }
    }

    private var resolvedStroke: Color {
        switch style {
        case .sidebar:
            theme.shellStroke.opacity((theme.usesDarkChrome ? 0.42 : 0.50) * clarity.strokeMultiplier)
        case .settings, .palette, .panel:
            theme.floatingStroke.opacity(clarity.strokeMultiplier)
        case .card, .controlGroup, .terminalToolbar:
            style.stroke.opacity(clarity.strokeMultiplier)
        }
    }

    private var topHighlightOpacity: Double {
        if style == .settings || style == .palette || style == .panel {
            return theme.usesDarkChrome ? 0.018 : 0.028
        }
        if theme.usesDarkChrome {
            if style == .sidebar {
                return 0.020
            }
            return style == .terminalToolbar ? 0.045 : 0.075
        }
        if style == .sidebar {
            return 0.040
        }
        return style == .terminalToolbar ? 0.08 : 0.34
    }

    private var midHighlightOpacity: Double {
        if style == .settings || style == .palette || style == .panel {
            return theme.usesDarkChrome ? 0.006 : 0.010
        }
        if theme.usesDarkChrome {
            return 0.012
        }
        return style == .sidebar ? 0.014 : 0.04
    }

    @ViewBuilder
    private var surfaceFill: some View {
        if style == .settings || style == .palette || style == .panel {
            surfaceShape
                .fill(theme.floatingPanelBase)
                .overlay {
                    surfaceShape
                        .fill(resolvedTint)
                }
                .overlay {
                    surfaceShape
                        .fill(Color.white.opacity((theme.usesDarkChrome ? 0.004 : 0.010) * clarity.highlightMultiplier))
                }
        } else if style == .sidebar {
            surfaceShape
                .fill(theme.shellPanelBackground)
                .overlay {
                    surfaceShape
                        .fill(resolvedTint)
                }
                .overlay {
                    surfaceShape
                        .fill(theme.usesDarkChrome ? theme.terminalBackground.opacity(0.18) : Color.white.opacity(0.16))
                }
                .overlay {
                    LinearGradient(
                        colors: [
                            Color.white.opacity(theme.usesDarkChrome ? 0.018 : 0.20),
                            Color.clear,
                            theme.terminalBackground.opacity(theme.usesDarkChrome ? 0.16 : 0.030)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .clipShape(surfaceShape)
                }
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
                .opacity(theme.usesDarkChrome ? 0.82 : 0.42)
            LinearGradient(
                colors: theme.windowBackdropStops.map { $0.opacity(theme.usesDarkChrome ? 0.90 : 0.58) },
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
                    Color.white.opacity(theme.usesDarkChrome ? 0.045 : 0.26),
                    Color.clear,
                    Color.black.opacity(theme.usesDarkChrome ? 0.18 : 0.035)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            ConductorBackdropMotif(theme: theme)
        }
    }
}

private struct ConductorBackdropMotif: View {
    let theme: TerminalTheme

    var body: some View {
        GeometryReader { proxy in
            switch theme.designLanguage {
            case .neon:
                Path { path in
                    let step: CGFloat = 42
                    var x: CGFloat = 0
                    while x <= proxy.size.width {
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: proxy.size.height))
                        x += step
                    }
                    var y: CGFloat = 0
                    while y <= proxy.size.height {
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: proxy.size.width, y: y))
                        y += step
                    }
                }
                .stroke(theme.accent.opacity(0.045), lineWidth: 0.8)
            case .paper, .editorial:
                VStack(spacing: 26) {
                    ForEach(0..<28, id: \.self) { _ in
                        Rectangle()
                            .fill(theme.shellStroke.opacity(0.18))
                            .frame(height: 1)
                    }
                }
                .padding(.top, 20)
            case .glass, .fluid, .frost:
                ZStack {
                    Circle()
                        .fill(theme.accent.opacity(theme.usesDarkChrome ? 0.10 : 0.14))
                        .frame(width: proxy.size.width * 0.36)
                        .blur(radius: 52)
                        .offset(x: proxy.size.width * 0.30, y: -proxy.size.height * 0.20)
                    RoundedRectangle(cornerRadius: 36, style: .continuous)
                        .stroke(Color.white.opacity(theme.usesDarkChrome ? 0.040 : 0.13), lineWidth: 1)
                        .frame(width: proxy.size.width * 0.34, height: proxy.size.height * 0.48)
                        .offset(x: proxy.size.width * 0.25, y: proxy.size.height * 0.08)
                }
            case .botanical:
                HStack(alignment: .bottom, spacing: 22) {
                    ForEach(0..<14, id: \.self) { index in
                        Capsule()
                            .fill(theme.accent.opacity(index.isMultiple(of: 2) ? 0.050 : 0.026))
                            .frame(width: 8, height: CGFloat(80 + index * 12))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(.trailing, 42)
            case .sunlit, .warm:
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.18),
                        theme.accent.opacity(0.050),
                        Color.clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            case .studio, .minimal, .system:
                EmptyView()
            }
        }
        .allowsHitTesting(false)
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

    static let shellLeadingPadding = ConductorTokens.Space.shellLeading
    static let shellTrailingPadding = ConductorTokens.Space.shellTrailing
    static let shellTopPadding = ConductorTokens.Space.shellTop
    static let shellBottomPadding = ConductorTokens.Space.shellBottom
    static let shellGap = ConductorTokens.Space.shellGap
    static let shellJoinerWidth = ConductorTokens.Space.shellJoinerWidth
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
    nonisolated(unsafe) private static var reducedMotion = false

    // Motion is part of the interaction model: feedback is local, navigation
    // preserves continuity, spatial motion changes layout, and reveal motion
    // introduces transient panels. Terminal surfaces opt out of all of these.
    static var micro: Animation? {
        reducedMotion ? nil : .easeOut(duration: 0.040)
    }

    static var hover: Animation? {
        feedback
    }

    static var feedback: Animation? {
        reducedMotion ? nil : .easeOut(duration: 0.045)
    }

    static var press: Animation? {
        reducedMotion ? nil : .easeOut(duration: 0.032)
    }

    static var reveal: Animation? {
        reducedMotion ? nil : .smooth(duration: 0.135, extraBounce: 0.012)
    }

    static var search: Animation? {
        reducedMotion ? nil : .smooth(duration: 0.115, extraBounce: 0.010)
    }

    static var scroll: Animation? {
        reducedMotion ? nil : .smooth(duration: 0.145, extraBounce: 0.0)
    }

    static var selection: Animation? {
        navigation
    }

    static var selectionGlide: Animation? {
        magnetic(duration: 0.155, bounce: 0.016)
    }

    static var navigation: Animation? {
        magnetic(duration: 0.125, bounce: 0.018)
    }

    static var standard: Animation? {
        reducedMotion ? nil : .easeOut(duration: 0.095)
    }

    static var panel: Animation? {
        reducedMotion ? nil : .smooth(duration: 0.135, extraBounce: 0.012)
    }

    static var list: Animation? {
        magnetic(duration: 0.115, bounce: 0.014)
    }

    static var layout: Animation? {
        spatial
    }

    static var spatial: Animation? {
        magnetic(duration: 0.18, bounce: 0.020)
    }

    static var emphasized: Animation? {
        magnetic(duration: 0.19, bounce: 0.026)
    }

    static var attention: Animation? {
        reducedMotion ? nil : .smooth(duration: 0.165, extraBounce: 0.024)
    }

    static var dragPreview: Animation? {
        reducedMotion ? nil : .easeOut(duration: 0.075)
    }

    static var panelTransition: AnyTransition {
        reducedMotion ? .identity : .modifier(
            active: ConductorPanelRevealModifier(opacity: 0, scale: 0.988, y: -4, blur: 2),
            identity: ConductorPanelRevealModifier(opacity: 1, scale: 1, y: 0, blur: 0)
        )
    }

    static var settingsPanelTransition: AnyTransition {
        reducedMotion ? .identity : .opacity
    }

    static var searchTransition: AnyTransition {
        reducedMotion ? .identity : .modifier(
            active: ConductorPanelRevealModifier(opacity: 0, scale: 0.992, y: -4, blur: 1.5),
            identity: ConductorPanelRevealModifier(opacity: 1, scale: 1, y: 0, blur: 0)
        )
    }

    static var tabTransition: AnyTransition {
        reducedMotion ? .identity : .opacity.combined(with: .scale(scale: 0.988))
    }

    static var rowTransition: AnyTransition {
        reducedMotion ? .identity : .opacity.combined(with: .scale(scale: 0.996, anchor: .center))
    }

    static var notificationRowTransition: AnyTransition {
        reducedMotion ? .identity : .asymmetric(
            insertion: .opacity.combined(with: .offset(y: -4)),
            removal: .opacity.combined(with: .scale(scale: 0.992, anchor: .center))
        )
    }

    static var dropPreviewTransition: AnyTransition {
        reducedMotion ? .identity : .opacity.combined(with: .scale(scale: 0.992, anchor: .center))
    }

    static func setReducedMotion(_ value: Bool) {
        reducedMotion = value
    }

    static func magnetic(duration: Double = 0.18, bounce: Double = 0.045) -> Animation? {
        reducedMotion ? nil : .smooth(duration: duration, extraBounce: bounce)
    }

    static func perform(_ action: () -> Void) {
        perform(standard, action)
    }

    static func perform(_ animation: Animation? = ConductorMotion.standard, _ action: () -> Void) {
        if let animation {
            withAnimation(animation, action)
        } else {
            withoutAnimation(action)
        }
    }

    static func withoutAnimation(_ action: () -> Void) {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction, action)
    }

    static func transaction(_ animation: Animation?) -> Transaction {
        var transaction = Transaction(animation: animation)
        if animation == nil {
            transaction.disablesAnimations = true
        }
        return transaction
    }
}

private struct ConductorPanelRevealModifier: ViewModifier {
    let opacity: Double
    let scale: CGFloat
    let y: CGFloat
    let blur: CGFloat

    func body(content: Content) -> some View {
        content
            .opacity(opacity)
            .scaleEffect(scale, anchor: .topTrailing)
            .offset(y: y)
            .blur(radius: blur)
    }
}

struct ConductorPressButtonStyle: ButtonStyle {
    var pressedScale: CGFloat = 1.0

    private var effectivePressedScale: CGFloat {
        max(pressedScale, 0.94)
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? effectivePressedScale : 1)
            .transaction { transaction in
                transaction.animation = ConductorMotion.press
                transaction.disablesAnimations = ConductorMotion.press == nil
            }
    }
}

struct ConductorMagneticGlow: View {
    var cornerRadius: CGFloat
    var active = true
    var lineWidth: CGFloat = 1
    @Environment(\.conductorTheme) private var theme

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .stroke(
                LinearGradient(
                    colors: [
                        Color.white.opacity(theme.usesDarkChrome ? 0.20 : 0.42),
                        theme.floatingEmphasis.opacity(theme.usesDarkChrome ? 0.22 : 0.16),
                        theme.shellStroke.opacity(theme.usesDarkChrome ? 0.24 : 0.36)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: lineWidth
            )
            .opacity(active ? 1 : 0)
            .allowsHitTesting(false)
    }
}

private final class MacNativeTooltipView: NSView {
    var text: String = "" {
        didSet {
            toolTip = text
            updateActiveTarget()
            if isHovering {
                showTooltip()
            }
        }
    }

    private var isHovering = false
    private var trackingAreaToken: NSTrackingArea?
    private weak var activeTarget: NSView?
    private var previousTargetTooltip: String?
    private weak var registeredToolTipView: NSView?
    private var registeredToolTipTag: NSView.ToolTipTag?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    override func layout() {
        super.layout()
        rebuildTrackingArea()
        registerWindowToolTipRect()
        updateActiveTarget()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        rebuildTrackingArea()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        isHovering = true
        updateActiveTarget()
        showTooltip()
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        updateActiveTarget()
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        isHovering = false
        restoreActiveTarget()
        closeTooltip()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            unregisterWindowToolTipRect()
            restoreActiveTarget()
            closeTooltip()
        }
        super.viewWillMove(toWindow: newWindow)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        rebuildTrackingArea()
        registerWindowToolTipRect()
    }

    @objc func view(
        _ view: NSView,
        stringForToolTip tag: NSView.ToolTipTag,
        point: NSPoint,
        userData data: UnsafeMutableRawPointer?
    ) -> String {
        text
    }

    private func rebuildTrackingArea() {
        if let trackingAreaToken {
            removeTrackingArea(trackingAreaToken)
        }
        guard !bounds.isEmpty else {
            trackingAreaToken = nil
            return
        }
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        trackingAreaToken = trackingArea
        addTrackingArea(trackingArea)
    }

    private func registerWindowToolTipRect() {
        unregisterWindowToolTipRect()
        guard !bounds.isEmpty,
              !text.isEmpty,
              let contentView = window?.contentView else {
            return
        }
        let rectInContent = contentView.convert(bounds, from: self)
        guard !rectInContent.isEmpty else { return }
        registeredToolTipView = contentView
        registeredToolTipTag = contentView.addToolTip(rectInContent, owner: self, userData: nil)
    }

    private func unregisterWindowToolTipRect() {
        guard let registeredToolTipView, let registeredToolTipTag else { return }
        registeredToolTipView.removeToolTip(registeredToolTipTag)
        self.registeredToolTipView = nil
        self.registeredToolTipTag = nil
    }

    private func updateActiveTarget() {
        guard !text.isEmpty,
              let window,
              let contentView = window.contentView else {
            restoreActiveTarget()
            return
        }

        let windowPoint = window.mouseLocationOutsideOfEventStream
        let localPoint = convert(windowPoint, from: nil)
        guard bounds.contains(localPoint) else {
            restoreActiveTarget()
            return
        }

        let contentPoint = contentView.convert(windowPoint, from: nil)
        guard let target = contentView.hitTest(contentPoint), target !== self else {
            restoreActiveTarget()
            return
        }

        if activeTarget !== target {
            restoreActiveTarget()
            activeTarget = target
            previousTargetTooltip = target.toolTip
        }
        target.toolTip = text
    }

    private func restoreActiveTarget() {
        if let activeTarget {
            activeTarget.toolTip = previousTargetTooltip
        }
        activeTarget = nil
        previousTargetTooltip = nil
    }

    private func showTooltip() {
        ConductorTooltipPanelManager.shared.show(text: text, relativeTo: self)
    }

    private func closeTooltip() {
        ConductorTooltipPanelManager.shared.hide(for: self)
    }
}

private struct MacNativeTooltipInstaller: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> MacNativeTooltipView {
        let view = MacNativeTooltipView(frame: .zero)
        view.text = text
        return view
    }

    func updateNSView(_ nsView: MacNativeTooltipView, context: Context) {
        nsView.text = text
    }
}

extension View {
    @ViewBuilder
    func macNativeTooltip(_ text: String, enabled: Bool = true) -> some View {
        if enabled && !text.isEmpty {
            self
                .help(text)
                .overlay {
                    GeometryReader { _ in
                        MacNativeTooltipInstaller(text: text)
                    }
                }
        } else {
            self
        }
    }
}

struct ConductorNativeIconButton: NSViewRepresentable {
    let systemImage: String
    let help: String
    var size: CGFloat = 28
    var symbolSize: CGFloat = 11
    var opacity: CGFloat = 0.62
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.conductorTheme) private var theme

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    func makeNSView(context: Context) -> NSButton {
        let button = NativeTooltipButton(frame: NSRect(x: 0, y: 0, width: size, height: size))
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.imagePosition = .imageOnly
        button.setButtonType(.momentaryChange)
        button.target = context.coordinator
        button.action = #selector(Coordinator.performAction)
        button.focusRingType = .none
        button.translatesAutoresizingMaskIntoConstraints = false
        button.toolTip = help
        button.tooltipText = help
        configure(button)
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.action = action
        button.toolTip = help
        (button as? NativeTooltipButton)?.tooltipText = help
        button.isEnabled = isEnabled
        configure(button)
    }

    private func configure(_ button: NSButton) {
        button.image = NSImage(
            systemSymbolName: systemImage,
            accessibilityDescription: help
        )
        button.symbolConfiguration = NSImage.SymbolConfiguration(
            pointSize: symbolSize,
            weight: .semibold
        )
        button.contentTintColor = tintColor
    }

    private var tintColor: NSColor {
        if theme.usesDarkChrome {
            return NSColor.white.withAlphaComponent(opacity)
        }
        return NSColor.labelColor.withAlphaComponent(opacity)
    }

    final class Coordinator: NSObject {
        var action: () -> Void

        init(action: @escaping () -> Void) {
            self.action = action
        }

        @objc func performAction() {
            action()
        }
    }

    final class NativeTooltipButton: NSButton {
        var tooltipText = "" {
            didSet {
                toolTip = tooltipText
                if isHovering {
                    showTooltip()
                }
            }
        }

        private var isHovering = false
        private var trackingAreaToken: NSTrackingArea?

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let trackingAreaToken {
                removeTrackingArea(trackingAreaToken)
            }
            let trackingArea = NSTrackingArea(
                rect: bounds,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
            trackingAreaToken = trackingArea
            addTrackingArea(trackingArea)
        }

        override func mouseEntered(with event: NSEvent) {
            super.mouseEntered(with: event)
            isHovering = true
            showTooltip()
        }

        override func mouseExited(with event: NSEvent) {
            super.mouseExited(with: event)
            isHovering = false
            closeTooltip()
        }

        override func mouseDown(with event: NSEvent) {
            closeTooltip()
            super.mouseDown(with: event)
        }

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            if newWindow == nil {
                closeTooltip()
            }
            super.viewWillMove(toWindow: newWindow)
        }

        private func showTooltip() {
            ConductorTooltipPanelManager.shared.show(text: tooltipText, relativeTo: self)
        }

        private func closeTooltip() {
            ConductorTooltipPanelManager.shared.hide(for: self)
        }
    }
}

@MainActor
private final class ConductorTooltipPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
private final class ConductorTooltipPanelManager {
    static let shared = ConductorTooltipPanelManager()

    private weak var sourceView: NSView?
    private var panel: ConductorTooltipPanel?

    func show(text: String, relativeTo view: NSView) {
        guard !text.isEmpty,
              !view.bounds.isEmpty,
              let sourceWindow = view.window,
              let screen = sourceWindow.screen ?? NSScreen.main else {
            hide()
            return
        }

        let viewController = ConductorNativeTooltipContentViewController(text: text)
        viewController.loadViewIfNeeded()
        let fittingSize = viewController.view.fittingSize
        let size = NSSize(
            width: min(260, max(48, fittingSize.width)),
            height: max(28, fittingSize.height)
        )

        let anchorInWindow = view.convert(view.bounds, to: nil)
        let anchorInScreen = sourceWindow.convertToScreen(anchorInWindow)
        let visibleFrame = screen.visibleFrame
        let spacing: CGFloat = 7
        var origin = NSPoint(
            x: anchorInScreen.midX - size.width / 2,
            y: anchorInScreen.minY - size.height - spacing
        )

        if origin.y < visibleFrame.minY {
            origin.y = anchorInScreen.maxY + spacing
        }
        origin.x = min(
            max(origin.x, visibleFrame.minX + 6),
            visibleFrame.maxX - size.width - 6
        )

        let panel = self.panel ?? makePanel()
        self.panel = panel
        sourceView = view
        panel.contentViewController = viewController
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.orderFrontRegardless()
    }

    func hide(for view: NSView) {
        guard sourceView === view else { return }
        hide()
    }

    func hide() {
        panel?.orderOut(nil)
        sourceView = nil
    }

    private func makePanel() -> ConductorTooltipPanel {
        let panel = ConductorTooltipPanel(
            contentRect: NSRect(x: 0, y: 0, width: 52, height: 30),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.transient, .ignoresCycle]
        return panel
    }
}

private final class ConductorNativeTooltipContentViewController: NSViewController {
    private let text: String

    init(text: String) {
        self.text = text
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        self.text = ""
        super.init(coder: coder)
    }

    override func loadView() {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 11.5, weight: .medium)
        label.textColor = NSColor.white.withAlphaComponent(0.92)
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor(calibratedWhite: 0.07, alpha: 0.94).cgColor
        container.layer?.cornerRadius = 7
        container.layer?.masksToBounds = true
        container.layer?.borderWidth = 1 / max(NSScreen.main?.backingScaleFactor ?? 2, 1)
        container.layer?.borderColor = NSColor.white.withAlphaComponent(0.14).cgColor
        container.addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 9),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -9),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 5),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -5),
            container.widthAnchor.constraint(lessThanOrEqualToConstant: 260),
            container.widthAnchor.constraint(greaterThanOrEqualToConstant: 48)
        ])

        view = container
    }
}

struct ConductorIconButton: View {
    let systemImage: String
    let help: String
    var title: String? = nil
    var disabled = false
    var active = false
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorFontFamily) private var fontFamily
    @Environment(\.conductorTheme) private var theme

    private var foreground: Color {
        active ? theme.shellChromeText : theme.shellChromeText.opacity(hovering ? 0.82 : 0.64)
    }

    private var buttonStroke: Color {
        if theme.usesDarkChrome {
            return Color.white.opacity(active ? 0.105 : (hovering ? 0.075 : 0.034))
        }
        return theme.shellStroke.opacity(active ? 0.58 : (hovering ? 0.42 : 0.26))
    }

    private var buttonFill: Color {
        if theme.usesDarkChrome {
            return Color.white.opacity(active ? 0.060 : (hovering ? 0.040 : 0.008))
        }
        return active ? theme.shellSelectedFill.opacity(0.70) : (hovering ? theme.shellHoverFill.opacity(0.66) : theme.shellControlFill.opacity(0.48))
    }

    var body: some View {
        Button {
            guard !disabled else { return }
            action()
        } label: {
            HStack(spacing: title == nil ? 0 : 5) {
                Image(systemName: systemImage)
                    .font(.conductorSystem(size: 11, weight: .semibold, family: fontFamily, scale: fontScale))
                if let title {
                    Text(title)
                        .font(.conductorSystem(size: 10.5, weight: .semibold, family: fontFamily, scale: fontScale))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, title == nil ? 0 : 8)
            .frame(width: title == nil ? 23 : nil, height: 23)
            .background(buttonFill)
            .overlay {
                RoundedRectangle(cornerRadius: ConductorTokens.Radius.control, style: .continuous)
                    .stroke(buttonStroke, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: ConductorTokens.Radius.control, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: ConductorTokens.Radius.control, style: .continuous))
        }
        .buttonStyle(ConductorPressButtonStyle(pressedScale: 0.97))
        .disabled(disabled)
        .opacity(disabled ? 0.34 : 1)
        .scaleEffect(hovering && !disabled ? 1.018 : 1)
        .animation(ConductorMotion.selection, value: active)
        .animation(ConductorMotion.micro, value: disabled)
        .animation(ConductorMotion.hover, value: hovering)
        .onHover { hovering = $0 }
        .fixedSize(horizontal: true, vertical: false)
        .layoutPriority(2)
        .macNativeTooltip(help, enabled: title == nil)
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
                    .init(color: .black, location: 0),
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
    @Environment(\.conductorTheme) private var theme

    var body: some View {
        HStack(spacing: 1) {
            content
        }
        .padding(2)
        .background(theme.usesDarkChrome ? theme.terminalRaisedBackground.opacity(0.46) : theme.shellControlFill.opacity(0.38))
        .clipShape(RoundedRectangle(cornerRadius: ConductorTokens.Radius.controlGroup - 2, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ConductorTokens.Radius.controlGroup - 2, style: .continuous)
                .stroke(theme.usesDarkChrome ? Color.white.opacity(0.046) : theme.shellStroke.opacity(0.30), lineWidth: 1)
        }
        .fixedSize(horizontal: true, vertical: false)
        .layoutPriority(2)
    }
}

struct ConductorSegmentDivider: View {
    @Environment(\.conductorTheme) private var theme

    var body: some View {
        Rectangle()
            .fill(theme.usesDarkChrome ? Color.white.opacity(0.032) : theme.shellStroke.opacity(0.34))
            .frame(width: 1, height: 14)
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
                        .fill(theme.terminalBackground.opacity(theme.usesDarkChrome ? 0.88 : 0.72))
                    LinearGradient(
                        colors: [
                            theme.terminalRaisedBackground.opacity(theme.usesDarkChrome ? 0.82 : 0.60),
                            theme.terminalChrome.opacity(theme.usesDarkChrome ? 0.54 : 0.42),
                            theme.terminalBackground.opacity(theme.usesDarkChrome ? 0.70 : 0.56)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    LinearGradient(
                        colors: [
                            Color.white.opacity(theme.usesDarkChrome ? 0.012 : 0.018),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
            }
            .overlay(alignment: .bottom) {
                LinearGradient(
                    colors: [
                        Color.clear,
                        theme.terminalOuterStroke.opacity(theme.usesDarkChrome ? 0.30 : 0.22),
                        Color.black.opacity(theme.usesDarkChrome ? 0.10 : 0.025),
                        Color.clear
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                    .frame(height: 1)
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
        applyTextAppearance(to: field)
        field.delegate = context.coordinator
        field.lineBreakMode = .byTruncatingTail
        field.usesSingleLineMode = true
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        context.coordinator.attach(field)
        DispatchQueue.main.async {
            field.window?.makeFirstResponder(field)
            applyTextAppearance(to: field)
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
        applyTextAppearance(to: field)
        context.coordinator.text = $text
        context.coordinator.onCommit = onCommit
        context.coordinator.onCancel = onCancel
        context.coordinator.attach(field)
    }

    private func applyTextAppearance(to field: NSTextField) {
        field.textColor = textColor
        guard let editor = field.currentEditor() as? NSTextView else { return }
        editor.textColor = textColor
        editor.insertionPointColor = textColor
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
