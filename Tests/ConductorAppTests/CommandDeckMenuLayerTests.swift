@testable import ConductorApp
import XCTest

final class CommandDeckMenuLayerTests: XCTestCase {
    func testWorkspaceContextActionsStayWorkspaceOrAgentScoped() {
        XCTAssertEqual(
            WorkspaceContextActionPresentation.staticActions.map(\.deckLayer),
            [.workspace, .workspace, .workspace, .workspace, .workspace, .workspace]
        )
        XCTAssertEqual(WorkspaceContextActionPresentation.agentLaunchLayer, .agent)
    }

    func testWorkspaceContextActionsDoNotContainGlobalOrCapabilityActions() {
        let forbidden: Set<CommandDeckLayer> = [.global, .capability]

        XCTAssertTrue(WorkspaceContextActionPresentation.staticActions.allSatisfy { !forbidden.contains($0.deckLayer) })
    }

    func testPaneMoreMenuContainsOnlyPaneScopedActions() {
        XCTAssertTrue(PaneHeaderActionPresentation.moreActions.allSatisfy { $0.deckLayer == .pane })
    }
}
