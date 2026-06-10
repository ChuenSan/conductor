import CmuxCore
import Foundation

struct SidebarWorkspaceSummary: Equatable {
    let pathText: String
    let metricsText: String
    let activeDetailText: String?
    let tooltipText: String
    let paneCount: Int

    init(
        workspace: Workspace,
        isSelected: Bool,
        paneTitles: [PaneID: String],
        paneCwds: [PaneID: String]
    ) {
        let tabCount = workspace.tabs.count
        let paneCount = workspace.tabs.reduce(0) { $0 + $1.paneCount }
        let pathText = Self.compactPath(workspace.path)
        let metricsText = "\(tabCount) 标签 · \(paneCount) 面板"
        let activeDetailText = Self.activeDetailText(
            workspace: workspace,
            isSelected: isSelected,
            paneTitles: paneTitles,
            paneCwds: paneCwds
        )

        var tooltipLines = [workspace.name, pathText, metricsText]
        if let activeDetailText {
            tooltipLines.append(activeDetailText)
        }

        self.pathText = pathText
        self.metricsText = metricsText
        self.activeDetailText = activeDetailText
        self.tooltipText = tooltipLines.joined(separator: "\n")
        self.paneCount = paneCount
    }

    private static func activeDetailText(
        workspace: Workspace,
        isSelected: Bool,
        paneTitles: [PaneID: String],
        paneCwds: [PaneID: String]
    ) -> String? {
        guard isSelected,
              let activeTabID = workspace.activeTab,
              let activeTab = workspace.tabs.first(where: { $0.id == activeTabID }) else { return nil }

        let tabTitle = activeTab.customTitle ?? paneTitles[activeTab.activePane] ?? activeTab.title
        guard let cwd = paneCwds[activeTab.activePane] else {
            return "当前：\(tabTitle)"
        }
        return "当前：\(tabTitle) · \(compactPath(cwd))"
    }

    private static func compactPath(_ path: String) -> String {
        (path as NSString).abbreviatingWithTildeInPath
    }
}
