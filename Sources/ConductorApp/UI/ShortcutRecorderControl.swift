import AppKit
import ConductorCore
import SwiftUI

final class ShortcutRecorderFocusState {
    static let shared = ShortcutRecorderFocusState()

    var isRecording = false

    private init() {}
}

enum ShortcutRecorderPresentation {
    static func displayText(for shortcut: String?, isRecording: Bool) -> String {
        if isRecording { return L("按下快捷键…") }
        guard let shortcut, !shortcut.isEmpty else { return L("录入") }
        return ShortcutSymbolizer.symbolize(shortcut)
    }

    static func accessibilityLabel(commandTitle: String, shortcut: String?, isRecording: Bool) -> String {
        if isRecording {
            return L("正在录入 %@ 快捷键，按 Escape 取消", commandTitle)
        }
        guard let shortcut, !shortcut.isEmpty else {
            return L("设置 %@ 快捷键", commandTitle)
        }
        return L("修改 %@ 快捷键，当前为 %@", commandTitle, ShortcutSymbolizer.symbolize(shortcut))
    }

    static func captureSpec(from event: NSEvent) -> String? {
        guard event.keyCode != 53, let chord = KeyChord(event: event) else { return nil }
        return ShortcutSettingsModel.canonicalSpec(for: chord)
    }
}

struct ShortcutRecorderControl: NSViewRepresentable {
    let commandTitle: String
    let shortcut: String?
    let isRecording: Bool
    let onBeginRecording: () -> Void
    let onCapture: (String) -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> ShortcutRecorderButton {
        let button = ShortcutRecorderButton(frame: .zero)
        button.onBeginRecording = onBeginRecording
        button.onCapture = onCapture
        button.onCancel = onCancel
        return button
    }

    func updateNSView(_ button: ShortcutRecorderButton, context: Context) {
        button.commandTitle = commandTitle
        button.shortcut = shortcut
        button.isRecordingShortcut = isRecording
        button.onBeginRecording = onBeginRecording
        button.onCapture = onCapture
        button.onCancel = onCancel
        button.refresh()
        if isRecording, button.window?.firstResponder !== button {
            button.window?.makeFirstResponder(button)
        }
    }
}

@MainActor
final class ShortcutRecorderButton: NSButton {
    var commandTitle = ""
    var shortcut: String?
    var isRecordingShortcut = false
    var onBeginRecording: (() -> Void)?
    var onCapture: ((String) -> Void)?
    var onCancel: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = false
        setButtonType(.momentaryChange)
        focusRingType = .none
        wantsLayer = true
        layer?.cornerRadius = Radius.sm
        layer?.cornerCurve = .continuous
        target = self
        action = #selector(beginRecording)
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func refresh() {
        let display = ShortcutRecorderPresentation.displayText(for: shortcut, isRecording: isRecordingShortcut)
        title = display
        toolTip = ShortcutRecorderPresentation.accessibilityLabel(
            commandTitle: commandTitle,
            shortcut: shortcut,
            isRecording: isRecordingShortcut
        )
        setAccessibilityLabel(toolTip)
        font = .systemFont(ofSize: 11.5, weight: .semibold)
        contentTintColor = NSColor(isRecordingShortcut ? AppStyle.accent : AppStyle.textSecondary)
        layer?.backgroundColor = NSColor(isRecordingShortcut ? AppStyle.activeFill : AppStyle.hoverFill)
            .withAlphaComponent(isRecordingShortcut ? 0.38 : 0.18)
            .cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor(isRecordingShortcut ? AppStyle.accent : AppStyle.separator)
            .withAlphaComponent(isRecordingShortcut ? 0.55 : 0.38)
            .cgColor
    }

    @objc private func beginRecording() {
        onBeginRecording?()
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        guard isRecordingShortcut else {
            super.keyDown(with: event)
            return
        }
        if event.keyCode == 53 {
            onCancel?()
            return
        }
        guard let spec = ShortcutRecorderPresentation.captureSpec(from: event) else { return }
        onCapture?(spec)
    }

    override func keyUp(with event: NSEvent) {
        guard !isRecordingShortcut else { return }
        super.keyUp(with: event)
    }
}
