@testable import ConductorApp
import ConductorCore
import XCTest

final class ChoreographySuppressionTests: XCTestCase {
    func testConsumesOneSuppressionPerInjectedCommand() {
        var suppression = ChoreographySuppression()
        let pane = PaneID("p1")

        suppression.suppressNextCommand(in: pane)
        suppression.suppressNextCommand(in: pane)

        XCTAssertTrue(suppression.consume(for: pane))
        XCTAssertTrue(suppression.consume(for: pane))
        XCTAssertFalse(suppression.consume(for: pane))
    }

    func testSuppressionIsScopedPerPane() {
        var suppression = ChoreographySuppression()
        let first = PaneID("p1")
        let second = PaneID("p2")

        suppression.suppressNextCommand(in: first)

        XCTAssertFalse(suppression.consume(for: second))
        XCTAssertTrue(suppression.consume(for: first))
    }
}
