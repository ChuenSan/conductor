import AppKit
import SwiftUI

enum TerminalTheme: String, CaseIterable, Codable, Identifiable {
    case codexDark
    case paperCanvas

    var id: String { rawValue }

    static var allCases: [TerminalTheme] {
        [.paperCanvas, .codexDark]
    }

    private static let legacyThemeMigrationMap: [String: TerminalTheme] = [
        "macOSDark": .codexDark,
        "slateDusk": .codexDark,
        "carbonMist": .codexDark,
        "blueHour": .codexDark,
        "stoneVeil": .codexDark,
        "harborFog": .codexDark,
        "clayAsh": .codexDark,
        "lichenMist": .codexDark,
        "midnightGlass": .codexDark,
        "microGlass": .codexDark,
        "tokyoNight": .codexDark,
        "forestLab": .codexDark,
        "obsidianGlass": .codexDark,
        "flexoki": .paperCanvas,
        "aurora": .paperCanvas,
        "graphite": .paperCanvas,
        "ember": .paperCanvas,
        "paperTrail": .paperCanvas,
        "nordicFrost": .paperCanvas,
        "solarDune": .paperCanvas,
        "porcelainWhite": .paperCanvas,
        "cloudGlass": .paperCanvas,
        "milkGlass": .paperCanvas,
        "pearlStudio": .paperCanvas,
        "opalGlass": .paperCanvas,
        "prismAir": .paperCanvas,
        "lavenderFlux": .paperCanvas,
        "mintGlass": .paperCanvas,
        "sunriseGradient": .paperCanvas,
        "skyGradient": .paperCanvas,
        "roseQuartz": .paperCanvas,
    ]

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        if let migrated = Self.legacyThemeMigrationMap[raw] {
            self = migrated
        } else if let value = Self(rawValue: raw) {
            self = value
        } else {
            self = .codexDark
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    var title: String {
        switch self {
        case .codexDark:
            ConductorLocalization.text(zh: "暗色", en: "Dark")
        case .paperCanvas:
            ConductorLocalization.text(zh: "浅色", en: "Light")
        }
    }

    var next: TerminalTheme {
        let themes = Self.allCases
        guard let index = themes.firstIndex(of: self) else { return .codexDark }
        return themes[(index + 1) % themes.count]
    }

    var usesDarkChrome: Bool {
        self == .codexDark
    }

    var chromeColorScheme: ColorScheme {
        usesDarkChrome ? .dark : .light
    }

    var terminalRaisedBackground: Color {
        Color(nsColor: usesDarkChrome ? .underPageBackgroundColor : .controlBackgroundColor)
    }

    var terminalChrome: Color {
        Color(nsColor: .controlBackgroundColor)
    }

    var terminalBackground: Color {
        switch self {
        case .codexDark:
            Color(red: 0.082, green: 0.084, blue: 0.090)
        case .paperCanvas:
            Color(red: 0.992, green: 0.992, blue: 0.990)
        }
    }

    var ghosttyTerminalBackgroundHex: String {
        switch self {
        case .codexDark:
            "#15161a"
        case .paperCanvas:
            "#fdfdfb"
        }
    }

    var floatingPanelBase: Color {
        Color(nsColor: .windowBackgroundColor).opacity(usesDarkChrome ? 0.94 : 0.96)
    }

    var floatingPanelWash: Color {
        Color.primary.opacity(usesDarkChrome ? 0.026 : 0.018)
    }

    var floatingControlFill: Color {
        Color.primary.opacity(usesDarkChrome ? ConductorTokens.Chrome.controlFillOpacityDark : ConductorTokens.Chrome.controlFillOpacity)
    }

    var floatingControlStrongFill: Color {
        Color.primary.opacity(usesDarkChrome ? ConductorTokens.Chrome.controlStrongFillOpacityDark : ConductorTokens.Chrome.controlStrongFillOpacity)
    }

    var floatingStroke: Color {
        ConductorTokens.Chrome.structuralSeparator(dark: usesDarkChrome)
    }

    var floatingSeparator: Color {
        floatingStroke.opacity(0.55)
    }

    var floatingEmphasis: Color {
        Color.accentColor
    }

    var floatingSelectedFill: Color {
        Color(nsColor: .unemphasizedSelectedContentBackgroundColor).opacity(usesDarkChrome ? 0.72 : 0.64)
    }

    var floatingHoverFill: Color {
        ConductorTokens.Chrome.hover(dark: usesDarkChrome)
    }

    var shellChromeText: Color {
        Color.primary
    }

    var shellChromeTextMuted: Color {
        Color.secondary
    }

    var terminalOuterStroke: Color {
        ConductorTokens.Chrome.structuralSeparator(dark: usesDarkChrome)
    }

    var accent: Color {
        Color.accentColor
    }

    var ghosttyConfig: String {
        switch self {
        case .codexDark:
            """
            palette = 0=#121318
            palette = 1=#d86868
            palette = 2=#7fb982
            palette = 3=#c6a85f
            palette = 4=#7ba1d8
            palette = 5=#aa8ac5
            palette = 6=#73b4bd
            palette = 7=#dadde3
            palette = 8=#626772
            palette = 9=#e37b7b
            palette = 10=#95cb98
            palette = 11=#d8bd78
            palette = 12=#93b7e8
            palette = 13=#bea0d6
            palette = 14=#8ccbd2
            palette = 15=#f0f1f3
            background = #15161a
            foreground = #e7e8eb
            cursor-color = #4c80db
            cursor-text = #15161a
            selection-background = #24324a
            selection-foreground = #f0f1f3
            """
        case .paperCanvas:
            """
            palette = 0=#1a1c20
            palette = 1=#b94747
            palette = 2=#4d7f52
            palette = 3=#8a6f2f
            palette = 4=#315f9f
            palette = 5=#77518e
            palette = 6=#407f88
            palette = 7=#e8e8e4
            palette = 8=#6f737a
            palette = 9=#c75a5a
            palette = 10=#5e965f
            palette = 11=#9a7f3f
            palette = 12=#426fb3
            palette = 13=#895fa0
            palette = 14=#4e929a
            palette = 15=#fdfdfb
            background = #fdfdfb
            foreground = #1b1d20
            cursor-color = #3f78d6
            cursor-text = #fdfdfb
            selection-background = #dce7f8
            selection-foreground = #15171a
            """
        }
    }
}
