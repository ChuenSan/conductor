@testable import ConductorApp
import XCTest

final class CapabilityLibraryPresentationTests: XCTestCase {
    func testCapabilityLibraryUsesStableSectionOrder() {
        XCTAssertEqual(
            CapabilityLibrarySection.allCases,
            [.overview, .cli, .skills, .mcp, .hooks, .providersAndUsage, .activity, .snippets]
        )
    }

    func testCapabilityLibraryPanelTabsMapToExistingToolsTabs() {
        XCTAssertEqual(
            CapabilityLibrarySection.panelTabs,
            [.cli, .skills, .mcp, .hooks, .providersAndUsage, .snippets]
        )
        XCTAssertEqual(CapabilityLibrarySection.providersAndUsage.toolsTab, .usage)
    }

    func testCapabilityLibraryPrimaryLabels() {
        XCTAssertEqual(CapabilityLibraryPresentation.title, "能力库")
        XCTAssertEqual(CapabilityLibraryPresentation.englishTitle, "Capability Library")
        XCTAssertEqual(CapabilityLibraryPresentation.toolbarHelp, "打开能力库")
    }
}
