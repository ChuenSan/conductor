@testable import ConductorApp
import XCTest

final class PaneHeaderActionPresentationTests: XCTestCase {
    func testPromotesFrequentPaneActionsToHeaderButtons() {
        XCTAssertEqual(PaneHeaderActionPresentation.primaryActions, [.splitRight, .splitDown, .zoom, .close])
    }

    func testKeepsTextAndPathActionsInMoreMenu() {
        XCTAssertEqual(
            PaneHeaderActionPresentation.moreActions,
            [.copy, .paste, .selectAll, .clear, .copyCwd, .openInFinder, .commandLog, .exportText])
    }

    func testPaneHeaderActionsArePaneScoped() {
        let actions = PaneHeaderActionPresentation.primaryActions + PaneHeaderActionPresentation.moreActions

        XCTAssertFalse(actions.isEmpty)
        XCTAssertTrue(actions.allSatisfy { $0.deckLayer == .pane })
    }
}
