import SwiftUI

enum TerminalTheme: String, CaseIterable, Identifiable {
    case flexoki
    case poimandres
    case xcode

    var id: String { rawValue }

    var title: String {
        switch self {
        case .flexoki: "Flexoki"
        case .poimandres: "Poimandres"
        case .xcode: "Xcode"
        }
    }

    var shellBackground: Color {
        switch self {
        case .flexoki: Color(red: 0.07, green: 0.07, blue: 0.06)
        case .poimandres: Color(red: 0.08, green: 0.08, blue: 0.12)
        case .xcode: Color(red: 0.16, green: 0.17, blue: 0.21)
        }
    }

    var sidebarBackground: Color {
        switch self {
        case .flexoki: Color(red: 0.12, green: 0.12, blue: 0.11)
        case .poimandres: Color(red: 0.10, green: 0.11, blue: 0.15)
        case .xcode: Color(red: 0.20, green: 0.21, blue: 0.25)
        }
    }

    var accent: Color {
        switch self {
        case .flexoki: Color(red: 0.83, green: 0.63, blue: 0.18)
        case .poimandres: Color(red: 0.36, green: 0.89, blue: 0.78)
        case .xcode: Color(red: 0.53, green: 0.52, blue: 0.77)
        }
    }

    var ghosttyConfig: String {
        switch self {
        case .flexoki:
            return """
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
        case .poimandres:
            return """
            palette = 0=#16161e
            palette = 1=#d0679d
            palette = 2=#5de4c7
            palette = 3=#fffac2
            palette = 4=#89ddff
            palette = 5=#fcc5e9
            palette = 6=#add7ff
            palette = 7=#ffffff
            palette = 8=#a6accd
            palette = 9=#d0679d
            palette = 10=#5de4c7
            palette = 11=#fffac2
            palette = 12=#add7ff
            palette = 13=#fae4fc
            palette = 14=#89ddff
            palette = 15=#ffffff
            background = #16161e
            foreground = #a6accd
            cursor-color = #ffffff
            cursor-text = #16161e
            selection-background = #a6accd
            selection-foreground = #ffffff
            """
        case .xcode:
            return """
            palette = 0=#494d5c
            palette = 1=#bb383a
            palette = 2=#94c66e
            palette = 3=#d28e5d
            palette = 4=#8884c5
            palette = 5=#b73999
            palette = 6=#00aba4
            palette = 7=#e7e8eb
            palette = 8=#7f869e
            palette = 9=#bb383a
            palette = 10=#94c66e
            palette = 11=#d28e5d
            palette = 12=#8884c5
            palette = 13=#b73999
            palette = 14=#00aba4
            palette = 15=#e7e8eb
            background = #292c36
            foreground = #e7e8eb
            cursor-color = #e7e8eb
            cursor-text = #292c36
            selection-background = #494d5c
            selection-foreground = #e7e8eb
            """
        }
    }
}
