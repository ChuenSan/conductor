@testable import ConductorApp
import ConductorCore
import XCTest

final class SidebarWorkspaceSummaryTests: XCTestCase {
    func testSummarizesPathAndCountsForWorkspaceRows() {
        let firstPane = PaneID("p-1")
        let secondPane = PaneID("p-2")
        let thirdPane = PaneID("p-3")
        let workspace = Workspace(
            id: WorkspaceID("w-1"),
            name: "c",
            path: NSHomeDirectory() + "/Desktop/c",
            tabs: [
                Tab.single(id: TabID("t-1"), title: "zsh", pane: firstPane),
                Tab(
                    id: TabID("t-2"),
                    title: "zsh",
                    rootSplit: .split(
                        id: SplitID("s-1"),
                        axis: .vertical,
                        ratio: 0.5,
                        first: .leaf(secondPane),
                        second: .leaf(thirdPane)
                    ),
                    activePane: thirdPane,
                    customTitle: "开发"
                ),
            ],
            activeTab: TabID("t-2")
        )

        let summary = SidebarWorkspaceSummary(
            workspace: workspace,
            isSelected: true,
            paneTitles: [thirdPane: "Sources"],
            paneCwds: [thirdPane: NSHomeDirectory() + "/Desktop/c/Sources"]
        )

        XCTAssertEqual(summary.pathText, "~/Desktop/c")
        XCTAssertEqual(summary.metricsText, "2 标签 · 3 面板")
        XCTAssertEqual(summary.activeDetailText, "当前：开发 · ~/Desktop/c/Sources")
        XCTAssertEqual(summary.tooltipText, "c\n~/Desktop/c\n2 标签 · 3 面板\n当前：开发 · ~/Desktop/c/Sources")
    }

    func testHidesActiveDetailForInactiveWorkspaceRows() {
        let pane = PaneID("p-1")
        let workspace = Workspace(
            id: WorkspaceID("w-1"),
            name: "c",
            path: "/tmp/c",
            tabs: [Tab.single(id: TabID("t-1"), title: "zsh", pane: pane)],
            activeTab: TabID("t-1")
        )

        let summary = SidebarWorkspaceSummary(
            workspace: workspace,
            isSelected: false,
            paneTitles: [pane: "tmp"],
            paneCwds: [pane: "/tmp/c"]
        )

        XCTAssertEqual(summary.pathText, "/tmp/c")
        XCTAssertEqual(summary.metricsText, "1 标签 · 1 面板")
        XCTAssertNil(summary.activeDetailText)
        XCTAssertEqual(summary.tooltipText, "c\n/tmp/c\n1 标签 · 1 面板")
    }
}
