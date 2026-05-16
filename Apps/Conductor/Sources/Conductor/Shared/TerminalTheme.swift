import SwiftUI

enum TerminalTheme: String, CaseIterable, Codable, Identifiable {
    case codexDark
    case flexoki

    var id: String { rawValue }

    var title: String {
        switch self {
        case .codexDark:
            "Codex Dark"
        case .flexoki:
            "Flexoki"
        }
    }

    var terminalBackground: Color {
        switch self {
        case .codexDark:
            Color(red: 0.055, green: 0.058, blue: 0.070)
        case .flexoki:
            Color(red: 0.063, green: 0.059, blue: 0.059)
        }
    }

    var accent: Color {
        switch self {
        case .codexDark:
            Color(red: 0.43, green: 0.35, blue: 0.86)
        case .flexoki:
            Color(red: 0.75, green: 0.50, blue: 0.16)
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
        }
    }
}
