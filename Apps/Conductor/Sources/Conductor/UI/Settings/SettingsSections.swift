import ConductorCore
import AppKit
import CodexBar
import SwiftUI

private func L(_ zh: String, _ en: String) -> String {
    ConductorLocalization.text(zh: zh, en: en)
}


extension AppearanceSettingsPanel {
    func overviewSettings(snapshot: SettingsSnapshot) -> some View {
        Form {
            Section(L("设置入口", "Settings")) {
                SettingsOverviewPath(snapshot: snapshot) { section in
                    selectSection(section)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    func usageSettings(snapshot: SettingsSnapshot) -> some View {
        ConductorUsageSettingsContent(
            style: usagePanelStyle,
            languageIdentifier: snapshot.appearance.language.usageFeatureLanguageIdentifier)
            .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var usagePanelStyle: ConductorUsagePanelStyle {
        ConductorUsagePanelStyle(
            panelBase: theme.floatingPanelBase,
            panelWash: theme.floatingPanelWash,
            controlFill: theme.floatingControlFill,
            controlStrongFill: theme.floatingControlStrongFill,
            stroke: theme.floatingStroke,
            separator: theme.floatingSeparator,
            emphasis: theme.floatingEmphasis,
            primaryText: theme.shellChromeText,
            secondaryText: theme.shellChromeTextMuted.opacity(0.86),
            tertiaryText: theme.shellChromeTextMuted.opacity(0.64),
            usesDarkChrome: theme.usesDarkChrome)
    }

    private func appearanceDensityBinding(current: AppearanceDensity) -> Binding<AppearanceDensity> {
        Binding(
            get: { current },
            set: { density in
                guard density != current else { return }
                model.performShellMotion(ConductorMotion.selection) {
                    model.setAppearanceDensity(density)
                }
            }
        )
    }

    private func appearanceLanguageBinding(current: AppearanceLanguage) -> Binding<AppearanceLanguage> {
        Binding(
            get: { current },
            set: { language in
                guard language != current else { return }
                model.performShellMotion(ConductorMotion.selection) {
                    model.setLanguage(language)
                }
            }
        )
    }

    private func appearanceFontFamilyBinding(current: AppearanceFontFamily) -> Binding<AppearanceFontFamily> {
        Binding(
            get: { current },
            set: { family in
                guard family != current else { return }
                model.performShellMotion(ConductorMotion.selection) {
                    model.setFontFamily(family)
                }
            }
        )
    }

    private func appearanceFontScaleBinding(current: AppearanceFontScale) -> Binding<AppearanceFontScale> {
        Binding(
            get: { current },
            set: { scale in
                guard scale != current else { return }
                model.performShellMotion(ConductorMotion.selection) {
                    model.setFontScale(scale)
                }
            }
        )
    }

    private func terminalThemeBinding(current: TerminalTheme) -> Binding<TerminalTheme> {
        Binding(
            get: { current },
            set: { theme in
                guard theme != current else { return }
                model.performShellMotion(ConductorMotion.selection) {
                    model.theme = theme
                }
            }
        )
    }

    private func terminalUseCustomFontBinding(renderer: TerminalRendererPreferences) -> Binding<Bool> {
        Binding(
            get: { renderer.useCustomFont },
            set: { useCustomFont in
                model.setTerminalUseCustomFont(useCustomFont)
            }
        )
    }

    private func terminalFontSizeBinding(current: CGFloat) -> Binding<Double> {
        Binding(
            get: { Double(current) },
            set: { fontSize in
                model.setTerminalFontSize(CGFloat(fontSize))
            }
        )
    }

    private func terminalLineHeightBinding(current: CGFloat) -> Binding<Double> {
        Binding(
            get: { Double(current) },
            set: { lineHeight in
                model.setTerminalLineHeight(CGFloat(lineHeight))
            }
        )
    }

    private func terminalBackgroundOpacityBinding(current: CGFloat) -> Binding<Double> {
        Binding(
            get: { Double(current) },
            set: { opacity in
                model.setTerminalBackgroundOpacity(CGFloat(opacity))
            }
        )
    }

    func interfaceSettings(snapshot: SettingsSnapshot) -> some View {
        let appearance = snapshot.appearance
        return Form {
            Section(L("外观控制", "Appearance Controls")) {
                Picker(
                    L("窗口密度", "Window Density"),
                    selection: appearanceDensityBinding(current: appearance.density)
                ) {
                    ForEach(AppearanceDensity.allCases) { density in
                        Text(density.title).tag(density)
                    }
                }
                .pickerStyle(.segmented)

                Text(appearance.density.subtitle)
                    .foregroundStyle(.secondary)

            }

            Section(L("文字", "Text")) {
                Picker(
                    L("语言", "Language"),
                    selection: appearanceLanguageBinding(current: appearance.language)
                ) {
                    ForEach(AppearanceLanguage.allCases) { language in
                        Text(language.title).tag(language)
                    }
                }
                .pickerStyle(.segmented)

                Text(appearance.language.subtitle)
                    .foregroundStyle(.secondary)

                Picker(
                    L("字体", "Font"),
                    selection: appearanceFontFamilyBinding(current: appearance.fontFamily)
                ) {
                    ForEach(AppearanceFontFamily.allCases) { family in
                        Text(family.title).tag(family)
                    }
                }
                .pickerStyle(.segmented)

                Text(appearance.fontFamily.subtitle)
                    .foregroundStyle(.secondary)

                Picker(
                    L("字号", "Font Size"),
                    selection: appearanceFontScaleBinding(current: appearance.fontScale)
                ) {
                    ForEach(AppearanceFontScale.allCases) { scale in
                        Text(scale.title).tag(scale)
                    }
                }
                .pickerStyle(.segmented)

                Text(appearance.fontScale.subtitle)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    func terminalSettingsDashboard(snapshot: SettingsSnapshot) -> some View {
        LazyVStack(alignment: .leading, spacing: 16) {
            terminalSettingsSectionRail(snapshot: snapshot)

            activeTerminalSettingsSection(snapshot: snapshot)
        }
    }

    func terminalSettingsSectionRail(snapshot: SettingsSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker(
                L("终端设置分区", "Terminal settings section"),
                selection: terminalSettingsSectionBinding
            ) {
                ForEach(TerminalSettingsSection.allCases) { section in
                    Label(section.title, systemImage: section.systemImage)
                        .tag(section)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            SettingsSectionLabel(
                title: selectedTerminalSettingsSection.title,
                subtitle: selectedTerminalSettingsSection.subtitle
            )
        }
    }

    private var terminalSettingsSectionBinding: Binding<TerminalSettingsSection> {
        Binding(
            get: { selectedTerminalSettingsSection },
            set: { section in
                guard section != selectedTerminalSettingsSection else { return }
                selectTerminalSettingsSection(section)
            }
        )
    }

    @ViewBuilder
    func activeTerminalSettingsSection(snapshot: SettingsSnapshot) -> some View {
        switch selectedTerminalSettingsSection {
        case .typography:
            terminalTypographySettings(snapshot: snapshot)
        case .display:
            terminalCursorSettings(snapshot: snapshot)
            terminalBackgroundSettings(snapshot: snapshot)
        case .selection:
            terminalSelectionMouseSettings(snapshot: snapshot)
        case .input:
            terminalClipboardSettings(snapshot: snapshot)
            terminalKeyboardSettings(snapshot: snapshot)
        }
    }

    func selectTerminalSettingsSection(_ section: TerminalSettingsSection) {
        guard selectedTerminalSettingsSection != section else { return }
        ConductorMotion.withoutAnimation {
            selectedTerminalSettingsSection = section
        }
    }

    func contentSwapEdge<T: Equatable>(from current: T, to next: T, in order: [T]) -> Edge {
        guard let currentIndex = order.firstIndex(of: current),
              let nextIndex = order.firstIndex(of: next) else {
            return .trailing
        }
        return nextIndex >= currentIndex ? .trailing : .leading
    }

    func shellAndProxySettings(snapshot: SettingsSnapshot) -> some View {
        LazyVStack(alignment: .leading, spacing: 18) {
            terminalShellSettings(snapshot: snapshot)

            SettingsSectionLabel(
                title: L("网络环境", "Network Environment"),
                subtitle: L("写入新终端进程的代理变量，和 Shell 启动项属于同一条启动路径", "Proxy variables for new terminal processes live with startup behavior")
            )

            proxySettings(snapshot: snapshot)
        }
    }

    func automationSettings(snapshot: SettingsSnapshot) -> some View {
        LazyVStack(alignment: .leading, spacing: 18) {
            aiSettings(snapshot: snapshot)

            SettingsSectionLabel(
                title: L("终端提醒", "Terminal Alerts"),
                subtitle: L("保留铃声反馈设置", "Bell feedback settings")
            )

            terminalBellSettings(snapshot: snapshot)
        }
    }

    func updateSettings(snapshot: SettingsSnapshot) -> some View {
        SettingsUpdateSection(
            preferences: snapshot.updatePreferences,
            state: snapshot.updateState,
            setManifestURL: { model.setUpdateManifestURL($0) },
            setAutomaticChecksEnabled: { model.setAutomaticUpdateChecksEnabled($0) },
            setPrefersDeltaUpdates: { model.setPrefersDeltaUpdates($0) },
            checkForUpdates: { model.checkForUpdates(manual: true) },
            downloadUpdate: { model.downloadAvailableUpdate() },
            cancelUpdate: { model.cancelUpdateOperation() },
            installUpdate: { model.installDownloadedUpdateAndRelaunch() }
        )
    }

    @ViewBuilder
    func terminalShellSettings(snapshot: SettingsSnapshot) -> some View {
        let renderer = snapshot.appearance.terminalRenderer
        let commandOverride = renderer.ghosttyOverride(for: "initial-command")
        let directoryOverride = renderer.ghosttyOverride(for: "working-directory")
        let scrollbackOverride = renderer.ghosttyOverride(for: "scrollback-limit")
        let scrollbackValue = scrollbackOverride.enabled ? scrollbackOverride.normalizedValue : ""

        Form {
            Section(L("Shell 与启动", "Shell and Startup")) {
                LabeledContent(L("Shell 集成", "Shell Integration")) {
                    settingsStatusLabel(title: L("自动管理", "Managed"), systemImage: "lock.fill")
                }

                Text(L("已启用 detect，并保留 no-cursor；这里不需要手动配置", "Enabled with detect and no-cursor; no manual setup needed"))
                    .foregroundStyle(.secondary)

                LabeledContent(L("启动命令", "Startup Command")) {
                    ShellCommandSettingControl(
                        value: commandOverride.normalizedValue,
                        setValue: { setGhosttyOverrideValue(key: "initial-command", value: $0) },
                        reset: { resetGhosttyOverride(key: "initial-command") }
                    )
                }

                Text(L("留空时打开默认登录 shell；适合进入 tmux、ssh 或固定开发环境", "Leave empty for the default login shell; useful for tmux, ssh, or a fixed dev environment"))
                    .foregroundStyle(.secondary)

                LabeledContent(L("默认工作目录", "Default Working Directory")) {
                    WorkingDirectorySettingControl(
                        value: directoryOverride.normalizedValue,
                        setValue: { setGhosttyOverrideValue(key: "working-directory", value: $0) },
                        reset: { resetGhosttyOverride(key: "working-directory") }
                    )
                }

                Text(L("留空时继承工作区或新建终端时的目录", "Leave empty to inherit the workspace or new-terminal directory"))
                    .foregroundStyle(.secondary)

                LabeledContent(L("历史保留容量", "Scrollback Capacity")) {
                    ScrollbackPresetPicker(
                        value: scrollbackValue,
                        setValue: { model.setTerminalScrollbackLimit($0) },
                        reset: { model.setTerminalScrollbackLimit("") }
                    )
                }

                Text(L("Ghostty 按字节保留历史；设置会立即保存并刷新配置，容量扩展通常新建终端后生效", "Ghostty stores scrollback by bytes; changes save and refresh immediately, but capacity expansion usually applies to new terminals"))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    func terminalBackgroundSettings(snapshot: SettingsSnapshot) -> some View {
        let renderer = snapshot.appearance.terminalRenderer
        let blurOverride = renderer.ghosttyOverride(for: "background-blur")
        let imageOverride = renderer.ghosttyOverride(for: "background-image")
        let imageOpacityOverride = renderer.ghosttyOverride(for: "background-image-opacity")
        let imageFitOverride = renderer.ghosttyOverride(for: "background-image-fit")
        let selectionForegroundOverride = renderer.ghosttyOverride(for: "selection-foreground")
        let selectionBackgroundOverride = renderer.ghosttyOverride(for: "selection-background")
        let searchBackgroundOverride = renderer.ghosttyOverride(for: "search-background")

        return Form {
            Section(L("背景", "Background")) {
                LabeledContent(L("背景不透明度", "Background Opacity")) {
                    HStack(spacing: 10) {
                        Slider(
                            value: terminalBackgroundOpacityBinding(current: renderer.backgroundOpacity),
                            in: 0.35...1,
                            step: 0.01
                        )
                        .frame(width: 210)

                        Text(percentText(renderer.backgroundOpacity))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 48, alignment: .trailing)
                    }
                }

                Text(L("降低后可以透出窗口材质，100% 最清晰", "Lower values show the window material; 100% is clearest"))
                    .foregroundStyle(.secondary)

                LabeledContent(L("背景模糊", "Background Blur")) {
                    GhosttyBooleanOverridePicker(
                        state: booleanState(for: blurOverride),
                        action: { setBooleanOverride(key: "background-blur", state: $0) }
                    )
                }

                Text(L("透明背景下柔化后方内容，默认跟随内置策略", "Softens content behind transparent terminals; default follows the built-in policy"))
                    .foregroundStyle(.secondary)

                LabeledContent(L("背景图片", "Background Image")) {
                    GhosttyFileOverrideControl(
                        key: "background-image",
                        value: imageOverride.normalizedValue,
                        setValue: { setGhosttyOverrideValue(key: "background-image", value: $0) },
                        reset: { resetGhosttyOverride(key: "background-image") }
                    )
                }

                Text(L("选择一张图片作为终端背景，留空时使用主题背景", "Choose an image for the terminal background, or leave empty to use the theme"))
                    .foregroundStyle(.secondary)

                LabeledContent(L("图片显示方式", "Image Fit")) {
                    GhosttyPresetOverrideMenu(
                        value: imageFitOverride.normalizedValue,
                        options: [
                            GhosttyPresetOption(title: L("完整显示", "Contain"), value: "contain"),
                            GhosttyPresetOption(title: L("填满裁切", "Cover"), value: "cover"),
                            GhosttyPresetOption(title: L("拉伸", "Stretch"), value: "stretch"),
                            GhosttyPresetOption(title: L("原始大小", "Original"), value: "none")
                        ],
                        setValue: { setGhosttyOverrideValue(key: "background-image-fit", value: $0) },
                        reset: { resetGhosttyOverride(key: "background-image-fit") }
                    )
                }

                Text(L("控制背景图片如何填充终端区域", "Controls how the background image fills the terminal area"))
                    .foregroundStyle(.secondary)

                LabeledContent(L("图片透明度", "Image Opacity")) {
                    GhosttySliderOverrideControl(
                        key: "background-image-opacity",
                        value: imageOpacityOverride.normalizedValue,
                        range: 0...1,
                        step: 0.01,
                        defaultValue: 1,
                        valueText: { "\(Int(($0 * 100).rounded()))%" },
                        setValue: { setGhosttyOverrideValue(key: "background-image-opacity", value: String(format: "%.2f", Double($0))) },
                        reset: { resetGhosttyOverride(key: "background-image-opacity") }
                    )
                }

                Text(L("让背景图片更轻，避免干扰终端文字", "Makes the image quieter so terminal text stays readable"))
                    .foregroundStyle(.secondary)
            }

            Section(L("颜色", "Colors")) {
                LabeledContent(L("选区文字", "Selection Text")) {
                    GhosttyColorOverrideControl(
                        key: "selection-foreground",
                        value: selectionForegroundOverride.normalizedValue,
                        setValue: { setGhosttyOverrideValue(key: "selection-foreground", value: $0) },
                        reset: { resetGhosttyOverride(key: "selection-foreground") }
                    )
                }

                Text(L("选中内容时的文字颜色，默认跟随主题", "Text color for selected content; defaults to the theme"))
                    .foregroundStyle(.secondary)

                LabeledContent(L("选区背景", "Selection Background")) {
                    GhosttyColorOverrideControl(
                        key: "selection-background",
                        value: selectionBackgroundOverride.normalizedValue,
                        setValue: { setGhosttyOverrideValue(key: "selection-background", value: $0) },
                        reset: { resetGhosttyOverride(key: "selection-background") }
                    )
                }

                Text(L("拖选文本时的高亮颜色", "Highlight color used while selecting text"))
                    .foregroundStyle(.secondary)

                LabeledContent(L("搜索高亮", "Search Highlight")) {
                    GhosttyColorOverrideControl(
                        key: "search-background",
                        value: searchBackgroundOverride.normalizedValue,
                        setValue: { setGhosttyOverrideValue(key: "search-background", value: $0) },
                        reset: { resetGhosttyOverride(key: "search-background") }
                    )
                }

                Text(L("搜索命中结果的背景色", "Background color for search matches"))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    func terminalSelectionMouseSettings(snapshot: SettingsSnapshot) -> some View {
        let renderer = snapshot.appearance.terminalRenderer
        let clearTypingOverride = renderer.ghosttyOverride(for: "selection-clear-on-typing")
        let clearCopyOverride = renderer.ghosttyOverride(for: "selection-clear-on-copy")
        let copyOverride = renderer.ghosttyOverride(for: "copy-on-select")
        let hideMouseOverride = renderer.ghosttyOverride(for: "mouse-hide-while-typing")
        let reportingOverride = renderer.ghosttyOverride(for: "mouse-reporting")
        let scrollOverride = renderer.ghosttyOverride(for: "mouse-scroll-multiplier")
        let linkOverride = renderer.ghosttyOverride(for: "link-url")
        let previewOverride = renderer.ghosttyOverride(for: "link-previews")

        return Form {
            Section(L("选择、鼠标与链接", "Selection, Mouse, and Links")) {
                LabeledContent(L("输入时清除选区", "Clear Selection While Typing")) {
                    GhosttyBooleanOverridePicker(
                        state: booleanState(for: clearTypingOverride),
                        action: { setBooleanOverride(key: "selection-clear-on-typing", state: $0) }
                    )
                }

                Text(L("开始输入后自动取消当前选区", "Automatically clears the current selection when typing starts"))
                    .foregroundStyle(.secondary)

                LabeledContent(L("复制后清除选区", "Clear Selection After Copy")) {
                    GhosttyBooleanOverridePicker(
                        state: booleanState(for: clearCopyOverride),
                        action: { setBooleanOverride(key: "selection-clear-on-copy", state: $0) }
                    )
                }

                Text(L("复制完成后收起高亮，适合连续操作", "Clears the highlight after copying"))
                    .foregroundStyle(.secondary)

                LabeledContent(L("选中即复制", "Copy On Select")) {
                    GhosttyBooleanOverridePicker(
                        state: booleanState(for: copyOverride),
                        action: { setBooleanOverride(key: "copy-on-select", state: $0) }
                    )
                }

                Text(L("像 X11 终端一样，选中文本后立即写入剪贴板", "Copies selected text immediately, similar to X11 terminals"))
                    .foregroundStyle(.secondary)

                LabeledContent(L("输入时隐藏鼠标", "Hide Mouse While Typing")) {
                    GhosttyBooleanOverridePicker(
                        state: booleanState(for: hideMouseOverride),
                        action: { setBooleanOverride(key: "mouse-hide-while-typing", state: $0) }
                    )
                }

                Text(L("减少鼠标指针挡住终端文本的情况", "Keeps the pointer from covering terminal text while typing"))
                    .foregroundStyle(.secondary)

                LabeledContent(L("应用鼠标上报", "App Mouse Reporting")) {
                    GhosttyBooleanOverridePicker(
                        state: booleanState(for: reportingOverride),
                        action: { setBooleanOverride(key: "mouse-reporting", state: $0) }
                    )
                }

                Text(L("允许 vim、tmux、less 等终端应用接收鼠标事件", "Lets terminal apps such as vim, tmux, and less receive mouse events"))
                    .foregroundStyle(.secondary)

                LabeledContent(L("滚轮速度", "Scroll Speed")) {
                    GhosttyPresetOverrideMenu(
                        value: scrollOverride.normalizedValue,
                        options: [
                            GhosttyPresetOption(title: L("较慢", "Slower"), value: "0.5"),
                            GhosttyPresetOption(title: L("标准", "Standard"), value: "1"),
                            GhosttyPresetOption(title: L("较快", "Faster"), value: "2"),
                            GhosttyPresetOption(title: L("很快", "Fast"), value: "3")
                        ],
                        setValue: { setGhosttyOverrideValue(key: "mouse-scroll-multiplier", value: $0) },
                        reset: { resetGhosttyOverride(key: "mouse-scroll-multiplier") }
                    )
                }

                Text(L("调整鼠标或触控板滚动终端历史的速度", "Adjusts mouse or trackpad scroll speed through terminal history"))
                    .foregroundStyle(.secondary)

                LabeledContent(L("链接识别", "Link Detection")) {
                    GhosttyBooleanOverridePicker(
                        state: booleanState(for: linkOverride),
                        action: { setBooleanOverride(key: "link-url", state: $0) }
                    )
                }

                Text(L("识别终端输出里的 URL，方便点击打开", "Detects URLs in terminal output so they can be opened"))
                    .foregroundStyle(.secondary)

                LabeledContent(L("链接预览", "Link Previews")) {
                    GhosttyBooleanOverridePicker(
                        state: booleanState(for: previewOverride),
                        action: { setBooleanOverride(key: "link-previews", state: $0) }
                    )
                }

                Text(L("悬停链接时显示预览能力，默认跟随内置支持", "Shows link preview behavior on hover when supported"))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    func terminalClipboardSettings(snapshot: SettingsSnapshot) -> some View {
        let renderer = snapshot.appearance.terminalRenderer
        let readOverride = renderer.ghosttyOverride(for: "clipboard-read")
        let writeOverride = renderer.ghosttyOverride(for: "clipboard-write")
        let trimOverride = renderer.ghosttyOverride(for: "clipboard-trim-trailing-spaces")
        let protectionOverride = renderer.ghosttyOverride(for: "clipboard-paste-protection")
        let bracketedOverride = renderer.ghosttyOverride(for: "clipboard-paste-bracketed-safe")

        return Form {
            Section(L("剪贴板与粘贴安全", "Clipboard and Paste Safety")) {
                LabeledContent(L("允许读取剪贴板", "Allow Clipboard Read")) {
                    GhosttyBooleanOverridePicker(
                        state: booleanState(for: readOverride),
                        action: { setBooleanOverride(key: "clipboard-read", state: $0) }
                    )
                }

                Text(L("终端应用可以从系统剪贴板读取内容", "Terminal apps may read from the system clipboard"))
                    .foregroundStyle(.secondary)

                LabeledContent(L("允许写入剪贴板", "Allow Clipboard Write")) {
                    GhosttyBooleanOverridePicker(
                        state: booleanState(for: writeOverride),
                        action: { setBooleanOverride(key: "clipboard-write", state: $0) }
                    )
                }

                Text(L("终端应用可以把内容写入系统剪贴板", "Terminal apps may write to the system clipboard"))
                    .foregroundStyle(.secondary)

                LabeledContent(L("复制时清理尾随空格", "Trim Trailing Spaces")) {
                    GhosttyBooleanOverridePicker(
                        state: booleanState(for: trimOverride),
                        action: { setBooleanOverride(key: "clipboard-trim-trailing-spaces", state: $0) }
                    )
                }

                Text(L("复制多行输出时去掉行尾多余空格", "Removes extra spaces at line endings when copying output"))
                    .foregroundStyle(.secondary)

                LabeledContent(L("危险粘贴保护", "Paste Protection")) {
                    GhosttyBooleanOverridePicker(
                        state: booleanState(for: protectionOverride),
                        action: { setBooleanOverride(key: "clipboard-paste-protection", state: $0) }
                    )
                }

                Text(L("粘贴疑似多行命令或危险内容时保留确认保护", "Keeps confirmation protection for suspicious multi-line or risky pastes"))
                    .foregroundStyle(.secondary)

                LabeledContent(L("Bracketed Paste 安全模式", "Bracketed Paste Safety")) {
                    GhosttyBooleanOverridePicker(
                        state: booleanState(for: bracketedOverride),
                        action: { setBooleanOverride(key: "clipboard-paste-bracketed-safe", state: $0) }
                    )
                }

                Text(L("让支持的 shell 和编辑器更准确地区分键入与粘贴", "Helps supported shells and editors distinguish typed input from pasted text"))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    func terminalBellSettings(snapshot: SettingsSnapshot) -> some View {
        let renderer = snapshot.appearance.terminalRenderer
        let bellPathOverride = renderer.ghosttyOverride(for: "bell-audio-path")
        let bellVolumeOverride = renderer.ghosttyOverride(for: "bell-audio-volume")

        return Form {
            Section(L("铃声", "Bell")) {
                LabeledContent(L("铃声音频", "Bell Sound")) {
                    GhosttyFileOverrideControl(
                        key: "bell-audio-path",
                        value: bellPathOverride.normalizedValue,
                        setValue: { setGhosttyOverrideValue(key: "bell-audio-path", value: $0) },
                        reset: { resetGhosttyOverride(key: "bell-audio-path") }
                    )
                }

                Text(L("选择自定义铃声文件，留空时使用默认反馈", "Choose a custom bell sound file, or leave empty for the default feedback"))
                    .foregroundStyle(.secondary)

                LabeledContent(L("铃声音量", "Bell Volume")) {
                    GhosttySliderOverrideControl(
                        key: "bell-audio-volume",
                        value: bellVolumeOverride.normalizedValue,
                        range: 0...1,
                        step: 0.01,
                        defaultValue: 1,
                        valueText: { "\(Int(($0 * 100).rounded()))%" },
                        setValue: { setGhosttyOverrideValue(key: "bell-audio-volume", value: String(format: "%.2f", Double($0))) },
                        reset: { resetGhosttyOverride(key: "bell-audio-volume") }
                    )
                }

                Text(L("调低可以保留提示但不打断工作", "Lower volume keeps feedback without interrupting work"))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    func terminalKeyboardSettings(snapshot: SettingsSnapshot) -> some View {
        let renderer = snapshot.appearance.terminalRenderer
        let optionOverride = renderer.ghosttyOverride(for: "macos-option-as-alt")
        let remapOverride = renderer.ghosttyOverride(for: "key-remap")

        return Form {
            Section(L("键盘", "Keyboard")) {
                LabeledContent(L("Option 作为 Alt", "Option As Alt")) {
                    GhosttyPresetOverrideMenu(
                        value: optionOverride.normalizedValue,
                        options: [
                            GhosttyPresetOption(title: L("关闭", "Off"), value: "false"),
                            GhosttyPresetOption(title: L("左 Option", "Left Option"), value: "left"),
                            GhosttyPresetOption(title: L("右 Option", "Right Option"), value: "right"),
                            GhosttyPresetOption(title: L("左右都启用", "Both Options"), value: "true")
                        ],
                        setValue: { setGhosttyOverrideValue(key: "macos-option-as-alt", value: $0) },
                        reset: { resetGhosttyOverride(key: "macos-option-as-alt") }
                    )
                }

                Text(L("给 vim、emacs、tmux 等终端程序发送 Alt/Meta 组合键", "Sends Alt/Meta key combinations to terminal apps such as vim, emacs, and tmux"))
                    .foregroundStyle(.secondary)

                LabeledContent(L("高级键位映射", "Advanced Key Remap")) {
                    GhosttyInlineTextOverrideControl(
                        key: "key-remap",
                        placeholder: "ctrl+a=home",
                        value: remapOverride.normalizedValue,
                        systemImage: "keyboard",
                        setValue: { setGhosttyOverrideValue(key: "key-remap", value: $0) },
                        reset: { resetGhosttyOverride(key: "key-remap") }
                    )
                }

                Text(L("只在需要兼容特殊终端工作流时填写；常用快捷键请去命令页", "Use only for special terminal workflows; common shortcuts belong in Commands"))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    func terminalTypographySettings(snapshot: SettingsSnapshot) -> some View {
        let appearance = snapshot.appearance
        let renderer = appearance.terminalRenderer
        let downloadStates = snapshot.terminalFontDownloadStates
        return Form {
            TerminalRendererSummary(appearance: appearance)

            Section(L("字体与字格", "Typography")) {
                LabeledContent(L("终端字体", "Terminal Font")) {
                    HStack(spacing: 8) {
                        TerminalFontPickerMenu(
                            selection: renderer.fontPreset,
                            downloadStates: downloadStates,
                            action: { preset in
                                model.performShellMotion(ConductorMotion.selection) {
                                    model.setTerminalFontPreset(preset)
                                }
                            },
                            download: { preset in
                                model.downloadTerminalFont(preset)
                            }
                        )

                        let selectedChoice = TerminalFontLibrary.choices.first { $0.preset == renderer.fontPreset }
                        if let selectedChoice, !selectedChoice.isInstalled, selectedChoice.canDownload {
                            Button {
                                model.downloadTerminalFont(selectedChoice.preset)
                            } label: {
                                if downloadStates[selectedChoice.preset]?.isDownloading == true {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Label(
                                        selectedChoice.preset.directDownloadURL == nil ? L("获取", "Get") : L("下载", "Download"),
                                        systemImage: selectedChoice.preset.directDownloadURL == nil ? "safari" : "arrow.down.circle"
                                    )
                                    .labelStyle(.titleAndIcon)
                                }
                            }
                            .disabled(downloadStates[selectedChoice.preset]?.isDownloading == true)
                        }
                    }
                }

                Text(renderer.selectedFontStatusTitle)
                    .foregroundStyle(.secondary)

                Toggle(
                    L("自定义字体", "Custom Font"),
                    isOn: terminalUseCustomFontBinding(renderer: renderer)
                )
                .disabled(renderer.customFontFamilyName == nil)

                Text(customTerminalFontSubtitle(for: appearance))
                    .foregroundStyle(.secondary)

                Button(L("导入字体…", "Import Font...")) {
                    model.importTerminalFont()
                }

                LabeledContent(L("终端字号", "Terminal Font Size")) {
                    HStack(spacing: 10) {
                        Slider(
                            value: terminalFontSizeBinding(current: appearance.terminalFontSize),
                            in: Double(AppearancePreferences.minTerminalFontSize)...Double(AppearancePreferences.maxTerminalFontSize),
                            step: 0.5
                        )
                        .frame(width: 210)

                        Text(terminalFontSizeText(appearance.terminalFontSize))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 48, alignment: .trailing)
                    }
                }

                Text(L("调大更清晰，调小能显示更多行列", "Larger is easier to read; smaller fits more rows and columns"))
                    .foregroundStyle(.secondary)

                LabeledContent(L("行高", "Line Height")) {
                    HStack(spacing: 10) {
                        Slider(
                            value: terminalLineHeightBinding(current: renderer.lineHeight),
                            in: 0.80...1.50,
                            step: 0.01
                        )
                        .frame(width: 210)

                        Text(multiplierText(renderer.lineHeight))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 48, alignment: .trailing)
                    }
                }

                Text(L("让输出更紧凑或更舒展", "Makes terminal output tighter or more relaxed"))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    func terminalCursorSettings(snapshot: SettingsSnapshot) -> some View {
        let renderer = snapshot.appearance.terminalRenderer
        let colorOverride = renderer.ghosttyOverride(for: "cursor-color")
        let opacityOverride = renderer.ghosttyOverride(for: "cursor-opacity")
        let textOverride = renderer.ghosttyOverride(for: "cursor-text")
        let clickOverride = renderer.ghosttyOverride(for: "cursor-click-to-move")

        return Form {
            Section(L("光标", "Cursor")) {
                LabeledContent(L("光标样式", "Cursor Style")) {
                    Picker(
                        "",
                        selection: Binding(
                            get: { renderer.cursorStyle },
                            set: { model.setTerminalCursorStyle($0) }
                        )
                    ) {
                        ForEach(TerminalCursorStyle.allCases, id: \.self) { style in
                            Text(style.title)
                                .tag(style)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 236)
                }

                Text(L("选择块、空心块、竖线或下划线光标", "Choose block, hollow block, bar, or underline"))
                    .foregroundStyle(.secondary)

                Toggle(
                    L("光标闪烁", "Cursor Blink"),
                    isOn: Binding(
                        get: { renderer.cursorBlink },
                        set: { model.setTerminalCursorBlink($0) }
                    )
                )

                Text(L("关闭后光标保持常亮，适合减少视觉干扰", "Keeps the cursor steady when disabled"))
                    .foregroundStyle(.secondary)

                LabeledContent(L("光标颜色", "Cursor Color")) {
                    GhosttyColorOverrideControl(
                        key: "cursor-color",
                        value: colorOverride.normalizedValue,
                        setValue: { setGhosttyOverrideValue(key: "cursor-color", value: $0) },
                        reset: { resetGhosttyOverride(key: "cursor-color") }
                    )
                }

                Text(L("默认跟随主题，也可以指定一个固定颜色", "Follows the theme by default, or use a fixed color"))
                    .foregroundStyle(.secondary)

                LabeledContent(L("光标透明度", "Cursor Opacity")) {
                    GhosttySliderOverrideControl(
                        key: "cursor-opacity",
                        value: opacityOverride.normalizedValue,
                        range: 0.15...1,
                        step: 0.01,
                        defaultValue: 1,
                        valueText: { "\(Int(($0 * 100).rounded()))%" },
                        setValue: { setGhosttyOverrideValue(key: "cursor-opacity", value: String(format: "%.2f", Double($0))) },
                        reset: { resetGhosttyOverride(key: "cursor-opacity") }
                    )
                }

                Text(L("降低后光标更轻，保持 100% 最醒目", "Lower values make the cursor quieter; 100% is most visible"))
                    .foregroundStyle(.secondary)

                LabeledContent(L("光标内文字颜色", "Cursor Text Color")) {
                    GhosttyColorOverrideControl(
                        key: "cursor-text",
                        value: textOverride.normalizedValue,
                        setValue: { setGhosttyOverrideValue(key: "cursor-text", value: $0) },
                        reset: { resetGhosttyOverride(key: "cursor-text") }
                    )
                }

                Text(L("光标覆盖字符时使用的文字颜色", "Text color used when the cursor covers a character"))
                    .foregroundStyle(.secondary)

                LabeledContent(L("点击移动光标", "Click To Move Cursor")) {
                    GhosttyBooleanOverridePicker(
                        state: booleanState(for: clickOverride),
                        action: { setBooleanOverride(key: "cursor-click-to-move", state: $0) }
                    )
                }

                Text(L("允许鼠标点击把光标移动到目标位置", "Allows mouse clicks to move the cursor position"))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    func setGhosttyOverrideValue(key: String, value: String) {
        model.setGhosttyOverrideValue(key: key, value: value)
        model.setGhosttyOverrideEnabled(key: key, enabled: !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    func resetGhosttyOverride(key: String) {
        model.setGhosttyOverrideEnabled(key: key, enabled: false)
    }

    func booleanState(for override: TerminalGhosttyConfigOverride) -> GhosttyBooleanOverrideState {
        guard override.enabled else { return .defaultValue }
        return override.normalizedValue.lowercased() == "false" ? .off : .on
    }

    func setBooleanOverride(key: String, state: GhosttyBooleanOverrideState) {
        switch state {
        case .defaultValue:
            resetGhosttyOverride(key: key)
        case .on:
            setGhosttyOverrideValue(key: key, value: "true")
        case .off:
            setGhosttyOverrideValue(key: key, value: "false")
        }
    }

    func proxySettings(snapshot: SettingsSnapshot) -> some View {
        let proxy = snapshot.appearance.terminalRenderer.proxy
        return Form {
            Section(L("终端代理", "Terminal Proxy")) {
                Toggle(
                    L("启用代理", "Enable Proxy"),
                    isOn: Binding(
                        get: { proxy.enabled },
                        set: { model.setTerminalProxyEnabled($0) }
                    )
                )

                Text(L("写入新终端进程的 HTTP(S)/ALL_PROXY 环境变量", "Writes HTTP(S)/ALL_PROXY env vars for new terminal processes"))
                    .foregroundStyle(.secondary)

                LabeledContent("HTTP_PROXY") {
                    TextField(
                        "http://127.0.0.1:7890",
                        text: Binding(
                            get: { proxy.httpProxy },
                            set: { model.setTerminalProxyHTTP($0) }
                        )
                    )
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .frame(width: 278)
                }

                LabeledContent("HTTPS_PROXY") {
                    TextField(
                        "http://127.0.0.1:7890",
                        text: Binding(
                            get: { proxy.httpsProxy },
                            set: { model.setTerminalProxyHTTPS($0) }
                        )
                    )
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .frame(width: 278)
                }

                LabeledContent("ALL_PROXY") {
                    TextField(
                        "socks5://127.0.0.1:7890",
                        text: Binding(
                            get: { proxy.allProxy },
                            set: { model.setTerminalProxyAll($0) }
                        )
                    )
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .frame(width: 278)
                }

                LabeledContent("NO_PROXY") {
                    TextField(
                        "localhost,127.0.0.1,::1",
                        text: Binding(
                            get: { proxy.noProxy },
                            set: { model.setTerminalProxyNoProxy($0) }
                        )
                    )
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .frame(width: 278)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    func aiSettings(snapshot: SettingsSnapshot) -> some View {
        let appearance = snapshot.appearance
        let replyNotifications = appearance.agentReplyNotifications
        let agentCLIStatuses = snapshot.agentCLIStatuses
        return Form {
            Section(L("AI 安装检测", "AI Installation Check")) {
                ForEach(AgentHookProvider.allCases) { provider in
                    AgentCLIStatusRow(
                        provider: provider,
                        status: agentCLIStatuses[provider] ?? .unknown(provider: provider),
                        install: { model.openAgentInstallPage(provider) }
                    )
                }

                Text(L("检测登录 Shell PATH、常见安装目录和手动路径；安装后点重新检测。", "Scans login shell PATH, common install locations, and manual paths; scan again after installing."))
                    .foregroundStyle(.secondary)

                Button {
                    model.refreshAgentCLIStatuses()
                } label: {
                    Label(L("重新检测", "Scan Again"), systemImage: "arrow.clockwise")
                }
            }

            Section(L("系统通知", "System Notifications")) {
                NotificationPermissionStatusRow(
                    state: snapshot.notificationAuthorizationState,
                    check: model.checkNotificationPermissionFromToolbar,
                    test: model.sendTestSystemNotificationFromSettings
                )

                Toggle(
                    L("工作完成提醒", "Work Completion Alerts"),
                    isOn: Binding(
                        get: { replyNotifications.enabled },
                        set: { model.setAgentReplyNotificationsEnabled($0) }
                    )
                )

                Text(replyNotifications.enabled
                    ? L("后台命令、终端提醒和任务回复会尝试发送系统横幅", "Background commands, terminal alerts, and task replies can send system banners")
                    : L("关闭后不主动发送系统横幅和声音", "Turns off proactive system banners and sounds")
                )
                .foregroundStyle(.secondary)

                Toggle(
                    L("仅在未关注时通知", "Only When Unattended"),
                    isOn: Binding(
                        get: { replyNotifications.onlyWhenUnattended },
                        set: { model.setAgentReplyNotificationsOnlyWhenUnattended($0) }
                    )
                )

                Text(L("Conductor 不在前台，或相关终端未被选中时提醒", "Alerts when Conductor is inactive or the related terminal is not selected"))
                    .foregroundStyle(.secondary)

                Toggle(
                    L("包含事件摘要", "Include Event Summary"),
                    isOn: Binding(
                        get: { replyNotifications.includeSummary },
                        set: { model.setAgentReplyNotificationsIncludeSummary($0) }
                    )
                )

                Text(L("通知正文显示任务、终端或回复摘要", "Shows task, terminal, or reply details in the notification body"))
                    .foregroundStyle(.secondary)

                Toggle(
                    L("通知声音", "Notification Sound"),
                    isOn: Binding(
                        get: { replyNotifications.playSound },
                        set: { model.setAgentReplyNotificationsPlaySound($0) }
                    )
                )

                Text(L("使用系统默认通知声音", "Uses the default system notification sound"))
                    .foregroundStyle(.secondary)

                if let message = snapshot.notificationDeliveryTestMessage ?? snapshot.agentHookSettingsMessage {
                    LabeledContent {
                        Button {
                            model.openSystemNotificationSettings()
                        } label: {
                            Label(L("系统设置", "System Settings"), systemImage: "gearshape")
                        }
                    } label: {
                        Text(message)
                            .font(.conductorSystem(size: 10.5, weight: .medium, scale: appearance.fontScale))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .onAppear {
            if agentCLIStatuses.values.allSatisfy({ $0.state == .unknown }) {
                model.refreshAgentCLIStatuses()
            }
            model.refreshNotificationAuthorizationState()
        }
    }

    func customTerminalFontSubtitle(for appearance: AppearancePreferences) -> String {
        if let name = appearance.terminalRenderer.customFontFamilyName,
           appearance.terminalRenderer.useCustomFont {
            return name
        }
        return L("导入 .ttf/.otf/.ttc 并直接用于 Ghostty", "Import .ttf/.otf/.ttc and use it in Ghostty")
    }

    func terminalFontSizeText(_ value: CGFloat) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded.rounded() == rounded {
            return "\(Int(rounded)) pt"
        }
        return String(format: "%.1f pt", Double(rounded))
    }

    func multiplierText(_ value: CGFloat) -> String {
        String(format: "%.2fx", Double(value))
    }

    func percentText(_ value: CGFloat) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    private func settingsStatusLabel(title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.conductorSystem(size: 10.5, weight: .semibold, scale: fontScale))
            .labelStyle(.titleAndIcon)
            .lineLimit(1)
            .foregroundStyle(theme.floatingEmphasis)
    }

    func commandSettings() -> some View {
        LazyVStack(alignment: .leading, spacing: 10) {
            Label {
                Text(L("命令与快捷键", "Commands and Shortcuts"))
                    .font(.conductorSystem(size: 12, weight: .semibold, scale: fontScale))
                    .foregroundStyle(ConductorDesign.primaryText)
            } icon: {
                Image(systemName: "keyboard")
                    .font(.conductorSystem(size: 10, weight: .semibold, scale: fontScale))
                    .foregroundStyle(ConductorDesign.secondaryText)
                    .accessibilityHidden(true)
            }
            .labelStyle(.titleAndIcon)
            .frame(maxWidth: .infinity, alignment: .leading)

            ZStack(alignment: .topTrailing) {
                CommandShortcutGuide(
                    rows: commandShortcutRows(),
                    height: 320,
                    style: .plain,
                    editable: true,
                    recordingCommand: recordingShortcutCommand,
                    onRecord: { command in
                        recordingShortcutCommand = command
                        shortcutRecordingMessage = shortcutRecordingPrompt(for: command)
                    },
                    onReset: { command in
                        model.resetKeyboardShortcut(for: command)
                        shortcutRecordingMessage = L("已恢复默认快捷键。", "Restored the default shortcut.")
                    })

                if let recordingShortcutCommand {
                    shortcutRecorderOverlay(for: recordingShortcutCommand)
                        .padding(10)
                }
            }

            HStack(spacing: 8) {
                ControlGroup {
                    Button(L("全部恢复默认", "Reset All")) {
                        model.resetKeyboardShortcuts()
                        recordingShortcutCommand = nil
                        shortcutRecordingMessage = L("全部快捷键已恢复默认。", "All shortcuts were restored to defaults.")
                    }

                    Button(L("导入", "Import")) {
                        importShortcutProfile()
                    }

                    Button(L("导出", "Export")) {
                        exportShortcutProfile()
                    }
                }
                .font(.conductorSystem(size: 10.5, weight: .semibold, scale: fontScale))
                .controlSize(.small)

                Text(shortcutRecordingMessage ?? L("录制时按 Esc 取消；必须包含 Cmd，避免抢走正常输入。", "Press Esc to cancel while recording; shortcuts must include Cmd so normal typing stays safe."))
                    .font(.conductorSystem(size: 10, weight: .medium, scale: fontScale))
                    .foregroundStyle(ConductorDesign.tertiaryText)
                    .lineLimit(2)
            }
        }
    }

    private func importShortcutProfile() {
        recordingShortcutCommand = nil
        let panel = NSOpenPanel()
        panel.title = L("导入快捷键配置", "Import Shortcut Profile")
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        guard panel.runModal() == .OK,
              let url = panel.url else { return }
        do {
            let result = try model.importKeyboardShortcutProfile(from: url)
            shortcutRecordingMessage = shortcutImportMessage(result)
        } catch {
            shortcutRecordingMessage = L(
                "导入失败：\(error.localizedDescription)",
                "Import failed: \(error.localizedDescription)"
            )
        }
    }

    private func exportShortcutProfile() {
        recordingShortcutCommand = nil
        let panel = NSSavePanel()
        panel.title = L("导出快捷键配置", "Export Shortcut Profile")
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "conductor-shortcuts.json"
        guard panel.runModal() == .OK,
              let url = panel.url else { return }
        do {
            let count = try model.exportKeyboardShortcutProfile(to: url)
            shortcutRecordingMessage = L(
                "已导出 \(count) 个自定义快捷键。",
                "Exported \(count) custom shortcuts."
            )
        } catch {
            shortcutRecordingMessage = L(
                "导出失败：\(error.localizedDescription)",
                "Export failed: \(error.localizedDescription)"
            )
        }
    }

    private func shortcutImportMessage(_ result: KeyboardShortcutProfileImportResult) -> String {
        var parts = [
            L("已导入 \(result.importedCount) 个快捷键", "Imported \(result.importedCount) shortcuts")
        ]
        if result.replacedConflictCount > 0 {
            parts.append(L("处理 \(result.replacedConflictCount) 个冲突", "resolved \(result.replacedConflictCount) conflicts"))
        }
        if result.ignoredUnknownCommandCount > 0 {
            parts.append(L("忽略 \(result.ignoredUnknownCommandCount) 个未知命令", "ignored \(result.ignoredUnknownCommandCount) unknown commands"))
        }
        if result.rejectedShortcutCount > 0 {
            parts.append(L("拒绝 \(result.rejectedShortcutCount) 个无效快捷键", "rejected \(result.rejectedShortcutCount) invalid shortcuts"))
        }
        return parts.joined(separator: " · ")
    }

    private func shortcutRecorderOverlay(for command: ConductorShellCommand) -> some View {
        Label {
            HStack(spacing: 8) {
                Text(L("按下新的快捷键", "Press a new shortcut"))
                    .font(.conductorSystem(size: 10.5, weight: .semibold, scale: fontScale))
                    .foregroundStyle(ConductorDesign.primaryText)
                Text(command.rawValue)
                    .font(.conductorSystem(size: 9.2, weight: .medium, scale: fontScale))
                    .foregroundStyle(ConductorDesign.tertiaryText)
            }
        } icon: {
            Image(systemName: "record.circle")
                .font(.conductorSystem(size: 11, weight: .semibold, scale: fontScale))
                .foregroundStyle(theme.floatingEmphasis)
        }
        .labelStyle(.titleAndIcon)
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: ConductorTokens.Radius.controlGroup, style: .continuous))
        .background {
            ConductorKeyboardShortcutBridge(autofocus: true, forceAutofocus: true) { event in
                handleShortcutRecording(event, for: command)
            }
        }
    }

    private func handleShortcutRecording(_ event: NSEvent, for command: ConductorShellCommand) -> Bool {
        guard event.type == .keyDown else { return false }
        if event.keyCode == 53 {
            recordingShortcutCommand = nil
            shortcutRecordingMessage = L("已取消录制。", "Recording canceled.")
            return true
        }
        guard let shortcut = KeyboardShortcutDefinition(event: event) else {
            shortcutRecordingMessage = L("需要包含 Cmd 的组合键。", "Use a shortcut that includes Cmd.")
            return true
        }
        guard !shortcut.isReservedSystemShortcut else {
            shortcutRecordingMessage = L("Cmd-Q 保留给退出应用，不能覆盖。", "Cmd-Q is reserved for quitting the app.")
            return true
        }
        let conflictTitle = model.shortcutConflictTitle(for: shortcut, assigningTo: command)
        model.setKeyboardShortcut(shortcut, for: command)
        recordingShortcutCommand = nil
        if let conflictTitle {
            shortcutRecordingMessage = L(
                "已设为 \(shortcut.displayTitle)，并从「\(conflictTitle)」移除同一个快捷键。",
                "Set to \(shortcut.displayTitle) and removed the same shortcut from \"\(conflictTitle)\"."
            )
        } else {
            shortcutRecordingMessage = L(
                "已设为 \(shortcut.displayTitle)。",
                "Set to \(shortcut.displayTitle)."
            )
        }
        return true
    }

    private func shortcutRecordingPrompt(for command: ConductorShellCommand) -> String {
        let title = command.displayTitle(model: model)
        return L(
            "正在为「\(title)」录制；如果按到已有快捷键，会自动让原命令让位。",
            "Recording \"\(title)\"; choosing an existing shortcut will move it from the old command."
        )
    }

    func themeSettings(snapshot: SettingsSnapshot) -> some View {
        let activeTheme = snapshot.theme
        return Form {
            Section(L("外观", "Appearance")) {
                Picker(
                    L("模式", "Mode"),
                    selection: terminalThemeBinding(current: activeTheme)
                ) {
                    ForEach(TerminalTheme.allCases) { theme in
                        Text(theme.title).tag(theme)
                    }
                }
                .pickerStyle(.segmented)

                LabeledContent(L("当前", "Current"), value: activeTheme.title)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }}

enum TerminalSettingsSection: String, CaseIterable, Identifiable, Hashable {
    case typography
    case display
    case selection
    case input

    var id: String { rawValue }

    var title: String {
        switch self {
        case .typography:
            L("字体", "Font")
        case .display:
            L("显示", "Display")
        case .selection:
            L("选择", "Select")
        case .input:
            L("输入", "Input")
        }
    }

    var subtitle: String {
        switch self {
        case .typography:
            L("字体族、字号、行高和自定义字体", "Font family, size, line height, and custom fonts")
        case .display:
            L("光标、背景、透明度和图像背景", "Cursor, background, opacity, and background images")
        case .selection:
            L("选择行为、鼠标、链接和滚动", "Selection behavior, mouse, links, and scrolling")
        case .input:
            L("剪贴板、粘贴安全和键盘输入", "Clipboard, paste safety, and keyboard input")
        }
    }

    var systemImage: String {
        switch self {
        case .typography:
            "textformat"
        case .display:
            "display"
        case .selection:
            "cursorarrow"
        case .input:
            "keyboard"
        }
    }
}

struct SettingsPaneHeading: View {
    let section: SettingsSectionID
    @Environment(\.conductorFontScale) private var fontScale

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(section.title)
                    .font(.conductorSystem(size: 16, weight: .semibold, scale: fontScale))
                    .foregroundStyle(ConductorDesign.primaryText)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }

            Text(section.subtitle)
                .font(.conductorSystem(size: 10.8, weight: .regular, scale: fontScale))
                .foregroundStyle(ConductorDesign.tertiaryText)
                .lineLimit(1)
        }
        .padding(.bottom, 4)
    }
}

struct SettingsContentPlaceholder: View {
    let section: SettingsSectionID

    var body: some View {
        ContentUnavailableView {
            Label(section.title, systemImage: section.systemImage)
        } description: {
            Text(L("正在载入", "Loading"))
        }
        .overlay(alignment: .topTrailing) {
            ProgressView()
                .controlSize(.small)
                .padding(12)
        }
            .accessibilityLabel(section.title)
    }
}

struct SettingsSectionLabel: View {
    let title: String
    let subtitle: String
    @Environment(\.conductorFontScale) private var fontScale

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.conductorSystem(size: 11, weight: .semibold, scale: fontScale))
                .foregroundStyle(ConductorDesign.secondaryText)
            Text(subtitle)
                .font(.conductorSystem(size: 10.2, weight: .regular, scale: fontScale))
                .foregroundStyle(ConductorDesign.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 4)
    }
}

struct AgentCLIStatusRow: View {
    let provider: AgentHookProvider
    let status: AgentCLIStatus
    let install: () -> Void
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorTheme) private var theme

    private var subtitle: String {
        switch status.state {
        case .unknown:
            return L("尚未检测，打开此页会自动扫描", "Not scanned yet; this page scans automatically")
        case .checking:
            return L("正在检测命令行工具是否可用", "Checking whether the CLI is available")
        case .installed(let path):
            return path
        case .missing:
            return provider.installHint
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            LabeledContent(provider.title) {
                trailing
            }

            Text(subtitle)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var trailing: some View {
        switch status.state {
        case .checking:
            ProgressView()
                .controlSize(.small)
                .frame(width: 112, alignment: .trailing)
        case .installed:
            agentStatusLabel(title: L("已安装", "Installed"), systemImage: "checkmark.circle.fill")
        case .missing:
            Button {
                install()
            } label: {
                Label(L("安装", "Install"), systemImage: "arrow.down.circle")
            }
            .font(.conductorSystem(size: 10.5, weight: .semibold, scale: fontScale))
        case .unknown:
            agentStatusLabel(title: L("未检测", "Not Checked"), systemImage: "questionmark.circle")
        }
    }

    private func agentStatusLabel(title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.conductorSystem(size: 10.5, weight: .semibold, scale: fontScale))
            .labelStyle(.titleAndIcon)
            .lineLimit(1)
            .foregroundStyle(theme.floatingEmphasis)
    }
}

struct NotificationPermissionStatusRow: View {
    let state: AgentReplyNotificationAuthorizationState
    let check: () -> Void
    let test: () -> Void
    @Environment(\.conductorFontScale) private var fontScale

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            LabeledContent(L("系统通知权限", "System Notification Permission")) {
                HStack(spacing: 8) {
                    permissionStatusLabel

                    ControlGroup {
                        Button {
                            test()
                        } label: {
                            Label(L("测试", "Test"), systemImage: "bell.badge")
                        }
                        .help(L("发送一条测试系统通知", "Send a test system notification"))

                        Button {
                            check()
                        } label: {
                            Label(L("检查", "Check"), systemImage: "checkmark.shield")
                        }
                        .help(L("检查通知权限", "Check Notification Permission"))
                    }
                    .font(.conductorSystem(size: 10.5, weight: .semibold, scale: fontScale))
                    .controlSize(.small)
                }
            }

            Text(subtitle)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var permissionStatusLabel: some View {
        Label(title, systemImage: systemImage)
            .font(.conductorSystem(size: 10.5, weight: .semibold, scale: fontScale))
            .foregroundStyle(statusColor)
            .labelStyle(.titleAndIcon)
            .lineLimit(1)
    }

    private var title: String {
        switch state {
        case .authorized:
            L("已允许", "Allowed")
        case .denied:
            L("已拒绝", "Denied")
        case .notDetermined:
            L("未请求", "Not Requested")
        case .unavailable:
            L("不可用", "Unavailable")
        case .unknown:
            L("未知", "Unknown")
        }
    }

    private var subtitle: String {
        switch state {
        case .authorized:
            L("系统横幅和声音可用", "System banners and sound are available")
        case .denied:
            L("系统横幅需要在系统设置里允许", "Enable system banners in System Settings")
        case .notDetermined:
            L("尚未请求权限；点击检查会向 macOS 申请", "Permission has not been requested; Check asks macOS")
        case .unavailable:
            L("当前启动方式无法使用系统横幅；从正式应用启动后再试", "System banners are unavailable in this launch mode; start the app normally and try again")
        case .unknown:
            L("暂时无法确认；点击检查会重新读取系统状态", "Could not confirm yet; Check reads system state again")
        }
    }

    private var systemImage: String {
        switch state {
        case .authorized:
            "checkmark.circle.fill"
        case .denied:
            "xmark.circle.fill"
        case .notDetermined:
            "questionmark.circle"
        case .unavailable:
            "exclamationmark.triangle"
        case .unknown:
            "circle.dotted"
        }
    }

    private var statusColor: Color {
        switch state {
        case .authorized:
            Color.green
        case .denied:
            Color.red
        case .notDetermined, .unavailable:
            Color.orange
        case .unknown:
            Color.secondary
        }
    }
}

private struct SettingsOverviewPath: View {
    let snapshot: SettingsSnapshot
    let action: (SettingsSectionID) -> Void
    @Environment(\.conductorTheme) private var theme

    private var terminalSizeText: String {
        let rounded = (snapshot.appearance.terminalFontSize * 10).rounded() / 10
        if rounded.rounded() == rounded {
            return "\(Int(rounded)) pt"
        }
        return String(format: "%.1f pt", Double(rounded))
    }

    private var rows: [SettingsOverviewRoute] {
        [
            SettingsOverviewRoute(
                section: .interface,
                detail: "\(snapshot.appearance.language.title) · \(snapshot.appearance.density.title)"),
            SettingsOverviewRoute(
                section: .terminal,
                detail: "\(snapshot.appearance.terminalRenderer.effectiveFontFamilyName) · \(terminalSizeText)"),
            SettingsOverviewRoute(
                section: .shell,
                detail: snapshot.appearance.terminalRenderer.proxy.enabled ? L("代理开启", "Proxy On") : L("代理关闭", "Proxy Off")),
            SettingsOverviewRoute(
                section: .usage,
                detail: L("本地记录", "Local Records")),
            SettingsOverviewRoute(
                section: .automation,
                detail: snapshot.appearance.agentReplyNotifications.enabled
                    ? L("回复通知开启", "Reply Alerts On")
                    : L("回复通知关闭", "Reply Alerts Off")),
            SettingsOverviewRoute(
                section: .updates,
                detail: snapshot.updateState.phase.statusTitle),
            SettingsOverviewRoute(
                section: .themes,
                detail: snapshot.theme.title),
        ]
    }

    var body: some View {
        ForEach(rows, id: \.section) { row in
            Button {
                action(row.section)
            } label: {
                LabeledContent {
                    HStack(spacing: 6) {
                        Text(row.detail)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    }
                } label: {
                    Label(row.section.title, systemImage: row.section.systemImage)
                }
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(row.section.title)
            .accessibilityValue(row.detail)
        }
    }
}

private struct SettingsOverviewRoute: Hashable {
    let section: SettingsSectionID
    let detail: String
}
