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
}
