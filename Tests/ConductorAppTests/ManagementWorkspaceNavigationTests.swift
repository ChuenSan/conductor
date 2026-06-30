import XCTest
@testable import ConductorApp

final class ManagementWorkspaceNavigationTests: XCTestCase {
    func testCurrentDestinationPrefersSettings() {
        let destination = ManagementWorkspaceDestination.current(
            settingsPresented: true,
            toolsPresented: true,
            toolsTab: .usage,
            sessionsPresented: true)

        XCTAssertEqual(destination, .settings)
    }

    func testCurrentDestinationUsesSelectedToolsTab() {
        let destination = ManagementWorkspaceDestination.current(
            settingsPresented: false,
            toolsPresented: true,
            toolsTab: .mcp,
            sessionsPresented: false)

        XCTAssertEqual(destination, .tools(.mcp))
    }

    func testCurrentDestinationIncludesSessions() {
        let destination = ManagementWorkspaceDestination.current(
            settingsPresented: false,
            toolsPresented: false,
            toolsTab: .cli,
            sessionsPresented: true)

        XCTAssertEqual(destination, .sessions)
    }
}
