import SwiftUI

enum TerminalThemeDesignLanguage: String {
    case system
    case minimal
    case paper
    case fluid
    case studio
    case warm
    case glass
    case neon
    case editorial
    case frost
    case sunlit
    case botanical

    var title: String {
        switch self {
        case .system:
            "System"
        case .minimal:
            "Minimal"
        case .paper:
            "Paper"
        case .fluid:
            "Fluid"
        case .studio:
            "Studio"
        case .warm:
            "Warm"
        case .glass:
            "Glass"
        case .neon:
            "Neon"
        case .editorial:
            "Editorial"
        case .frost:
            "Frost"
        case .sunlit:
            "Sunlit"
        case .botanical:
            "Botanical"
        }
    }
}

enum TerminalTheme: String, CaseIterable, Codable, Identifiable {
    case macOSDark
    case codexDark
    case slateDusk
    case carbonMist
    case blueHour
    case flexoki
    case aurora
    case graphite
    case ember
    case midnightGlass
    case tokyoNight
    case paperTrail
    case nordicFrost
    case solarDune
    case forestLab

    var id: String { rawValue }

    var title: String {
        switch self {
        case .macOSDark:
            "macOS Dark"
        case .codexDark:
            "Codex Dark"
        case .slateDusk:
            "Slate Dusk"
        case .carbonMist:
            "Carbon Mist"
        case .blueHour:
            "Blue Hour"
        case .flexoki:
            "Flexoki"
        case .aurora:
            "Aurora"
        case .graphite:
            "Graphite"
        case .ember:
            "Ember"
        case .midnightGlass:
            "Midnight Glass"
        case .tokyoNight:
            "Tokyo Night"
        case .paperTrail:
            "Paper Trail"
        case .nordicFrost:
            "Nordic Frost"
        case .solarDune:
            "Solar Dune"
        case .forestLab:
            "Forest Lab"
        }
    }

    var designLanguage: TerminalThemeDesignLanguage {
        switch self {
        case .macOSDark:
            .system
        case .codexDark:
            .minimal
        case .slateDusk:
            .studio
        case .carbonMist:
            .minimal
        case .blueHour:
            .glass
        case .flexoki:
            .paper
        case .aurora:
            .fluid
        case .graphite:
            .studio
        case .ember:
            .warm
        case .midnightGlass:
            .glass
        case .tokyoNight:
            .neon
        case .paperTrail:
            .editorial
        case .nordicFrost:
            .frost
        case .solarDune:
            .sunlit
        case .forestLab:
            .botanical
        }
    }

    var themeDescription: String {
        switch self {
        case .macOSDark:
            "System dark chrome with familiar Mac contrast."
        case .codexDark:
            "Muted dark shell for long agent sessions."
        case .slateDusk:
            "Raised slate surfaces: dark, but not black."
        case .carbonMist:
            "Soft charcoal chrome with warmer mid-dark panels."
        case .blueHour:
            "Blue-gray evening shell with calmer terminal contrast."
        case .flexoki:
            "Ink-and-paper warmth with restrained terminal contrast."
        case .aurora:
            "Airy glass, cool panels, and soft cyan motion."
        case .graphite:
            "Neutral studio controls with precise gray layering."
        case .ember:
            "Warm command-room surfaces with orange focus."
        case .midnightGlass:
            "Deep translucent panes, glossy rails, and quiet blue focus."
        case .tokyoNight:
            "Dense night-mode chrome with neon status energy."
        case .paperTrail:
            "Editorial paper surface with ruled controls and ink accents."
        case .nordicFrost:
            "Frosted utility panels with crisp polar contrast."
        case .solarDune:
            "Sunlit sand panels with broad, calm terminal surfaces."
        case .forestLab:
            "Dark botanical workspace with green lab instrumentation."
        }
    }

    var next: TerminalTheme {
        let themes = Self.allCases
        guard let index = themes.firstIndex(of: self) else { return .codexDark }
        return themes[(index + 1) % themes.count]
    }

    var usesDarkChrome: Bool {
        switch self {
        case .macOSDark, .codexDark, .slateDusk, .carbonMist, .blueHour, .midnightGlass, .tokyoNight, .forestLab:
            true
        case .flexoki, .aurora, .graphite, .ember, .paperTrail, .nordicFrost, .solarDune:
            false
        }
    }

    var chromeColorScheme: ColorScheme {
        usesDarkChrome ? .dark : .light
    }

    var terminalRaisedBackground: Color {
        switch self {
        case .macOSDark:
            Color(red: 0.045, green: 0.047, blue: 0.052)
        case .codexDark:
            Color(red: 0.024, green: 0.035, blue: 0.052)
        case .slateDusk:
            Color(red: 0.120, green: 0.138, blue: 0.166)
        case .carbonMist:
            Color(red: 0.150, green: 0.145, blue: 0.138)
        case .blueHour:
            Color(red: 0.105, green: 0.132, blue: 0.172)
        case .flexoki:
            Color(red: 0.946, green: 0.928, blue: 0.880)
        case .aurora:
            Color(red: 0.902, green: 0.954, blue: 0.962)
        case .graphite:
            Color(red: 0.922, green: 0.930, blue: 0.942)
        case .ember:
            Color(red: 0.974, green: 0.918, blue: 0.858)
        case .midnightGlass:
            Color(red: 0.030, green: 0.045, blue: 0.070)
        case .tokyoNight:
            Color(red: 0.040, green: 0.043, blue: 0.092)
        case .paperTrail:
            Color(red: 0.970, green: 0.952, blue: 0.910)
        case .nordicFrost:
            Color(red: 0.898, green: 0.938, blue: 0.962)
        case .solarDune:
            Color(red: 0.970, green: 0.900, blue: 0.760)
        case .forestLab:
            Color(red: 0.035, green: 0.060, blue: 0.047)
        }
    }

    var terminalChrome: Color {
        switch self {
        case .macOSDark:
            Color(red: 0.074, green: 0.076, blue: 0.084)
        case .codexDark:
            Color(red: 0.047, green: 0.071, blue: 0.106)
        case .slateDusk:
            Color(red: 0.160, green: 0.178, blue: 0.214)
        case .carbonMist:
            Color(red: 0.188, green: 0.184, blue: 0.176)
        case .blueHour:
            Color(red: 0.142, green: 0.174, blue: 0.226)
        case .flexoki:
            Color(red: 0.972, green: 0.952, blue: 0.904)
        case .aurora:
            Color(red: 0.932, green: 0.978, blue: 0.982)
        case .graphite:
            Color(red: 0.952, green: 0.958, blue: 0.966)
        case .ember:
            Color(red: 0.990, green: 0.942, blue: 0.888)
        case .midnightGlass:
            Color(red: 0.052, green: 0.075, blue: 0.112)
        case .tokyoNight:
            Color(red: 0.060, green: 0.056, blue: 0.122)
        case .paperTrail:
            Color(red: 0.988, green: 0.974, blue: 0.940)
        case .nordicFrost:
            Color(red: 0.936, green: 0.966, blue: 0.984)
        case .solarDune:
            Color(red: 0.988, green: 0.936, blue: 0.822)
        case .forestLab:
            Color(red: 0.050, green: 0.085, blue: 0.066)
        }
    }

    var terminalBackground: Color {
        switch self {
        case .macOSDark:
            Color(red: 0.055, green: 0.057, blue: 0.063)
        case .codexDark:
            Color(red: 0.055, green: 0.058, blue: 0.070)
        case .slateDusk:
            Color(red: 0.112, green: 0.126, blue: 0.154)
        case .carbonMist:
            Color(red: 0.136, green: 0.132, blue: 0.126)
        case .blueHour:
            Color(red: 0.096, green: 0.122, blue: 0.160)
        case .flexoki:
            Color(red: 0.988, green: 0.968, blue: 0.920)
        case .aurora:
            Color(red: 0.956, green: 0.988, blue: 0.992)
        case .graphite:
            Color(red: 0.976, green: 0.980, blue: 0.986)
        case .ember:
            Color(red: 0.998, green: 0.956, blue: 0.910)
        case .midnightGlass:
            Color(red: 0.036, green: 0.046, blue: 0.070)
        case .tokyoNight:
            Color(red: 0.046, green: 0.044, blue: 0.090)
        case .paperTrail:
            Color(red: 0.996, green: 0.984, blue: 0.950)
        case .nordicFrost:
            Color(red: 0.966, green: 0.986, blue: 0.996)
        case .solarDune:
            Color(red: 1.000, green: 0.956, blue: 0.865)
        case .forestLab:
            Color(red: 0.030, green: 0.048, blue: 0.038)
        }
    }

    var ghosttyTerminalBackgroundHex: String {
        switch self {
        case .macOSDark:
            "#0e0f10"
        case .codexDark:
            "#0e0f12"
        case .slateDusk:
            "#1d2027"
        case .carbonMist:
            "#232220"
        case .blueHour:
            "#181f29"
        case .flexoki:
            "#fcf7eb"
        case .aurora:
            "#f4fcfd"
        case .graphite:
            "#f9fafb"
        case .ember:
            "#fff4e8"
        case .midnightGlass:
            "#090c12"
        case .tokyoNight:
            "#0c0b17"
        case .paperTrail:
            "#fefbf2"
        case .nordicFrost:
            "#f6fbfe"
        case .solarDune:
            "#fff4dd"
        case .forestLab:
            "#080c0a"
        }
    }

    var windowBackdropStops: [Color] {
        switch self {
        case .macOSDark:
            [
                Color(red: 0.102, green: 0.106, blue: 0.116),
                Color(red: 0.070, green: 0.073, blue: 0.082),
                Color(red: 0.042, green: 0.044, blue: 0.050)
            ]
        case .codexDark:
            [
                Color(red: 0.086, green: 0.096, blue: 0.116),
                Color(red: 0.060, green: 0.070, blue: 0.090),
                Color(red: 0.034, green: 0.040, blue: 0.054)
            ]
        case .slateDusk:
            [
                Color(red: 0.225, green: 0.245, blue: 0.285),
                Color(red: 0.160, green: 0.178, blue: 0.218),
                Color(red: 0.104, green: 0.116, blue: 0.146)
            ]
        case .carbonMist:
            [
                Color(red: 0.245, green: 0.235, blue: 0.220),
                Color(red: 0.182, green: 0.176, blue: 0.166),
                Color(red: 0.120, green: 0.116, blue: 0.110)
            ]
        case .blueHour:
            [
                Color(red: 0.180, green: 0.225, blue: 0.292),
                Color(red: 0.128, green: 0.158, blue: 0.210),
                Color(red: 0.074, green: 0.092, blue: 0.128)
            ]
        case .flexoki:
            [
                Color(red: 0.972, green: 0.952, blue: 0.904),
                Color(red: 0.932, green: 0.895, blue: 0.818),
                Color(red: 0.878, green: 0.832, blue: 0.735)
            ]
        case .aurora:
            [
                Color(red: 0.861, green: 0.945, blue: 0.953),
                Color(red: 0.760, green: 0.882, blue: 0.922),
                Color(red: 0.618, green: 0.717, blue: 0.879)
            ]
        case .graphite:
            [
                Color(red: 0.908, green: 0.918, blue: 0.930),
                Color(red: 0.820, green: 0.838, blue: 0.858),
                Color(red: 0.692, green: 0.712, blue: 0.735)
            ]
        case .ember:
            [
                Color(red: 0.988, green: 0.910, blue: 0.800),
                Color(red: 0.940, green: 0.742, blue: 0.584),
                Color(red: 0.746, green: 0.486, blue: 0.382)
            ]
        case .midnightGlass:
            [
                Color(red: 0.070, green: 0.090, blue: 0.135),
                Color(red: 0.035, green: 0.050, blue: 0.080),
                Color(red: 0.012, green: 0.018, blue: 0.030)
            ]
        case .tokyoNight:
            [
                Color(red: 0.105, green: 0.075, blue: 0.185),
                Color(red: 0.060, green: 0.055, blue: 0.120),
                Color(red: 0.025, green: 0.026, blue: 0.060)
            ]
        case .paperTrail:
            [
                Color(red: 0.992, green: 0.978, blue: 0.932),
                Color(red: 0.946, green: 0.918, blue: 0.852),
                Color(red: 0.850, green: 0.805, blue: 0.710)
            ]
        case .nordicFrost:
            [
                Color(red: 0.930, green: 0.964, blue: 0.986),
                Color(red: 0.796, green: 0.882, blue: 0.940),
                Color(red: 0.626, green: 0.732, blue: 0.810)
            ]
        case .solarDune:
            [
                Color(red: 0.996, green: 0.902, blue: 0.700),
                Color(red: 0.936, green: 0.760, blue: 0.498),
                Color(red: 0.702, green: 0.558, blue: 0.390)
            ]
        case .forestLab:
            [
                Color(red: 0.060, green: 0.116, blue: 0.086),
                Color(red: 0.034, green: 0.070, blue: 0.052),
                Color(red: 0.014, green: 0.030, blue: 0.024)
            ]
        }
    }

    var windowBackdropWash: Color {
        switch self {
        case .macOSDark:
            Color(red: 0.10, green: 0.32, blue: 0.58).opacity(0.08)
        case .codexDark:
            Color(red: 0.22, green: 0.40, blue: 0.72).opacity(0.080)
        case .slateDusk:
            Color(red: 0.50, green: 0.58, blue: 0.70).opacity(0.085)
        case .carbonMist:
            Color(red: 0.64, green: 0.55, blue: 0.44).opacity(0.080)
        case .blueHour:
            Color(red: 0.34, green: 0.58, blue: 0.86).opacity(0.095)
        case .flexoki:
            Color(red: 0.98, green: 0.74, blue: 0.34).opacity(0.15)
        case .aurora:
            Color(red: 0.18, green: 0.82, blue: 0.86).opacity(0.18)
        case .graphite:
            Color(red: 0.64, green: 0.68, blue: 0.75).opacity(0.16)
        case .ember:
            Color(red: 1.00, green: 0.38, blue: 0.15).opacity(0.17)
        case .midnightGlass:
            Color(red: 0.22, green: 0.52, blue: 0.95).opacity(0.14)
        case .tokyoNight:
            Color(red: 0.82, green: 0.20, blue: 0.98).opacity(0.18)
        case .paperTrail:
            Color(red: 0.54, green: 0.36, blue: 0.16).opacity(0.13)
        case .nordicFrost:
            Color(red: 0.34, green: 0.66, blue: 0.90).opacity(0.16)
        case .solarDune:
            Color(red: 0.98, green: 0.64, blue: 0.20).opacity(0.18)
        case .forestLab:
            Color(red: 0.14, green: 0.62, blue: 0.36).opacity(0.13)
        }
    }

    var shellPanelBackground: Color {
        switch self {
        case .macOSDark:
            Color(red: 0.082, green: 0.084, blue: 0.092).opacity(0.98)
        case .codexDark:
            Color(red: 0.062, green: 0.071, blue: 0.090).opacity(0.98)
        case .slateDusk:
            Color(red: 0.142, green: 0.156, blue: 0.184).opacity(0.965)
        case .carbonMist:
            Color(red: 0.168, green: 0.160, blue: 0.150).opacity(0.965)
        case .blueHour:
            Color(red: 0.120, green: 0.148, blue: 0.190).opacity(0.965)
        case .flexoki:
            Color(red: 0.930, green: 0.900, blue: 0.835).opacity(0.90)
        case .aurora:
            Color(red: 0.862, green: 0.938, blue: 0.946).opacity(0.90)
        case .graphite:
            Color(red: 0.892, green: 0.902, blue: 0.916).opacity(0.90)
        case .ember:
            Color(red: 0.950, green: 0.872, blue: 0.800).opacity(0.90)
        case .midnightGlass:
            Color(red: 0.070, green: 0.088, blue: 0.118).opacity(0.94)
        case .tokyoNight:
            Color(red: 0.070, green: 0.060, blue: 0.135).opacity(0.94)
        case .paperTrail:
            Color(red: 0.958, green: 0.930, blue: 0.868).opacity(0.92)
        case .nordicFrost:
            Color(red: 0.888, green: 0.938, blue: 0.964).opacity(0.92)
        case .solarDune:
            Color(red: 0.944, green: 0.834, blue: 0.650).opacity(0.90)
        case .forestLab:
            Color(red: 0.046, green: 0.080, blue: 0.062).opacity(0.94)
        }
    }

    var shellPanelStrong: Color {
        switch self {
        case .macOSDark:
            Color(red: 0.112, green: 0.116, blue: 0.126).opacity(0.96)
        case .codexDark:
            Color(red: 0.086, green: 0.100, blue: 0.124).opacity(0.96)
        case .slateDusk:
            Color(red: 0.180, green: 0.196, blue: 0.228).opacity(0.965)
        case .carbonMist:
            Color(red: 0.205, green: 0.196, blue: 0.184).opacity(0.965)
        case .blueHour:
            Color(red: 0.155, green: 0.188, blue: 0.238).opacity(0.965)
        case .flexoki:
            Color(red: 0.956, green: 0.924, blue: 0.862).opacity(0.94)
        case .aurora:
            Color(red: 0.894, green: 0.956, blue: 0.962).opacity(0.94)
        case .graphite:
            Color(red: 0.920, green: 0.928, blue: 0.940).opacity(0.94)
        case .ember:
            Color(red: 0.970, green: 0.898, blue: 0.830).opacity(0.94)
        case .midnightGlass:
            Color(red: 0.094, green: 0.118, blue: 0.158).opacity(0.94)
        case .tokyoNight:
            Color(red: 0.090, green: 0.075, blue: 0.170).opacity(0.94)
        case .paperTrail:
            Color(red: 0.986, green: 0.958, blue: 0.902).opacity(0.94)
        case .nordicFrost:
            Color(red: 0.924, green: 0.970, blue: 0.990).opacity(0.94)
        case .solarDune:
            Color(red: 0.972, green: 0.878, blue: 0.702).opacity(0.94)
        case .forestLab:
            Color(red: 0.062, green: 0.106, blue: 0.082).opacity(0.94)
        }
    }

    var settingsPanelBase: Color {
        floatingPanelBase
    }

    var settingsPanelWash: Color {
        floatingPanelWash
    }

    var settingsControlFill: Color {
        floatingControlFill
    }

    var settingsStroke: Color {
        floatingStroke
    }

    var floatingPanelBase: Color {
        switch self {
        case .macOSDark:
            Color(red: 0.118, green: 0.121, blue: 0.130).opacity(0.985)
        case .codexDark:
            Color(red: 0.106, green: 0.114, blue: 0.134).opacity(0.985)
        case .slateDusk:
            Color(red: 0.158, green: 0.172, blue: 0.202).opacity(0.980)
        case .carbonMist:
            Color(red: 0.184, green: 0.176, blue: 0.166).opacity(0.980)
        case .blueHour:
            Color(red: 0.138, green: 0.166, blue: 0.214).opacity(0.980)
        case .flexoki:
            Color(red: 0.966, green: 0.940, blue: 0.884).opacity(0.965)
        case .aurora:
            Color(red: 0.910, green: 0.962, blue: 0.966).opacity(0.965)
        case .graphite:
            Color(red: 0.918, green: 0.924, blue: 0.936).opacity(0.965)
        case .ember:
            Color(red: 0.976, green: 0.920, blue: 0.858).opacity(0.965)
        case .midnightGlass:
            Color(red: 0.090, green: 0.108, blue: 0.142).opacity(0.982)
        case .tokyoNight:
            Color(red: 0.088, green: 0.076, blue: 0.160).opacity(0.982)
        case .paperTrail:
            Color(red: 0.978, green: 0.952, blue: 0.902).opacity(0.966)
        case .nordicFrost:
            Color(red: 0.910, green: 0.962, blue: 0.984).opacity(0.966)
        case .solarDune:
            Color(red: 0.966, green: 0.866, blue: 0.688).opacity(0.966)
        case .forestLab:
            Color(red: 0.060, green: 0.094, blue: 0.074).opacity(0.982)
        }
    }

    var floatingPanelWash: Color {
        switch self {
        case .macOSDark:
            Color(red: 0.22, green: 0.25, blue: 0.30).opacity(0.035)
        case .codexDark:
            Color(red: 0.28, green: 0.36, blue: 0.52).opacity(0.040)
        case .slateDusk:
            Color(red: 0.50, green: 0.58, blue: 0.70).opacity(0.050)
        case .carbonMist:
            Color(red: 0.62, green: 0.54, blue: 0.44).opacity(0.048)
        case .blueHour:
            Color(red: 0.34, green: 0.54, blue: 0.80).opacity(0.054)
        case .flexoki:
            Color(red: 0.62, green: 0.52, blue: 0.38).opacity(0.050)
        case .aurora:
            Color(red: 0.44, green: 0.64, blue: 0.68).opacity(0.052)
        case .graphite:
            Color(red: 0.50, green: 0.54, blue: 0.62).opacity(0.050)
        case .ember:
            Color(red: 0.66, green: 0.46, blue: 0.36).opacity(0.052)
        case .midnightGlass:
            Color(red: 0.32, green: 0.50, blue: 0.78).opacity(0.050)
        case .tokyoNight:
            Color(red: 0.78, green: 0.28, blue: 0.92).opacity(0.056)
        case .paperTrail:
            Color(red: 0.56, green: 0.42, blue: 0.24).opacity(0.052)
        case .nordicFrost:
            Color(red: 0.42, green: 0.62, blue: 0.74).opacity(0.054)
        case .solarDune:
            Color(red: 0.76, green: 0.50, blue: 0.26).opacity(0.056)
        case .forestLab:
            Color(red: 0.24, green: 0.52, blue: 0.34).opacity(0.052)
        }
    }

    var floatingControlFill: Color {
        switch self {
        case .macOSDark, .codexDark, .slateDusk, .carbonMist, .blueHour, .midnightGlass, .tokyoNight, .forestLab:
            Color.white.opacity(0.075)
        default:
            Color.white.opacity(0.50)
        }
    }

    var floatingControlStrongFill: Color {
        switch self {
        case .macOSDark, .codexDark, .slateDusk, .carbonMist, .blueHour, .midnightGlass, .tokyoNight, .forestLab:
            Color.white.opacity(0.115)
        default:
            Color.white.opacity(0.68)
        }
    }

    var floatingStroke: Color {
        switch self {
        case .macOSDark:
            Color.white.opacity(0.105)
        case .codexDark:
            Color.white.opacity(0.105)
        case .slateDusk:
            Color.white.opacity(0.118)
        case .carbonMist:
            Color.white.opacity(0.112)
        case .blueHour:
            Color(red: 0.58, green: 0.74, blue: 1.0).opacity(0.135)
        case .flexoki:
            Color(red: 0.42, green: 0.31, blue: 0.18).opacity(0.14)
        case .aurora:
            Color(red: 0.10, green: 0.34, blue: 0.38).opacity(0.14)
        case .graphite:
            Color(red: 0.20, green: 0.22, blue: 0.25).opacity(0.13)
        case .ember:
            Color(red: 0.48, green: 0.18, blue: 0.10).opacity(0.14)
        case .midnightGlass:
            Color.white.opacity(0.130)
        case .tokyoNight:
            Color(red: 0.70, green: 0.55, blue: 1.0).opacity(0.16)
        case .paperTrail:
            Color(red: 0.38, green: 0.28, blue: 0.16).opacity(0.15)
        case .nordicFrost:
            Color(red: 0.12, green: 0.30, blue: 0.42).opacity(0.14)
        case .solarDune:
            Color(red: 0.46, green: 0.26, blue: 0.08).opacity(0.14)
        case .forestLab:
            Color(red: 0.42, green: 0.82, blue: 0.55).opacity(0.13)
        }
    }

    var floatingSeparator: Color {
        floatingStroke.opacity(0.78)
    }

    var floatingEmphasis: Color {
        switch self {
        case .macOSDark:
            Color(red: 0.48, green: 0.62, blue: 0.84)
        case .codexDark:
            Color(red: 0.42, green: 0.47, blue: 0.55)
        case .slateDusk:
            Color(red: 0.58, green: 0.66, blue: 0.78)
        case .carbonMist:
            Color(red: 0.70, green: 0.62, blue: 0.52)
        case .blueHour:
            Color(red: 0.46, green: 0.64, blue: 0.88)
        case .flexoki:
            Color(red: 0.52, green: 0.43, blue: 0.30)
        case .aurora:
            Color(red: 0.34, green: 0.48, blue: 0.52)
        case .graphite:
            Color(red: 0.43, green: 0.47, blue: 0.54)
        case .ember:
            Color(red: 0.56, green: 0.39, blue: 0.32)
        case .midnightGlass:
            Color(red: 0.48, green: 0.66, blue: 0.92)
        case .tokyoNight:
            Color(red: 0.92, green: 0.42, blue: 0.98)
        case .paperTrail:
            Color(red: 0.46, green: 0.34, blue: 0.20)
        case .nordicFrost:
            Color(red: 0.28, green: 0.52, blue: 0.66)
        case .solarDune:
            Color(red: 0.64, green: 0.42, blue: 0.18)
        case .forestLab:
            Color(red: 0.34, green: 0.68, blue: 0.42)
        }
    }

    var floatingSelectedFill: Color {
        switch self {
        case .macOSDark, .codexDark, .slateDusk, .carbonMist, .blueHour, .midnightGlass, .tokyoNight, .forestLab:
            Color.white.opacity(0.090)
        default:
            Color.black.opacity(0.060)
        }
    }

    var floatingHoverFill: Color {
        switch self {
        case .macOSDark, .codexDark, .slateDusk, .carbonMist, .blueHour, .midnightGlass, .tokyoNight, .forestLab:
            Color.white.opacity(0.055)
        default:
            Color.black.opacity(0.038)
        }
    }

    var floatingSelectedStroke: Color {
        switch self {
        case .macOSDark, .codexDark, .slateDusk, .carbonMist, .blueHour, .midnightGlass, .tokyoNight, .forestLab:
            Color.white.opacity(0.145)
        default:
            Color.black.opacity(0.135)
        }
    }

    var shellStroke: Color {
        switch self {
        case .macOSDark:
            Color.white.opacity(0.082)
        case .codexDark:
            Color.white.opacity(0.078)
        case .slateDusk:
            Color.white.opacity(0.098)
        case .carbonMist:
            Color.white.opacity(0.094)
        case .blueHour:
            Color(red: 0.58, green: 0.74, blue: 1.0).opacity(0.125)
        case .flexoki:
            Color(red: 0.42, green: 0.31, blue: 0.18).opacity(0.16)
        case .aurora:
            Color(red: 0.10, green: 0.36, blue: 0.42).opacity(0.16)
        case .graphite:
            Color(red: 0.22, green: 0.24, blue: 0.28).opacity(0.15)
        case .ember:
            Color(red: 0.50, green: 0.18, blue: 0.10).opacity(0.16)
        case .midnightGlass:
            Color.white.opacity(0.115)
        case .tokyoNight:
            Color(red: 0.75, green: 0.50, blue: 1.0).opacity(0.18)
        case .paperTrail:
            Color(red: 0.40, green: 0.30, blue: 0.18).opacity(0.18)
        case .nordicFrost:
            Color(red: 0.12, green: 0.32, blue: 0.44).opacity(0.16)
        case .solarDune:
            Color(red: 0.48, green: 0.28, blue: 0.10).opacity(0.16)
        case .forestLab:
            Color(red: 0.36, green: 0.72, blue: 0.46).opacity(0.16)
        }
    }

    var shellSelectedFill: Color {
        switch self {
        case .macOSDark, .codexDark, .slateDusk, .carbonMist, .blueHour, .midnightGlass, .tokyoNight, .forestLab:
            Color.white.opacity(0.085)
        default:
            Color.black.opacity(0.070)
        }
    }

    var shellHoverFill: Color {
        switch self {
        case .macOSDark, .codexDark, .slateDusk, .carbonMist, .blueHour, .midnightGlass, .tokyoNight, .forestLab:
            Color.white.opacity(0.055)
        default:
            Color.black.opacity(0.045)
        }
    }

    var shellControlFill: Color {
        switch self {
        case .macOSDark, .codexDark, .slateDusk, .carbonMist, .blueHour, .midnightGlass, .tokyoNight, .forestLab:
            Color.white.opacity(0.052)
        default:
            Color.black.opacity(0.038)
        }
    }

    var shellControlRaisedFill: Color {
        shellPanelStrong.opacity(0.62)
    }

    var shellChromeText: Color {
        switch self {
        case .macOSDark, .codexDark, .slateDusk, .carbonMist, .blueHour, .midnightGlass, .tokyoNight, .forestLab:
            Color(red: 0.894, green: 0.918, blue: 0.953)
        case .flexoki:
            Color(red: 0.165, green: 0.135, blue: 0.095)
        case .aurora:
            Color(red: 0.075, green: 0.150, blue: 0.185)
        case .graphite:
            Color(red: 0.135, green: 0.150, blue: 0.175)
        case .ember:
            Color(red: 0.190, green: 0.105, blue: 0.075)
        case .paperTrail:
            Color(red: 0.180, green: 0.145, blue: 0.095)
        case .nordicFrost:
            Color(red: 0.075, green: 0.135, blue: 0.170)
        case .solarDune:
            Color(red: 0.205, green: 0.128, blue: 0.060)
        }
    }

    var shellChromeTextMuted: Color {
        switch self {
        case .macOSDark, .codexDark, .slateDusk, .carbonMist, .blueHour, .midnightGlass, .tokyoNight, .forestLab:
            Color(red: 0.494, green: 0.537, blue: 0.612)
        default:
            shellChromeText.opacity(0.58)
        }
    }

    var terminalOuterStroke: Color {
        switch self {
        case .macOSDark:
            Color.white.opacity(0.120)
        case .codexDark:
            Color.white.opacity(0.110)
        case .slateDusk:
            Color.white.opacity(0.170)
        case .carbonMist:
            Color.white.opacity(0.155)
        case .blueHour:
            Color(red: 0.52, green: 0.70, blue: 1.0).opacity(0.260)
        case .flexoki:
            Color(red: 0.18, green: 0.12, blue: 0.08).opacity(0.70)
        case .aurora:
            Color(red: 0.02, green: 0.15, blue: 0.20).opacity(0.72)
        case .graphite:
            Color.black.opacity(0.62)
        case .ember:
            Color(red: 0.24, green: 0.08, blue: 0.04).opacity(0.70)
        case .midnightGlass:
            Color(red: 0.58, green: 0.72, blue: 1.0).opacity(0.38)
        case .tokyoNight:
            Color(red: 0.95, green: 0.45, blue: 1.0).opacity(0.48)
        case .paperTrail:
            Color(red: 0.32, green: 0.22, blue: 0.12).opacity(0.62)
        case .nordicFrost:
            Color(red: 0.04, green: 0.20, blue: 0.30).opacity(0.64)
        case .solarDune:
            Color(red: 0.36, green: 0.18, blue: 0.06).opacity(0.62)
        case .forestLab:
            Color(red: 0.38, green: 0.78, blue: 0.48).opacity(0.42)
        }
    }

    var accent: Color {
        switch self {
        case .macOSDark:
            Color(red: 0.240, green: 0.520, blue: 0.940)
        case .codexDark:
            Color(red: 0.43, green: 0.35, blue: 0.86)
        case .slateDusk:
            Color(red: 0.56, green: 0.65, blue: 0.78)
        case .carbonMist:
            Color(red: 0.72, green: 0.58, blue: 0.42)
        case .blueHour:
            Color(red: 0.42, green: 0.62, blue: 0.92)
        case .flexoki:
            Color(red: 0.75, green: 0.50, blue: 0.16)
        case .aurora:
            Color(red: 0.13, green: 0.70, blue: 0.76)
        case .graphite:
            Color(red: 0.43, green: 0.47, blue: 0.54)
        case .ember:
            Color(red: 0.95, green: 0.31, blue: 0.12)
        case .midnightGlass:
            Color(red: 0.38, green: 0.60, blue: 0.98)
        case .tokyoNight:
            Color(red: 0.95, green: 0.34, blue: 0.96)
        case .paperTrail:
            Color(red: 0.58, green: 0.36, blue: 0.16)
        case .nordicFrost:
            Color(red: 0.20, green: 0.56, blue: 0.74)
        case .solarDune:
            Color(red: 0.86, green: 0.48, blue: 0.12)
        case .forestLab:
            Color(red: 0.28, green: 0.74, blue: 0.38)
        }
    }

    var ghosttyConfig: String {
        switch self {
        case .macOSDark:
            """
            palette = 0=#1d1d1f
            palette = 1=#ff6961
            palette = 2=#63d297
            palette = 3=#ffd166
            palette = 4=#64a9ff
            palette = 5=#bf8cff
            palette = 6=#5ac8fa
            palette = 7=#d1d1d6
            palette = 8=#6e6e73
            palette = 9=#ff8a80
            palette = 10=#8ee6b2
            palette = 11=#ffe08a
            palette = 12=#8fc5ff
            palette = 13=#d3adff
            palette = 14=#8edcff
            palette = 15=#f5f5f7
            background = #111113
            foreground = #e8e8ed
            cursor-color = #0a84ff
            cursor-text = #111113
            selection-background = #2f3f58
            selection-foreground = #f5f5f7
            """
        case .codexDark:
            """
            palette = 0=#111318
            palette = 1=#f87171
            palette = 2=#86efac
            palette = 3=#fde68a
            palette = 4=#93c5fd
            palette = 5=#c4b5fd
            palette = 6=#67e8f9
            palette = 7=#e5e7eb
            palette = 8=#6b7280
            palette = 9=#fb7185
            palette = 10=#bbf7d0
            palette = 11=#fef3c7
            palette = 12=#bfdbfe
            palette = 13=#ddd6fe
            palette = 14=#a5f3fc
            palette = 15=#f8fafc
            background = #0e1016
            foreground = #e6e8ef
            cursor-color = #e6e8ef
            cursor-text = #0e1016
            selection-background = #343746
            selection-foreground = #ffffff
            """
        case .slateDusk:
            """
            palette = 0=#1b2028
            palette = 1=#f37f83
            palette = 2=#a6d189
            palette = 3=#e5c07b
            palette = 4=#8fb8f6
            palette = 5=#c9a7ff
            palette = 6=#8bd5ca
            palette = 7=#d9dee8
            palette = 8=#6f7888
            palette = 9=#ff9aa0
            palette = 10=#bce6a0
            palette = 11=#f0d18b
            palette = 12=#a9c9ff
            palette = 13=#d7bcff
            palette = 14=#a4e6dc
            palette = 15=#f3f6fb
            background = #202631
            foreground = #e4e8ef
            cursor-color = #9db4d2
            cursor-text = #202631
            selection-background = #3a4658
            selection-foreground = #f3f6fb
            """
        case .carbonMist:
            """
            palette = 0=#211f1d
            palette = 1=#e88373
            palette = 2=#a8c986
            palette = 3=#d8b66a
            palette = 4=#8da9ce
            palette = 5=#c7a0c8
            palette = 6=#86c9bd
            palette = 7=#ded8cf
            palette = 8=#766f68
            palette = 9=#f29a89
            palette = 10=#bddb9c
            palette = 11=#e3c47e
            palette = 12=#a5bbdc
            palette = 13=#d4b3d5
            palette = 14=#9fd9cf
            palette = 15=#f5efe6
            background = #242320
            foreground = #e9e2d8
            cursor-color = #c2a17e
            cursor-text = #242320
            selection-background = #4a4138
            selection-foreground = #f5efe6
            """
        case .blueHour:
            """
            palette = 0=#151d29
            palette = 1=#ef7f91
            palette = 2=#8fd0a7
            palette = 3=#e6c47a
            palette = 4=#82b5ff
            palette = 5=#bda9ff
            palette = 6=#7fd9e8
            palette = 7=#dce8f5
            palette = 8=#637287
            palette = 9=#ff9aae
            palette = 10=#a8e3bd
            palette = 11=#f0d28e
            palette = 12=#9dc6ff
            palette = 13=#cfc0ff
            palette = 14=#97e8f4
            palette = 15=#f3f9ff
            background = #182333
            foreground = #e2edf8
            cursor-color = #78aaff
            cursor-text = #182333
            selection-background = #314966
            selection-foreground = #f3f9ff
            """
        case .flexoki:
            """
            palette = 0=#100f0f
            palette = 1=#d14d41
            palette = 2=#879a39
            palette = 3=#d0a215
            palette = 4=#4385be
            palette = 5=#ce5d97
            palette = 6=#3aa99f
            palette = 7=#878580
            palette = 8=#575653
            palette = 9=#af3029
            palette = 10=#66800b
            palette = 11=#ad8301
            palette = 12=#205ea6
            palette = 13=#a02f6f
            palette = 14=#24837b
            palette = 15=#cecdc3
            background = #fffcf0
            foreground = #100f0f
            cursor-color = #205ea6
            cursor-text = #fffcf0
            selection-background = #d8e6f4
            selection-foreground = #100f0f
            """
        case .aurora:
            """
            palette = 0=#07131d
            palette = 1=#ff6b7a
            palette = 2=#78dcca
            palette = 3=#f6d365
            palette = 4=#7cc7ff
            palette = 5=#b6a4ff
            palette = 6=#4ddde0
            palette = 7=#d8eef7
            palette = 8=#536575
            palette = 9=#ff8793
            palette = 10=#9ff2df
            palette = 11=#ffe28a
            palette = 12=#a4d9ff
            palette = 13=#cabdff
            palette = 14=#7cf4f1
            palette = 15=#f4fbff
            background = #f4fdff
            foreground = #102331
            cursor-color = #128797
            cursor-text = #f4fdff
            selection-background = #c7ecf4
            selection-foreground = #102331
            """
        case .graphite:
            """
            palette = 0=#111318
            palette = 1=#e06c75
            palette = 2=#98c379
            palette = 3=#d7ba7d
            palette = 4=#7aa2f7
            palette = 5=#c678dd
            palette = 6=#56b6c2
            palette = 7=#d7dae0
            palette = 8=#5c6370
            palette = 9=#ff7b86
            palette = 10=#b5e890
            palette = 11=#f0cf8a
            palette = 12=#94bfff
            palette = 13=#d990ee
            palette = 14=#74d4df
            palette = 15=#f2f3f5
            background = #f8f9fb
            foreground = #1f2328
            cursor-color = #4f5662
            cursor-text = #f8f9fb
            selection-background = #dce3ed
            selection-foreground = #1f2328
            """
        case .ember:
            """
            palette = 0=#160d0a
            palette = 1=#ff5a3d
            palette = 2=#9bd66f
            palette = 3=#ffc857
            palette = 4=#79b8ff
            palette = 5=#ff8bd1
            palette = 6=#58d2c9
            palette = 7=#f1d7c6
            palette = 8=#72534a
            palette = 9=#ff765f
            palette = 10=#bdf18e
            palette = 11=#ffda7a
            palette = 12=#9dcbff
            palette = 13=#ffa7dc
            palette = 14=#7dece3
            palette = 15=#fff4eb
            background = #fff6ed
            foreground = #24110b
            cursor-color = #d94a23
            cursor-text = #fff6ed
            selection-background = #f4d4c4
            selection-foreground = #24110b
            """
        case .midnightGlass:
            """
            palette = 0=#0b1020
            palette = 1=#ff6b7a
            palette = 2=#72d2a8
            palette = 3=#f6d365
            palette = 4=#7fb5ff
            palette = 5=#b7a8ff
            palette = 6=#69e0f4
            palette = 7=#dce7ff
            palette = 8=#58637a
            palette = 9=#ff8793
            palette = 10=#98ecc6
            palette = 11=#ffe08c
            palette = 12=#9ec7ff
            palette = 13=#c9bcff
            palette = 14=#91f0ff
            palette = 15=#f6f9ff
            background = #090d16
            foreground = #e8f0ff
            cursor-color = #6fa4ff
            cursor-text = #090d16
            selection-background = #223554
            selection-foreground = #f6f9ff
            """
        case .tokyoNight:
            """
            palette = 0=#15161e
            palette = 1=#f7768e
            palette = 2=#9ece6a
            palette = 3=#e0af68
            palette = 4=#7aa2f7
            palette = 5=#bb9af7
            palette = 6=#7dcfff
            palette = 7=#c0caf5
            palette = 8=#565f89
            palette = 9=#ff899d
            palette = 10=#b4f9a8
            palette = 11=#f7c77f
            palette = 12=#9abaff
            palette = 13=#c7a9ff
            palette = 14=#9be5ff
            palette = 15=#dfe6ff
            background = #10121f
            foreground = #c0caf5
            cursor-color = #ff4df0
            cursor-text = #10121f
            selection-background = #2d3f76
            selection-foreground = #ffffff
            """
        case .paperTrail:
            """
            palette = 0=#1f1a14
            palette = 1=#a44a3f
            palette = 2=#66824a
            palette = 3=#b8892e
            palette = 4=#4f7198
            palette = 5=#8a5f7d
            palette = 6=#4f8582
            palette = 7=#ded4bf
            palette = 8=#746b5b
            palette = 9=#bd5a4d
            palette = 10=#78945a
            palette = 11=#c99a42
            palette = 12=#6384aa
            palette = 13=#9d7090
            palette = 14=#629895
            palette = 15=#fbf4df
            background = #fbf3df
            foreground = #241c13
            cursor-color = #8a5a24
            cursor-text = #fbf3df
            selection-background = #e4d5b6
            selection-foreground = #241c13
            """
        case .nordicFrost:
            """
            palette = 0=#2e3440
            palette = 1=#bf616a
            palette = 2=#a3be8c
            palette = 3=#ebcb8b
            palette = 4=#5e81ac
            palette = 5=#b48ead
            palette = 6=#88c0d0
            palette = 7=#e5e9f0
            palette = 8=#4c566a
            palette = 9=#d08770
            palette = 10=#b7d59c
            palette = 11=#f0d79b
            palette = 12=#81a1c1
            palette = 13=#c9a4c4
            palette = 14=#9bd4e2
            palette = 15=#eceff4
            background = #f5fbff
            foreground = #243142
            cursor-color = #2b6f8a
            cursor-text = #f5fbff
            selection-background = #d6e8f2
            selection-foreground = #243142
            """
        case .solarDune:
            """
            palette = 0=#22170d
            palette = 1=#c94f2d
            palette = 2=#7b8f3a
            palette = 3=#c18425
            palette = 4=#5377a8
            palette = 5=#9b6787
            palette = 6=#4d8f88
            palette = 7=#e8cfa5
            palette = 8=#80654a
            palette = 9=#dd6740
            palette = 10=#95a84f
            palette = 11=#d99d3b
            palette = 12=#6f91bd
            palette = 13=#ad7b99
            palette = 14=#62aaa1
            palette = 15=#fff0cf
            background = #fff0cf
            foreground = #26170b
            cursor-color = #b96019
            cursor-text = #fff0cf
            selection-background = #efd29b
            selection-foreground = #26170b
            """
        case .forestLab:
            """
            palette = 0=#08130d
            palette = 1=#e26d5c
            palette = 2=#74c476
            palette = 3=#d8b365
            palette = 4=#75aadb
            palette = 5=#b39ddb
            palette = 6=#69d2b7
            palette = 7=#d7eadc
            palette = 8=#4f6b59
            palette = 9=#ff8978
            palette = 10=#95e49a
            palette = 11=#e8c87b
            palette = 12=#98c6ef
            palette = 13=#c8b6ec
            palette = 14=#8be8cf
            palette = 15=#f0fff4
            background = #07100b
            foreground = #d8f1dd
            cursor-color = #4ade80
            cursor-text = #07100b
            selection-background = #173b27
            selection-foreground = #f0fff4
            """
        }
    }
}
