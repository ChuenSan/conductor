import Foundation

enum CapabilityLibrarySection: String, CaseIterable, Identifiable {
    case overview
    case cli
    case skills
    case mcp
    case hooks
    case providersAndUsage
    case activity
    case snippets

    var id: String { rawValue }

    static let panelTabs: [CapabilityLibrarySection] = [
        .cli,
        .skills,
        .mcp,
        .hooks,
        .providersAndUsage,
        .snippets,
    ]

    var title: String {
        switch self {
        case .overview: return L("总览")
        case .cli: return "CLI"
        case .skills: return "Skills"
        case .mcp: return "MCP"
        case .hooks: return "Hooks"
        case .providersAndUsage: return L("供应商与用量")
        case .activity: return L("活动")
        case .snippets: return L("片段")
        }
    }

    var systemImage: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .cli: return "terminal"
        case .skills: return "wand.and.stars"
        case .mcp: return "point.3.connected.trianglepath.dotted"
        case .hooks: return "link"
        case .providersAndUsage: return "chart.bar.xaxis"
        case .activity: return "waveform.path.ecg"
        case .snippets: return "text.badge.star"
        }
    }

    var toolsTab: ToolsTab? {
        switch self {
        case .cli: return .cli
        case .skills: return .skills
        case .mcp: return .mcp
        case .hooks: return .hooks
        case .providersAndUsage: return .usage
        case .snippets: return .snippets
        case .overview, .activity: return nil
        }
    }
}

enum CapabilityLibraryPresentation {
    static var title: String { L("能力库") }
    static let englishTitle = "Capability Library"
    static var toolbarHelp: String { L("打开能力库") }
    static var subtitle: String { L("管理 CLI、Skills、MCP、Hooks 和供应商能力") }
}
