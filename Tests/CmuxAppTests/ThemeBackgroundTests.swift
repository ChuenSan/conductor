@testable import CmuxApp
import AppKit
import SwiftUI
import XCTest

final class ThemeBackgroundTests: XCTestCase {
    func testSidebarBackgroundMatchesWindowBackgroundInEveryTheme() {
        XCTAssertEqual(components(of: Theme.dark.sidebarBackground), components(of: Theme.dark.windowBackground))
        XCTAssertEqual(components(of: Theme.light.sidebarBackground), components(of: Theme.light.windowBackground))
    }

    private func components(of color: Color) -> [CGFloat] {
        guard let nsColor = NSColor(color).usingColorSpace(.sRGB) else {
            XCTFail("Expected color to convert to sRGB")
            return []
        }
        return [nsColor.redComponent, nsColor.greenComponent, nsColor.blueComponent, nsColor.alphaComponent]
    }
}
