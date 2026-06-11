@testable import ConductorApp
import ConductorCore
import XCTest

@MainActor
final class SplitContainerViewTests: XCTestCase {
    func testRatioSplitViewRestyleUsesCurrentThemeBackground() {
        let original = ConfigStore.shared.config
        defer { ConfigStore.shared.set(original) }

        var light = original
        light.appearance.theme = "light"
        ConfigStore.shared.set(light)
        let split = RatioSplitView()
        split.restyleForCurrentTheme()
        let lightBackground = split.layer?.backgroundColor

        var dark = original
        dark.appearance.theme = "dark"
        ConfigStore.shared.set(dark)
        split.restyleForCurrentTheme()

        XCTAssertNotEqual(split.layer?.backgroundColor, lightBackground)
        XCTAssertEqual(split.layer?.backgroundColor, NSColor(AppStyle.windowBackground).cgColor)
    }
}
