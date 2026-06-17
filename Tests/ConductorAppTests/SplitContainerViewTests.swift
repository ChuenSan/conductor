@testable import ConductorApp
import ConductorCore
import XCTest

@MainActor
final class SplitContainerViewTests: XCTestCase {
    func testRatioSplitViewRestyleUsesClearBackground() {
        // 终端画布透明：split 背景恒为 clear（露出窗口毛玻璃，pane 卡片自带实色保可读），与主题无关。
        let split = RatioSplitView()
        split.restyleForCurrentTheme()
        XCTAssertEqual(split.layer?.backgroundColor?.alpha, 0)
    }
}
