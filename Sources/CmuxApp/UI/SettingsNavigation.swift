import SwiftUI

enum SettingsSectionID: String, CaseIterable, Identifiable {
    case appearance
    case terminal
    case ghostty
    case behavior
    case keybindings

    static let `default`: SettingsSectionID = .appearance

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appearance: "外观"
        case .terminal: "终端"
        case .ghostty: "高级"
        case .behavior: "行为"
        case .keybindings: "快捷键"
        }
    }

    var subtitle: String {
        switch self {
        case .appearance: "主题、字体、配色"
        case .terminal: "Shell 与会话"
        case .ghostty: "底层终端选项"
        case .behavior: "工作区默认行为"
        case .keybindings: "应用命令"
        }
    }

    var systemImage: String {
        switch self {
        case .appearance: "paintbrush"
        case .terminal: "terminal"
        case .ghostty: "slider.horizontal.3"
        case .behavior: "arrow.triangle.2.circlepath"
        case .keybindings: "keyboard"
        }
    }
}

struct CmuxGhosttyConfigGroup: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    let systemImage: String
    let keys: [String]

    var countTitle: String { "\(keys.count) 项" }
}

struct CmuxGhosttyConfigCopy: Equatable {
    let title: String
    let summary: String
}

enum CmuxGhosttyConfigControlKind {
    case boolean
    case choice([(label: String, value: String)])
    case color
    case filePath
    case fontFamily
    case integer(range: ClosedRange<Int>, step: Int)
    case percent(range: ClosedRange<Double>, defaultValue: Double, format: CmuxGhosttyPercentFormat)
    case decimal(range: ClosedRange<Double>, defaultValue: Double, step: Double)
    case text
}

enum CmuxGhosttyPercentFormat {
    case fraction
    case percentString
}

enum CmuxGhosttyConfigCatalog {
    static let knownKeySet = Set(productGroups.flatMap(\.keys))
    private static let localizedCopy: [String: CmuxGhosttyConfigCopy] = [
        "font-family": CmuxGhosttyConfigCopy(title: "字体", summary: "选择终端文字使用的等宽字体"),
        "font-size": CmuxGhosttyConfigCopy(title: "字号", summary: "调整终端文字大小"),
        "font-feature": CmuxGhosttyConfigCopy(title: "字体特性", summary: "开启或关闭字体连字等 OpenType 特性"),
        "adjust-cell-width": CmuxGhosttyConfigCopy(title: "字格宽度微调", summary: "细调每个字符占用的水平空间"),
        "adjust-cell-height": CmuxGhosttyConfigCopy(title: "字格高度微调", summary: "细调每行文字占用的垂直空间"),
        "adjust-font-baseline": CmuxGhosttyConfigCopy(title: "文字基线微调", summary: "上下移动文字，让字体看起来更居中"),
        "adjust-underline-position": CmuxGhosttyConfigCopy(title: "下划线位置", summary: "调整下划线离文字底部的距离"),
        "adjust-underline-thickness": CmuxGhosttyConfigCopy(title: "下划线粗细", summary: "调整下划线显示厚度"),
        "adjust-cursor-thickness": CmuxGhosttyConfigCopy(title: "光标粗细", summary: "调整竖线或下划线光标的厚度"),
        "adjust-cursor-height": CmuxGhosttyConfigCopy(title: "光标高度", summary: "调整光标在字格中的高度"),

        "cursor-style": CmuxGhosttyConfigCopy(title: "光标样式", summary: "选择块、空心块、竖线或下划线光标"),
        "cursor-style-blink": CmuxGhosttyConfigCopy(title: "光标闪烁", summary: "控制光标是否闪烁"),
        "cursor-color": CmuxGhosttyConfigCopy(title: "光标颜色", summary: "指定光标使用的颜色"),
        "cursor-opacity": CmuxGhosttyConfigCopy(title: "光标透明度", summary: "降低后光标更轻，100% 最醒目"),
        "cursor-text": CmuxGhosttyConfigCopy(title: "光标内文字颜色", summary: "光标覆盖文字时使用的文字颜色"),
        "cursor-click-to-move": CmuxGhosttyConfigCopy(title: "点击移动光标", summary: "允许鼠标点击把光标移动到目标位置"),

        "background-opacity": CmuxGhosttyConfigCopy(title: "背景不透明度", summary: "降低后可以透出窗口材质，100% 最清晰"),
        "background-blur": CmuxGhosttyConfigCopy(title: "背景模糊", summary: "透明背景下柔化后方内容"),
        "background-image": CmuxGhosttyConfigCopy(title: "背景图片", summary: "选择一张图片作为终端背景"),
        "background-image-opacity": CmuxGhosttyConfigCopy(title: "背景图片透明度", summary: "控制背景图片显示强度"),
        "background-image-fit": CmuxGhosttyConfigCopy(title: "背景图片填充", summary: "控制背景图片如何适配窗口"),
        "minimum-contrast": CmuxGhosttyConfigCopy(title: "最低对比度", summary: "提高文字与背景之间的可读性"),
        "selection-foreground": CmuxGhosttyConfigCopy(title: "选区文字颜色", summary: "被选中文字的前景色"),
        "selection-background": CmuxGhosttyConfigCopy(title: "选区背景颜色", summary: "文本选区的背景色"),
        "search-foreground": CmuxGhosttyConfigCopy(title: "搜索文字颜色", summary: "搜索命中文本的前景色"),
        "search-background": CmuxGhosttyConfigCopy(title: "搜索背景颜色", summary: "搜索命中文本的背景色"),
        "search-selected-foreground": CmuxGhosttyConfigCopy(title: "当前搜索文字颜色", summary: "当前搜索命中的文字颜色"),
        "search-selected-background": CmuxGhosttyConfigCopy(title: "当前搜索背景颜色", summary: "当前搜索命中的背景颜色"),

        "selection-clear-on-typing": CmuxGhosttyConfigCopy(title: "输入时清除选区", summary: "开始输入后自动取消当前选择"),
        "selection-clear-on-copy": CmuxGhosttyConfigCopy(title: "复制后清除选区", summary: "复制完成后自动取消当前选择"),
        "selection-word-chars": CmuxGhosttyConfigCopy(title: "单词选择字符", summary: "定义双击选择单词时包含哪些字符"),
        "copy-on-select": CmuxGhosttyConfigCopy(title: "选中即复制", summary: "选中文本后自动复制到剪贴板"),
        "mouse-hide-while-typing": CmuxGhosttyConfigCopy(title: "输入时隐藏鼠标", summary: "打字时暂时隐藏鼠标指针"),
        "mouse-reporting": CmuxGhosttyConfigCopy(title: "应用接收鼠标事件", summary: "允许终端程序接收鼠标点击和滚动"),
        "mouse-scroll-multiplier": CmuxGhosttyConfigCopy(title: "滚轮速度", summary: "放大或降低鼠标滚动速度"),
        "link-url": CmuxGhosttyConfigCopy(title: "识别链接", summary: "自动识别终端里的网址"),
        "link-previews": CmuxGhosttyConfigCopy(title: "链接预览", summary: "悬停链接时显示预览信息"),

        "clipboard-read": CmuxGhosttyConfigCopy(title: "允许读取剪贴板", summary: "允许终端程序读取剪贴板内容"),
        "clipboard-write": CmuxGhosttyConfigCopy(title: "允许写入剪贴板", summary: "允许终端程序写入剪贴板"),
        "clipboard-trim-trailing-spaces": CmuxGhosttyConfigCopy(title: "复制时去掉行尾空格", summary: "复制文本时自动清理每行末尾空格"),
        "clipboard-paste-protection": CmuxGhosttyConfigCopy(title: "粘贴保护", summary: "粘贴可疑多行内容时进行保护"),
        "clipboard-paste-bracketed-safe": CmuxGhosttyConfigCopy(title: "安全括号粘贴", summary: "使用更安全的括号粘贴模式"),

        "shell-integration": CmuxGhosttyConfigCopy(title: "Shell 集成", summary: "增强目录、命令状态等 Shell 交互能力"),
        "initial-command": CmuxGhosttyConfigCopy(title: "启动命令", summary: "打开终端后自动执行的命令"),
        "working-directory": CmuxGhosttyConfigCopy(title: "默认工作目录", summary: "新终端启动时进入的目录"),
        "scrollback-limit": CmuxGhosttyConfigCopy(title: "历史回滚行数", summary: "控制终端保留多少行历史输出"),

        "key-remap": CmuxGhosttyConfigCopy(title: "终端键位映射", summary: "改写发送给终端程序的按键"),
        "macos-option-as-alt": CmuxGhosttyConfigCopy(title: "Option 作为 Alt", summary: "指定哪些 Option 键按 Alt 发送")
    ]

    static let booleanKeys: Set<String> = [
        "cursor-style-blink", "cursor-click-to-move", "selection-clear-on-typing",
        "selection-clear-on-copy", "copy-on-select", "mouse-hide-while-typing",
        "mouse-reporting", "link-url", "link-previews", "clipboard-read",
        "clipboard-write", "clipboard-trim-trailing-spaces", "clipboard-paste-protection",
        "clipboard-paste-bracketed-safe", "shell-integration"
    ]

    static let choiceOptions: [String: [(label: String, value: String)]] = [
        "cursor-style": [("块", "block"), ("空心块", "block_hollow"), ("竖线", "bar"), ("下划线", "underline")],
        "background-image-fit": [("包含", "contain"), ("覆盖", "cover"), ("拉伸", "stretch"), ("不缩放", "none")],
        "macos-option-as-alt": [("左", "left"), ("右", "right"), ("两侧", "true"), ("关闭", "false")]
    ]

    static func copy(for key: String) -> CmuxGhosttyConfigCopy {
        localizedCopy[key] ?? CmuxGhosttyConfigCopy(title: "高级选项", summary: "底层终端配置")
    }

    static func controlKind(for key: String) -> CmuxGhosttyConfigControlKind {
        if let options = choiceOptions[key] { return .choice(options) }
        if booleanKeys.contains(key) { return .boolean }
        if key == "font-family" { return .fontFamily }
        if key == "background-image" || key == "working-directory" { return .filePath }
        if key.hasSuffix("-color") ||
            key.hasSuffix("-foreground") ||
            key.hasSuffix("-background") ||
            key == "cursor-text" {
            return .color
        }
        if key == "font-size" { return .integer(range: 8...36, step: 1) }
        if key == "scrollback-limit" { return .integer(range: 0...1_000_000, step: 1000) }
        if key == "minimum-contrast" { return .integer(range: 1...21, step: 1) }
        if key.hasPrefix("adjust-") {
            return .percent(range: -40...40, defaultValue: 0, format: .percentString)
        }
        if key == "background-opacity" ||
            key == "background-image-opacity" ||
            key == "cursor-opacity" {
            return .percent(range: 0...1, defaultValue: 1, format: .fraction)
        }
        if key == "mouse-scroll-multiplier" {
            return .decimal(range: 0.1...5, defaultValue: 1, step: 0.1)
        }
        return .text
    }

    static let productGroups: [CmuxGhosttyConfigGroup] = [
        CmuxGhosttyConfigGroup(
            id: "typography",
            title: "字体与字格",
            subtitle: "字体、字号、行高、字格和下划线微调",
            systemImage: "textformat.size",
            keys: [
                "font-family", "font-size", "font-feature",
                "adjust-cell-width", "adjust-cell-height",
                "adjust-font-baseline", "adjust-underline-position",
                "adjust-underline-thickness", "adjust-cursor-thickness",
                "adjust-cursor-height"
            ]
        ),
        CmuxGhosttyConfigGroup(
            id: "cursor",
            title: "光标",
            subtitle: "形状、颜色、闪烁、透明度和点击移动",
            systemImage: "cursorarrow",
            keys: [
                "cursor-style", "cursor-style-blink", "cursor-color",
                "cursor-opacity", "cursor-text", "cursor-click-to-move"
            ]
        ),
        CmuxGhosttyConfigGroup(
            id: "background",
            title: "背景与颜色",
            subtitle: "背景、透明度、选区、搜索高亮和对比度",
            systemImage: "paintpalette",
            keys: [
                "background-opacity", "background-blur", "background-image",
                "background-image-opacity", "background-image-fit",
                "minimum-contrast", "selection-foreground", "selection-background",
                "search-foreground", "search-background", "search-selected-foreground",
                "search-selected-background"
            ]
        ),
        CmuxGhosttyConfigGroup(
            id: "selection_mouse",
            title: "选择、鼠标与链接",
            subtitle: "选区清理、复制选择、滚轮速度和链接",
            systemImage: "cursorarrow.click",
            keys: [
                "selection-clear-on-typing", "selection-clear-on-copy",
                "selection-word-chars", "copy-on-select", "mouse-hide-while-typing",
                "mouse-reporting", "mouse-scroll-multiplier", "link-url", "link-previews"
            ]
        ),
        CmuxGhosttyConfigGroup(
            id: "clipboard",
            title: "剪贴板与粘贴",
            subtitle: "剪贴板读写、尾随空格和粘贴保护",
            systemImage: "doc.on.clipboard",
            keys: [
                "clipboard-read", "clipboard-write", "clipboard-trim-trailing-spaces",
                "clipboard-paste-protection", "clipboard-paste-bracketed-safe"
            ]
        ),
        CmuxGhosttyConfigGroup(
            id: "shell",
            title: "Shell 与启动",
            subtitle: "启动命令、默认目录、Shell 集成和历史容量",
            systemImage: "terminal",
            keys: [
                "shell-integration", "initial-command", "working-directory", "scrollback-limit"
            ]
        ),
        CmuxGhosttyConfigGroup(
            id: "keyboard",
            title: "键盘",
            subtitle: "终端输入层键位，不含应用命令快捷键",
            systemImage: "keyboard",
            keys: [
                "key-remap", "macos-option-as-alt"
            ]
        )
    ]
}
