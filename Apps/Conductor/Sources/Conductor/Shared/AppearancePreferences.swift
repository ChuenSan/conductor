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
            "紧凑"
        case .standard:
            "标准"
        case .spacious:
            "宽松"
        }
    }

    var subtitle: String {
        switch self {
        case .compact:
            "更多终端面积"
        case .standard:
            "平衡密度"
        case .spacious:
            "更松弛的控件"
        }
    }

    var toolbarHeight: CGFloat {
        switch self {
        case .compact:
            31
        case .standard:
            34
        case .spacious:
            38
        }
    }

    var workspaceTabWidth: CGFloat {
        switch self {
        case .compact:
            118
        case .standard:
            128
        case .spacious:
            140
        }
    }

    var workspaceTabHeight: CGFloat {
        switch self {
        case .compact:
            21
        case .standard:
            23
        case .spacious:
            25
        }
    }

    var paneTabRailHeight: CGFloat {
        switch self {
        case .compact:
            24
        case .standard:
            26
        case .spacious:
            29
        }
    }

    var paneTabHeight: CGFloat {
        switch self {
        case .compact:
            19
        case .standard:
            21
        case .spacious:
            23
        }
    }

    var paneTabWidth: CGFloat {
        switch self {
        case .compact:
            108
        case .standard:
            118
        case .spacious:
            130
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
            "柔和"
        case .balanced:
            "标准"
        case .crisp:
            "清晰"
        }
    }

    var subtitle: String {
        switch self {
        case .soft:
            "弱边界"
        case .balanced:
            "默认层级"
        case .crisp:
            "更明确"
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

struct AppearancePreferences: Codable, Equatable {
    var density: AppearanceDensity
    var chromeClarity: ChromeClarity
    var reducedMotion: Bool

    init(
        density: AppearanceDensity = .standard,
        chromeClarity: ChromeClarity = .balanced,
        reducedMotion: Bool = false
    ) {
        self.density = density
        self.chromeClarity = chromeClarity
        self.reducedMotion = reducedMotion
    }
}
