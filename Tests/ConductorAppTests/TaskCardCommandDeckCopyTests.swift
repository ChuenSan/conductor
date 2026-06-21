@testable import ConductorApp
import XCTest

final class TaskCardCommandDeckCopyTests: XCTestCase {
    func testTaskCardPanelCopyFramesCardsAsAssignableWork() {
        XCTAssertEqual(TaskCardCommandDeckCopy.title, "任务卡片")
        XCTAssertEqual(TaskCardCommandDeckCopy.subtitle, "拖到某个面板，交给 Shell 或 Agent 执行")
        XCTAssertEqual(TaskCardCommandDeckCopy.emptyTitle, "还没有可指派的任务")
    }

    func testTaskCardsBelongToTaskLayer() {
        XCTAssertEqual(TaskCardCommandDeckCopy.deckLayer, .task)
    }
}
