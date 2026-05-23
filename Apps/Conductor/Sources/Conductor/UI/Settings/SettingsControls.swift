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
            }
            .frame(width: 236, alignment: .trailing)
        }
        .menuStyle(.button)
    }
}

struct GhosttyResetButton: View {
    let disabled: Bool
    let action: () -> Void
    @Environment(\.conductorTheme) private var theme

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.uturn.backward")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(disabled ? ConductorDesign.tertiaryText : theme.floatingEmphasis)
                .frame(width: 24, height: 24)
                .background(theme.floatingControlFill)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(ConductorPressButtonStyle())
        .disabled(disabled)
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
                        .stroke(theme.floatingStroke.opacity(0.75), lineWidth: 1)
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
                .stroke(theme.floatingStroke.opacity(0.64), lineWidth: 1)
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
                .stroke(theme.floatingStroke.opacity(0.75), lineWidth: 1)
        }
    }
}

struct SettingsPreferenceGroup<Content: View>: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let content: Content
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorTheme) private var theme

    init(
        title: String,
        subtitle: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Image(systemName: systemImage)
                    .font(.conductorSystem(size: 10.5, weight: .semibold, scale: fontScale))
                    .foregroundStyle(theme.floatingEmphasis.opacity(0.82))
                    .frame(width: 14)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.conductorSystem(size: 11.5, weight: .bold, scale: fontScale))
                        .foregroundStyle(ConductorDesign.primaryText)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.conductorSystem(size: 10.1, weight: .medium, scale: fontScale))
                        .foregroundStyle(ConductorDesign.tertiaryText)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)
            }

            content
        }
        .padding(.top, 2)
    }
}

struct SettingsFormSurface<Content: View>: View {
    let content: Content
    @Environment(\.conductorTheme) private var theme

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        LazyVStack(spacing: 0) {
            content
        }
        .background(theme.floatingControlFill.opacity(0.28))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(theme.floatingStroke.opacity(0.48), lineWidth: 0.8)
        }
    }
}

struct SettingsControlRow<Trailing: View>: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let trailing: Trailing
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorTheme) private var theme

    init(
        title: String,
        subtitle: String,
        systemImage: String,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.conductorSystem(size: 11, weight: .semibold, scale: fontScale))
                .foregroundStyle(theme.floatingEmphasis.opacity(0.84))
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.conductorSystem(size: 12.5, weight: .semibold, scale: fontScale))
                    .foregroundStyle(ConductorDesign.primaryText)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.conductorSystem(size: 10.5, weight: .medium, scale: fontScale))
                    .foregroundStyle(ConductorDesign.tertiaryText)
                    .lineLimit(2)
            }

            Spacer(minLength: 12)

            trailing
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 52)
    }
}

struct SettingsToggleRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let isOn: Binding<Bool>

    var body: some View {
        SettingsControlRow(
            title: title,
            subtitle: subtitle,
            systemImage: systemImage
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
    let systemImage: String
    let text: Binding<String>

    var body: some View {
        SettingsControlRow(
            title: title,
            subtitle: subtitle,
            systemImage: systemImage
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
    let systemImage: String
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
            subtitle: subtitle,
            systemImage: systemImage
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
            .fill(theme.floatingSeparator.opacity(0.70))
            .frame(height: 1)
            .padding(.leading, 50)
    }
}

struct SettingsSegmentedPicker<Option: Hashable>: View {
    let options: [Option]
    let selection: Option
    let title: (Option) -> String
    let action: (Option) -> Void

    var body: some View {
        Picker(
            "",
            selection: Binding(
                get: { selection },
                set: { value in
                    guard value != selection else { return }
                    action(value)
                }
            )
        ) {
            ForEach(options, id: \.self) { option in
                Text(title(option))
                    .tag(option)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 278)
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
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: section.systemImage)
                    .font(.conductorSystem(size: 10.5, weight: .semibold, scale: fontScale))
                    .foregroundStyle(selected ? theme.floatingEmphasis : ConductorDesign.secondaryText)
                    .frame(width: 14)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 1) {
                    Text(section.title)
                        .font(.conductorSystem(size: 11.6, weight: selected ? .semibold : .medium, scale: fontScale))
                        .foregroundStyle(ConductorDesign.primaryText)
                        .lineLimit(1)
                    Text(section.subtitle)
                        .font(.conductorSystem(size: 9.4, weight: .medium, scale: fontScale))
                        .foregroundStyle(ConductorDesign.tertiaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 7)
            .frame(height: 44, alignment: .center)
            .background(rowBackground)
            .clipShape(RoundedRectangle(cornerRadius: ConductorTokens.Radius.row, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: ConductorTokens.Radius.row, style: .continuous))
        }
        .buttonStyle(ConductorPressButtonStyle())
        .onHover { value in
            ConductorMotion.perform(ConductorMotion.hover) {
                hovering = value
            }
        }
        .animation(ConductorMotion.selectionGlide, value: selected)
        .animation(ConductorMotion.hover, value: hovering)
    }

    private var rowBackground: some View {
        let shape = RoundedRectangle(cornerRadius: ConductorTokens.Radius.row, style: .continuous)
        return ZStack {
            shape
                .fill(hovering ? theme.floatingHoverFill : Color.clear)
            if selected {
                shape
                    .fill(theme.floatingSelectedFill)
                    .matchedGeometryEffect(id: "settings-section-selection", in: selectionNamespace)
            }
        }
    }
}

struct CommandShortcutGuide: View {
    let rows: [CommandShortcutGuideRowModel]
    var height: CGFloat = 178
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorTheme) private var theme

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 5) {
                ForEach(rows) { row in
                    if row.showsSectionTitle {
                        Text(row.item.section)
                            .font(.conductorSystem(size: 9.5, weight: .semibold, scale: fontScale))
                            .foregroundStyle(ConductorDesign.tertiaryText)
                            .padding(.top, row.isFirst ? 0 : 4)
                            .padding(.horizontal, 2)
                    }
                    CommandShortcutGuideRow(item: row.item)
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.visible)
        .frame(height: height)
        .background(theme.floatingControlFill)
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(theme.floatingStroke, lineWidth: 1)
        }
    }
}

struct CommandShortcutGuideRow: View {
    let item: CommandShortcutGuideItem
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorTheme) private var theme

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: item.systemImage)
                .font(.conductorSystem(size: 10, weight: .semibold, scale: fontScale))
                .foregroundStyle(ConductorDesign.secondaryText)
                .frame(width: 18)

            Text(item.title)
                .font(.conductorSystem(size: 11, weight: .semibold, scale: fontScale))
                .foregroundStyle(ConductorDesign.primaryText)
                .lineLimit(1)

            Spacer(minLength: 8)

            Text(item.shortcut)
                .font(.conductorSystem(size: 9.5, weight: .semibold, scale: fontScale))
                .foregroundStyle(ConductorDesign.secondaryText)
                .padding(.horizontal, 6)
                .frame(height: 17)
                .background(theme.floatingSelectedFill)
                .clipShape(Capsule())
        }
        .padding(.horizontal, 8)
        .frame(height: 26)
    }
}

struct SelectedThemeShowcase: View {
    let theme: TerminalTheme
    @Environment(\.conductorFontScale) private var fontScale

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ThemePreviewArtwork(theme: theme, height: 238)

            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(L("当前主题", "Current Theme"))
                        .font(.conductorSystem(size: 10.5, weight: .semibold, scale: fontScale))
                        .foregroundStyle(ConductorDesign.tertiaryText)
                        .textCase(.uppercase)
                    Text(theme.title)
                        .font(.conductorSystem(size: 22, weight: .bold, scale: fontScale))
                        .foregroundStyle(ConductorDesign.primaryText)
                        .lineLimit(1)
                    Text(theme.themeDescription)
                        .font(.conductorSystem(size: 11.2, weight: .medium, scale: fontScale))
                        .foregroundStyle(ConductorDesign.secondaryText)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                HStack(spacing: 5) {
                    ThemeSwatch(color: theme.accent, width: 30)
                    ThemeSwatch(color: theme.floatingPanelBase, width: 30)
                    ThemeSwatch(color: theme.terminalChrome, width: 30)
                    ThemeSwatch(color: theme.terminalBackground, width: 30)
                }

                Text(theme.designLanguage.title)
                    .font(.conductorSystem(size: 10.5, weight: .bold, scale: fontScale))
                    .foregroundStyle(theme.floatingEmphasis)
                    .padding(.horizontal, 9)
                    .frame(height: 24)
                    .background(theme.floatingSelectedFill)
                    .clipShape(Capsule())
            }
        }
        .padding(12)
        .background(
            LinearGradient(
                colors: [
                    theme.floatingControlStrongFill,
                    theme.floatingControlFill.opacity(0.62)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: ConductorTokens.Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ConductorTokens.Radius.card, style: .continuous)
                .stroke(theme.floatingStroke.opacity(0.82), lineWidth: 1)
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
            HStack(spacing: 12) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.conductorSystem(size: 13, weight: .semibold, scale: fontScale))
                    .foregroundStyle(selected ? activeTheme.floatingEmphasis : ConductorDesign.tertiaryText.opacity(0.62))
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 7) {
                        Text(theme.title)
                            .font(.conductorSystem(size: 12.4, weight: .semibold, scale: fontScale))
                            .foregroundStyle(ConductorDesign.primaryText)
                            .lineLimit(1)

                        Text(theme.designLanguage.title)
                            .font(.conductorSystem(size: 9.3, weight: .bold, scale: fontScale))
                            .foregroundStyle(activeTheme.floatingEmphasis.opacity(0.9))
                            .padding(.horizontal, 6)
                            .frame(height: 17)
                            .background(activeTheme.floatingControlFill.opacity(0.58))
                            .clipShape(Capsule())
                    }

                    Text(theme.themeDescription)
                        .font(.conductorSystem(size: 10.1, weight: .medium, scale: fontScale))
                        .foregroundStyle(ConductorDesign.tertiaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: 12)

                HStack(spacing: 4) {
                    ThemeSwatch(color: theme.accent, width: 22)
                    ThemeSwatch(color: theme.floatingPanelBase, width: 22)
                    ThemeSwatch(color: theme.terminalChrome, width: 22)
                    ThemeSwatch(color: theme.terminalBackground, width: 22)
                }
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 52)
            .background(rowFill)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { value in
            ConductorMotion.perform(ConductorMotion.hover) {
                hovering = value
            }
        }
        .animation(ConductorMotion.hover, value: hovering)
    }

    private var rowFill: Color {
        if selected {
            return activeTheme.floatingSelectedFill
        }
        if hovering {
            return activeTheme.floatingHoverFill.opacity(0.72)
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
                .stroke(Color.white.opacity(theme.usesDarkChrome ? 0.22 : 0.42), lineWidth: 1)
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
                        .fill(theme.accent.opacity(0.16))
                        .frame(width: proxy.size.width * 0.42)
                        .blur(radius: 22)
                        .offset(x: proxy.size.width * 0.28, y: -proxy.size.height * 0.18)
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(theme.usesDarkChrome ? 0.18 : 0.34), lineWidth: 1)
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
