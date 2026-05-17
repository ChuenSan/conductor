import SwiftUI

enum TerminalTheme: String, CaseIterable, Codable, Identifiable {
    case codexDark
    case flexoki
    case aurora
    case graphite
    case ember

    var id: String { rawValue }

    var title: String {
        switch self {
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

    var terminalRaisedBackground: Color {
        switch self {
        case .codexDark:
            Color(red: 0.024, green: 0.035, blue: 0.052)
        case .flexoki:
            Color(red: 0.055, green: 0.047, blue: 0.040)
        case .aurora:
            Color(red: 0.014, green: 0.050, blue: 0.076)
        case .graphite:
            Color(red: 0.044, green: 0.046, blue: 0.052)
        case .ember:
            Color(red: 0.069, green: 0.031, blue: 0.018)
        }
    }

    var terminalChrome: Color {
        switch self {
        case .codexDark:
            Color(red: 0.047, green: 0.071, blue: 0.106)
        case .flexoki:
            Color(red: 0.090, green: 0.071, blue: 0.055)
        case .aurora:
            Color(red: 0.026, green: 0.083, blue: 0.120)
        case .graphite:
            Color(red: 0.075, green: 0.078, blue: 0.086)
        case .ember:
            Color(red: 0.114, green: 0.052, blue: 0.030)
        }
    }

    var terminalBackground: Color {
        switch self {
        case .codexDark:
            Color(red: 0.055, green: 0.058, blue: 0.070)
        case .flexoki:
            Color(red: 0.063, green: 0.059, blue: 0.059)
        case .aurora:
            Color(red: 0.024, green: 0.070, blue: 0.105)
        case .graphite:
            Color(red: 0.061, green: 0.064, blue: 0.071)
        case .ember:
            Color(red: 0.082, green: 0.042, blue: 0.029)
        }
    }

    var windowBackdropStops: [Color] {
        switch self {
        case .codexDark:
            [
                Color(red: 0.925, green: 0.944, blue: 0.968),
                Color(red: 0.875, green: 0.910, blue: 0.948),
                Color(red: 0.824, green: 0.862, blue: 0.910)
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
        case .codexDark:
            Color(red: 0.80, green: 0.87, blue: 0.98).opacity(0.16)
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
        case .codexDark:
            Color(red: 0.945, green: 0.960, blue: 0.982).opacity(0.74)
        case .flexoki:
            Color(red: 0.968, green: 0.940, blue: 0.875).opacity(0.76)
        case .aurora:
            Color(red: 0.900, green: 0.966, blue: 0.972).opacity(0.74)
        case .graphite:
            Color(red: 0.920, green: 0.928, blue: 0.940).opacity(0.76)
        case .ember:
            Color(red: 0.984, green: 0.912, blue: 0.838).opacity(0.74)
        }
    }

    var shellPanelStrong: Color {
        switch self {
        case .codexDark:
            Color(red: 0.982, green: 0.988, blue: 0.996).opacity(0.84)
        case .flexoki:
            Color(red: 0.988, green: 0.960, blue: 0.900).opacity(0.84)
        case .aurora:
            Color(red: 0.942, green: 0.990, blue: 0.994).opacity(0.82)
        case .graphite:
            Color(red: 0.972, green: 0.976, blue: 0.982).opacity(0.82)
        case .ember:
            Color(red: 0.996, green: 0.936, blue: 0.872).opacity(0.82)
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
        case .codexDark:
            Color(red: 0.945, green: 0.960, blue: 0.982).opacity(0.78)
        case .flexoki:
            Color(red: 0.968, green: 0.940, blue: 0.875).opacity(0.78)
        case .aurora:
            Color(red: 0.900, green: 0.966, blue: 0.972).opacity(0.78)
        case .graphite:
            Color(red: 0.920, green: 0.928, blue: 0.940).opacity(0.78)
        case .ember:
            Color(red: 0.984, green: 0.912, blue: 0.838).opacity(0.78)
        }
    }

    var floatingPanelWash: Color {
        switch self {
        case .codexDark:
            Color(red: 0.62, green: 0.68, blue: 0.76).opacity(0.045)
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
        case .codexDark:
            Color.white.opacity(0.20)
        case .flexoki:
            Color(red: 1.0, green: 0.972, blue: 0.910).opacity(0.32)
        case .aurora:
            Color(red: 0.940, green: 1.0, blue: 1.0).opacity(0.26)
        case .graphite:
            Color.white.opacity(0.22)
        case .ember:
            Color(red: 1.0, green: 0.940, blue: 0.884).opacity(0.30)
        }
    }

    var floatingControlStrongFill: Color {
        switch self {
        case .codexDark:
            Color.white.opacity(0.30)
        case .flexoki:
            Color(red: 1.0, green: 0.972, blue: 0.910).opacity(0.44)
        case .aurora:
            Color(red: 0.940, green: 1.0, blue: 1.0).opacity(0.36)
        case .graphite:
            Color.white.opacity(0.32)
        case .ember:
            Color(red: 1.0, green: 0.940, blue: 0.884).opacity(0.42)
        }
    }

    var floatingStroke: Color {
        switch self {
        case .codexDark:
            Color(red: 0.20, green: 0.23, blue: 0.30).opacity(0.13)
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
        floatingEmphasis.opacity(0.13)
    }

    var floatingHoverFill: Color {
        floatingEmphasis.opacity(0.070)
    }

    var floatingSelectedStroke: Color {
        floatingEmphasis.opacity(0.34)
    }

    var shellStroke: Color {
        switch self {
        case .codexDark:
            Color(red: 0.18, green: 0.22, blue: 0.32).opacity(0.15)
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
        floatingEmphasis.opacity(0.10)
    }

    var shellHoverFill: Color {
        floatingEmphasis.opacity(0.055)
    }

    var shellControlFill: Color {
        Color.black.opacity(0.045)
    }

    var shellControlRaisedFill: Color {
        shellPanelStrong.opacity(0.62)
    }

    var terminalOuterStroke: Color {
        switch self {
        case .codexDark:
            Color.black.opacity(0.68)
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
            background = #100f0f
            foreground = #cecdc3
            cursor-color = #cecdc3
            cursor-text = #100f0f
            selection-background = #403e3c
            selection-foreground = #cecdc3
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
            background = #06121c
            foreground = #d9edf5
            cursor-color = #9ff2df
            cursor-text = #06121c
            selection-background = #17394a
            selection-foreground = #f4fbff
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
            background = #111318
            foreground = #e3e5e8
            cursor-color = #d7dae0
            cursor-text = #111318
            selection-background = #30343b
            selection-foreground = #f2f3f5
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
            background = #160d0a
            foreground = #f4dfd0
            cursor-color = #ffb38a
            cursor-text = #160d0a
            selection-background = #4c2419
            selection-foreground = #fff4eb
            """
        }
    }
}
