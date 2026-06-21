@testable import ConductorApp
import ConductorCore
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

    @MainActor
    func testPaneContextMenuRefreshesAfterLanguageChange() {
        let originalLanguage = AppLanguage.current
        defer { AppLanguage.apply(originalLanguage) }

        AppLanguage.apply(AppLanguage.english)
        let hostView = NSView()
        let container = PaneContainerView(paneID: PaneID("pane-i18n-test"), hostView: hostView, title: "Terminal")

        XCTAssertEqual(container.hostView.menu?.items.first?.title, "Copy")

        AppLanguage.apply(AppLanguage.simplifiedChinese)

        XCTAssertEqual(container.hostView.menu?.items.first?.title, "复制")
    }
}
