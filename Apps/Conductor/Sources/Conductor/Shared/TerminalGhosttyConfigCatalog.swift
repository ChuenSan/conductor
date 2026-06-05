import Foundation

struct GhosttyConfigKeyGroup: Identifiable, Equatable {
    let id: String
    let title: String
    let keys: [String]

    var countTitle: String {
        ConductorLocalization.text(zh: "\(keys.count) 个真实配置", en: "\(keys.count) real keys")
    }
}

struct GhosttyConfigFunctionGroup: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    let systemImage: String
    let keys: [String]

    var countTitle: String {
        ConductorLocalization.text(zh: "\(keys.count) 项", en: "\(keys.count) settings")
    }
}

private struct GhosttyConfigSearchRecord {
    let groupText: String
    let keyTextByKey: [String: String]
}

enum GhosttyConfigControlStyle: Equatable {
    case boolean
    case choice([String])
    case percent
    case duration
    case color
    case filePath
    case number
    case text
}

enum TerminalGhosttyConfigCatalog {
    // Source: /tmp/codex-ghostty-reference/src/config/Config.zig and
    // /Applications/Ghostty.app/Contents/Resources/ghostty/doc/ghostty.5.md.
    // Keep this as a grounded map before exposing settings. Do not add UI for a
    // Ghostty option unless the key exists here or in newer bundled docs.
    static let sourceTitle = "Ghostty Config.zig + ghostty.5"
    static let totalKeyCount = 194
    static let allKnownKeys: [String] = [
        "font-family", "font-family-bold", "font-family-italic", "font-family-bold-italic",
        "font-style", "font-style-bold", "font-style-italic", "font-style-bold-italic",
        "font-synthetic-style", "font-feature", "font-size", "font-variation",
        "font-variation-bold", "font-variation-italic", "font-variation-bold-italic",
        "font-codepoint-map", "clipboard-codepoint-map", "font-thicken",
        "font-thicken-strength", "font-shaping-break", "alpha-blending",
        "adjust-cell-width", "adjust-cell-height", "adjust-font-baseline",
        "adjust-underline-position", "adjust-underline-thickness",
        "adjust-strikethrough-position", "adjust-strikethrough-thickness",
        "adjust-overline-position", "adjust-overline-thickness",
        "adjust-cursor-thickness", "adjust-cursor-height", "adjust-box-thickness",
        "adjust-icon-height", "grapheme-width-method", "freetype-load-flags",
        "background-image", "background-image-opacity", "background-image-position",
        "background-image-fit", "background-image-repeat", "selection-foreground",
        "selection-background", "selection-clear-on-typing", "selection-clear-on-copy",
        "selection-word-chars", "minimum-contrast", "palette-generate",
        "palette-harmonious", "cursor-color", "cursor-opacity", "cursor-style",
        "cursor-style-blink", "cursor-text", "cursor-click-to-move",
        "mouse-hide-while-typing", "scroll-to-bottom", "mouse-shift-capture",
        "mouse-reporting", "mouse-scroll-multiplier", "background-opacity",
        "background-opacity-cells", "background-blur", "unfocused-split-opacity",
        "unfocused-split-fill", "split-divider-color", "split-preserve-zoom",
        "search-foreground", "search-background", "search-selected-foreground",
        "search-selected-background", "initial-command", "wait-after-command",
        "abnormal-command-exit-runtime", "scrollback-limit",
        "link-url", "link-previews", "x11-instance-name", "working-directory",
        "key-remap", "window-padding-x", "window-padding-y", "window-padding-balance",
        "window-padding-color", "window-vsync", "window-inherit-working-directory",
        "tab-inherit-working-directory", "split-inherit-working-directory",
        "window-inherit-font-size", "window-decoration", "window-title-font-family",
        "window-subtitle", "window-theme", "window-colorspace", "window-height",
        "window-width", "window-position-x", "window-position-y", "window-save-state",
        "window-step-resize", "window-new-tab-position", "window-show-tab-bar",
        "window-titlebar-background", "window-titlebar-foreground", "resize-overlay",
        "resize-overlay-position", "resize-overlay-duration", "focus-follows-mouse",
        "clipboard-read", "clipboard-write", "clipboard-trim-trailing-spaces",
        "clipboard-paste-protection", "clipboard-paste-bracketed-safe", "title-report",
        "image-storage-limit", "copy-on-select", "right-click-action",
        "middle-click-action", "click-repeat-interval", "config-file",
        "config-default-files", "confirm-close-surface", "quit-after-last-window-closed",
        "quit-after-last-window-closed-delay", "initial-window", "undo-timeout",
        "quick-terminal-position", "quick-terminal-size", "gtk-quick-terminal-layer",
        "gtk-quick-terminal-namespace", "quick-terminal-screen",
        "quick-terminal-animation-duration", "quick-terminal-autohide",
        "quick-terminal-space-behavior", "quick-terminal-keyboard-interactivity",
        "shell-integration", "shell-integration-features", "command-palette-entry",
        "osc-color-report-format", "vt-kam-allowed", "custom-shader",
        "custom-shader-animation", "bell-features", "bell-audio-path",
        "bell-audio-volume", "macos-non-native-fullscreen",
        "macos-window-buttons", "macos-titlebar-style", "macos-titlebar-proxy-icon",
        "macos-dock-drop-behavior", "macos-option-as-alt", "macos-window-shadow",
        "macos-hidden", "macos-auto-secure-input", "macos-secure-input-indication",
        "macos-applescript", "macos-icon", "macos-custom-icon", "macos-icon-frame",
        "macos-icon-ghost-color", "macos-icon-screen-color", "macos-shortcuts",
        "linux-cgroup", "linux-cgroup-memory-limit", "linux-cgroup-processes-limit",
        "linux-cgroup-hard-fail", "gtk-opengl-debug", "gtk-single-instance",
        "gtk-titlebar", "gtk-tabs-location", "gtk-titlebar-hide-when-maximized",
        "gtk-toolbar-style", "gtk-titlebar-style", "gtk-wide-tabs", "gtk-custom-css",
        "progress-style", "bold-color", "faint-opacity",
        "enquiry-response", "async-backend", "auto-update", "auto-update-channel",
        "_xdg-terminal-exec", "bold-italic", "ssh-env", "ssh-terminfo",
        "clipboard-copy", "config-reload", "force-autohint"
    ]
    static let knownKeySet = Set(allKnownKeys)

    static let productGroups: [GhosttyConfigFunctionGroup] = [
        GhosttyConfigFunctionGroup(
            id: "typography",
            title: ConductorLocalization.text(zh: "字体与字格", en: "Typography"),
            subtitle: ConductorLocalization.text(zh: "只保留会直接影响终端阅读体验的字体、字号、行高和字格微调。", en: "Only settings that directly affect terminal reading: fonts, size, line height, and cell metrics."),
            systemImage: "textformat.size",
            keys: [
                "font-family", "font-family-bold", "font-family-italic", "font-family-bold-italic",
                "font-feature", "font-size", "adjust-cell-width", "adjust-cell-height",
                "adjust-font-baseline", "adjust-underline-position", "adjust-underline-thickness",
                "adjust-cursor-thickness", "adjust-cursor-height"
            ]
        ),
        GhosttyConfigFunctionGroup(
            id: "cursor",
            title: ConductorLocalization.text(zh: "光标", en: "Cursor"),
            subtitle: ConductorLocalization.text(zh: "光标形状、颜色、闪烁和点击移动，都是终端日常使用会感知到的项。", en: "Cursor shape, color, blink, and click-to-move: visible daily-use terminal behavior."),
            systemImage: "cursorarrow",
            keys: [
                "cursor-style", "cursor-style-blink", "cursor-color",
                "cursor-opacity", "cursor-text", "cursor-click-to-move"
            ]
        ),
        GhosttyConfigFunctionGroup(
            id: "background",
            title: ConductorLocalization.text(zh: "背景与颜色", en: "Background and Colors"),
            subtitle: ConductorLocalization.text(zh: "终端背景、背景图、模糊、选区和搜索高亮；窗口模式只保留浅色和暗色。", en: "Terminal background, image, blur, selection, and search highlights; window mode is limited to light and dark."),
            systemImage: "paintpalette",
            keys: [
                "background-opacity", "background-blur", "background-image",
                "background-image-opacity", "background-image-position", "background-image-fit",
                "minimum-contrast", "selection-foreground", "selection-background",
                "search-foreground", "search-background", "search-selected-foreground",
                "search-selected-background"
            ]
        ),
        GhosttyConfigFunctionGroup(
            id: "selection_mouse",
            title: ConductorLocalization.text(zh: "选择、鼠标与链接", en: "Selection, Mouse, and Links"),
            subtitle: ConductorLocalization.text(zh: "复制选择、滚轮速度、鼠标上报和链接预览这类交互设置。", en: "Selection copy behavior, scroll speed, mouse reporting, and link previews."),
            systemImage: "cursorarrow.click",
            keys: [
                "selection-clear-on-typing", "selection-clear-on-copy", "selection-word-chars",
                "copy-on-select", "mouse-hide-while-typing", "mouse-reporting",
                "mouse-scroll-multiplier", "link-url", "link-previews"
            ]
        ),
        GhosttyConfigFunctionGroup(
            id: "clipboard_paste",
            title: ConductorLocalization.text(zh: "剪贴板与粘贴安全", en: "Clipboard and Paste Safety"),
            subtitle: ConductorLocalization.text(zh: "只放会影响复制粘贴安全和体验的开关。", en: "Only controls that affect copy/paste safety and behavior."),
            systemImage: "doc.on.clipboard",
            keys: [
                "clipboard-read", "clipboard-write", "clipboard-trim-trailing-spaces",
                "clipboard-paste-protection", "clipboard-paste-bracketed-safe"
            ]
        ),
        GhosttyConfigFunctionGroup(
            id: "shell",
            title: ConductorLocalization.text(zh: "Shell 与启动", en: "Shell and Startup"),
            subtitle: ConductorLocalization.text(zh: "Shell 集成、启动命令、默认目录和滚屏历史。", en: "Shell integration, startup command, default directory, and scrollback history."),
            systemImage: "terminal",
            keys: [
                "shell-integration", "initial-command", "working-directory", "scrollback-limit"
            ]
        ),
        GhosttyConfigFunctionGroup(
            id: "bell",
            title: ConductorLocalization.text(zh: "铃声", en: "Bell"),
            subtitle: ConductorLocalization.text(zh: "终端铃声提示。", en: "Terminal bell feedback."),
            systemImage: "bell",
            keys: [
                "bell-features", "bell-audio-path", "bell-audio-volume"
            ]
        ),
        GhosttyConfigFunctionGroup(
            id: "keyboard",
            title: ConductorLocalization.text(zh: "键盘", en: "Keyboard"),
            subtitle: ConductorLocalization.text(zh: "只保留终端输入相关的键盘项；应用命令快捷键放在命令页。", en: "Only terminal-input keyboard options; app command shortcuts stay in the Commands page."),
            systemImage: "keyboard",
            keys: [
                "key-remap", "macos-option-as-alt"
            ]
        )
    ]

    static let functionGroups: [GhosttyConfigFunctionGroup] = [
        GhosttyConfigFunctionGroup(
            id: "typography",
            title: ConductorLocalization.text(zh: "字体与字格", en: "Typography and Cells"),
            subtitle: ConductorLocalization.text(zh: "字体族、字号、字形、连字、行高和单元格微调。", en: "Font families, size, shaping, ligatures, line height, and cell metrics."),
            systemImage: "textformat.size",
            keys: [
                "font-family", "font-family-bold", "font-family-italic", "font-family-bold-italic",
                "font-style", "font-style-bold", "font-style-italic", "font-style-bold-italic",
                "font-synthetic-style", "font-feature", "font-size", "font-variation",
                "font-variation-bold", "font-variation-italic", "font-variation-bold-italic",
                "font-codepoint-map", "clipboard-codepoint-map", "font-thicken",
                "font-thicken-strength", "font-shaping-break", "adjust-cell-width",
                "adjust-cell-height", "adjust-font-baseline", "adjust-underline-position",
                "adjust-underline-thickness", "adjust-strikethrough-position",
                "adjust-strikethrough-thickness", "adjust-overline-position",
                "adjust-overline-thickness", "adjust-cursor-thickness",
                "adjust-cursor-height", "adjust-box-thickness", "adjust-icon-height",
                "grapheme-width-method", "freetype-load-flags", "force-autohint"
            ]
        ),
        GhosttyConfigFunctionGroup(
            id: "cursor",
            title: ConductorLocalization.text(zh: "光标", en: "Cursor"),
            subtitle: ConductorLocalization.text(zh: "控制光标形状、颜色、闪烁、透明度和点击移动。", en: "Controls cursor shape, color, blink, opacity, and click-to-move behavior."),
            systemImage: "cursorarrow",
            keys: [
                "cursor-color", "cursor-opacity", "cursor-style", "cursor-style-blink",
                "cursor-text", "cursor-click-to-move"
            ]
        ),
        GhosttyConfigFunctionGroup(
            id: "background",
            title: ConductorLocalization.text(zh: "背景与视觉", en: "Background and Visuals"),
            subtitle: ConductorLocalization.text(zh: "背景图、透明度、模糊、对比度、调色板和搜索高亮。", en: "Background images, opacity, blur, contrast, palettes, and search highlights."),
            systemImage: "rectangle.on.rectangle.angled",
            keys: [
                "background-image", "background-image-opacity", "background-image-position",
                "background-image-fit", "background-image-repeat", "background-opacity",
                "background-opacity-cells", "background-blur", "alpha-blending",
                "minimum-contrast", "palette-generate", "palette-harmonious",
                "selection-foreground", "selection-background", "search-foreground",
                "search-background", "search-selected-foreground", "search-selected-background",
                "bold-color", "faint-opacity", "bold-italic", "unfocused-split-opacity",
                "unfocused-split-fill", "split-divider-color"
            ]
        ),
        GhosttyConfigFunctionGroup(
            id: "selection_mouse",
            title: ConductorLocalization.text(zh: "选择、鼠标与链接", en: "Selection, Mouse, and Links"),
            subtitle: ConductorLocalization.text(zh: "选区清理、单词边界、鼠标捕获、滚轮速度和链接预览。", en: "Selection clearing, word boundaries, mouse capture, scroll speed, and link previews."),
            systemImage: "cursorarrow.click",
            keys: [
                "selection-clear-on-typing", "selection-clear-on-copy", "selection-word-chars",
                "mouse-hide-while-typing", "scroll-to-bottom", "mouse-shift-capture",
                "mouse-reporting", "mouse-scroll-multiplier", "link-url", "link-previews",
                "copy-on-select", "right-click-action", "middle-click-action",
                "click-repeat-interval"
            ]
        ),
        GhosttyConfigFunctionGroup(
            id: "clipboard_paste",
            title: ConductorLocalization.text(zh: "剪贴板与粘贴安全", en: "Clipboard and Paste Safety"),
            subtitle: ConductorLocalization.text(zh: "控制读写剪贴板、粘贴保护、括号粘贴和尾随空格。", en: "Controls clipboard access, paste protection, bracketed paste, and trailing spaces."),
            systemImage: "doc.on.clipboard",
            keys: [
                "clipboard-read", "clipboard-write", "clipboard-trim-trailing-spaces",
                "clipboard-paste-protection", "clipboard-paste-bracketed-safe",
                "clipboard-copy", "title-report"
            ]
        ),
        GhosttyConfigFunctionGroup(
            id: "shell_session",
            title: ConductorLocalization.text(zh: "Shell、命令与会话", en: "Shell, Commands, and Sessions"),
            subtitle: ConductorLocalization.text(zh: "启动命令、工作目录、Shell 集成、滚屏容量和命令退出行为。", en: "Startup commands, working directory, shell integration, scrollback, and command exit behavior."),
            systemImage: "terminal",
            keys: [
                "initial-command", "working-directory", "shell-integration",
                "shell-integration-features", "wait-after-command",
                "abnormal-command-exit-runtime", "scrollback-limit",
                "window-inherit-working-directory", "tab-inherit-working-directory",
                "split-inherit-working-directory", "window-inherit-font-size",
                "enquiry-response", "ssh-env", "ssh-terminfo"
            ]
        ),
        GhosttyConfigFunctionGroup(
            id: "windows_tabs_splits",
            title: ConductorLocalization.text(zh: "窗口、标签与分屏", en: "Windows, Tabs, and Splits"),
            subtitle: ConductorLocalization.text(zh: "窗口尺寸、标签栏、分屏透明度、关闭确认和 resize overlay。", en: "Window sizes, tab bar behavior, split visuals, close confirmation, and resize overlays."),
            systemImage: "rectangle.split.3x1",
            keys: [
                "window-padding-x", "window-padding-y", "window-padding-balance",
                "window-padding-color", "window-vsync", "window-decoration",
                "window-title-font-family", "window-subtitle", "window-theme",
                "window-colorspace", "window-height", "window-width",
                "window-position-x", "window-position-y", "window-save-state",
                "window-step-resize", "window-new-tab-position", "window-show-tab-bar",
                "window-titlebar-background", "window-titlebar-foreground",
                "resize-overlay", "resize-overlay-position", "resize-overlay-duration",
                "focus-follows-mouse", "confirm-close-surface",
                "quit-after-last-window-closed", "quit-after-last-window-closed-delay",
                "initial-window", "undo-timeout", "split-preserve-zoom"
            ]
        ),
        GhosttyConfigFunctionGroup(
            id: "bell-progress",
            title: ConductorLocalization.text(zh: "铃声与进度", en: "Bell and Progress"),
            subtitle: ConductorLocalization.text(zh: "铃声文件/音量和进度样式。", en: "Bell sound, volume, and progress style."),
            systemImage: "bell",
            keys: [
                "bell-features", "bell-audio-path", "bell-audio-volume", "progress-style"
            ]
        ),
        GhosttyConfigFunctionGroup(
            id: "keyboard_actions",
            title: ConductorLocalization.text(zh: "键盘与动作", en: "Keyboard and Actions"),
            subtitle: ConductorLocalization.text(zh: "快捷键映射、命令面板入口、macOS 快捷键和终端键盘模式。", en: "Key remaps, command palette entries, macOS shortcuts, and terminal keyboard modes."),
            systemImage: "keyboard",
            keys: [
                "key-remap", "command-palette-entry", "vt-kam-allowed",
                "macos-option-as-alt", "macos-shortcuts"
            ]
        ),
        GhosttyConfigFunctionGroup(
            id: "files_config",
            title: ConductorLocalization.text(zh: "文件、配置与资源", en: "Files, Config, and Resources"),
            subtitle: ConductorLocalization.text(zh: "配置文件、图片缓存、自定义 shader 和自动重载。", en: "Config files, image cache limits, custom shaders, and config reload behavior."),
            systemImage: "folder",
            keys: [
                "config-file", "config-default-files", "config-reload",
                "image-storage-limit", "custom-shader", "custom-shader-animation"
            ]
        ),
        GhosttyConfigFunctionGroup(
            id: "platform",
            title: ConductorLocalization.text(zh: "平台集成", en: "Platform Integration"),
            subtitle: ConductorLocalization.text(zh: "macOS、GTK、Linux、X11、桌面环境和更新相关行为。", en: "macOS, GTK, Linux, X11, desktop environment, and update behavior."),
            systemImage: "desktopcomputer",
            keys: [
                "x11-instance-name", "quick-terminal-position", "quick-terminal-size",
                "gtk-quick-terminal-layer", "gtk-quick-terminal-namespace",
                "quick-terminal-screen", "quick-terminal-animation-duration",
                "quick-terminal-autohide", "quick-terminal-space-behavior",
                "quick-terminal-keyboard-interactivity", "macos-non-native-fullscreen",
                "macos-window-buttons", "macos-titlebar-style",
                "macos-titlebar-proxy-icon", "macos-dock-drop-behavior",
                "macos-window-shadow", "macos-hidden", "macos-auto-secure-input",
                "macos-secure-input-indication", "macos-applescript", "macos-icon",
                "macos-custom-icon", "macos-icon-frame", "macos-icon-ghost-color",
                "macos-icon-screen-color", "linux-cgroup",
                "linux-cgroup-memory-limit", "linux-cgroup-processes-limit",
                "linux-cgroup-hard-fail", "gtk-opengl-debug", "gtk-single-instance",
                "gtk-titlebar", "gtk-tabs-location",
                "gtk-titlebar-hide-when-maximized", "gtk-toolbar-style",
                "gtk-titlebar-style", "gtk-wide-tabs", "gtk-custom-css",
                "auto-update", "auto-update-channel", "_xdg-terminal-exec"
            ]
        ),
        GhosttyConfigFunctionGroup(
            id: "protocol_runtime",
            title: ConductorLocalization.text(zh: "终端协议与运行时", en: "Terminal Protocol and Runtime"),
            subtitle: ConductorLocalization.text(zh: "OSC、异步后端、颜色报告和较少使用的运行时开关。", en: "OSC, async backend, color reports, and less common runtime toggles."),
            systemImage: "waveform.path.ecg",
            keys: [
                "osc-color-report-format", "async-backend"
            ]
        )
    ]

    static let groups: [GhosttyConfigKeyGroup] = [
        GhosttyConfigKeyGroup(
            id: "font",
            title: ConductorLocalization.text(zh: "字体与字形", en: "Fonts and glyphs"),
            keys: [
                "font-family", "font-family-bold", "font-family-italic", "font-family-bold-italic",
                "font-style", "font-style-bold", "font-style-italic", "font-style-bold-italic",
                "font-synthetic-style", "font-feature", "font-size", "font-variation",
                "font-variation-bold", "font-variation-italic", "font-variation-bold-italic",
                "font-codepoint-map", "font-thicken", "font-thicken-strength", "font-shaping-break"
            ]
        ),
        GhosttyConfigKeyGroup(
            id: "cursor",
            title: ConductorLocalization.text(zh: "光标", en: "Cursor"),
            keys: ["cursor-color", "cursor-opacity", "cursor-style", "cursor-style-blink", "cursor-text", "cursor-click-to-move"]
        ),
        GhosttyConfigKeyGroup(
            id: "background",
            title: ConductorLocalization.text(zh: "背景", en: "Background"),
            keys: [
                "background-image", "background-image-opacity", "background-image-position",
                "background-image-fit", "background-image-repeat", "background-opacity",
                "background-opacity-cells", "background-blur"
            ]
        ),
        GhosttyConfigKeyGroup(
            id: "metrics",
            title: ConductorLocalization.text(zh: "字格与线条微调", en: "Cell and line metrics"),
            keys: [
                "adjust-cell-width", "adjust-cell-height", "adjust-font-baseline",
                "adjust-underline-position", "adjust-underline-thickness",
                "adjust-strikethrough-position", "adjust-strikethrough-thickness",
                "adjust-overline-position", "adjust-overline-thickness",
                "adjust-cursor-thickness", "adjust-cursor-height", "adjust-box-thickness",
                "adjust-icon-height"
            ]
        ),
        GhosttyConfigKeyGroup(
            id: "selection",
            title: ConductorLocalization.text(zh: "选择与鼠标", en: "Selection and mouse"),
            keys: [
                "selection-foreground", "selection-background", "selection-clear-on-typing",
                "selection-clear-on-copy", "selection-word-chars", "mouse-hide-while-typing",
                "mouse-shift-capture", "mouse-reporting", "mouse-scroll-multiplier", "scroll-to-bottom"
            ]
        ),
        GhosttyConfigKeyGroup(
            id: "clipboard",
            title: ConductorLocalization.text(zh: "剪贴板与粘贴", en: "Clipboard and paste"),
            keys: [
                "clipboard-read", "clipboard-write", "clipboard-trim-trailing-spaces",
                "clipboard-paste-protection", "clipboard-paste-bracketed-safe",
                "clipboard-copy", "copy-on-select"
            ]
        ),
        GhosttyConfigKeyGroup(
            id: "shell",
            title: ConductorLocalization.text(zh: "Shell 集成", en: "Shell integration"),
            keys: ["shell-integration", "shell-integration-features"]
        ),
        GhosttyConfigKeyGroup(
            id: "macos",
            title: ConductorLocalization.text(zh: "macOS 与窗口", en: "macOS and windows"),
            keys: [
                "window-vsync", "window-colorspace", "window-padding-x", "window-padding-y",
                "window-padding-balance", "window-padding-color", "window-theme",
                "macos-titlebar-style", "macos-titlebar-proxy-icon", "macos-option-as-alt",
                "macos-auto-secure-input", "macos-secure-input-indication", "macos-shortcuts"
            ]
        )
    ]

    static let activeKeys: [String] = [
        "font-family",
        "font-size",
        "adjust-cell-height",
        "background-opacity",
        "cursor-style",
        "cursor-style-blink",
        "cursor-text",
        "shell-integration",
        "shell-integration-features",
        // cmux/GhosttyKit fork extension used by our embedded macOS surface.
        "macos-background-from-layer",
        "macos-titlebar-proxy-icon"
    ]

    static func functionGroup(for key: String) -> GhosttyConfigFunctionGroup {
        functionGroups.first { $0.keys.contains(key) }
            ?? GhosttyConfigFunctionGroup(
                id: "other",
                title: ConductorLocalization.text(zh: "其他", en: "Other"),
                subtitle: ConductorLocalization.text(zh: "较少使用或新版本 Ghostty 的配置项。", en: "Less common or newer Ghostty settings."),
                systemImage: "ellipsis.circle",
                keys: [key]
            )
    }

    static func filteredProductGroups(matching rawQuery: String) -> [GhosttyConfigFunctionGroup] {
        let query = normalizedSearchText(rawQuery)
        guard !query.isEmpty else { return productGroups }

        return productGroups.compactMap { group in
            guard let record = productSearchIndex[group.id] else { return nil }
            let keys = record.groupText.contains(query)
                ? group.keys
                : group.keys.filter { key in
                    record.keyTextByKey[key]?.contains(query) ?? normalizedSearchText(key).contains(query)
                }
            guard !keys.isEmpty else { return nil }
            return GhosttyConfigFunctionGroup(
                id: group.id,
                title: group.title,
                subtitle: group.subtitle,
                systemImage: group.systemImage,
                keys: keys
            )
        }
    }

    static func description(for key: String) -> String {
        switch key {
        case "font-family":
            ConductorLocalization.text(zh: "终端正文使用的字体族；会影响新建和已刷新 surface。", en: "Font family used for terminal text; affects new and refreshed surfaces.")
        case "font-size":
            ConductorLocalization.text(zh: "终端字符字号，和应用壳层字号分开管理。", en: "Terminal character size, managed separately from shell UI text size.")
        case "adjust-cell-height":
            ConductorLocalization.text(zh: "拉开或压缩每行高度，用来改善拥挤或过松的字体。", en: "Expands or tightens row height to make a font feel less cramped or loose.")
        case "background-opacity":
            ConductorLocalization.text(zh: "控制终端背景不透明度，影响 Ghostty 渲染层的背景填充。", en: "Controls terminal background opacity in the Ghostty renderer.")
        case "cursor-style":
            ConductorLocalization.text(zh: "选择块状、空心块、竖线或下划线光标。", en: "Chooses block, hollow block, bar, or underline cursor shape.")
        case "cursor-style-blink":
            ConductorLocalization.text(zh: "控制光标是否闪烁。", en: "Controls whether the cursor blinks.")
        case "shell-integration", "shell-integration-features":
            ConductorLocalization.text(zh: "让 Ghostty 注入 shell 集成功能；本应用默认保留 no-cursor，避免 shell 覆盖光标样式。", en: "Enables Ghostty shell integration; this app keeps no-cursor so shell integration does not override cursor styling.")
        case _ where key.hasPrefix("font-family"):
            ConductorLocalization.text(zh: "为粗体/斜体等字重指定专用字体族。", en: "Sets a dedicated font family for bold, italic, or related faces.")
        case _ where key.hasPrefix("font-style"):
            ConductorLocalization.text(zh: "指定字体样式名称，用于匹配字体家族里的具体字形。", en: "Specifies a font style name to match a concrete face inside the family.")
        case _ where key.hasPrefix("font-variation"):
            ConductorLocalization.text(zh: "传递可变字体轴参数，例如字重、宽度或光学尺寸。", en: "Passes variable-font axis values such as weight, width, or optical size.")
        case _ where key.hasPrefix("font-") || key.hasPrefix("adjust-") || key == "grapheme-width-method":
            ConductorLocalization.text(zh: "微调字形、字格、基线或线条粗细，适合修正特定字体的观感。", en: "Fine-tunes glyphs, cells, baselines, or line thickness for a specific font.")
        case _ where key.hasPrefix("cursor-"):
            ConductorLocalization.text(zh: "调整光标的颜色、透明度、形状、文字反色或交互方式。", en: "Adjusts cursor color, opacity, shape, text contrast, or interaction behavior.")
        case _ where key.hasPrefix("background-image"):
            ConductorLocalization.text(zh: "设置终端背景图片以及图片的透明度、位置、填充和重复方式。", en: "Sets a terminal background image plus its opacity, position, fit, and repeat behavior.")
        case _ where key.hasPrefix("background-"):
            ConductorLocalization.text(zh: "控制终端背景的透明、模糊或单元格背景处理方式。", en: "Controls terminal background opacity, blur, or per-cell background handling.")
        case _ where key.hasPrefix("selection-"):
            ConductorLocalization.text(zh: "控制选区颜色、清理时机和双击选词边界。", en: "Controls selection colors, clearing behavior, and word boundaries.")
        case _ where key.hasPrefix("search-"):
            ConductorLocalization.text(zh: "控制终端内搜索命中的前景色、背景色和当前命中样式。", en: "Controls foreground, background, and active-match styling for terminal search.")
        case _ where key.hasPrefix("mouse-") || key == "right-click-action" || key == "middle-click-action":
            ConductorLocalization.text(zh: "控制鼠标捕获、滚动速度、右键/中键动作和输入时隐藏指针。", en: "Controls mouse capture, scroll speed, right/middle-click actions, and hiding the pointer while typing.")
        case _ where key.hasPrefix("clipboard-") || key == "copy-on-select":
            ConductorLocalization.text(zh: "控制剪贴板读写、复制策略、粘贴保护和安全粘贴模式。", en: "Controls clipboard access, copy behavior, paste protection, and safe paste modes.")
        case _ where key.hasPrefix("bell-"):
            ConductorLocalization.text(zh: "配置终端铃声的功能、音频文件和音量。", en: "Configures terminal bell behavior, sound file, and volume.")
        case _ where key.hasPrefix("window-"):
            ConductorLocalization.text(zh: "Ghostty 原生窗口设置；在 Conductor 内通常只作为高级兼容项。", en: "Native Ghostty window setting; usually an advanced compatibility option inside Conductor.")
        case _ where key.hasPrefix("split-") || key.hasPrefix("unfocused-split-"):
            ConductorLocalization.text(zh: "控制 Ghostty 原生分屏视觉；Conductor 自己的分屏仍由应用壳层管理。", en: "Controls native Ghostty split visuals; Conductor split layout remains app-owned.")
        case _ where key.hasPrefix("quick-terminal-") || key.hasPrefix("gtk-quick-terminal"):
            ConductorLocalization.text(zh: "Ghostty quick terminal 设置；嵌入式 Conductor surface 一般不会直接使用。", en: "Ghostty quick-terminal setting; embedded Conductor surfaces usually do not use it directly.")
        case _ where key.hasPrefix("macos-"):
            ConductorLocalization.text(zh: "macOS 平台集成行为，例如标题栏、Dock、Secure Input 或快捷键。", en: "macOS platform behavior such as title bars, Dock, Secure Input, or shortcuts.")
        case _ where key.hasPrefix("gtk-") || key.hasPrefix("linux-") || key.hasPrefix("x11-") || key == "_xdg-terminal-exec":
            ConductorLocalization.text(zh: "非 macOS 平台或桌面环境相关设置，保留给配置兼容和迁移。", en: "Non-macOS platform or desktop-environment setting kept for compatibility and migration.")
        case _ where key.hasPrefix("config-"):
            ConductorLocalization.text(zh: "控制 Ghostty 配置文件加载、默认文件和重载行为。", en: "Controls Ghostty config loading, default files, and reload behavior.")
        case _ where key.hasPrefix("custom-shader"):
            ConductorLocalization.text(zh: "加载自定义 shader 或控制其动画，用于高级视觉效果。", en: "Loads a custom shader or controls its animation for advanced visuals.")
        case _ where key.hasSuffix("duration") || key.hasSuffix("after") || key.hasSuffix("timeout") || key.hasSuffix("delay"):
            ConductorLocalization.text(zh: "时间阈值或动画持续时间，通常写作 1s、500ms 这类值。", en: "A timing threshold or animation duration, usually written as values like 1s or 500ms.")
        case _ where key.hasSuffix("opacity") || key.hasSuffix("volume") || key == "minimum-contrast":
            ConductorLocalization.text(zh: "数值型强度设置，通常使用 0 到 1 的小数。", en: "Numeric intensity setting, usually a 0 to 1 decimal.")
        case _ where key.hasSuffix("color") || key.hasSuffix("foreground") || key.hasSuffix("background"):
            ConductorLocalization.text(zh: "颜色配置，通常使用 #RRGGBB 十六进制值。", en: "Color setting, usually a #RRGGBB hex value.")
        default:
            ConductorLocalization.text(zh: "Ghostty 原生高级配置项；启用后会追加到生成的 config。", en: "Native advanced Ghostty setting; enabled values are appended to generated config.")
        }
    }

    static func displayTitle(for key: String) -> String {
        switch key {
        case "font-family": ConductorLocalization.text(zh: "终端字体", en: "Terminal Font")
        case "font-family-bold": ConductorLocalization.text(zh: "粗体字体", en: "Bold Font")
        case "font-family-italic": ConductorLocalization.text(zh: "斜体字体", en: "Italic Font")
        case "font-family-bold-italic": ConductorLocalization.text(zh: "粗斜体字体", en: "Bold Italic Font")
        case "font-style": ConductorLocalization.text(zh: "常规字形样式", en: "Regular Font Style")
        case "font-style-bold": ConductorLocalization.text(zh: "粗体字形样式", en: "Bold Font Style")
        case "font-style-italic": ConductorLocalization.text(zh: "斜体字形样式", en: "Italic Font Style")
        case "font-style-bold-italic": ConductorLocalization.text(zh: "粗斜体字形样式", en: "Bold Italic Font Style")
        case "font-synthetic-style": ConductorLocalization.text(zh: "合成粗斜体", en: "Synthetic Styles")
        case "font-feature": ConductorLocalization.text(zh: "字体特性", en: "Font Features")
        case "font-size": ConductorLocalization.text(zh: "终端字号", en: "Terminal Font Size")
        case "font-variation": ConductorLocalization.text(zh: "可变字体轴", en: "Font Variations")
        case "font-codepoint-map": ConductorLocalization.text(zh: "字符字体映射", en: "Codepoint Font Map")
        case "clipboard-codepoint-map": ConductorLocalization.text(zh: "剪贴板字符映射", en: "Clipboard Codepoint Map")
        case "font-thicken": ConductorLocalization.text(zh: "字体加粗微调", en: "Font Thickening")
        case "font-thicken-strength": ConductorLocalization.text(zh: "字体加粗强度", en: "Font Thickening Strength")
        case "font-shaping-break": ConductorLocalization.text(zh: "禁用连字断点", en: "Font Shaping Break")
        case "adjust-cell-width": ConductorLocalization.text(zh: "字格宽度", en: "Cell Width")
        case "adjust-cell-height": ConductorLocalization.text(zh: "行高", en: "Line Height")
        case "adjust-font-baseline": ConductorLocalization.text(zh: "字体基线", en: "Font Baseline")
        case "adjust-underline-position": ConductorLocalization.text(zh: "下划线位置", en: "Underline Position")
        case "adjust-underline-thickness": ConductorLocalization.text(zh: "下划线粗细", en: "Underline Thickness")
        case "adjust-strikethrough-position": ConductorLocalization.text(zh: "删除线位置", en: "Strikethrough Position")
        case "adjust-strikethrough-thickness": ConductorLocalization.text(zh: "删除线粗细", en: "Strikethrough Thickness")
        case "adjust-overline-position": ConductorLocalization.text(zh: "上划线位置", en: "Overline Position")
        case "adjust-overline-thickness": ConductorLocalization.text(zh: "上划线粗细", en: "Overline Thickness")
        case "adjust-cursor-thickness": ConductorLocalization.text(zh: "光标粗细", en: "Cursor Thickness")
        case "adjust-cursor-height": ConductorLocalization.text(zh: "光标高度", en: "Cursor Height")
        case "adjust-box-thickness": ConductorLocalization.text(zh: "方框线粗细", en: "Box Thickness")
        case "adjust-icon-height": ConductorLocalization.text(zh: "图标高度", en: "Icon Height")
        case "grapheme-width-method": ConductorLocalization.text(zh: "复杂字符宽度算法", en: "Grapheme Width Method")
        case "freetype-load-flags": ConductorLocalization.text(zh: "FreeType 加载参数", en: "FreeType Load Flags")
        case "force-autohint": ConductorLocalization.text(zh: "强制自动 Hinting", en: "Force Autohint")
        case "cursor-color": ConductorLocalization.text(zh: "光标颜色", en: "Cursor Color")
        case "cursor-opacity": ConductorLocalization.text(zh: "光标透明度", en: "Cursor Opacity")
        case "cursor-style": ConductorLocalization.text(zh: "光标样式", en: "Cursor Style")
        case "cursor-style-blink": ConductorLocalization.text(zh: "光标闪烁", en: "Cursor Blink")
        case "cursor-text": ConductorLocalization.text(zh: "光标内文字颜色", en: "Cursor Text Color")
        case "cursor-click-to-move": ConductorLocalization.text(zh: "点击移动光标", en: "Click To Move Cursor")
        case "background-image": ConductorLocalization.text(zh: "背景图片", en: "Background Image")
        case "background-image-opacity": ConductorLocalization.text(zh: "背景图片透明度", en: "Background Image Opacity")
        case "background-image-position": ConductorLocalization.text(zh: "背景图片位置", en: "Background Image Position")
        case "background-image-fit": ConductorLocalization.text(zh: "背景图片填充", en: "Background Image Fit")
        case "background-image-repeat": ConductorLocalization.text(zh: "背景图片重复", en: "Background Image Repeat")
        case "background-opacity": ConductorLocalization.text(zh: "背景不透明度", en: "Background Opacity")
        case "background-opacity-cells": ConductorLocalization.text(zh: "单元格背景透明", en: "Cell Background Opacity")
        case "background-blur": ConductorLocalization.text(zh: "背景模糊", en: "Background Blur")
        case "alpha-blending": ConductorLocalization.text(zh: "半透明混合", en: "Alpha Blending")
        case "minimum-contrast": ConductorLocalization.text(zh: "最低对比度", en: "Minimum Contrast")
        case "palette-generate": ConductorLocalization.text(zh: "自动生成调色板", en: "Generate Palette")
        case "palette-harmonious": ConductorLocalization.text(zh: "调色板协调", en: "Harmonious Palette")
        case "selection-foreground": ConductorLocalization.text(zh: "选区文字颜色", en: "Selection Text Color")
        case "selection-background": ConductorLocalization.text(zh: "选区背景颜色", en: "Selection Background")
        case "search-foreground": ConductorLocalization.text(zh: "搜索文字颜色", en: "Search Text Color")
        case "search-background": ConductorLocalization.text(zh: "搜索背景颜色", en: "Search Background")
        case "search-selected-foreground": ConductorLocalization.text(zh: "当前搜索文字颜色", en: "Active Search Text Color")
        case "search-selected-background": ConductorLocalization.text(zh: "当前搜索背景颜色", en: "Active Search Background")
        case "bold-color": ConductorLocalization.text(zh: "粗体颜色", en: "Bold Color")
        case "faint-opacity": ConductorLocalization.text(zh: "弱化文字透明度", en: "Faint Text Opacity")
        case "bold-italic": ConductorLocalization.text(zh: "粗斜体支持", en: "Bold Italic Support")
        case "unfocused-split-opacity": ConductorLocalization.text(zh: "未聚焦分屏透明度", en: "Unfocused Split Opacity")
        case "unfocused-split-fill": ConductorLocalization.text(zh: "未聚焦分屏遮罩", en: "Unfocused Split Fill")
        case "split-divider-color": ConductorLocalization.text(zh: "分屏分隔线颜色", en: "Split Divider Color")
        case "selection-clear-on-typing": ConductorLocalization.text(zh: "输入时清除选区", en: "Clear Selection On Typing")
        case "selection-clear-on-copy": ConductorLocalization.text(zh: "复制后清除选区", en: "Clear Selection On Copy")
        case "selection-word-chars": ConductorLocalization.text(zh: "双击选词字符", en: "Word Selection Characters")
        case "mouse-hide-while-typing": ConductorLocalization.text(zh: "输入时隐藏鼠标", en: "Hide Mouse While Typing")
        case "scroll-to-bottom": ConductorLocalization.text(zh: "输出时滚到底部", en: "Scroll To Bottom")
        case "mouse-shift-capture": ConductorLocalization.text(zh: "Shift 鼠标捕获", en: "Shift Mouse Capture")
        case "mouse-reporting": ConductorLocalization.text(zh: "鼠标事件上报", en: "Mouse Reporting")
        case "mouse-scroll-multiplier": ConductorLocalization.text(zh: "滚轮速度", en: "Scroll Speed")
        case "link-url": ConductorLocalization.text(zh: "链接识别", en: "Link Detection")
        case "link-previews": ConductorLocalization.text(zh: "链接预览", en: "Link Previews")
        case "copy-on-select": ConductorLocalization.text(zh: "选择即复制", en: "Copy On Select")
        case "right-click-action": ConductorLocalization.text(zh: "右键动作", en: "Right Click Action")
        case "middle-click-action": ConductorLocalization.text(zh: "中键动作", en: "Middle Click Action")
        case "click-repeat-interval": ConductorLocalization.text(zh: "连击间隔", en: "Click Repeat Interval")
        case "clipboard-read": ConductorLocalization.text(zh: "允许读取剪贴板", en: "Allow Clipboard Read")
        case "clipboard-write": ConductorLocalization.text(zh: "允许写入剪贴板", en: "Allow Clipboard Write")
        case "clipboard-trim-trailing-spaces": ConductorLocalization.text(zh: "复制时去掉行尾空格", en: "Trim Trailing Spaces")
        case "clipboard-paste-protection": ConductorLocalization.text(zh: "粘贴保护", en: "Paste Protection")
        case "clipboard-paste-bracketed-safe": ConductorLocalization.text(zh: "安全括号粘贴", en: "Safe Bracketed Paste")
        case "clipboard-copy": ConductorLocalization.text(zh: "复制动作", en: "Clipboard Copy")
        case "title-report": ConductorLocalization.text(zh: "标题上报", en: "Title Reporting")
        case "initial-command": ConductorLocalization.text(zh: "启动命令", en: "Initial Command")
        case "working-directory": ConductorLocalization.text(zh: "工作目录", en: "Working Directory")
        case "shell-integration": ConductorLocalization.text(zh: "Shell 集成", en: "Shell Integration")
        case "shell-integration-features": ConductorLocalization.text(zh: "Shell 集成功能", en: "Shell Integration Features")
        case "wait-after-command": ConductorLocalization.text(zh: "命令结束后等待", en: "Wait After Command")
        case "abnormal-command-exit-runtime": ConductorLocalization.text(zh: "异常退出保留时间", en: "Abnormal Exit Runtime")
        case "scrollback-limit": ConductorLocalization.text(zh: "滚屏历史上限", en: "Scrollback Limit")
        case "enquiry-response": ConductorLocalization.text(zh: "终端询问响应", en: "Enquiry Response")
        case "ssh-env": ConductorLocalization.text(zh: "SSH 环境变量", en: "SSH Environment")
        case "ssh-terminfo": ConductorLocalization.text(zh: "SSH Terminfo", en: "SSH Terminfo")
        default:
            generatedDisplayTitle(for: key)
        }
    }

    private static func generatedDisplayTitle(for key: String) -> String {
        let words = key
            .replacingOccurrences(of: "_", with: "")
            .split(separator: "-")
            .map(String.init)
        let core = words.map { word -> String in
            switch word {
            case "window": "窗口"
            case "tab", "tabs": "标签"
            case "split": "分屏"
            case "macos": "macOS"
            case "gtk": "GTK"
            case "linux": "Linux"
            case "quick": "快速"
            case "terminal": "终端"
            case "titlebar": "标题栏"
            case "title": "标题"
            case "background": "背景"
            case "foreground": "文字"
            case "color", "colorspace": "颜色"
            case "position": "位置"
            case "duration": "持续时间"
            case "delay": "延迟"
            case "timeout": "超时"
            case "bell": "铃声"
            case "audio": "音频"
            case "volume": "音量"
            case "config": "配置"
            case "file", "files": "文件"
            case "default": "默认"
            case "custom": "自定义"
            case "shader": "Shader"
            case "keyboard": "键盘"
            case "shortcut", "shortcuts": "快捷键"
            case "command": "命令"
            case "palette": "面板"
            case "entry": "入口"
            case "auto": "自动"
            case "update": "更新"
            case "channel": "通道"
            case "clipboard": "剪贴板"
            case "paste": "粘贴"
            case "close": "关闭"
            case "surface": "终端面"
            case "confirm": "确认"
            case "mouse": "鼠标"
            case "focus": "聚焦"
            case "follows": "跟随"
            case "padding": "内边距"
            case "height": "高度"
            case "width": "宽度"
            case "opacity": "透明度"
            case "style": "样式"
            case "theme": "主题"
            case "icon": "图标"
            case "screen": "屏幕"
            case "memory": "内存"
            case "limit": "上限"
            case "processes": "进程数"
            case "single": "单实例"
            case "instance": "实例"
            case "cgroup": "CGroup"
            case "x11": "X11"
            case "xdg": "XDG"
            case "exec": "执行"
            case "async": "异步"
            case "backend": "后端"
            case "osc": "OSC"
            case "report": "报告"
            case "format": "格式"
            case "vt": "VT"
            case "kam": "键盘锁"
            case "allowed": "允许"
            case "progress": "进度"
            case "initial": "初始"
            case "inherit": "继承"
            case "directory": "目录"
            case "save": "保存"
            case "state": "状态"
            case "new": "新建"
            case "show": "显示"
            case "bar": "栏"
            case "resize": "调整大小"
            case "overlay": "浮层"
            default: word.capitalized
            }
        }.joined()

        return core.isEmpty ? key : core
    }

    static func controlStyle(for key: String) -> GhosttyConfigControlStyle {
        switch key {
        case "cursor-style":
            .choice(["block", "block_hollow", "bar", "underline"])
        case "background-image-position":
            .choice(["center", "top-left", "top-right", "bottom-left", "bottom-right"])
        case "background-image-fit":
            .choice(["contain", "cover", "stretch", "none"])
        case "background-image-repeat":
            .choice(["no-repeat", "repeat", "repeat-x", "repeat-y"])
        case "shell-integration":
            .choice(["detect", "none", "fish", "zsh", "bash", "elvish"])
        case "window-decoration":
            .choice(["auto", "client", "server", "none"])
        case "window-theme":
            .choice(["auto", "light", "dark"])
        case "window-colorspace":
            .choice(["srgb", "display-p3"])
        case "progress-style":
            .choice(["native", "synthesize", "off"])
        case "auto-update-channel":
            .choice(["stable", "tip"])
        case "macos-option-as-alt":
            .choice(["false", "left", "right", "true"])
        case "working-directory", "bell-audio-path":
            .filePath
        case _ where booleanKeys.contains(key):
            .boolean
        case _ where key.hasPrefix("background-image") || key.hasSuffix("path") || key == "config-file" || key == "custom-shader":
            .filePath
        case _ where key.hasSuffix("color") || key.hasSuffix("foreground") || key.hasSuffix("background") || key == "bold-color" || key == "unfocused-split-fill":
            .color
        case _ where key.hasSuffix("opacity") || key.hasSuffix("volume") || key == "minimum-contrast" || key == "faint-opacity":
            .percent
        case _ where key.hasSuffix("duration") || key.hasSuffix("after") || key.hasSuffix("timeout") || key.hasSuffix("delay") || key.hasSuffix("interval") || key.hasSuffix("runtime"):
            .duration
        case _ where key.hasPrefix("adjust-") || key.hasSuffix("limit") || key.hasSuffix("width") || key.hasSuffix("height") || key.hasSuffix("size"):
            .number
        default:
            .text
        }
    }

    static func groupTitle(for key: String) -> String {
        switch key {
        case _ where key.hasPrefix("font-"):
            ConductorLocalization.text(zh: "字体", en: "Fonts")
        case _ where key.hasPrefix("cursor-"):
            ConductorLocalization.text(zh: "光标", en: "Cursor")
        case _ where key.hasPrefix("background-") || key == "alpha-blending":
            ConductorLocalization.text(zh: "背景", en: "Background")
        case _ where key.hasPrefix("selection-") || key.hasPrefix("mouse-") || key == "scroll-to-bottom":
            ConductorLocalization.text(zh: "选择/鼠标", en: "Selection/Mouse")
        case _ where key.hasPrefix("clipboard-") || key == "copy-on-select":
            ConductorLocalization.text(zh: "剪贴板", en: "Clipboard")
        case _ where key.hasPrefix("window-") || key.hasPrefix("macos-"):
            ConductorLocalization.text(zh: "窗口/macOS", en: "Window/macOS")
        case _ where key.hasPrefix("gtk-") || key.hasPrefix("linux-"):
            ConductorLocalization.text(zh: "跨平台", en: "Cross-platform")
        case _ where key.hasPrefix("quick-terminal-"):
            ConductorLocalization.text(zh: "Quick Terminal", en: "Quick Terminal")
        case _ where key.hasPrefix("adjust-"):
            ConductorLocalization.text(zh: "字格微调", en: "Metrics")
        default:
            ConductorLocalization.text(zh: "运行时", en: "Runtime")
        }
    }

    static func valueHint(for key: String) -> String {
        switch key {
        case _ where key.hasPrefix("cursor-color") || key.hasSuffix("foreground") || key.hasSuffix("background") || key.hasSuffix("color"):
            "#RRGGBB"
        case _ where key.hasPrefix("font-family"):
            "Menlo"
        case _ where key.hasPrefix("adjust-"):
            "+10%"
        case _ where key.hasSuffix("opacity") || key.hasSuffix("volume") || key == "minimum-contrast":
            "0.8"
        case _ where key.hasPrefix("background-image") || key.hasSuffix("path") || key == "config-file" || key == "custom-shader":
            "/path/to/file"
        case _ where key.contains("duration") || key.hasSuffix("after") || key.hasSuffix("timeout"):
            "1s"
        case _ where key.hasPrefix("macos-option-as-alt"):
            "left"
        case _ where key == "cursor-style":
            "block | bar | underline | block_hollow"
        case _ where key == "shell-integration-features":
            "no-cursor,sudo,title,ssh-env"
        case _ where key == "shell-integration":
            "detect"
        case _ where key.hasPrefix("clipboard-"):
            "allow"
        default:
            "true / false / value"
        }
    }

    private static let booleanKeys: Set<String> = [
        "alpha-blending", "font-synthetic-style", "selection-clear-on-typing",
        "selection-clear-on-copy", "cursor-style-blink", "cursor-click-to-move",
        "mouse-hide-while-typing", "scroll-to-bottom", "mouse-shift-capture",
        "mouse-reporting", "background-opacity-cells", "split-preserve-zoom",
        "link-url", "link-previews", "window-padding-balance", "window-vsync",
        "window-inherit-working-directory", "tab-inherit-working-directory",
        "split-inherit-working-directory", "window-inherit-font-size",
        "window-save-state", "window-step-resize", "window-show-tab-bar",
        "focus-follows-mouse", "clipboard-read", "clipboard-write",
        "clipboard-trim-trailing-spaces", "clipboard-paste-protection",
        "clipboard-paste-bracketed-safe", "title-report", "copy-on-select",
        "config-default-files", "confirm-close-surface",
        "quit-after-last-window-closed", "initial-window",
        "quick-terminal-autohide", "custom-shader-animation",
        "macos-non-native-fullscreen",
        "macos-titlebar-proxy-icon", "macos-window-shadow", "macos-hidden",
        "macos-auto-secure-input", "macos-secure-input-indication",
        "macos-applescript", "macos-shortcuts", "linux-cgroup",
        "linux-cgroup-hard-fail", "gtk-opengl-debug", "gtk-single-instance",
        "gtk-titlebar-hide-when-maximized", "gtk-wide-tabs",
        "bold-italic", "ssh-env",
        "clipboard-copy", "config-reload", "force-autohint", "vt-kam-allowed",
        "auto-update", "background-blur"
    ]

    private static let productSearchIndex: [String: GhosttyConfigSearchRecord] = {
        Dictionary(uniqueKeysWithValues: productGroups.map { group in
            let groupText = normalizedSearchText([group.title, group.subtitle, group.id].joined(separator: " "))
            let keyTextByKey = Dictionary(uniqueKeysWithValues: group.keys.map { key in
                (
                    key,
                    normalizedSearchText([
                        key,
                        displayTitle(for: key),
                        description(for: key),
                        groupTitle(for: key),
                        valueHint(for: key)
                    ].joined(separator: " "))
                )
            })
            return (group.id, GhosttyConfigSearchRecord(groupText: groupText, keyTextByKey: keyTextByKey))
        })
    }()

    private static func normalizedSearchText(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
    }
}
