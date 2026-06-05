import ConductorCore
import AppKit
import SwiftUI

private func L(_ zh: String, _ en: String) -> String {
    ConductorLocalization.text(zh: zh, en: en)
}

enum GhosttyBooleanOverrideState: String, CaseIterable, Hashable {
    case defaultValue
    case on
    case off

    var title: String {
        switch self {
        case .defaultValue:
            L("默认", "Default")
        case .on:
            L("开", "On")
        case .off:
            L("关", "Off")
        }
    }
}

struct GhosttyBooleanOverridePicker: View {
    let state: GhosttyBooleanOverrideState
    let action: (GhosttyBooleanOverrideState) -> Void

    var body: some View {
        Picker(
            "",
            selection: Binding(
                get: { state },
                set: { value in
                    guard value != state else { return }
                    action(value)
                }
            )
        ) {
            ForEach(GhosttyBooleanOverrideState.allCases, id: \.self) { option in
                Text(option.title)
                    .tag(option)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 236)
    }
}

struct GhosttyPresetOption: Hashable {
    let title: String
    let value: String
}

struct GhosttyPresetOverrideMenu: View {
    let value: String
    let options: [GhosttyPresetOption]
    let setValue: (String) -> Void
    let reset: () -> Void
    @Environment(\.conductorTheme) private var theme

    private var menuOptions: [GhosttyPresetOption] {
        let defaultOption = GhosttyPresetOption(title: L("默认", "Default"), value: "")
        guard !value.isEmpty, !options.contains(where: { $0.value == value }) else {
            return [defaultOption] + options
        }
        return [defaultOption, GhosttyPresetOption(title: value, value: value)] + options
    }

    private var selection: Binding<String> {
        Binding {
            value
        } set: { newValue in
            if newValue.isEmpty {
                reset()
            } else {
                setValue(newValue)
            }
        }
    }

    var body: some View {
        Picker(L("预设", "Preset"), selection: selection) {
            ForEach(menuOptions, id: \.self) { option in
                Text(option.title).tag(option.value)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .controlSize(.small)
        .frame(width: 236, alignment: .trailing)
        .tint(theme.floatingEmphasis)
    }
}

struct ShellCommandSettingControl: View {
    let value: String
    let setValue: (String) -> Void
    let reset: () -> Void
    @Environment(\.conductorFontScale) private var fontScale

    var body: some View {
        HStack(spacing: 8) {
            TextField(L("默认登录 shell", "Default login shell"), text: Binding(
                get: { value },
                set: { setValue($0) }
            ))
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .frame(width: 186)

            ghosttyResetButton(
                disabled: value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                action: reset
            )
        }
        .frame(width: 236, alignment: .trailing)
    }
}

struct WorkingDirectorySettingControl: View {
    let value: String
    let setValue: (String) -> Void
    let reset: () -> Void
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorTheme) private var theme

    private var displayName: String {
        guard !value.isEmpty else { return L("继承", "Inherit") }
        return URL(fileURLWithPath: value).lastPathComponent
    }

    var body: some View {
        HStack(spacing: 8) {
            Button {
                let panel = NSOpenPanel()
                panel.allowsMultipleSelection = false
                panel.canChooseDirectories = true
                panel.canChooseFiles = false
                if panel.runModal() == .OK, let url = panel.url {
                    setValue(url.path)
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "folder")
                        .accessibilityHidden(true)
                    Text(L("选择", "Choose"))
                }
                .font(.conductorSystem(size: 10.5, weight: .semibold, scale: fontScale))
            }

            Text(displayName)
                .font(.conductorSystem(size: 10.5, weight: .semibold, scale: fontScale))
                .foregroundStyle(value.isEmpty ? ConductorDesign.tertiaryText : theme.floatingEmphasis)
                .lineLimit(1)
                .frame(width: 110, alignment: .leading)

            ghosttyResetButton(
                disabled: value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                action: reset
            )
        }
        .frame(width: 236, alignment: .trailing)
    }
}

struct ScrollbackPresetPicker: View {
    private struct Preset: Hashable {
        let title: String
        let value: String
    }

    let value: String
    let setValue: (String) -> Void
    let reset: () -> Void
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorTheme) private var theme

    private var presets: [Preset] {
        [
            Preset(title: L("默认 50MB", "Default 50MB"), value: ""),
            Preset(title: "10MB", value: "10000000"),
            Preset(title: "50MB", value: "50000000"),
            Preset(title: "100MB", value: "100000000"),
            Preset(title: "500MB", value: "500000000"),
            Preset(title: "1GB", value: "1000000000")
        ]
    }

    private var selectedPreset: Preset {
        presets.first { $0.value == value } ?? Preset(title: value, value: value)
    }

    private var presetOptions: [Preset] {
        presets.contains(selectedPreset) ? presets : [selectedPreset] + presets
    }

    private var selection: Binding<String> {
        Binding {
            selectedPreset.value
        } set: { newValue in
            if newValue.isEmpty {
                reset()
            } else {
                setValue(newValue)
            }
        }
    }

    var body: some View {
        Picker(L("滚动缓冲区", "Scrollback"), selection: selection) {
            ForEach(presetOptions, id: \.self) { preset in
                Text(preset.title).tag(preset.value)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .controlSize(.small)
        .frame(width: 236, alignment: .trailing)
        .tint(theme.floatingEmphasis)
    }
}

@MainActor
private func ghosttyResetButton(disabled: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Label(L("恢复默认值", "Reset to Default"), systemImage: "arrow.uturn.backward")
    }
    .labelStyle(.iconOnly)
    .buttonStyle(.borderless)
    .controlSize(.small)
    .disabled(disabled)
    .help(L("恢复默认值", "Reset to Default"))
    .accessibilityLabel(L("恢复默认值", "Reset to Default"))
}

struct GhosttyInlineTextOverrideControl: View {
    let key: String
    let placeholder: String
    let value: String
    let systemImage: String
    let setValue: (String) -> Void
    let reset: () -> Void
    @Environment(\.conductorFontScale) private var fontScale

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.conductorSystem(size: 10.5, weight: .semibold, scale: fontScale))
                .foregroundStyle(.secondary)
                .frame(width: 18)
                .accessibilityHidden(true)

            TextField(placeholder, text: Binding(
                get: { value },
                set: { setValue($0) }
            ))
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .frame(width: 176)

            ghosttyResetButton(
                disabled: value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                action: reset
            )
        }
        .frame(width: 236, alignment: .trailing)
    }
}

struct GhosttySliderOverrideControl: View {
    let key: String
    let value: String
    let range: ClosedRange<CGFloat>
    let step: CGFloat
    let defaultValue: CGFloat
    let valueText: (CGFloat) -> String
    let setValue: (CGFloat) -> Void
    let reset: () -> Void
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorTheme) private var theme

    private var currentValue: CGFloat {
        guard let parsed = Double(value) else { return defaultValue }
        return min(max(CGFloat(parsed), range.lowerBound), range.upperBound)
    }

    var body: some View {
        HStack(spacing: 10) {
            Slider(
                value: Binding(
                    get: { Double(currentValue) },
                    set: { setValue(CGFloat($0)) }
                ),
                in: Double(range.lowerBound)...Double(range.upperBound),
                step: Double(step)
            )
            .frame(width: 142)

            Text(valueText(currentValue))
                .font(.conductorSystem(size: 10.5, weight: .bold, scale: fontScale))
                .foregroundStyle(theme.floatingEmphasis)
                .monospacedDigit()
                .frame(width: 42, alignment: .trailing)

            ghosttyResetButton(
                disabled: value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                action: reset
            )
        }
        .frame(width: 236, alignment: .trailing)
    }
}

struct GhosttyColorOverrideControl: View {
    let key: String
    let value: String
    let setValue: (String) -> Void
    let reset: () -> Void
    @Environment(\.conductorTheme) private var theme

    private var currentColor: Color {
        Color.ghosttyHex(value) ?? Color(nsColor: .textColor)
    }

    var body: some View {
        HStack(spacing: 8) {
            ColorPicker("", selection: Binding(
                get: { currentColor },
                set: { setValue($0.ghosttyHexString ?? "#FFFFFF") }
            ))
            .labelsHidden()
            .frame(width: 44)

            Text(value.isEmpty ? L("默认", "Default") : value)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(theme.floatingEmphasis)
                .lineLimit(1)
                .frame(width: 112, alignment: .leading)

            ghosttyResetButton(
                disabled: value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                action: reset
            )
        }
        .frame(width: 236, alignment: .trailing)
    }
}

struct GhosttyFileOverrideControl: View {
    let key: String
    let value: String
    let setValue: (String) -> Void
    let reset: () -> Void
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorTheme) private var theme

    private var displayName: String {
        guard !value.isEmpty else { return L("未选择", "Not selected") }
        return URL(fileURLWithPath: value).lastPathComponent
    }

    var body: some View {
        HStack(spacing: 8) {
            Button {
                let panel = NSOpenPanel()
                panel.allowsMultipleSelection = false
                panel.canChooseDirectories = key == "working-directory"
                panel.canChooseFiles = key != "working-directory"
                if panel.runModal() == .OK, let url = panel.url {
                    setValue(url.path)
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "folder")
                        .accessibilityHidden(true)
                    Text(L("选择", "Choose"))
                }
                .font(.conductorSystem(size: 10.5, weight: .semibold, scale: fontScale))
            }

            Text(displayName)
                .font(.conductorSystem(size: 10.2, weight: .semibold, scale: fontScale))
                .foregroundStyle(theme.floatingEmphasis)
                .lineLimit(1)
                .frame(width: 110, alignment: .leading)

            ghosttyResetButton(
                disabled: value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                action: reset
            )
        }
        .frame(width: 236, alignment: .trailing)
    }
}

struct TerminalRendererSummary: View {
    let appearance: AppearancePreferences
    @Environment(\.conductorFontScale) private var fontScale

    var body: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 6) {
            GridRow {
                summaryField(
                    title: L("字体", "Font"),
                    value: appearance.terminalRenderer.effectiveFontFamilyName,
                    systemImage: "textformat"
                )
                summaryField(
                    title: L("字号", "Size"),
                    value: terminalFontSizeText(appearance.terminalFontSize),
                    systemImage: "textformat.size"
                )
            }
            GridRow {
                summaryField(
                    title: L("透明度", "Opacity"),
                    value: percentText(appearance.terminalRenderer.backgroundOpacity),
                    systemImage: "circle.lefthalf.filled"
                )
                summaryField(
                    title: L("代理", "Proxy"),
                    value: appearance.terminalRenderer.proxy.enabled ? L("开启", "On") : L("关闭", "Off"),
                    systemImage: "network"
                )
            }
        }
    }

    private func summaryField(title: String, value: String, systemImage: String) -> some View {
        LabeledContent {
            Text(value)
                .font(.conductorSystem(size: 10.6, weight: .semibold, scale: fontScale))
                .foregroundStyle(ConductorDesign.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        } label: {
            Label(title, systemImage: systemImage)
                .font(.conductorSystem(size: 9.8, weight: .medium, scale: fontScale))
                .foregroundStyle(ConductorDesign.tertiaryText)
        }
        .frame(width: 164, alignment: .leading)
    }

    private func terminalFontSizeText(_ value: CGFloat) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded.rounded() == rounded {
            return "\(Int(rounded)) pt"
        }
        return String(format: "%.1f pt", Double(rounded))
    }

    private func percentText(_ value: CGFloat) -> String {
        "\(Int((value * 100).rounded()))%"
    }
}

extension Color {
    var ghosttyHexString: String? {
        guard let color = NSColor(self).usingColorSpace(.deviceRGB) else { return nil }
        let red = Int((color.redComponent * 255).rounded())
        let green = Int((color.greenComponent * 255).rounded())
        let blue = Int((color.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", red, green, blue)
    }

    static func ghosttyHex(_ value: String) -> Color? {
        let trimmed = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
        guard trimmed.count == 6 || trimmed.count == 8 else { return nil }

        var raw: UInt64 = 0
        guard Scanner(string: trimmed).scanHexInt64(&raw) else { return nil }

        let red: CGFloat
        let green: CGFloat
        let blue: CGFloat
        let alpha: CGFloat
        if trimmed.count == 8 {
            red = CGFloat((raw & 0xFF00_0000) >> 24) / 255
            green = CGFloat((raw & 0x00FF_0000) >> 16) / 255
            blue = CGFloat((raw & 0x0000_FF00) >> 8) / 255
            alpha = CGFloat(raw & 0x0000_00FF) / 255
        } else {
            red = CGFloat((raw & 0xFF0000) >> 16) / 255
            green = CGFloat((raw & 0x00FF00) >> 8) / 255
            blue = CGFloat(raw & 0x0000FF) / 255
            alpha = 1
        }

        return Color(nsColor: NSColor(calibratedRed: red, green: green, blue: blue, alpha: alpha))
    }
}

struct TerminalFontPickerMenu: View {
    let selection: TerminalFontPreset
    let downloadStates: [TerminalFontPreset: TerminalFontDownloadState]
    let action: (TerminalFontPreset) -> Void
    let download: (TerminalFontPreset) -> Void
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorTheme) private var theme

    private var selectedChoice: TerminalFontChoice {
        TerminalFontLibrary.choices.first { $0.preset == selection }
            ?? TerminalFontLibrary.choices[0]
    }

    var body: some View {
        Menu {
            ForEach(TerminalFontLibrary.choices) { choice in
                Menu {
                    Button {
                        guard choice.preset != selection else { return }
                        action(choice.preset)
                    } label: {
                        Label(
                            choice.preset == selection ? L("当前使用", "Current Font") : L("设为终端字体", "Use for Terminal"),
                            systemImage: choice.preset == selection ? "checkmark.circle" : "textformat"
                        )
                    }
                    .disabled(choice.preset == selection)

                    if !choice.isInstalled, choice.canDownload {
                        Button {
                            download(choice.preset)
                        } label: {
                            Label(
                                choice.preset.directDownloadURL == nil ? L("打开获取页", "Open Get Page") : L("下载并安装", "Download and Install"),
                                systemImage: choice.preset.directDownloadURL == nil ? "safari" : "arrow.down.circle"
                            )
                        }
                        .disabled(downloadStates[choice.preset]?.isDownloading == true)
                    }
                } label: {
                    Label(
                        "\(choice.displayName) · \(menuStatusTitle(for: choice))",
                        systemImage: menuStatusIcon(for: choice)
                    )
                }
            }
        } label: {
            Label {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(selectedChoice.displayName)
                        .font(.conductorSystem(size: 11, weight: .semibold, scale: fontScale))
                        .lineLimit(1)
                    Text(selectedChoice.statusTitle)
                        .font(.conductorSystem(size: 9.5, weight: .medium, scale: fontScale))
                        .foregroundStyle(selectedChoice.isInstalled ? theme.floatingEmphasis : ConductorDesign.tertiaryText)
                        .lineLimit(1)
                }
            } icon: {
                Image(systemName: menuStatusIcon(for: selectedChoice))
                    .font(.system(size: 9, weight: .bold))
                    .accessibilityHidden(true)
            }
            .labelStyle(.titleAndIcon)
            .foregroundStyle(theme.floatingEmphasis)
            .frame(width: 212, alignment: .trailing)
        }
        .menuStyle(.button)
    }

    private func menuStatusTitle(for choice: TerminalFontChoice) -> String {
        switch downloadStates[choice.preset] {
        case .downloading:
            return L("下载中", "Downloading")
        case .installed(let family):
            return L("已安装：\(family)", "Installed: \(family)")
        case .failed:
            return L("下载失败", "Download Failed")
        case .idle, .none:
            return choice.statusTitle
        }
    }

    private func menuStatusIcon(for choice: TerminalFontChoice) -> String {
        switch downloadStates[choice.preset] {
        case .downloading:
            "arrow.down.circle"
        case .failed:
            "exclamationmark.triangle"
        case .installed:
            "checkmark.circle"
        case .idle, .none:
            choice.isInstalled ? "checkmark.circle" : "arrow.down.circle"
        }
    }
}

enum CommandShortcutGuideStyle {
    case grouped
    case plain
}

struct CommandShortcutGuide: View {
    let rows: [CommandShortcutGuideRowModel]
    var height: CGFloat = 178
    var style: CommandShortcutGuideStyle = .grouped
    var editable = false
    var recordingCommand: ConductorShellCommand?
    var onRecord: (ConductorShellCommand) -> Void = { _ in }
    var onReset: (ConductorShellCommand) -> Void = { _ in }
    @Environment(\.conductorFontScale) private var fontScale

    @ViewBuilder
    var body: some View {
        let guide = List {
            ForEach(sections) { section in
                Section {
                    ForEach(section.rows) { row in
                        CommandShortcutGuideRow(
                            row: row,
                            editable: editable,
                            isRecording: recordingCommand == row.item.command,
                            onRecord: onRecord,
                            onReset: onReset
                        )
                    }
                } header: {
                    Text(section.title.uppercased())
                        .font(.conductorSystem(size: 9.2, weight: .semibold, scale: fontScale))
                        .foregroundStyle(ConductorDesign.tertiaryText)
                }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .frame(height: height)

        switch style {
        case .grouped:
            GroupBox {
                guide
            }
        case .plain:
            guide
        }
    }

    private var sections: [CommandShortcutGuideSection] {
        var result: [CommandShortcutGuideSection] = []
        for row in rows {
            if result.last?.title == row.item.section {
                result[result.count - 1].rows.append(row)
            } else {
                result.append(CommandShortcutGuideSection(title: row.item.section, rows: [row]))
            }
        }
        return result
    }
}

private struct CommandShortcutGuideSection: Identifiable {
    var id: String { title }
    let title: String
    var rows: [CommandShortcutGuideRowModel]
}

private struct CommandShortcutGuideRow: View {
    let row: CommandShortcutGuideRowModel
    let editable: Bool
    let isRecording: Bool
    let onRecord: (ConductorShellCommand) -> Void
    let onReset: (ConductorShellCommand) -> Void
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorTheme) private var theme

    var body: some View {
        LabeledContent {
            HStack(spacing: 8) {
                Text(row.item.shortcut)
                    .font(.conductorSystem(size: 9.6, weight: isRecording ? .bold : .semibold, design: .monospaced, scale: fontScale))
                    .foregroundStyle(isRecording ? theme.floatingEmphasis : ConductorDesign.secondaryText)
                    .lineLimit(1)
                    .frame(minWidth: 54, alignment: .trailing)

                if editable {
                    ControlGroup {
                        Button {
                            onRecord(row.item.command)
                        } label: {
                            Label(isRecording ? L("按键", "Press") : L("更改", "Change"), systemImage: isRecording ? "record.circle.fill" : "keyboard")
                        }
                        .help(L("录制新的快捷键", "Record a new shortcut"))

                        Button {
                            onReset(row.item.command)
                        } label: {
                            Label(L("默认", "Default"), systemImage: "arrow.counterclockwise")
                        }
                        .help(L("恢复默认快捷键", "Restore default shortcut"))
                    }
                    .controlSize(.small)
                }
            }
        } label: {
            Label {
                VStack(alignment: .leading, spacing: 1) {
                    Text(row.item.title)
                        .font(.conductorSystem(size: 11.2, weight: .semibold, scale: fontScale))
                        .foregroundStyle(ConductorDesign.primaryText)
                        .lineLimit(1)
                    if editable {
                        Text(row.item.shortcutStatus)
                            .font(.conductorSystem(size: 9, weight: .medium, scale: fontScale))
                            .foregroundStyle(statusColor)
                            .lineLimit(1)
                    }
                }
            } icon: {
                Image(systemName: row.item.systemImage)
                    .font(.conductorSystem(size: 11, weight: .semibold, scale: fontScale))
                    .foregroundStyle(ConductorDesign.secondaryText)
                    .frame(width: 18)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(row.item.title), \(row.item.shortcutStatus), \(row.item.shortcut)")
    }

    private var statusColor: Color {
        if row.item.shortcutStatus == L("自定义", "Custom") {
            return theme.floatingEmphasis
        }
        if row.item.shortcutStatus == L("未设置", "Unassigned") {
            return ConductorDesign.tertiaryText
        }
        return ConductorDesign.secondaryText
    }
}
