import CoreGraphics
import Foundation

enum AppearanceDensity: String, CaseIterable, Codable, Identifiable {
    case compact
    case standard
    case spacious

    var id: String { rawValue }

    var title: String {
        switch self {
        case .compact:
            ConductorLocalization.text(zh: "紧凑", en: "Compact")
        case .standard:
            ConductorLocalization.text(zh: "标准", en: "Standard")
        case .spacious:
            ConductorLocalization.text(zh: "宽松", en: "Spacious")
        }
    }

    var subtitle: String {
        switch self {
        case .compact:
            ConductorLocalization.text(zh: "更多终端面积", en: "More terminal space")
        case .standard:
            ConductorLocalization.text(zh: "平衡密度", en: "Balanced density")
        case .spacious:
            ConductorLocalization.text(zh: "更松弛的控件", en: "Roomier controls")
        }
    }

    var toolbarHeight: CGFloat {
        switch self {
        case .compact:
            40
        case .standard:
            42
        case .spacious:
            46
        }
    }

    var workspaceTabWidth: CGFloat {
        switch self {
        case .compact:
            126
        case .standard:
            140
        case .spacious:
            154
        }
    }

    var workspaceTabHeight: CGFloat {
        switch self {
        case .compact:
            26
        case .standard:
            28
        case .spacious:
            30
        }
    }

    var paneTabRailHeight: CGFloat {
        switch self {
        case .compact:
            27
        case .standard:
            29
        case .spacious:
            32
        }
    }

    var paneTabHeight: CGFloat {
        switch self {
        case .compact:
            22
        case .standard:
            24
        case .spacious:
            27
        }
    }

    var paneTabWidth: CGFloat {
        switch self {
        case .compact:
            120
        case .standard:
            132
        case .spacious:
            146
        }
    }

    var sidebarWidth: CGFloat {
        switch self {
        case .compact:
            214
        case .standard:
            230
        case .spacious:
            246
        }
    }
}

enum AppearanceFontScale: String, CaseIterable, Codable, Identifiable {
    case small
    case standard
    case large

    var id: String { rawValue }

    var title: String {
        switch self {
        case .small:
            ConductorLocalization.text(zh: "小", en: "Small")
        case .standard:
            ConductorLocalization.text(zh: "标准", en: "Standard")
        case .large:
            ConductorLocalization.text(zh: "大", en: "Large")
        }
    }

    var subtitle: String {
        switch self {
        case .small:
            ConductorLocalization.text(zh: "更密集", en: "Denser")
        case .standard:
            ConductorLocalization.text(zh: "默认字号", en: "Default size")
        case .large:
            ConductorLocalization.text(zh: "更易读", en: "Easier to read")
        }
    }

    var multiplier: CGFloat {
        switch self {
        case .small:
            0.94
        case .standard:
            1.0
        case .large:
            1.10
        }
    }

    func size(_ base: CGFloat) -> CGFloat {
        (base * multiplier).rounded(.toNearestOrAwayFromZero)
    }
}

enum AppearanceLanguage: String, CaseIterable, Codable, Identifiable {
    case system
    case simplifiedChinese
    case english

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system:
            ConductorLocalization.text(zh: "跟随系统", en: "System")
        case .simplifiedChinese:
            "简体中文"
        case .english:
            "English"
        }
    }

    var subtitle: String {
        switch self {
        case .system:
            ConductorLocalization.text(zh: "使用 macOS 首选语言", en: "Use macOS preferred language")
        case .simplifiedChinese:
            ConductorLocalization.text(zh: "中文界面", en: "Chinese UI")
        case .english:
            "English UI"
        }
    }

    var localeIdentifier: String? {
        switch self {
        case .system:
            nil
        case .simplifiedChinese:
            "zh-Hans"
        case .english:
            "en"
        }
    }

    var usageFeatureLanguageIdentifier: String {
        switch resolvedForDisplay {
        case .system:
            "en"
        case .simplifiedChinese:
            "zh-Hans"
        case .english:
            "en"
        }
    }
}

enum AppearanceFontFamily: String, CaseIterable, Codable, Identifiable {
    case system
    case rounded
    case serif
    case monospaced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system:
            ConductorLocalization.text(zh: "系统", en: "System")
        case .rounded:
            ConductorLocalization.text(zh: "圆体", en: "Rounded")
        case .serif:
            ConductorLocalization.text(zh: "衬线", en: "Serif")
        case .monospaced:
            ConductorLocalization.text(zh: "等宽", en: "Mono")
        }
    }

    var subtitle: String {
        switch self {
        case .system:
            ConductorLocalization.text(zh: "macOS 默认", en: "macOS default")
        case .rounded:
            ConductorLocalization.text(zh: "更柔和", en: "Softer UI")
        case .serif:
            ConductorLocalization.text(zh: "更有编辑感", en: "Editorial feel")
        case .monospaced:
            ConductorLocalization.text(zh: "代码感更强", en: "Code-like")
        }
    }
}

extension AppearanceLanguage {
    var locale: Locale {
        localeIdentifier.map(Locale.init(identifier:)) ?? .autoupdatingCurrent
    }

    var resolvedForDisplay: AppearanceLanguage {
        switch self {
        case .system:
            let identifier = Locale.preferredLanguages.first ?? Locale.autoupdatingCurrent.identifier
            return identifier.lowercased().hasPrefix("zh") ? .simplifiedChinese : .english
        case .simplifiedChinese, .english:
            return self
        }
    }
}

enum ConductorAppearanceRuntime {
    nonisolated(unsafe) static var fontFamily: AppearanceFontFamily = .system
    nonisolated(unsafe) static var language: AppearanceLanguage = .english

    static func apply(_ appearance: AppearancePreferences) {
        fontFamily = appearance.fontFamily
        language = appearance.language
    }
}

enum ConductorLocalization {
    static func text(zh: String, en: String) -> String {
        ConductorAppearanceRuntime.language.resolvedForDisplay == .english ? en : zh
    }
}

struct AppearancePreferences: Codable, Equatable {
    static let defaultTerminalFontSize: CGFloat = 15
    static let minTerminalFontSize: CGFloat = 10
    static let maxTerminalFontSize: CGFloat = 22

    var density: AppearanceDensity
    var fontScale: AppearanceFontScale
    var language: AppearanceLanguage
    var fontFamily: AppearanceFontFamily
    var terminalFontSize: CGFloat
    var terminalRenderer: TerminalRendererPreferences
    var reducedMotion: Bool
    var agentReplyNotifications: AgentReplyNotificationPreferences
    var keyboardShortcuts: KeyboardShortcutPreferences

    init(
        density: AppearanceDensity = .standard,
        fontScale: AppearanceFontScale = .standard,
        language: AppearanceLanguage = .english,
        fontFamily: AppearanceFontFamily = .system,
        terminalFontSize: CGFloat = Self.defaultTerminalFontSize,
        terminalRenderer: TerminalRendererPreferences = TerminalRendererPreferences(),
        reducedMotion: Bool = false,
        agentReplyNotifications: AgentReplyNotificationPreferences = AgentReplyNotificationPreferences(),
        keyboardShortcuts: KeyboardShortcutPreferences = KeyboardShortcutPreferences()
    ) {
        self.density = density
        self.fontScale = fontScale
        self.language = language
        self.fontFamily = fontFamily
        self.terminalFontSize = Self.clampedTerminalFontSize(terminalFontSize)
        self.terminalRenderer = terminalRenderer
        self.reducedMotion = reducedMotion
        self.agentReplyNotifications = agentReplyNotifications
        self.keyboardShortcuts = keyboardShortcuts
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.density = try container.decodeIfPresent(AppearanceDensity.self, forKey: .density) ?? .standard
        self.fontScale = try container.decodeIfPresent(AppearanceFontScale.self, forKey: .fontScale) ?? .standard
        self.language = try container.decodeIfPresent(AppearanceLanguage.self, forKey: .language) ?? .english
        self.fontFamily = try container.decodeIfPresent(AppearanceFontFamily.self, forKey: .fontFamily) ?? .system
        let decodedTerminalFontSize = try container.decodeIfPresent(CGFloat.self, forKey: .terminalFontSize) ?? Self.defaultTerminalFontSize
        self.terminalFontSize = Self.clampedTerminalFontSize(decodedTerminalFontSize)
        self.terminalRenderer = try container.decodeIfPresent(TerminalRendererPreferences.self, forKey: .terminalRenderer) ?? TerminalRendererPreferences()
        self.reducedMotion = try container.decodeIfPresent(Bool.self, forKey: .reducedMotion) ?? false
        self.agentReplyNotifications = try container.decodeIfPresent(AgentReplyNotificationPreferences.self, forKey: .agentReplyNotifications) ?? AgentReplyNotificationPreferences()
        self.keyboardShortcuts = try container.decodeIfPresent(KeyboardShortcutPreferences.self, forKey: .keyboardShortcuts) ?? KeyboardShortcutPreferences()
    }

    static func clampedTerminalFontSize(_ value: CGFloat) -> CGFloat {
        min(max(value, minTerminalFontSize), maxTerminalFontSize)
    }

    private enum CodingKeys: String, CodingKey {
        case density
        case fontScale
        case language
        case fontFamily
        case terminalFontSize
        case terminalRenderer
        case reducedMotion
        case agentReplyNotifications
        case keyboardShortcuts
    }
}
