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

struct GhosttyChoiceOverrideMenu: View {
    let key: String
    let value: String
    let enabled: Bool
    let choices: [String]
    let setValue: (String) -> Void
    let setDefault: () -> Void
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorTheme) private var theme

    private var title: String {
        enabled && !value.isEmpty ? value : L("默认", "Default")
    }

    var body: some View {
        Menu {
            Button(L("默认", "Default")) {
                setDefault()
            }
            Divider()
            ForEach(choices, id: \.self) { choice in
                Button(choice) {
                    setValue(choice)
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(theme.floatingEmphasis)
            .frame(width: 236, alignment: .trailing)
        }
        .menuStyle(.button)
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
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorTheme) private var theme

    private var selectedTitle: String {
        guard !value.isEmpty else { return L("默认", "Default") }
        return options.first { $0.value == value }?.title ?? value
    }

    var body: some View {
        Menu {
            Button(L("默认", "Default")) {
                reset()
            }
            Divider()
            ForEach(options, id: \.self) { option in
                Button(option.title) {
                    setValue(option.value)
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(selectedTitle)
                    .font(.conductorSystem(size: 11, weight: .semibold, scale: fontScale))
                    .foregroundStyle(theme.floatingEmphasis)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .accessibilityHidden(true)
            }
            .frame(width: 236, alignment: .trailing)
        }
        .menuStyle(.button)
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

            GhosttyResetButton(
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

            GhosttyResetButton(
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
            Preset(title: L("默认", "Default"), value: ""),
            Preset(title: "10k", value: "10000"),
            Preset(title: "50k", value: "50000"),
            Preset(title: "100k", value: "100000"),
            Preset(title: L("无限制", "Unlimited"), value: "0")
        ]
    }

    private var selectedPreset: Preset {
        presets.first { $0.value == value } ?? Preset(title: value, value: value)
    }

    var body: some View {
        Menu {
            ForEach(presets, id: \.self) { preset in
                Button(preset.title) {
                    if preset.value.isEmpty {
                        reset()
                    } else {
                        setValue(preset.value)
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(selectedPreset.title)
                    .font(.conductorSystem(size: 11, weight: .semibold, scale: fontScale))
                    .foregroundStyle(theme.floatingEmphasis)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .accessibilityHidden(true)
            }
            .frame(width: 236, alignment: .trailing)
        }
        .menuStyle(.button)
    }
}

struct GhosttyResetButton: View {
    let disabled: Bool
    let action: () -> Void

    var body: some View {
        ConductorIconButton(
            state: ConductorControlState(
                id: "settings-reset",
                systemImage: "arrow.uturn.backward",
                isEnabled: !disabled,
                tooltip: L("恢复默认值", "Reset to Default"),
                accessibilityLabel: L("恢复默认值", "Reset to Default")
            ),
            variant: .settingsIcon,
            action: action
        )
    }
}

struct GhosttyInlineTextOverrideControl: View {
    let key: String
    let placeholder: String
    let value: String
    let systemImage: String
    let setValue: (String) -> Void
    let reset: () -> Void
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorTheme) private var theme

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.conductorSystem(size: 10.5, weight: .semibold, scale: fontScale))
                .foregroundStyle(theme.floatingEmphasis)
                .frame(width: 22, height: 22)
                .background(theme.floatingControlStrongFill)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .accessibilityHidden(true)

            TextField(placeholder, text: Binding(
                get: { value },
                set: { setValue($0) }
            ))
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .frame(width: 176)

            GhosttyResetButton(
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

            GhosttyResetButton(
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
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(currentColor)
                .frame(width: 22, height: 22)
                .overlay {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(theme.floatingStroke.opacity(0.42), lineWidth: 0.6)
                }

            ColorPicker("", selection: Binding(
                get: { currentColor },
                set: { setValue($0.ghosttyHexString ?? "#FFFFFF") }
            ))
            .labelsHidden()
            .frame(width: 34)

            Text(value.isEmpty ? L("默认", "Default") : value)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(theme.floatingEmphasis)
                .lineLimit(1)
                .frame(width: 112, alignment: .leading)

            GhosttyResetButton(
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

            GhosttyResetButton(
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
    @Environment(\.conductorTheme) private var theme

    var body: some View {
        HStack(spacing: 8) {
            summaryTile(
                title: L("字体", "Font"),
                value: appearance.terminalRenderer.effectiveFontFamilyName,
                systemImage: "textformat"
            )
            summaryTile(
                title: L("字号", "Size"),
                value: terminalFontSizeText(appearance.terminalFontSize),
                systemImage: "textformat.size"
            )
            summaryTile(
                title: L("透明度", "Opacity"),
                value: percentText(appearance.terminalRenderer.backgroundOpacity),
                systemImage: "circle.lefthalf.filled"
            )
            summaryTile(
                title: L("代理", "Proxy"),
                value: appearance.terminalRenderer.proxy.enabled ? L("开启", "On") : L("关闭", "Off"),
                systemImage: "network"
            )
        }
    }

    private func summaryTile(title: String, value: String, systemImage: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.conductorSystem(size: 10, weight: .semibold, scale: fontScale))
                .foregroundStyle(theme.floatingEmphasis)
                .frame(width: 22, height: 22)
                .background(theme.floatingControlStrongFill)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.conductorSystem(size: 9.5, weight: .semibold, scale: fontScale))
                    .foregroundStyle(ConductorDesign.tertiaryText)
                Text(value)
                    .font(.conductorSystem(size: 10.6, weight: .bold, scale: fontScale))
                    .foregroundStyle(ConductorDesign.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 9)
        .frame(height: 44)
        .background(theme.floatingControlFill.opacity(0.54))
        .clipShape(RoundedRectangle(cornerRadius: ConductorTokens.Radius.controlGroup, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ConductorTokens.Radius.controlGroup, style: .continuous)
                .stroke(theme.floatingStroke.opacity(0.34), lineWidth: 0.6)
        }
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
            HStack(spacing: 8) {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(selectedChoice.displayName)
                        .font(.conductorSystem(size: 11, weight: .semibold, scale: fontScale))
                        .lineLimit(1)
                    Text(selectedChoice.statusTitle)
                        .font(.conductorSystem(size: 9.5, weight: .medium, scale: fontScale))
                        .foregroundStyle(selectedChoice.isInstalled ? theme.floatingEmphasis : ConductorDesign.tertiaryText)
                        .lineLimit(1)
                }
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .accessibilityHidden(true)
            }
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

struct SettingsStatusPill: View {
    let title: String
    let systemImage: String
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorTheme) private var theme

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.conductorSystem(size: 9.5, weight: .bold, scale: fontScale))
                .accessibilityHidden(true)
            Text(title)
                .font(.conductorSystem(size: 10.5, weight: .bold, scale: fontScale))
        }
        .foregroundStyle(theme.floatingEmphasis)
        .padding(.horizontal, 10)
        .frame(height: 26)
        .background(theme.floatingControlStrongFill)
        .clipShape(Capsule())
        .overlay {
            Capsule()
                .stroke(theme.floatingStroke.opacity(0.38), lineWidth: 0.6)
        }
    }
}

struct SettingsPreferenceGroup<Content: View>: View {
    let title: String
    let content: Content
    @Environment(\.conductorFontScale) private var fontScale

    init(
        title: String,
        subtitle: String = "",
        systemImage: String = "",
        @ViewBuilder content: () -> Content
    ) {
        _ = subtitle
        _ = systemImage
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.conductorSystem(size: 10.2, weight: .semibold, scale: fontScale))
                .foregroundStyle(ConductorDesign.secondaryText)
                .lineLimit(1)

            content
        }
        .padding(.top, 1)
    }
}

struct SettingsFormSurface<Content: View>: View {
    let content: Content
    @Environment(\.conductorTheme) private var theme

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .background {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(theme.floatingControlFill.opacity(theme.usesDarkChrome ? 0.12 : 0.20))
        }
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(theme.floatingStroke.opacity(theme.usesDarkChrome ? 0.10 : 0.08), lineWidth: 0.5)
        }
    }
}

struct SettingsControlRow<Trailing: View>: View {
    let title: String
    let subtitle: String
    let trailing: Trailing
    @State private var hovering = false
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorTheme) private var theme

    init(
        title: String,
        subtitle: String,
        systemImage: String = "",
        @ViewBuilder trailing: () -> Trailing
    ) {
        _ = systemImage
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.conductorSystem(size: 11.4, weight: .medium, scale: fontScale))
                    .foregroundStyle(ConductorDesign.primaryText)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.conductorSystem(size: 9.3, weight: .medium, scale: fontScale))
                    .foregroundStyle(ConductorDesign.tertiaryText.opacity(0.86))
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            trailing
        }
        .padding(.horizontal, 9)
        .frame(minHeight: 40)
        .background(hovering ? theme.floatingHoverFill.opacity(0.16) : Color.clear)
        .contentShape(Rectangle())
        .conductorHover($hovering, animation: nil)
    }
}

struct SettingsToggleRow: View {
    let title: String
    let subtitle: String
    var systemImage: String = ""
    let isOn: Binding<Bool>

    var body: some View {
        SettingsControlRow(
            title: title,
            subtitle: subtitle
        ) {
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .labelsHidden()
        }
    }
}

struct SettingsTextFieldRow: View {
    let title: String
    let subtitle: String
    var systemImage: String = ""
    let text: Binding<String>

    var body: some View {
        SettingsControlRow(
            title: title,
            subtitle: subtitle
        ) {
            TextField("", text: text)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .frame(width: 278)
        }
    }
}

struct SettingsSliderRow: View {
    let title: String
    let subtitle: String
    var systemImage: String = ""
    let value: CGFloat
    let range: ClosedRange<CGFloat>
    let step: CGFloat
    let valueText: String
    let action: (CGFloat) -> Void
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorTheme) private var theme

    var body: some View {
        SettingsControlRow(
            title: title,
            subtitle: subtitle
        ) {
            HStack(spacing: 10) {
                Slider(
                    value: Binding(
                        get: { Double(value) },
                        set: { action(CGFloat($0)) }
                    ),
                    in: Double(range.lowerBound)...Double(range.upperBound),
                    step: Double(step)
                )
                .frame(width: 192)

                Text(valueText)
                    .font(.conductorSystem(size: 10.5, weight: .bold, scale: fontScale))
                    .foregroundStyle(theme.floatingEmphasis)
                    .monospacedDigit()
                    .frame(width: 46, alignment: .trailing)
            }
        }
    }
}

struct SettingsControlDivider: View {
    @Environment(\.conductorTheme) private var theme

    var body: some View {
        Rectangle()
            .fill(theme.floatingSeparator.opacity(0.56))
            .frame(height: 1)
            .padding(.leading, 9)
    }
}

struct SettingsSegmentedPicker<Option: Hashable>: View {
    let options: [Option]
    let selection: Option
    let title: (Option) -> String
    let action: (Option) -> Void
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorTheme) private var theme

    private let controlWidth: CGFloat = 284
    private let controlHeight: CGFloat = 22
    private let cornerRadius: CGFloat = 5

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.element) { index, option in
                segment(option)
                if index < options.count - 1 {
                    Rectangle()
                        .fill(theme.floatingSeparator.opacity(0.36))
                        .frame(width: 1, height: 14)
                        .opacity(option == selection || options[index + 1] == selection ? 0 : 1)
                }
            }
        }
        .padding(1)
        .frame(width: controlWidth, height: controlHeight)
        .background(theme.floatingControlFill.opacity(theme.usesDarkChrome ? 0.28 : 0.34))
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(theme.floatingStroke.opacity(theme.usesDarkChrome ? 0.18 : 0.20), lineWidth: 0.6)
        }
    }

    private func segment(_ option: Option) -> some View {
        let selected = option == selection
        return Button {
            guard option != selection else { return }
            action(option)
        } label: {
            Text(title(option))
                .font(.conductorSystem(size: 11.5, weight: selected ? .semibold : .medium, scale: fontScale))
                .foregroundStyle(selected ? ConductorDesign.primaryText : ConductorDesign.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            if selected {
                RoundedRectangle(cornerRadius: cornerRadius - 1, style: .continuous)
                    .fill(theme.floatingPanelBase.opacity(theme.usesDarkChrome ? 0.86 : 0.96))
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius - 1, style: .continuous)
                            .stroke(theme.floatingStroke.opacity(theme.usesDarkChrome ? 0.22 : 0.24), lineWidth: 0.6)
                    }
                    .shadow(color: Color.black.opacity(theme.usesDarkChrome ? 0.10 : 0.055), radius: 2, y: 0.8)
            }
        }
    }
}

struct SettingsMenuPicker<Option: Hashable>: View {
    let options: [Option]
    let selection: Option
    let title: (Option) -> String
    let action: (Option) -> Void
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorTheme) private var theme

    var body: some View {
        Menu {
            ForEach(options, id: \.self) { option in
                Button(title(option)) {
                    guard option != selection else { return }
                    action(option)
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(title(selection))
                    .font(.conductorSystem(size: 11, weight: .semibold, scale: fontScale))
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(theme.floatingEmphasis)
            .frame(width: 278, alignment: .trailing)
        }
        .menuStyle(.button)
    }
}

extension AppearanceFontFamily {
    var systemImage: String {
        switch self {
        case .system:
            "textformat"
        case .rounded:
            "textformat.alt"
        case .serif:
            "textformat.abc"
        case .monospaced:
            "number"
        }
    }
}

struct SettingsSidebarItem: View {
    let section: SettingsSectionID
    let selected: Bool
    let selectionNamespace: Namespace.ID
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorTheme) private var theme

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: section.systemImage)
                    .font(.conductorSystem(size: 9.8, weight: .semibold, scale: fontScale))
                    .foregroundStyle(selected ? theme.floatingEmphasis : ConductorDesign.secondaryText.opacity(0.86))
                    .frame(width: 17, height: 17)
                    .accessibilityHidden(true)

                Text(section.title)
                    .font(.conductorSystem(size: 10.8, weight: selected ? .semibold : .medium, scale: fontScale))
                    .foregroundStyle(ConductorDesign.primaryText)
                    .lineLimit(1)

                Spacer(minLength: 0)

                if selected {
                    Image(systemName: "chevron.right")
                        .font(.conductorSystem(size: 8.5, weight: .bold, scale: fontScale))
                        .foregroundStyle(theme.floatingEmphasis.opacity(0.84))
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 28, alignment: .center)
            .background(rowBackground)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(ConductorPressButtonStyle(pressedScale: 0.985, pressedOpacity: 0.96))
        .conductorHover($hovering, animation: nil)
        .animation(ConductorMotion.selectionGlide, value: selected)
    }

    private var rowBackground: some View {
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
        return ZStack {
            shape
                .fill(hovering ? theme.floatingHoverFill.opacity(0.18) : Color.clear)
            if selected {
                shape
                    .fill(theme.floatingSelectedFill.opacity(0.56))
                    .matchedGeometryEffect(id: "settings-section-selection", in: selectionNamespace)
            }
        }
    }
}

enum CommandShortcutGuideStyle {
    case card
    case plain
}

struct CommandShortcutGuide: View {
    let rows: [CommandShortcutGuideRowModel]
    var height: CGFloat = 178
    var style: CommandShortcutGuideStyle = .card
    var editable = false
    var recordingCommand: ConductorShellCommand?
    var onRecord: (ConductorShellCommand) -> Void = { _ in }
    var onReset: (ConductorShellCommand) -> Void = { _ in }
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorTheme) private var theme

    @ViewBuilder
    var body: some View {
        let guide = NativeCommandShortcutGuide(
            rows: rows,
            style: style,
            editable: editable,
            recordingCommand: recordingCommand,
            theme: theme,
            fontScale: fontScale,
            onRecord: onRecord,
            onReset: onReset
        )
        .scrollIndicators(.visible)
        .frame(height: height)

        switch style {
        case .card:
            guide
                .background(theme.floatingControlFill)
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(theme.floatingStroke.opacity(0.32), lineWidth: 0.7)
                }
        case .plain:
            guide
                .background(theme.floatingControlFill.opacity(theme.usesDarkChrome ? 0.10 : 0.16))
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(theme.floatingStroke.opacity(theme.usesDarkChrome ? 0.55 : 0.42))
                        .frame(height: 1)
                }
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(theme.floatingStroke.opacity(theme.usesDarkChrome ? 0.55 : 0.42))
                        .frame(height: 1)
                }
        }
    }
}

private struct NativeCommandShortcutGuide: NSViewRepresentable {
    let rows: [CommandShortcutGuideRowModel]
    let style: CommandShortcutGuideStyle
    let editable: Bool
    let recordingCommand: ConductorShellCommand?
    let theme: TerminalTheme
    let fontScale: AppearanceFontScale
    let onRecord: (ConductorShellCommand) -> Void
    let onReset: (ConductorShellCommand) -> Void

    func makeNSView(context: Context) -> NativeCommandShortcutGuideView {
        NativeCommandShortcutGuideView()
    }

    func updateNSView(_ view: NativeCommandShortcutGuideView, context: Context) {
        view.update(
            rows: rows,
            style: style,
            editable: editable,
            recordingCommand: recordingCommand,
            theme: theme,
            fontScale: fontScale,
            onRecord: onRecord,
            onReset: onReset
        )
    }
}

private final class NativeCommandShortcutGuideView: NSView, NSTableViewDataSource, NSTableViewDelegate {
    private let scrollView = NSScrollView()
    private let tableView = NSTableView()
    private let columnIdentifier = NSUserInterfaceItemIdentifier("command-shortcut-row")
    private var rows: [CommandShortcutGuideRowModel] = []
    private var style: CommandShortcutGuideStyle = .plain
    private var editable = false
    private var recordingCommand: ConductorShellCommand?
    private var theme: TerminalTheme = .graphite
    private var fontScale: AppearanceFontScale = .standard
    private var onRecord: ((ConductorShellCommand) -> Void)?
    private var onReset: ((ConductorShellCommand) -> Void)?

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        tableView.headerView = nil
        tableView.backgroundColor = .clear
        tableView.selectionHighlightStyle = .none
        tableView.focusRingType = .none
        tableView.allowsColumnSelection = false
        tableView.allowsMultipleSelection = false
        tableView.allowsEmptySelection = true
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.dataSource = self
        tableView.delegate = self
        let column = NSTableColumn(identifier: columnIdentifier)
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        scrollView.documentView = tableView

        addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    func update(
        rows: [CommandShortcutGuideRowModel],
        style: CommandShortcutGuideStyle,
        editable: Bool,
        recordingCommand: ConductorShellCommand?,
        theme: TerminalTheme,
        fontScale: AppearanceFontScale,
        onRecord: @escaping (ConductorShellCommand) -> Void,
        onReset: @escaping (ConductorShellCommand) -> Void
    ) {
        self.rows = rows
        self.style = style
        self.editable = editable
        self.recordingCommand = recordingCommand
        self.theme = theme
        self.fontScale = fontScale
        self.onRecord = onRecord
        self.onReset = onReset
        tableView.reloadData()
    }

    override func layout() {
        super.layout()
        tableView.tableColumns.first?.width = scrollView.contentView.bounds.width
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        rows.count
    }

    func tableView(_ tableView: NSTableView, heightOfRow rowIndex: Int) -> CGFloat {
        guard rows.indices.contains(rowIndex) else { return 30 }
        return rows[rowIndex].showsSectionTitle ? 47 : 30
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        NativeCommandShortcutTableRowView()
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row rowIndex: Int) -> NSView? {
        guard rows.indices.contains(rowIndex) else { return nil }
        let row = rows[rowIndex]
        let view = tableView.makeView(withIdentifier: columnIdentifier, owner: self) as? NativeCommandShortcutGuideRowView ?? NativeCommandShortcutGuideRowView()
        view.identifier = columnIdentifier
        view.update(
            row: row,
            style: style,
            editable: editable,
            isRecording: recordingCommand == row.item.command,
            theme: theme,
            fontScale: fontScale,
            onRecord: { [weak self] in self?.onRecord?(row.item.command) },
            onReset: { [weak self] in self?.onReset?(row.item.command) }
        )
        return view
    }
}

private final class NativeCommandShortcutTableRowView: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {}
    override func drawBackground(in dirtyRect: NSRect) {}
}

private final class NativeCommandShortcutGuideRowView: NSTableCellView {
    private var row: CommandShortcutGuideRowModel?
    private var style: CommandShortcutGuideStyle = .plain
    private var editable = false
    private var isRecording = false
    private var theme: TerminalTheme = .graphite
    private var fontScale: AppearanceFontScale = .standard
    private var onRecord: (() -> Void)?
    private var onReset: (() -> Void)?
    private let recordButton = NSButton()
    private let resetButton = NSButton()

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        wantsLayer = true
        setupButton(recordButton, action: #selector(recordShortcut))
        setupButton(resetButton, action: #selector(resetShortcut))
        addSubview(recordButton)
        addSubview(resetButton)
    }

    private func setupButton(_ button: NSButton, action: Selector) {
        button.bezelStyle = .texturedRounded
        button.isBordered = true
        button.controlSize = .small
        button.font = .systemFont(ofSize: 9.2, weight: .semibold)
        button.target = self
        button.action = action
        button.imagePosition = .imageLeading
    }

    func update(
        row: CommandShortcutGuideRowModel,
        style: CommandShortcutGuideStyle,
        editable: Bool,
        isRecording: Bool,
        theme: TerminalTheme,
        fontScale: AppearanceFontScale,
        onRecord: @escaping () -> Void,
        onReset: @escaping () -> Void
    ) {
        self.row = row
        self.style = style
        self.editable = editable
        self.isRecording = isRecording
        self.theme = theme
        self.fontScale = fontScale
        self.onRecord = onRecord
        self.onReset = onReset

        recordButton.title = isRecording ? L("按键", "Press") : L("更改", "Change")
        recordButton.image = NSImage(systemSymbolName: isRecording ? "record.circle.fill" : "keyboard", accessibilityDescription: nil)
        recordButton.isHidden = !editable
        resetButton.title = L("默认", "Default")
        resetButton.image = NSImage(systemSymbolName: "arrow.counterclockwise", accessibilityDescription: nil)
        resetButton.isHidden = !editable
        needsLayout = true
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        let contentY = contentOriginY
        let buttonWidth: CGFloat = 58
        let buttonHeight: CGFloat = 21
        let gap: CGFloat = 6
        resetButton.frame = NSRect(x: bounds.maxX - buttonWidth - 8, y: contentY + 4.5, width: buttonWidth, height: buttonHeight)
        recordButton.frame = NSRect(x: resetButton.frame.minX - buttonWidth - gap, y: contentY + 4.5, width: buttonWidth, height: buttonHeight)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let row else { return }
        drawSectionHeader(row)
        drawRowContent(row)
        if style == .plain {
            NSColor(theme.floatingStroke.opacity(theme.usesDarkChrome ? 0.22 : 0.16)).setFill()
            NSRect(x: 30, y: bounds.maxY - 1, width: max(0, bounds.width - 30), height: 1).fill()
        }
    }

    private var contentOriginY: CGFloat {
        row?.showsSectionTitle == true ? 17 : 0
    }

    private func drawSectionHeader(_ row: CommandShortcutGuideRowModel) {
        guard row.showsSectionTitle else { return }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontScale.size(9.2), weight: .semibold),
            .foregroundColor: NSColor(ConductorDesign.tertiaryText)
        ]
        let title = row.item.section.uppercased()
        title.draw(at: NSPoint(x: 4, y: row.isFirst ? 1 : 7), withAttributes: attrs)
        NSColor(theme.floatingStroke.opacity(theme.usesDarkChrome ? 0.38 : 0.30)).setFill()
        NSRect(x: 92, y: row.isFirst ? 8 : 14, width: max(0, bounds.width - 100), height: 1).fill()
    }

    private func drawRowContent(_ row: CommandShortcutGuideRowModel) {
        let y = contentOriginY
        let contentHeight: CGFloat = 30
        let iconRect = NSRect(x: 6, y: y + 6, width: 18, height: 18)
        let icon = NSImage(systemSymbolName: row.item.systemImage, accessibilityDescription: nil)
        icon?.isTemplate = true
        NSColor(ConductorDesign.secondaryText).set()
        icon?.draw(in: iconRect.insetBy(dx: 3.5, dy: 3.5))

        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontScale.size(11), weight: .semibold),
            .foregroundColor: NSColor(ConductorDesign.primaryText)
        ]
        let trailingWidth: CGFloat = editable ? 205 : 76
        let titleRect = NSRect(x: 32, y: y + 7, width: max(0, bounds.width - trailingWidth - 40), height: 16)
        (row.item.title as NSString).draw(in: titleRect, withAttributes: titleAttrs)

        let shortcutAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontScale.size(9.5), weight: .semibold),
            .foregroundColor: NSColor(isRecording ? theme.floatingEmphasis : ConductorDesign.secondaryText)
        ]
        let shortcut = row.item.shortcut as NSString
        let shortcutSize = shortcut.size(withAttributes: shortcutAttrs)
        let shortcutWidth = min(max(shortcutSize.width + 12, 44), 92)
        let shortcutX = editable ? recordButton.frame.minX - shortcutWidth - 8 : bounds.maxX - shortcutWidth - 8
        let shortcutRect = NSRect(x: shortcutX, y: y + 7, width: shortcutWidth, height: style == .plain ? 16 : 17)
        NSColor(shortcutBackground).setFill()
        NSBezierPath(roundedRect: shortcutRect, xRadius: style == .plain ? 4 : 8, yRadius: style == .plain ? 4 : 8).fill()
        shortcut.draw(
            at: NSPoint(x: shortcutRect.midX - shortcutSize.width / 2, y: shortcutRect.midY - shortcutSize.height / 2),
            withAttributes: shortcutAttrs
        )

        _ = contentHeight
    }

    private var shortcutBackground: Color {
        switch style {
        case .card:
            return theme.floatingSelectedFill
        case .plain:
            return theme.floatingSelectedFill.opacity(theme.usesDarkChrome ? 0.46 : 0.54)
        }
    }

    @objc private func recordShortcut() {
        onRecord?()
    }

    @objc private func resetShortcut() {
        onReset?()
    }
}

struct CommandShortcutSectionDivider: View {
    let title: String
    let isFirst: Bool
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorTheme) private var theme

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.conductorSystem(size: 9.2, weight: .semibold, scale: fontScale))
                .foregroundStyle(ConductorDesign.tertiaryText)
                .textCase(.uppercase)
            Rectangle()
                .fill(theme.floatingStroke.opacity(theme.usesDarkChrome ? 0.38 : 0.30))
                .frame(height: 1)
        }
        .padding(.top, isFirst ? 0 : 8)
        .padding(.horizontal, 4)
    }
}

struct CommandShortcutGuideRow: View {
    let item: CommandShortcutGuideItem
    var style: CommandShortcutGuideStyle = .card
    var editable = false
    var isRecording = false
    var onRecord: () -> Void = {}
    var onReset: () -> Void = {}
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorTheme) private var theme

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: item.systemImage)
                .font(.conductorSystem(size: 10, weight: .semibold, scale: fontScale))
                .foregroundStyle(ConductorDesign.secondaryText)
                .frame(width: 18)
                .accessibilityHidden(true)

            Text(item.title)
                .font(.conductorSystem(size: 11, weight: .semibold, scale: fontScale))
                .foregroundStyle(ConductorDesign.primaryText)
                .lineLimit(1)

            Spacer(minLength: 8)

            Text(item.shortcut)
                .font(.conductorSystem(size: 9.5, weight: .semibold, scale: fontScale))
                .foregroundStyle(isRecording ? theme.floatingEmphasis : ConductorDesign.secondaryText)
                .padding(.horizontal, style == .plain ? 5 : 6)
                .frame(height: style == .plain ? 16 : 17)
                .background(shortcutBackground)
                .clipShape(RoundedRectangle(cornerRadius: style == .plain ? 4 : 8, style: .continuous))

            if editable {
                ShortcutGuideInlineButton(
                    title: isRecording ? L("按键", "Press") : L("更改", "Change"),
                    systemImage: isRecording ? "record.circle.fill" : "keyboard",
                    emphasized: isRecording,
                    tooltip: L("录制新的快捷键", "Record a new shortcut"),
                    action: onRecord
                )

                ShortcutGuideInlineButton(
                    title: L("默认", "Default"),
                    systemImage: "arrow.counterclockwise",
                    tooltip: L("恢复默认快捷键", "Restore default shortcut"),
                    action: onReset
                )
            }
        }
        .padding(.horizontal, style == .plain ? 6 : 8)
        .frame(height: style == .plain ? 30 : 28)
        .overlay(alignment: .bottom) {
            if style == .plain {
                Rectangle()
                    .fill(theme.floatingStroke.opacity(theme.usesDarkChrome ? 0.22 : 0.16))
                    .frame(height: 1)
                    .padding(.leading, 30)
            }
        }
    }

    private var shortcutBackground: Color {
        switch style {
        case .card:
            return theme.floatingSelectedFill
        case .plain:
            return theme.floatingSelectedFill.opacity(theme.usesDarkChrome ? 0.46 : 0.54)
        }
    }
}

private struct ShortcutGuideInlineButton: View {
    let title: String
    let systemImage: String
    var emphasized = false
    let tooltip: String
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorTheme) private var theme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.conductorSystem(size: 9, weight: .semibold, scale: fontScale))
                    .accessibilityHidden(true)
                Text(title)
                    .font(.conductorSystem(size: 9.2, weight: .semibold, scale: fontScale))
                    .lineLimit(1)
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, 7)
            .frame(height: 21)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(stroke, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(ConductorPressButtonStyle(pressedScale: 0.99, pressedOpacity: 0.97))
        .conductorHover($hovering)
        .macNativeTooltip(tooltip)
        .accessibilityLabel(Text(tooltip))
    }

    private var foreground: Color {
        if emphasized {
            return theme.floatingEmphasis
        }
        return hovering ? ConductorDesign.primaryText : ConductorDesign.secondaryText
    }

    private var background: Color {
        if emphasized {
            return theme.floatingEmphasis.opacity(theme.usesDarkChrome ? 0.16 : 0.10)
        }
        return hovering ? theme.floatingHoverFill.opacity(0.72) : theme.floatingControlFill.opacity(0.28)
    }

    private var stroke: Color {
        if emphasized {
            return theme.floatingEmphasis.opacity(theme.usesDarkChrome ? 0.34 : 0.26)
        }
        return theme.floatingStroke.opacity(hovering ? 0.40 : 0.18)
    }
}

struct SelectedThemeShowcase: View {
    let theme: TerminalTheme
    @Environment(\.conductorFontScale) private var fontScale

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ThemePreviewArtwork(theme: theme, height: 52)
                .frame(width: 96)

            VStack(alignment: .leading, spacing: 2) {
                Text(L("当前主题", "Current Theme"))
                    .font(.conductorSystem(size: 9.6, weight: .semibold, scale: fontScale))
                    .foregroundStyle(ConductorDesign.tertiaryText)
                    .textCase(.uppercase)

                Text(theme.title)
                    .font(.conductorSystem(size: 13.5, weight: .semibold, scale: fontScale))
                    .foregroundStyle(ConductorDesign.primaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            HStack(spacing: 4) {
                ThemeSwatch(color: theme.accent, width: 18)
                ThemeSwatch(color: theme.terminalChrome, width: 18)
                ThemeSwatch(color: theme.terminalBackground, width: 18)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(theme.floatingControlFill.opacity(theme.usesDarkChrome ? 0.18 : 0.24))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(theme.floatingStroke.opacity(theme.usesDarkChrome ? 0.24 : 0.18))
                .frame(height: 1)
        }
    }
}

struct ThemeOptionRow: View {
    let theme: TerminalTheme
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorTheme) private var activeTheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.conductorSystem(size: 12, weight: .semibold, scale: fontScale))
                    .foregroundStyle(selected ? activeTheme.floatingEmphasis : ConductorDesign.tertiaryText.opacity(0.62))
                    .frame(width: 16)
                    .accessibilityHidden(true)

                Text(theme.title)
                    .font(.conductorSystem(size: 12.0, weight: .medium, scale: fontScale))
                    .foregroundStyle(ConductorDesign.primaryText)
                    .lineLimit(1)

                Spacer(minLength: 8)

                HStack(spacing: 4) {
                    ThemeSwatch(color: theme.accent, width: 16)
                    ThemeSwatch(color: theme.terminalChrome, width: 16)
                    ThemeSwatch(color: theme.terminalBackground, width: 16)
                }
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 32)
            .background(rowFill)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .conductorHover($hovering, animation: nil)
    }

    private var rowFill: Color {
        if selected {
            return activeTheme.floatingSelectedFill
        }
        if hovering {
            return activeTheme.floatingHoverFill.opacity(0.44)
        }
        return Color.clear
    }
}

struct ThemePreviewArtwork: View {
    let theme: TerminalTheme
    var height: CGFloat
    var showsSidebar: Bool = true

    private var large: Bool {
        height > 100
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(
                colors: theme.windowBackdropStops,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            ThemePreviewMotif(theme: theme)
                .opacity(large ? 1 : 0.72)

            HStack(spacing: large ? 8 : 5) {
                if showsSidebar {
                    VStack(alignment: .leading, spacing: large ? 7 : 5) {
                        HStack(spacing: 3) {
                            Circle()
                                .fill(Color.white.opacity(0.82))
                                .frame(width: large ? 5 : 4, height: large ? 5 : 4)
                            Circle()
                                .fill(theme.accent.opacity(0.76))
                                .frame(width: large ? 5 : 4, height: large ? 5 : 4)
                            Spacer(minLength: 0)
                        }
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(theme.shellSelectedFill)
                            .frame(height: large ? 12 : 8)
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(theme.shellHoverFill)
                            .frame(width: large ? 42 : 26, height: large ? 10 : 8)
                        Spacer(minLength: 0)
                    }
                    .padding(large ? 9 : 6)
                    .frame(width: large ? 72 : 45)
                    .background(theme.shellPanelBackground)
                    .clipShape(RoundedRectangle(cornerRadius: large ? 10 : 7, style: .continuous))
                }

                VStack(spacing: 0) {
                    HStack(spacing: large ? 6 : 4) {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(theme.accent.opacity(0.80))
                            .frame(width: large ? 32 : 18, height: large ? 5 : 4)
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(Color.white.opacity(theme.usesDarkChrome ? 0.22 : 0.58))
                            .frame(width: large ? 48 : 28, height: large ? 5 : 4)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, large ? 10 : 7)
                    .frame(height: large ? 25 : 16)
                    .background(theme.terminalChrome.opacity(0.92))

                    VStack(alignment: .leading, spacing: large ? 5 : 3) {
                        PreviewTerminalLine(prompt: "$", text: "swift build", accent: theme.accent, fontSize: large ? 10 : 8.5)
                        PreviewTerminalLine(prompt: ">", text: "Conductor", accent: theme.accent, fontSize: large ? 10 : 8.5)
                        Rectangle()
                            .fill(theme.accent.opacity(0.86))
                            .frame(width: large ? 42 : 22, height: large ? 3 : 2)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(large ? 11 : 7)
                    .background(theme.terminalBackground)
                }
                .clipShape(RoundedRectangle(cornerRadius: large ? 10 : 7, style: .continuous))
            }
            .padding(large ? 10 : 6)
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: large ? 13 : 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: large ? 13 : 9, style: .continuous)
                .stroke(Color.white.opacity(theme.usesDarkChrome ? 0.12 : 0.24), lineWidth: 0.6)
        }
    }
}

struct ThemePreviewMotif: View {
    let theme: TerminalTheme

    var body: some View {
        GeometryReader { proxy in
            switch theme.designLanguage {
            case .neon:
                Path { path in
                    let step: CGFloat = 18
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
                .stroke(theme.accent.opacity(0.20), lineWidth: 0.7)
            case .paper, .editorial:
                VStack(spacing: 13) {
                    ForEach(0..<12, id: \.self) { _ in
                        Rectangle()
                            .fill(theme.shellStroke.opacity(0.36))
                            .frame(height: 1)
                    }
                }
                .padding(.top, 14)
                .padding(.horizontal, 14)
            case .glass, .fluid, .frost:
                ZStack {
                    Circle()
                        .fill(theme.accent.opacity(0.08))
                        .frame(width: proxy.size.width * 0.42)
                        .blur(radius: 12)
                        .offset(x: proxy.size.width * 0.28, y: -proxy.size.height * 0.18)
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(theme.usesDarkChrome ? 0.10 : 0.20), lineWidth: 0.6)
                        .frame(width: proxy.size.width * 0.42, height: proxy.size.height * 0.44)
                        .offset(x: proxy.size.width * 0.22, y: proxy.size.height * 0.18)
                }
            case .botanical:
                HStack(alignment: .bottom, spacing: 11) {
                    ForEach(0..<9, id: \.self) { index in
                        Capsule()
                            .fill(theme.accent.opacity(index.isMultiple(of: 2) ? 0.20 : 0.10))
                            .frame(width: 5, height: CGFloat(24 + index * 7))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(18)
            case .sunlit, .warm:
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.24),
                        theme.accent.opacity(0.16),
                        Color.clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            case .studio, .minimal, .system:
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(theme.usesDarkChrome ? 0.025 : 0.18),
                                Color.clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
        }
        .allowsHitTesting(false)
    }
}

struct PreviewTerminalLine: View {
    let prompt: String
    let text: String
    let accent: Color
    var fontSize: CGFloat = 8.5

    var body: some View {
        HStack(spacing: 4) {
            Text(prompt)
                .foregroundStyle(accent)
            Text(text)
                .foregroundStyle(Color.white.opacity(0.78))
                .lineLimit(1)
        }
        .font(.system(size: fontSize, weight: .medium, design: .monospaced))
    }
}

struct ThemeSwatch: View {
    let color: Color
    var width: CGFloat = 16

    var body: some View {
        RoundedRectangle(cornerRadius: 2.5, style: .continuous)
            .fill(color)
            .frame(width: width, height: 5)
            .overlay {
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .stroke(Color.white.opacity(0.36), lineWidth: 0.5)
            }
    }
}
