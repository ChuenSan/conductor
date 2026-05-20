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

enum ChromeClarity: String, CaseIterable, Codable, Identifiable {
    case soft
    case balanced
    case crisp

    var id: String { rawValue }

    var title: String {
        switch self {
        case .soft:
            ConductorLocalization.text(zh: "柔和", en: "Soft")
        case .balanced:
            ConductorLocalization.text(zh: "标准", en: "Balanced")
        case .crisp:
            ConductorLocalization.text(zh: "清晰", en: "Crisp")
        }
    }

    var subtitle: String {
        switch self {
        case .soft:
            ConductorLocalization.text(zh: "弱边界", en: "Softer edges")
        case .balanced:
            ConductorLocalization.text(zh: "默认层级", en: "Default hierarchy")
        case .crisp:
            ConductorLocalization.text(zh: "更明确", en: "Clearer layers")
        }
    }

    var glassTintMultiplier: Double {
        switch self {
        case .soft:
            1.16
        case .balanced:
            1.0
        case .crisp:
            0.72
        }
    }

    var strokeMultiplier: Double {
        switch self {
        case .soft:
            0.66
        case .balanced:
            1.0
        case .crisp:
            1.0
        }
    }

    var accentFillMultiplier: Double {
        switch self {
        case .soft:
            0.78
        case .balanced:
            1.0
        case .crisp:
            1.08
        }
    }

    var highlightMultiplier: Double {
        switch self {
        case .soft:
            0.72
        case .balanced:
            1.0
        case .crisp:
            1.12
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
    nonisolated(unsafe) static var language: AppearanceLanguage = .system

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
    static let defaultTerminalFontSize: CGFloat = 13
    static let minTerminalFontSize: CGFloat = 10
    static let maxTerminalFontSize: CGFloat = 22

    var density: AppearanceDensity
    var chromeClarity: ChromeClarity
    var fontScale: AppearanceFontScale
    var language: AppearanceLanguage
    var fontFamily: AppearanceFontFamily
    var terminalFontSize: CGFloat
    var reducedMotion: Bool
    var agentNotifications: AgentNotificationPreferences

    init(
        density: AppearanceDensity = .standard,
        chromeClarity: ChromeClarity = .balanced,
        fontScale: AppearanceFontScale = .standard,
        language: AppearanceLanguage = .system,
        fontFamily: AppearanceFontFamily = .system,
        terminalFontSize: CGFloat = Self.defaultTerminalFontSize,
        reducedMotion: Bool = false,
        agentNotifications: AgentNotificationPreferences = AgentNotificationPreferences()
    ) {
        self.density = density
        self.chromeClarity = chromeClarity
        self.fontScale = fontScale
        self.language = language
        self.fontFamily = fontFamily
        self.terminalFontSize = Self.clampedTerminalFontSize(terminalFontSize)
        self.reducedMotion = reducedMotion
        self.agentNotifications = agentNotifications
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.density = try container.decodeIfPresent(AppearanceDensity.self, forKey: .density) ?? .standard
        self.chromeClarity = try container.decodeIfPresent(ChromeClarity.self, forKey: .chromeClarity) ?? .balanced
        self.fontScale = try container.decodeIfPresent(AppearanceFontScale.self, forKey: .fontScale) ?? .standard
        self.language = try container.decodeIfPresent(AppearanceLanguage.self, forKey: .language) ?? .system
        self.fontFamily = try container.decodeIfPresent(AppearanceFontFamily.self, forKey: .fontFamily) ?? .system
        let decodedTerminalFontSize = try container.decodeIfPresent(CGFloat.self, forKey: .terminalFontSize) ?? Self.defaultTerminalFontSize
        self.terminalFontSize = Self.clampedTerminalFontSize(decodedTerminalFontSize)
        self.reducedMotion = try container.decodeIfPresent(Bool.self, forKey: .reducedMotion) ?? false
        self.agentNotifications = try container.decodeIfPresent(AgentNotificationPreferences.self, forKey: .agentNotifications) ?? AgentNotificationPreferences()
    }

    static func clampedTerminalFontSize(_ value: CGFloat) -> CGFloat {
        min(max(value, minTerminalFontSize), maxTerminalFontSize)
    }

    private enum CodingKeys: String, CodingKey {
        case density
        case chromeClarity
        case fontScale
        case language
        case fontFamily
        case terminalFontSize
        case reducedMotion
        case agentNotifications
    }
}

struct AgentNotificationPreferences: Codable, Equatable {
    var codex: Bool
    var claudeCode: Bool

    init(codex: Bool = true, claudeCode: Bool = false) {
        self.codex = codex
        self.claudeCode = claudeCode
    }

    func isEnabled(for provider: AgentHookProvider) -> Bool {
        switch provider {
        case .codex:
            codex
        case .claudeCode:
            claudeCode
        }
    }

    func isEnabled(forAgentName agent: String) -> Bool {
        guard let provider = AgentHookProvider(cliName: agent) else { return false }
        return isEnabled(for: provider)
    }

    mutating func setEnabled(_ enabled: Bool, for provider: AgentHookProvider) {
        switch provider {
        case .codex:
            codex = enabled
        case .claudeCode:
            claudeCode = enabled
        }
    }
}
