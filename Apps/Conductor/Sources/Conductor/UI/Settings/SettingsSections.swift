import ConductorCore
import AppKit
import CodexBar
import SwiftUI

private func L(_ zh: String, _ en: String) -> String {
    ConductorLocalization.text(zh: zh, en: en)
}


extension AppearanceSettingsPanel {
    func overviewSettings(snapshot: SettingsSnapshot) -> some View {
        LazyVStack(alignment: .leading, spacing: 16) {
            SettingsPreferenceGroup(
                title: L("当前状态", "Current State"),
                subtitle: L("主题、终端字体、密度和工作流开关", "Theme, terminal font, density, and workflow toggles"),
                systemImage: "rectangle.grid.2x2"
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    SettingsOverviewGrid(snapshot: snapshot)

                    VStack(spacing: 0) {
                        SettingsQuickJumpButton(
                            title: L("调整终端", "Tune Terminal"),
                            subtitle: snapshot.appearance.terminalRenderer.selectedFontStatusTitle,
                            systemImage: "terminal"
                        ) {
                            selectSection(.terminal)
                        }

                        SettingsControlDivider()

                        SettingsQuickJumpButton(
                            title: L("换主题", "Change Theme"),
                            subtitle: snapshot.theme.title,
                            systemImage: "swatchpalette"
                        ) {
                            selectSection(.themes)
                        }
                    }
                    .background(theme.floatingControlFill.opacity(0.24))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        }
    }

    func usageSettings(snapshot: SettingsSnapshot) -> some View {
        ConductorUsageSettingsContent(
            style: usagePanelStyle,
            languageIdentifier: snapshot.appearance.language.usageFeatureLanguageIdentifier)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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

    func interfaceSettings(snapshot: SettingsSnapshot) -> some View {
        let appearance = snapshot.appearance
        return LazyVStack(alignment: .leading, spacing: 16) {
            SettingsPreferenceGroup(
                title: L("外观控制", "Appearance Controls"),
                subtitle: L("像系统偏好设置一样直接调整，不用在卡片海里找选项", "Direct controls, tuned like a native settings inspector"),
                systemImage: "slider.horizontal.3"
            ) {
                SettingsFormSurface {
                    SettingsControlRow(
                        title: L("窗口密度", "Window Density"),
                        subtitle: appearance.density.subtitle,
                        systemImage: "rectangle.compress.vertical"
                    ) {
                        SettingsSegmentedPicker(
                            options: AppearanceDensity.allCases,
                            selection: appearance.density,
                            title: { $0.title }
                        ) { density in
                            model.performShellMotion(ConductorMotion.selection) {
                                model.setAppearanceDensity(density)
                            }
                        }
                    }

                    SettingsControlDivider()

                    SettingsControlRow(
                        title: L("浮层清晰度", "Layer Clarity"),
                        subtitle: appearance.chromeClarity.subtitle,
                        systemImage: "square.stack.3d.up"
                    ) {
                        SettingsSegmentedPicker(
                            options: ChromeClarity.allCases,
                            selection: appearance.chromeClarity,
                            title: { $0.title }
                        ) { clarity in
                            model.performShellMotion(ConductorMotion.selection) {
                                model.setChromeClarity(clarity)
                            }
                        }
                    }
                }
            }

            SettingsPreferenceGroup(
                title: L("文字", "Text"),
                subtitle: L("这些只影响应用壳层文字，不会触碰终端渲染", "Shell text only; terminal rendering stays separate"),
                systemImage: "textformat"
            ) {
                SettingsFormSurface {
                    SettingsControlRow(
                        title: L("语言", "Language"),
                        subtitle: appearance.language.subtitle,
                        systemImage: "character.bubble"
                    ) {
                        SettingsSegmentedPicker(
                            options: AppearanceLanguage.allCases,
                            selection: appearance.language,
                            title: { $0.title }
                        ) { language in
                            model.performShellMotion(ConductorMotion.selection) {
                                model.setLanguage(language)
                            }
                        }
                    }

                    SettingsControlDivider()

                    SettingsControlRow(
                        title: L("字体", "Font"),
                        subtitle: appearance.fontFamily.subtitle,
                        systemImage: appearance.fontFamily.systemImage
                    ) {
                        SettingsSegmentedPicker(
                            options: AppearanceFontFamily.allCases,
                            selection: appearance.fontFamily,
                            title: { $0.title }
                        ) { family in
                            model.performShellMotion(ConductorMotion.selection) {
                                model.setFontFamily(family)
                            }
                        }
                    }

                    SettingsControlDivider()

                    SettingsControlRow(
                        title: L("字号", "Font Size"),
                        subtitle: appearance.fontScale.subtitle,
                        systemImage: "textformat.size"
                    ) {
                        SettingsSegmentedPicker(
                            options: AppearanceFontScale.allCases,
                            selection: appearance.fontScale,
                            title: { $0.title }
                        ) { scale in
                            model.performShellMotion(ConductorMotion.selection) {
                                model.setFontScale(scale)
                            }
                        }
                    }
                }
            }

        }
    }

    func terminalSettingsDashboard(snapshot: SettingsSnapshot) -> some View {
        LazyVStack(alignment: .leading, spacing: 16) {
            terminalSettingsSectionRail(snapshot: snapshot)

            activeTerminalSettingsSection(snapshot: snapshot)
                .id(selectedTerminalSettingsSection)
                .transition(ConductorMotion.contentSwapTransition(edge: terminalContentEdge))
        }
        .animation(ConductorMotion.contentSwap, value: selectedTerminalSettingsSection)
    }

    func terminalSettingsSectionRail(snapshot: SettingsSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TerminalSettingsSectionRail(
                selection: selectedTerminalSettingsSection
            ) { section in
                selectTerminalSettingsSection(section)
            }

            SettingsSectionLabel(
                title: selectedTerminalSettingsSection.title,
                subtitle: selectedTerminalSettingsSection.subtitle
            )
        }
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
        terminalContentEdge = contentSwapEdge(
            from: selectedTerminalSettingsSection,
            to: section,
            in: TerminalSettingsSection.allCases
        )
        ConductorMotion.perform(ConductorMotion.contentSwap) {
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
                subtitle: L("命令完成通知和铃声是工作流反馈，不再散落在终端视觉设置里", "Command finish alerts and bell feedback belong with workflow feedback")
            )

            terminalNotificationSettings(snapshot: snapshot)
        }
    }

    @ViewBuilder
    func terminalShellSettings(snapshot: SettingsSnapshot) -> some View {
        let renderer = snapshot.appearance.terminalRenderer
        let commandOverride = renderer.ghosttyOverride(for: "initial-command")
        let directoryOverride = renderer.ghosttyOverride(for: "working-directory")
        let scrollbackOverride = renderer.ghosttyOverride(for: "scrollback-limit")

        SettingsPreferenceGroup(
            title: L("Shell 与启动", "Shell and Startup"),
            subtitle: L("启动命令、默认目录和滚屏历史，按终端用户真正会设置的方式呈现", "Startup command, default directory, and scrollback history presented as product settings"),
            systemImage: "terminal"
        ) {
            SettingsFormSurface {
                SettingsControlRow(
                    title: L("Shell 集成", "Shell Integration"),
                    subtitle: L("已启用 detect，并保留 no-cursor；这里不需要手动配置", "Enabled with detect and no-cursor; no manual setup needed"),
                    systemImage: "point.3.connected.trianglepath.dotted"
                ) {
                    SettingsStatusPill(title: L("自动管理", "Managed"), systemImage: "lock.fill")
                }

                SettingsControlDivider()

                SettingsControlRow(
                    title: L("启动命令", "Startup Command"),
                    subtitle: L("留空时打开默认登录 shell；适合进入 tmux、ssh 或固定开发环境", "Leave empty for the default login shell; useful for tmux, ssh, or a fixed dev environment"),
                    systemImage: "terminal"
                ) {
                    ShellCommandSettingControl(
                        value: commandOverride.normalizedValue,
                        setValue: { setGhosttyOverrideValue(key: "initial-command", value: $0) },
                        reset: { resetGhosttyOverride(key: "initial-command") }
                    )
                }

                SettingsControlDivider()

                SettingsControlRow(
                    title: L("默认工作目录", "Default Working Directory"),
                    subtitle: L("留空时继承工作区或新建终端时的目录", "Leave empty to inherit the workspace or new-terminal directory"),
                    systemImage: "folder"
                ) {
                    WorkingDirectorySettingControl(
                        value: directoryOverride.normalizedValue,
                        setValue: { setGhosttyOverrideValue(key: "working-directory", value: $0) },
                        reset: { resetGhosttyOverride(key: "working-directory") }
                    )
                }

                SettingsControlDivider()

                SettingsControlRow(
                    title: L("滚屏历史", "Scrollback History"),
                    subtitle: L("控制终端保留多少历史输出；越大越占内存", "Controls how much terminal history is retained; larger values use more memory"),
                    systemImage: "scroll"
                ) {
                    ScrollbackPresetPicker(
                        value: scrollbackOverride.normalizedValue,
                        setValue: { setGhosttyOverrideValue(key: "scrollback-limit", value: $0) },
                        reset: { resetGhosttyOverride(key: "scrollback-limit") }
                    )
                }
            }
        }
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

        return SettingsPreferenceGroup(
            title: L("背景与颜色", "Background and Colors"),
            subtitle: L("终端画布、背景图、选区和搜索高亮；整套主题仍在主题页管理", "Terminal canvas, background image, selection, and search highlight; full themes stay in Themes"),
            systemImage: "paintpalette"
        ) {
            SettingsFormSurface {
                SettingsSliderRow(
                    title: L("背景不透明度", "Background Opacity"),
                    subtitle: L("降低后可以透出窗口材质，100% 最清晰", "Lower values show the window material; 100% is clearest"),
                    systemImage: "circle.lefthalf.filled",
                    value: renderer.backgroundOpacity,
                    range: 0.35...1,
                    step: 0.01,
                    valueText: percentText(renderer.backgroundOpacity)
                ) { opacity in
                    model.setTerminalBackgroundOpacity(opacity)
                }

                SettingsControlDivider()

                SettingsControlRow(
                    title: L("背景模糊", "Background Blur"),
                    subtitle: L("透明背景下柔化后方内容，默认跟随内置策略", "Softens content behind transparent terminals; default follows the built-in policy"),
                    systemImage: "water.waves"
                ) {
                    GhosttyBooleanOverridePicker(
                        state: booleanState(for: blurOverride),
                        action: { setBooleanOverride(key: "background-blur", state: $0) }
                    )
                }

                SettingsControlDivider()

                SettingsControlRow(
                    title: L("背景图片", "Background Image"),
                    subtitle: L("选择一张图片作为终端背景，留空时使用主题背景", "Choose an image for the terminal background, or leave empty to use the theme"),
                    systemImage: "photo"
                ) {
                    GhosttyFileOverrideControl(
                        key: "background-image",
                        value: imageOverride.normalizedValue,
                        setValue: { setGhosttyOverrideValue(key: "background-image", value: $0) },
                        reset: { resetGhosttyOverride(key: "background-image") }
                    )
                }

                SettingsControlDivider()

                SettingsControlRow(
                    title: L("图片显示方式", "Image Fit"),
                    subtitle: L("控制背景图片如何填充终端区域", "Controls how the background image fills the terminal area"),
                    systemImage: "rectangle.resize"
                ) {
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

                SettingsControlDivider()

                SettingsControlRow(
                    title: L("图片透明度", "Image Opacity"),
                    subtitle: L("让背景图片更轻，避免干扰终端文字", "Makes the image quieter so terminal text stays readable"),
                    systemImage: "slider.horizontal.3"
                ) {
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

                SettingsControlDivider()

                SettingsControlRow(
                    title: L("选区文字", "Selection Text"),
                    subtitle: L("选中内容时的文字颜色，默认跟随主题", "Text color for selected content; defaults to the theme"),
                    systemImage: "text.cursor"
                ) {
                    GhosttyColorOverrideControl(
                        key: "selection-foreground",
                        value: selectionForegroundOverride.normalizedValue,
                        setValue: { setGhosttyOverrideValue(key: "selection-foreground", value: $0) },
                        reset: { resetGhosttyOverride(key: "selection-foreground") }
                    )
                }

                SettingsControlDivider()

                SettingsControlRow(
                    title: L("选区背景", "Selection Background"),
                    subtitle: L("拖选文本时的高亮颜色", "Highlight color used while selecting text"),
                    systemImage: "selection.pin.in.out"
                ) {
                    GhosttyColorOverrideControl(
                        key: "selection-background",
                        value: selectionBackgroundOverride.normalizedValue,
                        setValue: { setGhosttyOverrideValue(key: "selection-background", value: $0) },
                        reset: { resetGhosttyOverride(key: "selection-background") }
                    )
                }

                SettingsControlDivider()

                SettingsControlRow(
                    title: L("搜索高亮", "Search Highlight"),
                    subtitle: L("搜索命中结果的背景色", "Background color for search matches"),
                    systemImage: "magnifyingglass"
                ) {
                    GhosttyColorOverrideControl(
                        key: "search-background",
                        value: searchBackgroundOverride.normalizedValue,
                        setValue: { setGhosttyOverrideValue(key: "search-background", value: $0) },
                        reset: { resetGhosttyOverride(key: "search-background") }
                    )
                }
            }
        }
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

        return SettingsPreferenceGroup(
            title: L("选择、鼠标与链接", "Selection, Mouse, and Links"),
            subtitle: L("日常复制、鼠标交互和链接识别，不展示底层配置细节", "Daily copy, mouse interaction, and link detection without raw config details"),
            systemImage: "cursorarrow.click"
        ) {
            SettingsFormSurface {
                SettingsControlRow(
                    title: L("输入时清除选区", "Clear Selection While Typing"),
                    subtitle: L("开始输入后自动取消当前选区", "Automatically clears the current selection when typing starts"),
                    systemImage: "keyboard"
                ) {
                    GhosttyBooleanOverridePicker(
                        state: booleanState(for: clearTypingOverride),
                        action: { setBooleanOverride(key: "selection-clear-on-typing", state: $0) }
                    )
                }

                SettingsControlDivider()

                SettingsControlRow(
                    title: L("复制后清除选区", "Clear Selection After Copy"),
                    subtitle: L("复制完成后收起高亮，适合连续操作", "Clears the highlight after copying"),
                    systemImage: "doc.on.doc"
                ) {
                    GhosttyBooleanOverridePicker(
                        state: booleanState(for: clearCopyOverride),
                        action: { setBooleanOverride(key: "selection-clear-on-copy", state: $0) }
                    )
                }

                SettingsControlDivider()

                SettingsControlRow(
                    title: L("选中即复制", "Copy On Select"),
                    subtitle: L("像 X11 终端一样，选中文本后立即写入剪贴板", "Copies selected text immediately, similar to X11 terminals"),
                    systemImage: "doc.on.clipboard"
                ) {
                    GhosttyBooleanOverridePicker(
                        state: booleanState(for: copyOverride),
                        action: { setBooleanOverride(key: "copy-on-select", state: $0) }
                    )
                }

                SettingsControlDivider()

                SettingsControlRow(
                    title: L("输入时隐藏鼠标", "Hide Mouse While Typing"),
                    subtitle: L("减少鼠标指针挡住终端文本的情况", "Keeps the pointer from covering terminal text while typing"),
                    systemImage: "cursorarrow.slash"
                ) {
                    GhosttyBooleanOverridePicker(
                        state: booleanState(for: hideMouseOverride),
                        action: { setBooleanOverride(key: "mouse-hide-while-typing", state: $0) }
                    )
                }

                SettingsControlDivider()

                SettingsControlRow(
                    title: L("应用鼠标上报", "App Mouse Reporting"),
                    subtitle: L("允许 vim、tmux、less 等终端应用接收鼠标事件", "Lets terminal apps such as vim, tmux, and less receive mouse events"),
                    systemImage: "point.topleft.down.curvedto.point.bottomright.up"
                ) {
                    GhosttyBooleanOverridePicker(
                        state: booleanState(for: reportingOverride),
                        action: { setBooleanOverride(key: "mouse-reporting", state: $0) }
                    )
                }

                SettingsControlDivider()

                SettingsControlRow(
                    title: L("滚轮速度", "Scroll Speed"),
                    subtitle: L("调整鼠标或触控板滚动终端历史的速度", "Adjusts mouse or trackpad scroll speed through terminal history"),
                    systemImage: "scroll"
                ) {
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

                SettingsControlDivider()

                SettingsControlRow(
                    title: L("链接识别", "Link Detection"),
                    subtitle: L("识别终端输出里的 URL，方便点击打开", "Detects URLs in terminal output so they can be opened"),
                    systemImage: "link"
                ) {
                    GhosttyBooleanOverridePicker(
                        state: booleanState(for: linkOverride),
                        action: { setBooleanOverride(key: "link-url", state: $0) }
                    )
                }

                SettingsControlDivider()

                SettingsControlRow(
                    title: L("链接预览", "Link Previews"),
                    subtitle: L("悬停链接时显示预览能力，默认跟随内置支持", "Shows link preview behavior on hover when supported"),
                    systemImage: "rectangle.on.rectangle"
                ) {
                    GhosttyBooleanOverridePicker(
                        state: booleanState(for: previewOverride),
                        action: { setBooleanOverride(key: "link-previews", state: $0) }
                    )
                }
            }
        }
    }

    func terminalClipboardSettings(snapshot: SettingsSnapshot) -> some View {
        let renderer = snapshot.appearance.terminalRenderer
        let readOverride = renderer.ghosttyOverride(for: "clipboard-read")
        let writeOverride = renderer.ghosttyOverride(for: "clipboard-write")
        let trimOverride = renderer.ghosttyOverride(for: "clipboard-trim-trailing-spaces")
        let protectionOverride = renderer.ghosttyOverride(for: "clipboard-paste-protection")
        let bracketedOverride = renderer.ghosttyOverride(for: "clipboard-paste-bracketed-safe")

        return SettingsPreferenceGroup(
            title: L("剪贴板与粘贴安全", "Clipboard and Paste Safety"),
            subtitle: L("把安全相关行为说成人话：读写、清理空格、粘贴保护", "Human-facing controls for clipboard access, trimming, and paste protection"),
            systemImage: "doc.on.clipboard"
        ) {
            SettingsFormSurface {
                SettingsControlRow(
                    title: L("允许读取剪贴板", "Allow Clipboard Read"),
                    subtitle: L("终端应用可以从系统剪贴板读取内容", "Terminal apps may read from the system clipboard"),
                    systemImage: "arrow.down.doc"
                ) {
                    GhosttyBooleanOverridePicker(
                        state: booleanState(for: readOverride),
                        action: { setBooleanOverride(key: "clipboard-read", state: $0) }
                    )
                }

                SettingsControlDivider()

                SettingsControlRow(
                    title: L("允许写入剪贴板", "Allow Clipboard Write"),
                    subtitle: L("终端应用可以把内容写入系统剪贴板", "Terminal apps may write to the system clipboard"),
                    systemImage: "arrow.up.doc"
                ) {
                    GhosttyBooleanOverridePicker(
                        state: booleanState(for: writeOverride),
                        action: { setBooleanOverride(key: "clipboard-write", state: $0) }
                    )
                }

                SettingsControlDivider()

                SettingsControlRow(
                    title: L("复制时清理尾随空格", "Trim Trailing Spaces"),
                    subtitle: L("复制多行输出时去掉行尾多余空格", "Removes extra spaces at line endings when copying output"),
                    systemImage: "text.alignleft"
                ) {
                    GhosttyBooleanOverridePicker(
                        state: booleanState(for: trimOverride),
                        action: { setBooleanOverride(key: "clipboard-trim-trailing-spaces", state: $0) }
                    )
                }

                SettingsControlDivider()

                SettingsControlRow(
                    title: L("危险粘贴保护", "Paste Protection"),
                    subtitle: L("粘贴疑似多行命令或危险内容时保留确认保护", "Keeps confirmation protection for suspicious multi-line or risky pastes"),
                    systemImage: "exclamationmark.shield"
                ) {
                    GhosttyBooleanOverridePicker(
                        state: booleanState(for: protectionOverride),
                        action: { setBooleanOverride(key: "clipboard-paste-protection", state: $0) }
                    )
                }

                SettingsControlDivider()

                SettingsControlRow(
                    title: L("Bracketed Paste 安全模式", "Bracketed Paste Safety"),
                    subtitle: L("让支持的 shell 和编辑器更准确地区分键入与粘贴", "Helps supported shells and editors distinguish typed input from pasted text"),
                    systemImage: "brackets.curly"
                ) {
                    GhosttyBooleanOverridePicker(
                        state: booleanState(for: bracketedOverride),
                        action: { setBooleanOverride(key: "clipboard-paste-bracketed-safe", state: $0) }
                    )
                }
            }
        }
    }

    func terminalNotificationSettings(snapshot: SettingsSnapshot) -> some View {
        let renderer = snapshot.appearance.terminalRenderer
        let finishOverride = renderer.ghosttyOverride(for: "notify-on-command-finish")
        let actionOverride = renderer.ghosttyOverride(for: "notify-on-command-finish-action")
        let afterOverride = renderer.ghosttyOverride(for: "notify-on-command-finish-after")
        let bellPathOverride = renderer.ghosttyOverride(for: "bell-audio-path")
        let bellVolumeOverride = renderer.ghosttyOverride(for: "bell-audio-volume")

        return SettingsPreferenceGroup(
            title: L("通知与铃声", "Notifications and Bell"),
            subtitle: L("命令结束提醒和终端铃声；AI Agent 通知仍在 AI 页管理", "Command-finish alerts and terminal bell; AI agent notifications stay in AI"),
            systemImage: "bell.badge"
        ) {
            SettingsFormSurface {
                SettingsControlRow(
                    title: L("命令完成通知", "Command Finish Notification"),
                    subtitle: L("长命令结束后提醒你回来处理", "Alerts you when a long-running command finishes"),
                    systemImage: "checkmark.circle"
                ) {
                    GhosttyBooleanOverridePicker(
                        state: booleanState(for: finishOverride),
                        action: { setBooleanOverride(key: "notify-on-command-finish", state: $0) }
                    )
                }

                SettingsControlDivider()

                SettingsControlRow(
                    title: L("通知方式", "Notification Action"),
                    subtitle: L("选择只发系统通知，还是同时吸引注意", "Choose whether to only notify or also request attention"),
                    systemImage: "app.badge"
                ) {
                    GhosttyPresetOverrideMenu(
                        value: actionOverride.normalizedValue,
                        options: [
                            GhosttyPresetOption(title: L("系统通知", "Notification"), value: "notify"),
                            GhosttyPresetOption(title: L("请求注意", "Request Attention"), value: "attention"),
                            GhosttyPresetOption(title: L("通知并请求注意", "Notify and Attention"), value: "notify,attention")
                        ],
                        setValue: { setGhosttyOverrideValue(key: "notify-on-command-finish-action", value: $0) },
                        reset: { resetGhosttyOverride(key: "notify-on-command-finish-action") }
                    )
                }

                SettingsControlDivider()

                SettingsControlRow(
                    title: L("超过多久提醒", "Notify After"),
                    subtitle: L("只有运行时间超过这个阈值的命令才提醒", "Only commands longer than this threshold will alert"),
                    systemImage: "timer"
                ) {
                    GhosttyPresetOverrideMenu(
                        value: afterOverride.normalizedValue,
                        options: [
                            GhosttyPresetOption(title: L("5 秒", "5 seconds"), value: "5s"),
                            GhosttyPresetOption(title: L("10 秒", "10 seconds"), value: "10s"),
                            GhosttyPresetOption(title: L("30 秒", "30 seconds"), value: "30s"),
                            GhosttyPresetOption(title: L("1 分钟", "1 minute"), value: "1m")
                        ],
                        setValue: { setGhosttyOverrideValue(key: "notify-on-command-finish-after", value: $0) },
                        reset: { resetGhosttyOverride(key: "notify-on-command-finish-after") }
                    )
                }

                SettingsControlDivider()

                SettingsControlRow(
                    title: L("铃声音频", "Bell Sound"),
                    subtitle: L("选择自定义铃声文件，留空时使用默认反馈", "Choose a custom bell sound file, or leave empty for the default feedback"),
                    systemImage: "speaker.wave.2"
                ) {
                    GhosttyFileOverrideControl(
                        key: "bell-audio-path",
                        value: bellPathOverride.normalizedValue,
                        setValue: { setGhosttyOverrideValue(key: "bell-audio-path", value: $0) },
                        reset: { resetGhosttyOverride(key: "bell-audio-path") }
                    )
                }

                SettingsControlDivider()

                SettingsControlRow(
                    title: L("铃声音量", "Bell Volume"),
                    subtitle: L("调低可以保留提示但不打断工作", "Lower volume keeps feedback without interrupting work"),
                    systemImage: "speaker.wave.1"
                ) {
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
            }
        }
    }

    func terminalKeyboardSettings(snapshot: SettingsSnapshot) -> some View {
        let renderer = snapshot.appearance.terminalRenderer
        let optionOverride = renderer.ghosttyOverride(for: "macos-option-as-alt")
        let remapOverride = renderer.ghosttyOverride(for: "key-remap")

        return SettingsPreferenceGroup(
            title: L("键盘", "Keyboard"),
            subtitle: L("这里放终端输入层设置；应用级快捷键仍在命令页管理", "Terminal input settings live here; app shortcuts stay in Commands"),
            systemImage: "keyboard"
        ) {
            SettingsFormSurface {
                SettingsControlRow(
                    title: L("Option 作为 Alt", "Option As Alt"),
                    subtitle: L("给 vim、emacs、tmux 等终端程序发送 Alt/Meta 组合键", "Sends Alt/Meta key combinations to terminal apps such as vim, emacs, and tmux"),
                    systemImage: "option"
                ) {
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

                SettingsControlDivider()

                SettingsControlRow(
                    title: L("高级键位映射", "Advanced Key Remap"),
                    subtitle: L("只在需要兼容特殊终端工作流时填写；常用快捷键请去命令页", "Use only for special terminal workflows; common shortcuts belong in Commands"),
                    systemImage: "keyboard.badge.ellipsis"
                ) {
                    GhosttyInlineTextOverrideControl(
                        key: "key-remap",
                        placeholder: "ctrl+a=home",
                        value: remapOverride.normalizedValue,
                        systemImage: "keyboard",
                        setValue: { setGhosttyOverrideValue(key: "key-remap", value: $0) },
                        reset: { resetGhosttyOverride(key: "key-remap") }
                    )
                }
            }
        }
    }

    func terminalTypographySettings(snapshot: SettingsSnapshot) -> some View {
        let appearance = snapshot.appearance
        let renderer = appearance.terminalRenderer
        let downloadStates = snapshot.terminalFontDownloadStates
        return VStack(alignment: .leading, spacing: 16) {
            TerminalRendererSummary(appearance: appearance)

            SettingsPreferenceGroup(
                title: L("字体与字格", "Typography"),
                subtitle: L("管理终端实际使用的字体、字号、行高和字格密度", "Controls the terminal font, size, line height, and cell density"),
                systemImage: "textformat.size"
            ) {
                SettingsFormSurface {
                    SettingsControlRow(
                        title: L("终端字体", "Terminal Font"),
                        subtitle: renderer.selectedFontStatusTitle,
                        systemImage: "textformat"
                    ) {
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
                                .font(.conductorSystem(size: 10.5, weight: .semibold, scale: fontScale))
                                .disabled(downloadStates[selectedChoice.preset]?.isDownloading == true)
                            }
                        }
                    }

                    SettingsControlDivider()

                    SettingsControlRow(
                        title: L("自定义字体", "Custom Font"),
                        subtitle: customTerminalFontSubtitle(for: appearance),
                        systemImage: "square.and.arrow.down"
                    ) {
                        HStack(spacing: 8) {
                            Toggle("", isOn: Binding(
                                get: { renderer.useCustomFont },
                                set: { model.setTerminalUseCustomFont($0) }
                            ))
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .disabled(renderer.customFontFamilyName == nil)

                            Button(L("导入", "Import")) {
                                model.importTerminalFont()
                            }
                        }
                    }

                    SettingsControlDivider()

                    SettingsSliderRow(
                        title: L("终端字号", "Terminal Font Size"),
                        subtitle: L("调大更清晰，调小能显示更多行列", "Larger is easier to read; smaller fits more rows and columns"),
                        systemImage: "textformat.size",
                        value: appearance.terminalFontSize,
                        range: AppearancePreferences.minTerminalFontSize...AppearancePreferences.maxTerminalFontSize,
                        step: 0.5,
                        valueText: terminalFontSizeText(appearance.terminalFontSize)
                    ) { fontSize in
                        model.setTerminalFontSize(fontSize)
                    }

                    SettingsControlDivider()

                    SettingsSliderRow(
                        title: L("行高", "Line Height"),
                        subtitle: L("让输出更紧凑或更舒展", "Makes terminal output tighter or more relaxed"),
                        systemImage: "arrow.up.and.down.text.horizontal",
                        value: renderer.lineHeight,
                        range: 0.80...1.50,
                        step: 0.01,
                        valueText: multiplierText(renderer.lineHeight)
                    ) { lineHeight in
                        model.setTerminalLineHeight(lineHeight)
                    }
                }
            }
        }
    }

    func terminalCursorSettings(snapshot: SettingsSnapshot) -> some View {
        let renderer = snapshot.appearance.terminalRenderer
        let colorOverride = renderer.ghosttyOverride(for: "cursor-color")
        let opacityOverride = renderer.ghosttyOverride(for: "cursor-opacity")
        let textOverride = renderer.ghosttyOverride(for: "cursor-text")
        let clickOverride = renderer.ghosttyOverride(for: "cursor-click-to-move")

        return SettingsPreferenceGroup(
            title: L("光标", "Cursor"),
            subtitle: L("光标形状、颜色、闪烁和点击移动，都是日常输入会感知到的项", "Cursor shape, color, blink, and click-to-move are visible during daily typing"),
            systemImage: "cursorarrow"
        ) {
            SettingsFormSurface {
                SettingsControlRow(
                    title: L("光标样式", "Cursor Style"),
                    subtitle: L("选择块、空心块、竖线或下划线光标", "Choose block, hollow block, bar, or underline"),
                    systemImage: "cursorarrow"
                    ) {
                        SettingsSegmentedPicker(
                            options: TerminalCursorStyle.allCases,
                            selection: renderer.cursorStyle,
                            title: { $0.title }
                        ) { style in
                            model.setTerminalCursorStyle(style)
                    }
                }

                SettingsControlDivider()

                SettingsToggleRow(
                    title: L("光标闪烁", "Cursor Blink"),
                    subtitle: L("关闭后光标保持常亮，适合减少视觉干扰", "Keeps the cursor steady when disabled"),
                    systemImage: "cursorarrow.motionlines",
                    isOn: Binding(
                        get: { renderer.cursorBlink },
                        set: { model.setTerminalCursorBlink($0) }
                    )
                )

                SettingsControlDivider()

                SettingsControlRow(
                    title: L("光标颜色", "Cursor Color"),
                    subtitle: L("默认跟随主题，也可以指定一个固定颜色", "Follows the theme by default, or use a fixed color"),
                    systemImage: "paintpalette"
                ) {
                    GhosttyColorOverrideControl(
                        key: "cursor-color",
                        value: colorOverride.normalizedValue,
                        setValue: { setGhosttyOverrideValue(key: "cursor-color", value: $0) },
                        reset: { resetGhosttyOverride(key: "cursor-color") }
                    )
                }

                SettingsControlDivider()

                SettingsControlRow(
                    title: L("光标透明度", "Cursor Opacity"),
                    subtitle: L("降低后光标更轻，保持 100% 最醒目", "Lower values make the cursor quieter; 100% is most visible"),
                    systemImage: "slider.horizontal.3"
                ) {
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

                SettingsControlDivider()

                SettingsControlRow(
                    title: L("光标内文字颜色", "Cursor Text Color"),
                    subtitle: L("光标覆盖字符时使用的文字颜色", "Text color used when the cursor covers a character"),
                    systemImage: "character.cursor.ibeam"
                ) {
                    GhosttyColorOverrideControl(
                        key: "cursor-text",
                        value: textOverride.normalizedValue,
                        setValue: { setGhosttyOverrideValue(key: "cursor-text", value: $0) },
                        reset: { resetGhosttyOverride(key: "cursor-text") }
                    )
                }

                SettingsControlDivider()

                SettingsControlRow(
                    title: L("点击移动光标", "Click To Move Cursor"),
                    subtitle: L("允许鼠标点击把光标移动到目标位置", "Allows mouse clicks to move the cursor position"),
                    systemImage: "cursorarrow.click"
                ) {
                    GhosttyBooleanOverridePicker(
                        state: booleanState(for: clickOverride),
                        action: { setBooleanOverride(key: "cursor-click-to-move", state: $0) }
                    )
                }
            }
        }
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
        return VStack(alignment: .leading, spacing: 16) {
            SettingsPreferenceGroup(
                title: L("终端代理", "Terminal Proxy"),
                subtitle: proxy.statusTitle,
                systemImage: "network"
            ) {
                SettingsFormSurface {
                    SettingsToggleRow(
                        title: L("启用代理", "Enable Proxy"),
                        subtitle: L("写入新终端进程的 HTTP(S)/ALL_PROXY 环境变量", "Writes HTTP(S)/ALL_PROXY env vars for new terminal processes"),
                        systemImage: "switch.2",
                        isOn: Binding(
                            get: { proxy.enabled },
                            set: { model.setTerminalProxyEnabled($0) }
                        )
                    )

                    SettingsControlDivider()

                    SettingsTextFieldRow(
                        title: "HTTP_PROXY",
                        subtitle: "http://127.0.0.1:7890",
                        systemImage: "globe",
                        text: Binding(
                            get: { proxy.httpProxy },
                            set: { model.setTerminalProxyHTTP($0) }
                        )
                    )

                    SettingsControlDivider()

                    SettingsTextFieldRow(
                        title: "HTTPS_PROXY",
                        subtitle: "http://127.0.0.1:7890",
                        systemImage: "lock.globe",
                        text: Binding(
                            get: { proxy.httpsProxy },
                            set: { model.setTerminalProxyHTTPS($0) }
                        )
                    )

                    SettingsControlDivider()

                    SettingsTextFieldRow(
                        title: "ALL_PROXY",
                        subtitle: "socks5://127.0.0.1:7890",
                        systemImage: "point.3.connected.trianglepath.dotted",
                        text: Binding(
                            get: { proxy.allProxy },
                            set: { model.setTerminalProxyAll($0) }
                        )
                    )

                    SettingsControlDivider()

                    SettingsTextFieldRow(
                        title: "NO_PROXY",
                        subtitle: "localhost,127.0.0.1,::1",
                        systemImage: "nosign",
                        text: Binding(
                            get: { proxy.noProxy },
                            set: { model.setTerminalProxyNoProxy($0) }
                        )
                    )
                }
            }
        }
    }

    func aiSettings(snapshot: SettingsSnapshot) -> some View {
        let appearance = snapshot.appearance
        let agentCLIStatuses = snapshot.agentCLIStatuses
        return VStack(alignment: .leading, spacing: 16) {
            SettingsPreferenceGroup(
                title: L("AI 安装检测", "AI Installation Check"),
                subtitle: L("检测本机可用的 AI CLI，并给未安装的代理提供官方安装入口", "Detects local AI CLIs and provides official install pages for missing agents"),
                systemImage: "magnifyingglass"
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    SettingsFormSurface {
                        ForEach(AgentHookProvider.allCases) { provider in
                            AgentCLIStatusRow(
                                provider: provider,
                                status: agentCLIStatuses[provider] ?? .unknown(provider: provider),
                                install: { model.openAgentInstallPage(provider) }
                            )

                            if provider.id != AgentHookProvider.allCases.last?.id {
                                SettingsControlDivider()
                            }
                        }
                    }

                    HStack {
                        Text(L("检测 PATH、/opt/homebrew/bin 和 /usr/local/bin；安装后点重新检测。", "Scans PATH, /opt/homebrew/bin, and /usr/local/bin; scan again after installing."))
                            .font(.conductorSystem(size: 10.3, weight: .medium, scale: fontScale))
                            .foregroundStyle(ConductorDesign.tertiaryText)
                            .fixedSize(horizontal: false, vertical: true)

                        Spacer(minLength: 12)

                        Button {
                            model.refreshAgentCLIStatuses()
                        } label: {
                            Label(L("重新检测", "Scan Again"), systemImage: "arrow.clockwise")
                        }
                    }
                }
            }

            SettingsPreferenceGroup(
                title: L("Agent 通知", "Agent Notifications"),
                subtitle: L("Codex、Claude Code 等本地 agent hook", "Local agent hooks for Codex, Claude Code, and others"),
                systemImage: "bell.badge"
            ) {
                SettingsFormSurface {
                    ForEach(AgentHookProvider.allCases) { provider in
                        SettingsToggleRow(
                            title: provider.title,
                            subtitle: appearance.agentNotifications.isEnabled(for: provider) ? L("通知桥接已开启", "Notification bridge enabled") : L("不会安装或触发通知桥接", "Notification bridge disabled"),
                            systemImage: provider.systemImage,
                            isOn: Binding(
                                get: { appearance.agentNotifications.isEnabled(for: provider) },
                                set: { enabled in
                                    model.performShellMotion(ConductorMotion.selection) {
                                        model.setAgentNotificationsEnabled(enabled, for: provider)
                                    }
                                }
                            )
                        )

                        if provider.id != AgentHookProvider.allCases.last?.id {
                            SettingsControlDivider()
                        }
                    }
                }
                if let message = snapshot.agentHookSettingsMessage {
                    Text(message)
                        .font(.conductorSystem(size: 10.5, weight: .medium, scale: appearance.fontScale))
                        .foregroundStyle(ConductorDesign.tertiaryText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .onAppear {
            if agentCLIStatuses.values.allSatisfy({ $0.state == .unknown }) {
                model.refreshAgentCLIStatuses()
            }
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

    func commandSettings() -> some View {
        LazyVStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "keyboard")
                    .font(.conductorSystem(size: 10, weight: .semibold, scale: fontScale))
                    .foregroundStyle(ConductorDesign.secondaryText)
                    .accessibilityHidden(true)
                Text(L("命令与快捷键", "Commands and Shortcuts"))
                    .font(.conductorSystem(size: 12, weight: .semibold, scale: fontScale))
                    .foregroundStyle(ConductorDesign.primaryText)
                Spacer(minLength: 0)
            }

            CommandShortcutGuide(rows: commandShortcutRows(), height: 320, style: .plain)
        }
    }

    func themeSettings(snapshot: SettingsSnapshot) -> some View {
        let activeTheme = snapshot.theme
        return LazyVStack(alignment: .leading, spacing: 16) {
            SettingsPreferenceGroup(
                title: L("当前主题", "Current Theme"),
                subtitle: L("主题会同时影响窗口、终端和强调色", "Themes affect the window, terminal, and accent colors together"),
                systemImage: "swatchpalette"
            ) {
                SelectedThemeShowcase(theme: activeTheme)
            }

            SettingsPreferenceGroup(
                title: L("选择主题", "Choose Theme"),
                subtitle: L("选择后立即应用到当前窗口", "Selection applies immediately to the current window"),
                systemImage: "list.bullet"
            ) {
                SettingsFormSurface {
                    ForEach(TerminalTheme.allCases) { theme in
                        ThemeOptionRow(
                            theme: theme,
                            selected: activeTheme == theme
                        ) {
                            model.performShellMotion(ConductorMotion.selection) {
                                model.theme = theme
                            }
                        }

                        if theme.id != TerminalTheme.allCases.last?.id {
                            SettingsControlDivider()
                        }
                    }
                }
            }
        }
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
struct TerminalSettingsSectionRail: View {
    let selection: TerminalSettingsSection
    let action: (TerminalSettingsSection) -> Void
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorTheme) private var theme

    var body: some View {
        HStack(spacing: 4) {
            ForEach(TerminalSettingsSection.allCases) { section in
                Button {
                    guard section != selection else { return }
                    action(section)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: section.systemImage)
                            .font(.conductorSystem(size: 10.5, weight: .semibold, scale: fontScale))
                            .frame(width: 13)
                            .accessibilityHidden(true)
                        Text(section.title)
                            .font(.conductorSystem(size: 10.8, weight: section == selection ? .semibold : .medium, scale: fontScale))
                            .lineLimit(1)
                    }
                    .foregroundStyle(section == selection ? ConductorDesign.primaryText : ConductorDesign.secondaryText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 30)
                    .background(section == selection ? theme.floatingSelectedFill : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(theme.floatingControlFill.opacity(0.26))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(theme.floatingStroke.opacity(0.42), lineWidth: 0.8)
        }
    }
}

struct SettingsSidebarSummary: View {
    let theme: TerminalTheme
    let appearance: AppearancePreferences
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorTheme) private var activeTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "gearshape")
                    .font(.conductorSystem(size: 11, weight: .semibold, scale: fontScale))
                    .foregroundStyle(activeTheme.floatingEmphasis)
                    .frame(width: 16)
                    .accessibilityHidden(true)

                Text(L("设置", "Settings"))
                    .font(.conductorSystem(size: 12.4, weight: .bold, scale: fontScale))
                    .foregroundStyle(ConductorDesign.primaryText)
                    .lineLimit(1)
            }

            Text("\(theme.title) · \(appearance.density.title) · \(appearance.fontScale.title)")
                .font(.conductorSystem(size: 10.2, weight: .medium, scale: fontScale))
                .foregroundStyle(ConductorDesign.tertiaryText)
                .lineLimit(1)
        }
        .padding(.horizontal, 7)
        .padding(.bottom, 2)
    }
}

struct SettingsPaneHeading: View {
    let section: SettingsSectionID
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorTheme) private var theme

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Image(systemName: section.systemImage)
                        .font(.conductorSystem(size: 12, weight: .semibold, scale: fontScale))
                        .foregroundStyle(theme.floatingEmphasis)
                        .frame(width: 15)
                        .accessibilityHidden(true)

                    Text(section.title)
                        .font(.conductorSystem(size: 18, weight: .bold, scale: fontScale))
                        .foregroundStyle(ConductorDesign.primaryText)
                        .lineLimit(1)
                }
                Text(section.subtitle)
                    .font(.conductorSystem(size: 11.2, weight: .medium, scale: fontScale))
                    .foregroundStyle(ConductorDesign.tertiaryText)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(.bottom, 2)
    }
}

struct SettingsSectionLabel: View {
    let title: String
    let subtitle: String
    @Environment(\.conductorFontScale) private var fontScale

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.conductorSystem(size: 11.5, weight: .bold, scale: fontScale))
                .foregroundStyle(ConductorDesign.secondaryText)
                .textCase(.uppercase)
            Text(subtitle)
                .font(.conductorSystem(size: 10.4, weight: .medium, scale: fontScale))
                .foregroundStyle(ConductorDesign.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 2)
    }
}

struct SettingsInfoRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorTheme) private var theme

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.conductorSystem(size: 11, weight: .semibold, scale: fontScale))
                .foregroundStyle(theme.floatingEmphasis.opacity(0.88))
                .frame(width: 18)
                .accessibilityHidden(true)

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

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 52)
    }
}

struct AgentCLIStatusRow: View {
    let provider: AgentHookProvider
    let status: AgentCLIStatus
    let install: () -> Void
    @Environment(\.conductorFontScale) private var fontScale

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
        SettingsControlRow(
            title: provider.title,
            subtitle: subtitle,
            systemImage: provider.systemImage
        ) {
            trailing
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
            SettingsStatusPill(title: L("已安装", "Installed"), systemImage: "checkmark.circle.fill")
        case .missing:
            Button {
                install()
            } label: {
                Label(L("安装", "Install"), systemImage: "arrow.down.circle")
            }
            .font(.conductorSystem(size: 10.5, weight: .semibold, scale: fontScale))
        case .unknown:
            SettingsStatusPill(title: L("未检测", "Not Checked"), systemImage: "questionmark.circle")
        }
    }
}

struct SettingsOverviewGrid: View {
    let snapshot: SettingsSnapshot
    @Environment(\.conductorFontScale) private var fontScale

    private var terminalSizeText: String {
        let rounded = (snapshot.appearance.terminalFontSize * 10).rounded() / 10
        if rounded.rounded() == rounded {
            return "\(Int(rounded)) pt"
        }
        return String(format: "%.1f pt", Double(rounded))
    }

    var body: some View {
        SettingsFormSurface {
            SettingsOverviewTile(
                title: L("主题", "Theme"),
                value: snapshot.theme.title,
                systemImage: "swatchpalette"
            )
            SettingsControlDivider()
            SettingsOverviewTile(
                title: L("终端字体", "Terminal Font"),
                value: snapshot.appearance.terminalRenderer.effectiveFontFamilyName,
                systemImage: "textformat"
            )
            SettingsControlDivider()
            SettingsOverviewTile(
                title: L("字号", "Size"),
                value: terminalSizeText,
                systemImage: "textformat.size"
            )
            SettingsControlDivider()
            SettingsOverviewTile(
                title: L("密度", "Density"),
                value: snapshot.appearance.density.title,
                systemImage: "rectangle.compress.vertical"
            )
            SettingsControlDivider()
            SettingsOverviewTile(
                title: L("代理", "Proxy"),
                value: snapshot.appearance.terminalRenderer.proxy.enabled ? L("开启", "On") : L("关闭", "Off"),
                systemImage: "network"
            )
            SettingsControlDivider()
            SettingsOverviewTile(
                title: L("AI 通知", "AI Alerts"),
                value: snapshot.appearance.agentNotifications.codex || snapshot.appearance.agentNotifications.claudeCode ? L("开启", "On") : L("关闭", "Off"),
                systemImage: "sparkles"
            )
        }
    }
}

struct SettingsOverviewTile: View {
    let title: String
    let value: String
    let systemImage: String
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorTheme) private var theme

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.conductorSystem(size: 11, weight: .semibold, scale: fontScale))
                .foregroundStyle(theme.floatingEmphasis.opacity(0.84))
                .frame(width: 18)
                .accessibilityHidden(true)

            Text(title)
                .font(.conductorSystem(size: 12.2, weight: .medium, scale: fontScale))
                .foregroundStyle(ConductorDesign.primaryText)
                .lineLimit(1)

            Spacer(minLength: 12)

            Text(value)
                .font(.conductorSystem(size: 12.1, weight: .semibold, scale: fontScale))
                .foregroundStyle(ConductorDesign.secondaryText)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
    }
}

struct SettingsQuickJumpButton: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorTheme) private var theme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.conductorSystem(size: 11.5, weight: .semibold, scale: fontScale))
                    .foregroundStyle(theme.floatingEmphasis.opacity(0.86))
                    .frame(width: 18)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.conductorSystem(size: 12.3, weight: .bold, scale: fontScale))
                        .foregroundStyle(ConductorDesign.primaryText)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.conductorSystem(size: 10.3, weight: .medium, scale: fontScale))
                        .foregroundStyle(ConductorDesign.tertiaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.conductorSystem(size: 10, weight: .bold, scale: fontScale))
                    .foregroundStyle(ConductorDesign.tertiaryText)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(hovering ? theme.floatingHoverFill.opacity(0.70) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(ConductorPressButtonStyle())
        .conductorHover($hovering)
    }
}
