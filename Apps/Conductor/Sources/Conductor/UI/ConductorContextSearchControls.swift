import AppKit
import SwiftUI

enum ConductorSearchHistory {
    private static let prefix = "conductor.searchHistory."

    static func load(scope: String) -> [String] {
        UserDefaults.standard.stringArray(forKey: prefix + scope) ?? []
    }

    static func record(_ query: String, scope: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }
        var values = load(scope: scope)
        values.removeAll { $0.caseInsensitiveCompare(trimmed) == .orderedSame }
        values.insert(trimmed, at: 0)
        UserDefaults.standard.set(Array(values.prefix(10)), forKey: prefix + scope)
    }
}

struct ConductorContextSearchTextField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let focusToken: Int
    let theme: TerminalTheme
    let fontFamily: AppearanceFontFamily
    let fontScale: AppearanceFontScale
    let onNavigate: (Bool) -> Void
    let onClose: () -> Void

    func makeNSView(context: Context) -> ConductorSearchNSTextField {
        let field = ConductorSearchNSTextField()
        field.delegate = context.coordinator
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.lineBreakMode = .byTruncatingTail
        field.usesSingleLineMode = true
        field.onWindowAttached = { [weak coordinator = context.coordinator, weak field] in
            guard let field else { return }
            coordinator?.focusIfPossible(field)
        }
        applyStyle(to: field)
        return field
    }

    func updateNSView(_ field: ConductorSearchNSTextField, context: Context) {
        context.coordinator.text = $text
        context.coordinator.onNavigate = onNavigate
        context.coordinator.onClose = onClose
        context.coordinator.requestFocusIfNeeded(focusToken, field: field)
        if field.stringValue != text {
            field.stringValue = text
        }
        applyStyle(to: field)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onNavigate: onNavigate, onClose: onClose)
    }

    private func applyStyle(to field: NSTextField) {
        field.font = .conductorSystemFont(ofSize: 11.5, weight: .medium, family: fontFamily, scale: fontScale)
        field.textColor = NSColor(theme.shellChromeText)
        field.placeholderAttributedString = NSAttributedString(
            string: placeholder,
            attributes: [
                .foregroundColor: NSColor(theme.shellChromeText.opacity(0.42)),
                .font: NSFont.conductorSystemFont(ofSize: 11.5, weight: .medium, family: fontFamily, scale: fontScale)
            ]
        )
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>
        var onNavigate: (Bool) -> Void
        var onClose: () -> Void
        private var appliedFocusToken: Int?
        private var pendingFocusToken: Int?

        init(
            text: Binding<String>,
            onNavigate: @escaping (Bool) -> Void,
            onClose: @escaping () -> Void
        ) {
            self.text = text
            self.onNavigate = onNavigate
            self.onClose = onClose
        }

        func requestFocusIfNeeded(_ token: Int, field: ConductorSearchNSTextField) {
            guard appliedFocusToken != token else { return }
            pendingFocusToken = token
            focusIfPossible(field)
        }

        func focusIfPossible(_ field: ConductorSearchNSTextField) {
            guard let token = pendingFocusToken,
                  let window = field.window else {
                return
            }
            DispatchQueue.main.async { [weak self, weak field, weak window] in
                guard let self,
                      let field,
                      let window,
                      self.pendingFocusToken == token else {
                    return
                }
                window.makeFirstResponder(field)
                field.selectText(nil)
                self.appliedFocusToken = token
                self.pendingFocusToken = nil
            }
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            text.wrappedValue = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.insertNewline(_:)),
                 #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
                let previous = NSApp.currentEvent?.modifierFlags.contains(.shift) == true
                onNavigate(previous)
                return true
            case #selector(NSResponder.moveDown(_:)):
                onNavigate(false)
                return true
            case #selector(NSResponder.moveUp(_:)):
                onNavigate(true)
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                onClose()
                return true
            default:
                return false
            }
        }
    }
}

@MainActor
final class ConductorSearchNSTextField: NSTextField {
    var onWindowAttached: (() -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        onWindowAttached?()
    }
}

struct ConductorContextSearchIconButton: View {
    let systemImage: String
    let help: String
    var disabled = false
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.conductorTheme) private var theme

    var body: some View {
        Button {
            guard !disabled else { return }
            action()
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 10.5, weight: .bold))
                .foregroundStyle(theme.shellChromeText.opacity(disabled ? 0.26 : (hovering ? 0.82 : 0.56)))
                .frame(width: 22, height: 22)
                .background(Color.white.opacity(hovering && !disabled ? 0.070 : 0.018))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(ConductorPressButtonStyle(pressedScale: 0.95))
        .disabled(disabled)
        .onHover { hovering = $0 }
        .animation(ConductorMotion.hover, value: hovering)
        .macNativeTooltip(help)
    }
}

struct ConductorContextSearchScopeChip: View {
    let systemImage: String
    let title: String
    @Environment(\.conductorTheme) private var theme
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorFontFamily) private var fontFamily

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.conductorSystem(size: 10.5, weight: .semibold, family: fontFamily, scale: fontScale))
            Text(title)
                .font(.conductorSystem(size: 11, weight: .semibold, family: fontFamily, scale: fontScale))
                .lineLimit(1)
        }
        .foregroundStyle(theme.shellChromeText.opacity(0.72))
        .padding(.horizontal, 8)
        .frame(width: 118, height: 22, alignment: .leading)
        .background(Color.white.opacity(theme.usesDarkChrome ? 0.045 : 0.075))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

struct ConductorContextSearchSurface<Content: View>: View {
    @ViewBuilder var content: Content
    @Environment(\.conductorTheme) private var theme

    var body: some View {
        HStack(spacing: 7) {
            content
        }
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .frame(height: 32)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(theme.terminalChrome.opacity(theme.usesDarkChrome ? 0.96 : 0.92))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(theme.usesDarkChrome ? 0.10 : 0.18), lineWidth: 1)
                }
                .shadow(color: Color.black.opacity(theme.usesDarkChrome ? 0.26 : 0.14), radius: 14, x: 0, y: 8)
        }
    }
}
