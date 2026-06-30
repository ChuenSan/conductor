import Foundation

enum CommandDeckLayer: String, CaseIterable, Equatable {
    case global
    case workspace
    case pane
    case agent
    case capability

    var title: String {
        switch self {
        case .global: return L("全局")
        case .workspace: return L("工作区")
        case .pane: return L("面板")
        case .agent: return "Agent"
        case .capability: return L("能力")
        }
    }
}

enum CommandDeckCommandScope {
    private static let explicitScopes: [String: CommandDeckLayer] = [
        "openSettings": .global,
        "commandPalette": .global,
        "shortcutCheatSheet": .global,
        "increaseFontSize": .global,
        "decreaseFontSize": .global,
        "resetFontSize": .global,

        "newTab": .workspace,
        "reopenClosedTab": .workspace,
        "nextTab": .workspace,
        "prevTab": .workspace,
        "toggleRecentTab": .workspace,
        "equalizeSplits": .workspace,

        "splitRight": .pane,
        "splitDown": .pane,
        "closePane": .pane,
        "copyPane": .pane,
        "pastePane": .pane,
        "selectAllPane": .pane,
        "clearPane": .pane,
        "copyPaneCwd": .pane,
        "openPaneInFinder": .pane,
        "exportPaneText": .pane,
        "openPaneCommandLog": .pane,
        "focusPaneLeft": .pane,
        "focusPaneRight": .pane,
        "focusPaneUp": .pane,
        "focusPaneDown": .pane,
        "toggleZoom": .pane,
        "findInTerminal": .pane,
        "searchSelection": .pane,
        "findNext": .pane,
        "findPrev": .pane,

        "missionControl": .agent,
        "queuePrompt": .agent,

        "openSnippets": .capability,
        "coCreate": .capability,
    ]

    static func scope(forCommandID id: String) -> CommandDeckLayer {
        if id.hasPrefix("selectTab") { return .workspace }
        return explicitScopes[id] ?? .global
    }
}
