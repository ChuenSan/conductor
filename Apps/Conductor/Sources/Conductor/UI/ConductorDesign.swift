@preconcurrency import AppKit
import SwiftUI

private struct ConductorFontScaleKey: EnvironmentKey {
    static let defaultValue = AppearanceFontScale.standard
}

private struct ConductorFontFamilyKey: EnvironmentKey {
    static let defaultValue = AppearanceFontFamily.system
}

private struct ConductorThemeKey: EnvironmentKey {
    static let defaultValue = TerminalTheme.codexDark
}

private struct ConductorSplitResizeActiveKey: EnvironmentKey {
    static let defaultValue = false
}

private struct ConductorFilePanelLayoutActiveKey: EnvironmentKey {
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

    var conductorFilePanelLayoutActive: Bool {
        get { self[ConductorFilePanelLayoutActiveKey.self] }
        set { self[ConductorFilePanelLayoutActiveKey.self] = newValue }
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
    enum Chrome {
        static let separatorOpacity: Double = 0.055
        static let separatorOpacityDark: Double = 0.095
        static let structuralSeparatorOpacity: Double = 0.10
        static let structuralSeparatorOpacityDark: Double = 0.14
        static let hoverOpacity: Double = 0.030
        static let hoverOpacityDark: Double = 0.040
        static let selectionOpacity: Double = 0.070
        static let selectionOpacityDark: Double = 0.105
        static let controlFillOpacity: Double = 0.026
        static let controlFillOpacityDark: Double = 0.034
        static let controlStrongFillOpacity: Double = 0.042
        static let controlStrongFillOpacityDark: Double = 0.052
        static let dropTargetFillOpacity: Double = 0.075
        static let dropTargetFillOpacityDark: Double = 0.095
        static let dropTargetStrokeOpacity: Double = 0.46
        static let dropTargetStrokeOpacityDark: Double = 0.54
        static let focusRingOpacity: Double = 0.58
        static let focusRingOpacityDark: Double = 0.68

        static func separator(dark: Bool) -> Color {
            Color.primary.opacity(dark ? separatorOpacityDark : separatorOpacity)
        }

        static func structuralSeparator(dark: Bool) -> Color {
            Color.primary.opacity(dark ? structuralSeparatorOpacityDark : structuralSeparatorOpacity)
        }

        static func hover(dark: Bool) -> Color {
            Color.primary.opacity(dark ? hoverOpacityDark : hoverOpacity)
        }

        static func selection(dark: Bool) -> Color {
            Color.accentColor.opacity(dark ? selectionOpacityDark : selectionOpacity)
        }

        static func dropTargetFill(dark: Bool) -> Color {
            Color.accentColor.opacity(dark ? dropTargetFillOpacityDark : dropTargetFillOpacity)
        }

        static func dropTargetStroke(dark: Bool) -> Color {
            Color.accentColor.opacity(dark ? dropTargetStrokeOpacityDark : dropTargetStrokeOpacity)
        }

        static func focusRing(dark: Bool) -> Color {
            Color.accentColor.opacity(dark ? focusRingOpacityDark : focusRingOpacity)
        }
    }

    enum Palette {
        static let textPrimary = Color.primary
        static let textSecondary = Color.secondary
        static let textTertiary = Color.secondary.opacity(0.68)
    }

    enum Radius {
        static let sidebar: CGFloat = 10
        static let panel: CGFloat = 8
        static let commandPalette: CGFloat = 8
        static let controlGroup: CGFloat = 8
        static let control: CGFloat = 6
        static let workspaceTab: CGFloat = 7
        static let terminalPane: CGFloat = 8
        static let terminalTab: CGFloat = 6
        static let row: CGFloat = 7
    }

    enum Space {
        static let shellLeading: CGFloat = 2
        static let shellTrailing: CGFloat = 0
        static let shellTop: CGFloat = 0
        static let shellBottom: CGFloat = 0
        static let shellGap: CGFloat = 0
        static let shellJoinerWidth: CGFloat = 0
        static let sidebarWidth: CGFloat = 230
        static let sidebarCollapsedWidth: CGFloat = 68
        static let sidebarCollapsedBodyWidth: CGFloat = 68
        static let sidebarCollapsedCapHeight: CGFloat = 50
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
    }

    enum Typography {
        static let appTitle = Font.system(size: 14, weight: .bold)
        static let appSubtitle = Font.system(size: 11)
        static let section = Font.system(size: 10, weight: .semibold)
        static let row = Font.system(size: 12.5, weight: .medium)
        static let rowSelected = Font.system(size: 12.5, weight: .semibold)
        static let toolbar = Font.system(size: 11, weight: .semibold)
        static let workspaceTab = Font.system(size: 12, weight: .medium)
        static let workspaceTabSelected = Font.system(size: 12, weight: .semibold)
        static let terminalTab = Font.system(size: 11, weight: .medium)
        static let terminalTabSelected = Font.system(size: 11, weight: .semibold)
        static let status = Font.system(size: 10.5, weight: .medium)
    }

    enum Shadow {
        static let panelOpacity = 0.045
        static let panelRadius: CGFloat = 14
        static let panelY: CGFloat = 6
        static let controlOpacity = 0.018
        static let controlRadius: CGFloat = 5
        static let controlY: CGFloat = 1
        static let selectedOpacity = 0.018
        static let selectedRadius: CGFloat = 6
        static let selectedY: CGFloat = 1
    }

    enum Settings {
        static func panelWash(dark: Bool) -> Color {
            Color.primary.opacity(dark ? 0.012 : 0.006)
        }

        static func panelChromeWash(dark: Bool) -> Color {
            Color.primary.opacity(dark ? 0.014 : 0.008)
        }

        static func panelStroke(dark: Bool) -> Color {
            ConductorTokens.Chrome.structuralSeparator(dark: dark).opacity(dark ? 0.34 : 0.26)
        }

        static func panelShadow(dark: Bool) -> Color {
            Color(nsColor: .shadowColor).opacity(dark ? 0.14 : 0.07)
        }

        static func subtleSeparator(dark: Bool) -> Color {
            ConductorTokens.Chrome.separator(dark: dark).opacity(0.42)
        }
    }
}

enum ConductorDesign {
    static let primaryText = ConductorTokens.Palette.textPrimary
    static let secondaryText = ConductorTokens.Palette.textSecondary
    static let tertiaryText = ConductorTokens.Palette.textTertiary

    static let shellLeadingPadding = ConductorTokens.Space.shellLeading
    static let shellTrailingPadding = ConductorTokens.Space.shellTrailing
    static let shellTopPadding = ConductorTokens.Space.shellTop
    static let shellBottomPadding = ConductorTokens.Space.shellBottom
    static let shellGap = ConductorTokens.Space.shellGap
    static let sidebarWidth = ConductorTokens.Space.sidebarWidth
    static let sidebarCollapsedWidth = ConductorTokens.Space.sidebarCollapsedWidth
    static let sidebarCollapsedBodyWidth = ConductorTokens.Space.sidebarCollapsedBodyWidth
    static let sidebarCollapsedCapHeight = ConductorTokens.Space.sidebarCollapsedCapHeight
    static let toolbarHeight = ConductorTokens.Space.toolbarHeight

    static func sidebarWidth(for appearance: AppearancePreferences) -> CGFloat {
        appearance.density.sidebarWidth
    }

    static func toolbarHeight(for appearance: AppearancePreferences) -> CGFloat {
        appearance.density.toolbarHeight
    }
}

enum ConductorMotion {
    nonisolated(unsafe) private static var reducedMotion = false

    enum Timing {
        static let tap: Double = 0.08
        static let feedback: Double = 0.10
        static let hover: Double = 0.10
        static let list: Double = 0.12
        static let standard: Double = 0.14
        static let search: Double = 0.16
        static let navigation: Double = 0.12
        static let reveal: Double = 0.16
        static let panelDrawer: Double = 0.18
        static let contentSwap: Double = 0.12
        static let spatial: Double = 0.0
        static let panel: Double = 0.18
        static let emphasized: Double = 0.16
        static let dragPreview: Double = 0.08
    }

    // Motion is part of the interaction model: feedback is local, navigation
    // preserves continuity, spatial motion changes layout, and reveal motion
    // introduces transient panels. Terminal surfaces opt out of all of these.
    static var micro: Animation? {
        nil
    }

    static var hover: Animation? {
        nil
    }

    static var feedback: Animation? {
        nil
    }

    static var press: Animation? {
        nil
    }

    static var reveal: Animation? {
        nil
    }

    static var search: Animation? {
        nil
    }

    static var scroll: Animation? {
        nil
    }

    static var selection: Animation? {
        navigation
    }

    static var selectionGlide: Animation? {
        nil
    }

    static var navigation: Animation? {
        nil
    }

    static var standard: Animation? {
        nil
    }

    static var panel: Animation? {
        nil
    }

    static var list: Animation? {
        nil
    }

    static var layout: Animation? {
        nil
    }

    static var spatial: Animation? {
        nil
    }

    static var emphasized: Animation? {
        nil
    }

    static var attention: Animation? {
        nil
    }

    static var delivery: Animation? {
        nil
    }

    static var cascade: Animation? {
        nil
    }

    static var contentSwap: Animation? {
        nil
    }

    static var dragPreview: Animation? {
        nil
    }

    static var panelDrawer: Animation? {
        nil
    }

    static var panelTransition: AnyTransition {
        .identity
    }

    static var settingsPanelTransition: AnyTransition {
        .identity
    }

    static var sidebarContentTransition: AnyTransition {
        .identity
    }

    static var searchTransition: AnyTransition {
        .identity
    }

    static func contentSwapTransition(edge: Edge) -> AnyTransition {
        .identity
    }

    static var tabTransition: AnyTransition {
        .identity
    }

    static var rowTransition: AnyTransition {
        .identity
    }

    static var dropPreviewTransition: AnyTransition {
        .identity
    }

    static func workspaceSpreadTransition(itemCount: Int) -> AnyTransition {
        .identity
    }

    static func setReducedMotion(_ value: Bool) {
        reducedMotion = value
    }

    static func rowTransition(itemCount: Int) -> AnyTransition {
        guard itemCount <= animatedCollectionLimit else { return .identity }
        return rowTransition
    }

    static func list(itemCount: Int) -> Animation? {
        guard itemCount <= animatedCollectionLimit else { return nil }
        return list
    }

    static func shouldAnimateDecorative(itemCount: Int, limit: Int = signatureCollectionLimit) -> Bool {
        false
    }

    static func cascadeDelay(index: Int, itemCount: Int) -> TimeInterval {
        0
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

    private static let animatedCollectionLimit = 48
    private static let signatureCollectionLimit = 24

}

struct ConductorVerticalFadeMask: View {
    var edgeHeight: CGFloat = 16
    var fadesTop = true
    var fadesBottom = true

    var body: some View {
        GeometryReader { proxy in
            let height = max(proxy.size.height, 1)
            let stop = min(edgeHeight / height, 0.45)
            LinearGradient(
                stops: [
                    .init(color: fadesTop ? .clear : .black, location: 0),
                    .init(color: .black, location: fadesTop ? stop : 0),
                    .init(color: .black, location: fadesBottom ? 1 - stop : 1),
                    .init(color: fadesBottom ? .clear : .black, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
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
        let field = ConductorRenameNSTextField()
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
        field.onAttachedToWindow = { [weak coordinator = context.coordinator] field in
            coordinator?.focusIfNeeded(selectAll: true)
            coordinator?.applyTextAppearance(to: field, textColor: textColor)
        }
        DispatchQueue.main.async {
            context.coordinator.focusIfNeeded(selectAll: true)
            context.coordinator.applyTextAppearance(to: field, textColor: textColor)
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
        context.coordinator.applyTextAppearance(to: field, textColor: textColor)
        context.coordinator.focusIfNeeded(selectAll: false)
    }

    private func applyTextAppearance(to field: NSTextField) {
        field.textColor = textColor
        guard let editor = field.currentEditor() as? NSTextView else { return }
        editor.textColor = textColor
        editor.insertionPointColor = textColor
    }

    static func dismantleNSView(_ field: NSTextField, coordinator: Coordinator) {
        if let field = field as? ConductorRenameNSTextField {
            field.onAttachedToWindow = nil
        }
        coordinator.detach()
    }

    final class ConductorRenameNSTextField: NSTextField {
        var onAttachedToWindow: ((ConductorRenameNSTextField) -> Void)?

        override var acceptsFirstResponder: Bool { true }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.window != nil else { return }
                self.onAttachedToWindow?(self)
            }
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate, @unchecked Sendable {
        var text: Binding<String>
        var onCommit: () -> Void
        var onCancel: () -> Void
        private var handledEndEditing = false
        private var didSelectInitialText = false
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

        @MainActor
        func focusIfNeeded(selectAll: Bool) {
            guard let field,
                  !handledEndEditing,
                  let window = field.window else {
                return
            }
            if window.firstResponder !== field,
               field.currentEditor() == nil {
                window.makeFirstResponder(field)
            }
            guard selectAll, !didSelectInitialText else { return }
            field.currentEditor()?.selectAll(nil)
            didSelectInitialText = true
        }

        @MainActor
        func applyTextAppearance(to field: NSTextField, textColor: NSColor) {
            field.textColor = textColor
            guard let editor = field.currentEditor() as? NSTextView else { return }
            editor.textColor = textColor
            editor.insertionPointColor = textColor
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
