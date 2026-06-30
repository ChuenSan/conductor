@testable import ConductorApp
import XCTest

@MainActor
final class WindowChromePolicyTests: XCTestCase {
    func testMainWindowDoesNotMoveByContentBackground() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )

        WindowChromePolicy.applyMainWindowChrome(to: window)

        XCTAssertFalse(window.isMovableByWindowBackground)
    }

    func testCollapsedSidebarTabBarAvoidsWindowButtons() {
        let leadingInset = WindowChromePolicy.tabBarLeadingInset(
            sidebarCollapsed: true,
            sidebarWidth: AppStyle.sidebarCollapsedWidth)

        XCTAssertGreaterThanOrEqual(
            AppStyle.sidebarCollapsedWidth + leadingInset,
            WindowChromePolicy.titlebarButtonAvoidanceWidth)
    }

    func testCollapsedSidebarTitlebarInsetStaysCompact() {
        let leadingInset = WindowChromePolicy.tabBarLeadingInset(
            sidebarCollapsed: true,
            sidebarWidth: AppStyle.sidebarCollapsedWidth)

        XCTAssertLessThanOrEqual(leadingInset, 44)
    }

    func testExpandedSidebarDoesNotAddTitlebarInset() {
        let leadingInset = WindowChromePolicy.tabBarLeadingInset(
            sidebarCollapsed: false,
            sidebarWidth: AppStyle.sidebarWidth)

        XCTAssertEqual(leadingInset, 0)
    }
}
