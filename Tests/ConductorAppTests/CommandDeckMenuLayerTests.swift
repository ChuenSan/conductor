@testable import ConductorApp
import XCTest

final class CommandDeckMenuLayerTests: XCTestCase {
    func testWorkspaceContextActionsMatchMenuOrder() {
        XCTAssertEqual(
            WorkspaceContextAction.allCases,
            [
                .rename,
                .revealInFinder,
                .copyPath,
                .reauthorizeDirectory,
                .saveLayout,
                .restoreLayout,
                .deleteLayout,
                .choreographyRules,
                .removeWorkspace,
            ]
        )

        XCTAssertEqual(WorkspaceContextActionPresentation.allMenuActions, WorkspaceContextAction.allCases)
    }

    func testWorkspaceContextActionGroupsReflectConditionalLayoutEntries() {
        XCTAssertEqual(
            WorkspaceContextActionPresentation.staticActions,
            [.rename, .revealInFinder, .copyPath, .reauthorizeDirectory, .saveLayout, .choreographyRules, .removeWorkspace]
        )
        XCTAssertEqual(WorkspaceContextActionPresentation.conditionalLayoutActions, [.restoreLayout, .deleteLayout])
    }

    func testWorkspaceContextActionsDoNotContainGlobalOrCapabilityActions() {
        let forbidden: Set<CommandDeckLayer> = [.global, .capability]

        XCTAssertTrue(WorkspaceContextActionPresentation.allMenuActions.allSatisfy { !forbidden.contains($0.deckLayer) })
    }

    func testWorkspaceContextAgentLaunchesAreAgentScoped() {
        XCTAssertEqual(WorkspaceContextActionPresentation.agentLaunchLayer, .agent)
    }

    func testPaneMoreMenuContainsOnlyPaneScopedActions() {
        XCTAssertTrue(PaneHeaderActionPresentation.moreActions.allSatisfy { $0.deckLayer == .pane })
    }
}
