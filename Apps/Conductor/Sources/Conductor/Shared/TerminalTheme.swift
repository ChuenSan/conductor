import SwiftUI

enum TerminalTheme: String, CaseIterable, Codable, Identifiable {
    case macOSDark
    case codexDark
    case flexoki
    case aurora
    case graphite
    case ember

    var id: String { rawValue }

    var title: String {
        switch self {
        case .macOSDark:
            "macOS Dark"
        case .codexDark:
            "Codex Dark"
        case .flexoki:
            "Flexoki"
        case .aurora:
            "Aurora"
        case .graphite:
            "Graphite"
        case .ember:
            "Ember"
        }
    }

    var next: TerminalTheme {
        let themes = Self.allCases
        guard let index = themes.firstIndex(of: self) else { return .codexDark }
        return themes[(index + 1) % themes.count]
    }

    var usesDarkChrome: Bool {
        switch self {
        case .macOSDark, .codexDark:
            true
        case .flexoki, .aurora, .graphite, .ember:
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
        case .flexoki:
            Color(red: 0.946, green: 0.928, blue: 0.880)
        case .aurora:
            Color(red: 0.902, green: 0.954, blue: 0.962)
        case .graphite:
            Color(red: 0.922, green: 0.930, blue: 0.942)
        case .ember:
            Color(red: 0.974, green: 0.918, blue: 0.858)
        }
    }

    var terminalChrome: Color {
        switch self {
        case .macOSDark:
            Color(red: 0.074, green: 0.076, blue: 0.084)
        case .codexDark:
            Color(red: 0.047, green: 0.071, blue: 0.106)
        case .flexoki:
            Color(red: 0.972, green: 0.952, blue: 0.904)
        case .aurora:
            Color(red: 0.932, green: 0.978, blue: 0.982)
        case .graphite:
            Color(red: 0.952, green: 0.958, blue: 0.966)
        case .ember:
            Color(red: 0.990, green: 0.942, blue: 0.888)
        }
    }

    var terminalBackground: Color {
        switch self {
        case .macOSDark:
            Color(red: 0.055, green: 0.057, blue: 0.063)
        case .codexDark:
            Color(red: 0.055, green: 0.058, blue: 0.070)
        case .flexoki:
            Color(red: 0.988, green: 0.968, blue: 0.920)
        case .aurora:
            Color(red: 0.956, green: 0.988, blue: 0.992)
        case .graphite:
            Color(red: 0.976, green: 0.980, blue: 0.986)
        case .ember:
            Color(red: 0.998, green: 0.956, blue: 0.910)
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
        }
    }

    var windowBackdropWash: Color {
        switch self {
        case .macOSDark:
            Color(red: 0.10, green: 0.32, blue: 0.58).opacity(0.08)
        case .codexDark:
            Color(red: 0.22, green: 0.40, blue: 0.72).opacity(0.080)
        case .flexoki:
            Color(red: 0.98, green: 0.74, blue: 0.34).opacity(0.15)
        case .aurora:
            Color(red: 0.18, green: 0.82, blue: 0.86).opacity(0.18)
        case .graphite:
            Color(red: 0.64, green: 0.68, blue: 0.75).opacity(0.16)
        case .ember:
            Color(red: 1.00, green: 0.38, blue: 0.15).opacity(0.17)
        }
    }

    var shellPanelBackground: Color {
        switch self {
        case .macOSDark:
            Color(red: 0.082, green: 0.084, blue: 0.092).opacity(0.98)
        case .codexDark:
            Color(red: 0.062, green: 0.071, blue: 0.090).opacity(0.98)
        case .flexoki:
            Color(red: 0.930, green: 0.900, blue: 0.835).opacity(0.90)
        case .aurora:
            Color(red: 0.862, green: 0.938, blue: 0.946).opacity(0.90)
        case .graphite:
            Color(red: 0.892, green: 0.902, blue: 0.916).opacity(0.90)
        case .ember:
            Color(red: 0.950, green: 0.872, blue: 0.800).opacity(0.90)
        }
    }

    var shellPanelStrong: Color {
        switch self {
        case .macOSDark:
            Color(red: 0.112, green: 0.116, blue: 0.126).opacity(0.96)
        case .codexDark:
            Color(red: 0.086, green: 0.100, blue: 0.124).opacity(0.96)
        case .flexoki:
            Color(red: 0.956, green: 0.924, blue: 0.862).opacity(0.94)
        case .aurora:
            Color(red: 0.894, green: 0.956, blue: 0.962).opacity(0.94)
        case .graphite:
            Color(red: 0.920, green: 0.928, blue: 0.940).opacity(0.94)
        case .ember:
            Color(red: 0.970, green: 0.898, blue: 0.830).opacity(0.94)
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
        case .flexoki:
            Color(red: 0.966, green: 0.940, blue: 0.884).opacity(0.965)
        case .aurora:
            Color(red: 0.910, green: 0.962, blue: 0.966).opacity(0.965)
        case .graphite:
            Color(red: 0.918, green: 0.924, blue: 0.936).opacity(0.965)
        case .ember:
            Color(red: 0.976, green: 0.920, blue: 0.858).opacity(0.965)
        }
    }

    var floatingPanelWash: Color {
        switch self {
        case .macOSDark:
            Color(red: 0.22, green: 0.25, blue: 0.30).opacity(0.035)
        case .codexDark:
            Color(red: 0.28, green: 0.36, blue: 0.52).opacity(0.040)
        case .flexoki:
            Color(red: 0.62, green: 0.52, blue: 0.38).opacity(0.050)
        case .aurora:
            Color(red: 0.44, green: 0.64, blue: 0.68).opacity(0.052)
        case .graphite:
            Color(red: 0.50, green: 0.54, blue: 0.62).opacity(0.050)
        case .ember:
            Color(red: 0.66, green: 0.46, blue: 0.36).opacity(0.052)
        }
    }

    var floatingControlFill: Color {
        switch self {
        case .macOSDark, .codexDark:
            Color.white.opacity(0.075)
        default:
            Color.white.opacity(0.50)
        }
    }

    var floatingControlStrongFill: Color {
        switch self {
        case .macOSDark, .codexDark:
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
        case .flexoki:
            Color(red: 0.42, green: 0.31, blue: 0.18).opacity(0.14)
        case .aurora:
            Color(red: 0.10, green: 0.34, blue: 0.38).opacity(0.14)
        case .graphite:
            Color(red: 0.20, green: 0.22, blue: 0.25).opacity(0.13)
        case .ember:
            Color(red: 0.48, green: 0.18, blue: 0.10).opacity(0.14)
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
        case .flexoki:
            Color(red: 0.52, green: 0.43, blue: 0.30)
        case .aurora:
            Color(red: 0.34, green: 0.48, blue: 0.52)
        case .graphite:
            Color(red: 0.43, green: 0.47, blue: 0.54)
        case .ember:
            Color(red: 0.56, green: 0.39, blue: 0.32)
        }
    }

    var floatingSelectedFill: Color {
        switch self {
        case .macOSDark, .codexDark:
            Color.white.opacity(0.090)
        default:
            Color.black.opacity(0.060)
        }
    }

    var floatingHoverFill: Color {
        switch self {
        case .macOSDark, .codexDark:
            Color.white.opacity(0.055)
        default:
            Color.black.opacity(0.038)
        }
    }

    var floatingSelectedStroke: Color {
        switch self {
        case .macOSDark, .codexDark:
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
        case .flexoki:
            Color(red: 0.42, green: 0.31, blue: 0.18).opacity(0.16)
        case .aurora:
            Color(red: 0.10, green: 0.36, blue: 0.42).opacity(0.16)
        case .graphite:
            Color(red: 0.22, green: 0.24, blue: 0.28).opacity(0.15)
        case .ember:
            Color(red: 0.50, green: 0.18, blue: 0.10).opacity(0.16)
        }
    }

    var shellSelectedFill: Color {
        switch self {
        case .macOSDark, .codexDark:
            floatingEmphasis.opacity(0.10)
        default:
            Color.black.opacity(0.090)
        }
    }

    var shellHoverFill: Color {
        switch self {
        case .macOSDark, .codexDark:
            floatingEmphasis.opacity(0.055)
        default:
            Color.black.opacity(0.060)
        }
    }

    var shellControlFill: Color {
        switch self {
        case .macOSDark, .codexDark:
            Color.white.opacity(0.070)
        default:
            Color.black.opacity(0.045)
        }
    }

    var shellControlRaisedFill: Color {
        shellPanelStrong.opacity(0.62)
    }

    var shellChromeText: Color {
        switch self {
        case .macOSDark, .codexDark:
            Color(red: 0.894, green: 0.918, blue: 0.953)
        case .flexoki:
            Color(red: 0.165, green: 0.135, blue: 0.095)
        case .aurora:
            Color(red: 0.075, green: 0.150, blue: 0.185)
        case .graphite:
            Color(red: 0.135, green: 0.150, blue: 0.175)
        case .ember:
            Color(red: 0.190, green: 0.105, blue: 0.075)
        }
    }

    var shellChromeTextMuted: Color {
        switch self {
        case .macOSDark, .codexDark:
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
        case .flexoki:
            Color(red: 0.18, green: 0.12, blue: 0.08).opacity(0.70)
        case .aurora:
            Color(red: 0.02, green: 0.15, blue: 0.20).opacity(0.72)
        case .graphite:
            Color.black.opacity(0.62)
        case .ember:
            Color(red: 0.24, green: 0.08, blue: 0.04).opacity(0.70)
        }
    }

    var accent: Color {
        switch self {
        case .macOSDark:
            Color(red: 0.240, green: 0.520, blue: 0.940)
        case .codexDark:
            Color(red: 0.43, green: 0.35, blue: 0.86)
        case .flexoki:
            Color(red: 0.75, green: 0.50, blue: 0.16)
        case .aurora:
            Color(red: 0.13, green: 0.70, blue: 0.76)
        case .graphite:
            Color(red: 0.43, green: 0.47, blue: 0.54)
        case .ember:
            Color(red: 0.95, green: 0.31, blue: 0.12)
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
        }
    }
}
