import ConductorCore
import SwiftUI

/// 设置面板：主窗口内 inspector，跟随主题、自定义控件 + 微交互。
/// 改控件 → `coordinator.applyConfig` 即时生效 + 落盘 config.yaml。
struct SettingsView: View {
    let coordinator: AppCoordinator
    var onClose: () -> Void = {}
    @ObservedObject private var configStore = ConfigStore.shared

    @State private var shell = ConfigStore.shared.config.terminal.shell ?? ""
    @State private var selectedSection: SettingsSectionID = .default
    /// 键位编辑用本地草稿：避免每个按键都落盘，提交（回车）时才生效。
    @State private var keybindingDrafts: [String: String] = [:]
    @State private var languageChoice: String = AppLanguage.current

    private var config: AppConfig { configStore.config }

    private var languageBinding: Binding<String> {
        Binding(
            get: { languageChoice },
            set: { choice in
                guard choice != languageChoice else { return }
                languageChoice = choice
                AppLanguage.apply(choice)   // 持久化 + 热生效（整棵 UI 即时重建）
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            HStack(alignment: .top, spacing: 14) {
                sectionRail

                ScrollView {
                    VStack(spacing: 18) {
                        selectedSectionContent
                    }
                    .padding(.top, 12)
                    .padding(.trailing, 22)
                    .padding(.bottom, 22)
                }
                .scrollIndicators(.visible)
            }
        }
        .frame(maxHeight: .infinity)
        .background(AppStyle.windowBackground)   // 纯色主题背景：跟随浅/深，不用毛玻璃（停靠面板背后无内容，材质会误跟系统外观）
        .overlay(alignment: .leading) {
            // 左缘细线：把停靠面板与终端画布分开（深色用高光、浅色用淡阴影线）
            Rectangle()
                .fill(AppStyle.separator)
                .frame(width: 1)
                .allowsHitTesting(false)
        }
    }

    private var header: some View {
        HStack {
            Text(L("设置"))
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(AppStyle.textPrimary)
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(AppStyle.textSecondary)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(AppStyle.hoverFill))
                    .contentShape(Circle())
            }
            .buttonStyle(PressScaleStyle())
        }
        .padding(.horizontal, 20)
        .padding(.top, 22)
        .padding(.bottom, 10)
    }

    private var sectionRail: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(SettingsSectionID.allCases) { section in
                SettingsRailButton(
                    section: section,
                    selected: selectedSection == section
                ) {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        selectedSection = section
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 10)
        .padding(.trailing, 4)
        .padding(.vertical, 12)
        .frame(width: 136)
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var selectedSectionContent: some View {
        switch selectedSection {
        case .appearance:
            appearanceSection
            if config.appearance.theme == "custom" { colorsSection }
        case .terminal:
            terminalSection
        case .ghostty:
            ghosttySection
        case .behavior:
            behaviorSection
        case .keybindings:
            keybindingsSection
        }
    }

    private var appearanceSection: some View {
        SettingsSection(title: L("外观")) {
            SettingsRow(label: L("主题"), first: true) {
                ThemedSegmented(options: [(L("深色"), "dark"), (L("浅色"), "light"), (L("自定义"), "custom")],
                                selection: bind(\.appearance.theme))
            }
            SettingsRow(label: L("语言")) {
                // 语言名按惯例保持各自语言原文，不随界面语言翻译
                ThemedSegmented(
                    options: [(L("跟随系统"), AppLanguage.system),
                              ("简体中文", AppLanguage.simplifiedChinese),
                              ("English", AppLanguage.english)],
                    selection: languageBinding)
            }
            SettingsRow(label: L("字体")) {
                Picker("", selection: bind(\.appearance.font.family)) {
                    ForEach(SystemFonts.monospaced, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .frame(maxWidth: 190)
            }
            SettingsRow(label: L("字号")) {
                ThemedStepper(value: bind(\.appearance.font.size), range: 6...72)
            }
            SettingsRow(label: L("光标")) {
                ThemedSegmented(options: [(L("竖线"), "bar"), (L("方块"), "block"), (L("下划线"), "underline")],
                                selection: bind(\.appearance.cursorStyle))
            }
            SettingsRow(label: L("水平内边距")) {
                ThemedStepper(value: bind(\.appearance.padding.x), range: 0...60)
            }
            SettingsRow(label: L("垂直内边距")) {
                ThemedStepper(value: bind(\.appearance.padding.y), range: 0...60)
            }
        }
    }

    private var terminalSection: some View {
        SettingsSection(title: L("终端")) {
            SettingsRow(label: "Shell", first: true) {
                ThemedTextField(placeholder: L("登录 shell"), text: $shell) {
                    update { $0.terminal.shell = shell.isEmpty ? nil : shell }
                }
            }
            SettingsRow(label: L("回滚行数")) {
                ThemedStepper(value: bind(\.terminal.scrollback), range: 60_000...1_000_000, step: 10_000)
            }
            SettingsRow(label: L("选中即复制")) {
                ThemedToggle(isOn: bind(\.terminal.copyOnSelect))
            }
            SettingsRow(label: L("有运行进程时关闭需确认")) {
                ThemedToggle(isOn: bind(\.terminal.confirmCloseRunning))
            }
        }
    }

    private var ghosttySection: some View {
        VStack(spacing: 16) {
            SettingsSection(title: L("常用能力")) {
                GhosttyMappedConfigRow(
                    title: L("字体与字号"),
                    summary: L("字体、字号和字格微调会直接影响终端阅读感"),
                    keys: ["font-family", "font-size", "adjust-cell-height"],
                    first: true
                )
                GhosttyMappedConfigRow(
                    title: L("窗口与光标"),
                    summary: L("窗口留白、光标样式和颜色会跟随下方设置即时生效"),
                    keys: ["cursor-style", "cursor-color"]
                )
                GhosttyMappedConfigRow(
                    title: L("主题颜色"),
                    summary: L("背景、文字、选区和搜索颜色统一归到颜色分类里")
                )
            }

            ForEach(ConductorGhosttyConfigCatalog.productGroups) { group in
                SettingsSection(title: group.title) {
                    GhosttyConfigGroupHeader(group: group, first: true)
                    ForEach(group.keys, id: \.self) { key in
                        GhosttyOverrideRow(
                            key: key,
                            value: configStore.config.ghosttyOverrides[key] ?? "",
                            setValue: { setGhosttyOverride(key, to: $0) },
                            reset: { setGhosttyOverride(key, to: "") }
                        )
                    }
                }
            }
        }
    }

    private var behaviorSection: some View {
        SettingsSection(title: L("行为")) {
            SettingsRow(label: L("启动时恢复布局"), first: true) {
                ThemedToggle(isOn: bind(\.behavior.restoreLayoutOnLaunch))
            }
            SettingsRow(label: L("新标签目录")) {
                ThemedSegmented(options: [(L("工作区"), "workspace"), (L("当前"), "activePane"), (L("主目录"), "home")],
                                selection: bind(\.behavior.newTabCwd))
            }
        }
    }

    // MARK: 自定义配色（仅 theme=custom 时显示）

    private var colorsSection: some View {
        SettingsSection(title: L("自定义配色")) {
            SettingsRow(label: L("背景"), first: true) {
                ColorPicker("", selection: colorBinding({ $0?.background }, "1b1c22", { $0.background = $1 })).labelsHidden()
            }
            SettingsRow(label: L("前景")) {
                ColorPicker("", selection: colorBinding({ $0?.foreground }, "e6e6e6", { $0.foreground = $1 })).labelsHidden()
            }
            SettingsRow(label: L("光标")) {
                ColorPicker("", selection: colorBinding({ $0?.cursor }, "7aa2f7", { $0.cursor = $1 })).labelsHidden()
            }
            SettingsRow(label: L("选区")) {
                ColorPicker("", selection: colorBinding({ $0?.selection }, "33467c", { $0.selection = $1 })).labelsHidden()
            }
        }
    }

    private func colorBinding(_ get: @escaping (Colors?) -> String?, _ fallback: String,
                              _ set: @escaping (inout Colors, String) -> Void) -> Binding<Color> {
        Binding(
            get: { Color(hex: get(configStore.config.appearance.colors) ?? fallback) ?? .gray },
            set: { newColor in
                update { cfg in
                    var colors = cfg.appearance.colors ?? Colors()
                    set(&colors, newColor.hexString)
                    cfg.appearance.colors = colors
                }
            })
    }

    // MARK: 快捷键自定义（输入键位串，回车生效；留空回落内置默认）

    private var keybindingsSection: some View {
        SettingsSection(title: L("快捷键")) {
            ForEach(Array(coordinator.commandRegistry.commands.enumerated()), id: \.element.id) { idx, cmd in
                SettingsRow(label: cmd.title, first: idx == 0) {
                    ThemedTextField(placeholder: cmd.defaultKeybinding ?? L("未设置"),
                                    text: keybindingDraftBinding(cmd.id)) {
                        commitKeybinding(cmd.id)
                    }
                }
            }
        }
    }

    private func keybindingDraftBinding(_ id: String) -> Binding<String> {
        Binding(
            get: { keybindingDrafts[id] ?? coordinator.commandRegistry.effectiveKeybinding(for: id) ?? "" },
            set: { keybindingDrafts[id] = $0 })
    }

    private func commitKeybinding(_ id: String) {
        let raw = (keybindingDrafts[id] ?? "").trimmingCharacters(in: .whitespaces).lowercased()
        update { cfg in
            if raw.isEmpty { cfg.keybindings.removeValue(forKey: id) }
            else { cfg.keybindings[id] = raw }
        }
        keybindingDrafts[id] = nil   // 回落到“有效键位”展示
    }

    private func bind<T>(_ keyPath: WritableKeyPath<AppConfig, T>) -> Binding<T> {
        Binding(
            get: { configStore.config[keyPath: keyPath] },
            set: { newValue in update { $0[keyPath: keyPath] = newValue } })
    }

    private func update(_ mutate: (inout AppConfig) -> Void) {
        var c = configStore.config
        mutate(&c)
        coordinator.applyConfig(c)
    }

    private func setGhosttyOverride(_ key: String, to value: String) {
        update { config in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                config.ghosttyOverrides.removeValue(forKey: key)
                return
            }
            config.ghosttyOverrides[key] = trimmed
        }
    }
}

private struct SettingsRailButton: View {
    let section: SettingsSectionID
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: section.systemImage)
                    .font(.system(size: 12.5, weight: .semibold))
                    .frame(width: 17)
                VStack(alignment: .leading, spacing: 1) {
                    Text(section.title)
                        .font(.system(size: 12.5, weight: selected ? .semibold : .medium))
                    Text(section.subtitle)
                        .font(.system(size: 9.5, weight: .medium))
                        .lineLimit(1)
                        .foregroundStyle(AppStyle.textTertiary)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(selected ? AppStyle.textPrimary : AppStyle.textSecondary)
            .padding(.horizontal, 9)
            .frame(height: 42)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? AppStyle.activeFill.opacity(0.78) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct GhosttyMappedConfigRow: View {
    let title: String
    let summary: String
    var keys: [String] = []
    var first = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(AppStyle.textPrimary)
            Text(summary)
                .font(.system(size: 11.5))
                .foregroundStyle(AppStyle.textSecondary)
                .lineLimit(2)
        }
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .help(keys.isEmpty ? "" : keys.joined(separator: ", "))
    }
}

private struct GhosttyConfigGroupHeader: View {
    let group: ConductorGhosttyConfigGroup
    var first = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: group.systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppStyle.accent)
                .frame(width: 18, height: 22)
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text(group.title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(AppStyle.textPrimary)
                    Spacer(minLength: 8)
                    Text(group.countTitle)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(AppStyle.textTertiary)
                }
                Text(group.subtitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(AppStyle.textSecondary)
                    .lineLimit(2)
            }
        }
        .padding(.top, 2)
        .padding(.bottom, 6)
    }
}

private struct GhosttyOverrideRow: View {
    let key: String
    let value: String
    let setValue: (String) -> Void
    let reset: () -> Void

    private var isOverridden: Bool { !value.isEmpty }
    private var copy: ConductorGhosttyConfigCopy { ConductorGhosttyConfigCatalog.copy(for: key) }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(copy.title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(AppStyle.textPrimary)
                Text(copy.summary)
                    .font(.system(size: 11))
                    .foregroundStyle(AppStyle.textSecondary)
                    .lineLimit(2)
                Text(isOverridden ? L("已自定义") : L("使用默认值"))
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(isOverridden ? AppStyle.accent : AppStyle.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 10)
            control
            Button(action: reset) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(isOverridden ? AppStyle.textSecondary : AppStyle.textTertiary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressScaleStyle())
            .disabled(!isOverridden)
            .help(L("恢复默认"))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(minHeight: 58)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(isOverridden ? AppStyle.activeFill.opacity(0.22) : Color.clear)
        )
        .help(key)
    }

    @ViewBuilder
    private var control: some View {
        switch ConductorGhosttyConfigCatalog.controlKind(for: key) {
        case .boolean:
            ThemedSegmented(
                options: [(L("默认"), ""), (L("开"), "true"), (L("关"), "false")],
                selection: Binding(get: { value }, set: setValue)
            )
        case let .choice(options):
            Picker("", selection: Binding(get: { value }, set: setValue)) {
                Text(L("默认")).tag("")
                ForEach(options, id: \.value) { option in
                    Text(option.label).tag(option.value)
                }
            }
            .labelsHidden()
            .frame(width: 136)
        case .color:
            GhosttyColorControl(value: value, setValue: setValue)
        case .filePath:
            GhosttyPathControl(key: key, value: value, setValue: setValue)
        case .fontFamily:
            Picker("", selection: Binding(get: { value }, set: setValue)) {
                Text(L("默认")).tag("")
                ForEach(SystemFonts.monospaced, id: \.self) { family in
                    Text(family).tag(family)
                }
            }
            .labelsHidden()
            .frame(width: 150)
        case let .integer(range, step):
            GhosttyIntegerControl(value: value, range: range, step: step, setValue: setValue)
        case let .percent(range, defaultValue, format):
            GhosttyPercentControl(value: value, range: range, defaultValue: defaultValue, format: format, setValue: setValue)
        case let .decimal(range, defaultValue, step):
            GhosttyDecimalControl(value: value, range: range, defaultValue: defaultValue, step: step, setValue: setValue)
        case .text:
            GhosttyFreeTextControl(value: value, setValue: setValue)
        }
    }
}

private struct GhosttyFreeTextControl: View {
    let value: String
    let setValue: (String) -> Void
    @State private var isEditing = false
    @FocusState private var focused: Bool

    private var showsEditor: Bool { isEditing || !value.isEmpty }

    var body: some View {
        if showsEditor {
            ThemedTextField(
                placeholder: L("输入自定义值"),
                text: Binding(get: { value }, set: setValue)
            )
            .focused($focused)
            .frame(width: 172)
            .onAppear {
                guard isEditing else { return }
                DispatchQueue.main.async { focused = true }
            }
        } else {
            HStack(spacing: 8) {
                Text(L("默认"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppStyle.textTertiary)
                    .frame(width: 48, alignment: .trailing)
                Button {
                    isEditing = true
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(AppStyle.textSecondary)
                }
                .buttonStyle(IconButtonStyle(size: 28))
                .help(L("添加自定义值"))
            }
        }
    }
}

private struct GhosttyIntegerControl: View {
    let value: String
    let range: ClosedRange<Int>
    let step: Int
    let setValue: (String) -> Void

    private var binding: Binding<Int> {
        Binding(
            get: { Int(value) ?? range.lowerBound },
            set: { newValue in setValue(String(min(max(newValue, range.lowerBound), range.upperBound))) }
        )
    }

    var body: some View {
        ThemedStepper(value: binding, range: range, step: step)
    }
}

private struct GhosttyDecimalControl: View {
    let value: String
    let range: ClosedRange<Double>
    let defaultValue: Double
    let step: Double
    let setValue: (String) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Slider(
                value: Binding(
                    get: { Double(value) ?? defaultValue },
                    set: { setValue(Self.formatted($0, step: step)) }
                ),
                in: range,
                step: step
            )
            .frame(width: 118)
            Text(Self.formatted(Double(value) ?? defaultValue, step: step))
                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(AppStyle.accent)
                .frame(width: 38, alignment: .trailing)
        }
    }

    private static func formatted(_ value: Double, step: Double) -> String {
        step < 1 ? String(format: "%.1f", value) : String(format: "%.0f", value)
    }
}

private struct GhosttyPercentControl: View {
    let value: String
    let range: ClosedRange<Double>
    let defaultValue: Double
    let format: ConductorGhosttyPercentFormat
    let setValue: (String) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Slider(
                value: Binding(
                    get: { parse(value) ?? defaultValue },
                    set: { setValue(serialize($0)) }
                ),
                in: range
            )
            .frame(width: 124)
            Text(display(parse(value) ?? defaultValue))
                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(AppStyle.accent)
                .frame(width: 46, alignment: .trailing)
        }
    }

    private func parse(_ raw: String) -> Double? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasSuffix("%") {
            return Double(trimmed.dropLast())
        }
        return Double(trimmed)
    }

    private func serialize(_ value: Double) -> String {
        switch format {
        case .fraction:
            return String(format: "%.2f", value)
        case .percentString:
            return "\(Int(value.rounded()))%"
        }
    }

    private func display(_ value: Double) -> String {
        switch format {
        case .fraction:
            return "\(Int((value * 100).rounded()))%"
        case .percentString:
            return "\(Int(value.rounded()))%"
        }
    }
}

private struct GhosttyColorControl: View {
    let value: String
    let setValue: (String) -> Void

    private var colorBinding: Binding<Color> {
        Binding(
            get: { Color(hex: value) ?? Color.white },
            set: { setValue($0.hexString) }
        )
    }

    var body: some View {
        HStack(spacing: 8) {
            ColorPicker("", selection: colorBinding)
                .labelsHidden()
                .frame(width: 36)
            Text(value.isEmpty ? L("默认") : "#\(value.trimmingCharacters(in: CharacterSet(charactersIn: "#")))")
                .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(value.isEmpty ? AppStyle.textTertiary : AppStyle.accent)
                .frame(width: 74, alignment: .leading)
        }
    }
}

private struct GhosttyPathControl: View {
    let key: String
    let value: String
    let setValue: (String) -> Void

    private var isImagePicker: Bool { key == "background-image" }

    var body: some View {
        Button(action: choosePath) {
            HStack(spacing: 6) {
                Image(systemName: isImagePicker ? "photo" : "folder")
                    .font(.system(size: 11.5, weight: .semibold))
                Text(value.isEmpty ? L("选择") : URL(fileURLWithPath: value).lastPathComponent)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(value.isEmpty ? AppStyle.textSecondary : AppStyle.accent)
            .frame(width: 142, height: 28)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(AppStyle.hoverFill.opacity(0.76))
            )
        }
        .buttonStyle(PressScaleStyle())
    }

    private func choosePath() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = !isImagePicker
        panel.canChooseFiles = isImagePicker
        if isImagePicker {
            panel.allowedContentTypes = [.png, .jpeg]
        }
        panel.prompt = isImagePicker ? L("选择图片") : L("选择目录")
        if panel.runModal() == .OK, let url = panel.url, isUsableSelection(url) {
            setValue(url.path)
        }
    }

    private func isUsableSelection(_ url: URL) -> Bool {
        guard isImagePicker else { return true }
        return ["png", "jpg", "jpeg"].contains(url.pathExtension.lowercased())
    }
}
