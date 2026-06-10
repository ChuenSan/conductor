@testable import CmuxApp
import XCTest

@MainActor
final class PaneDragInteractionTests: XCTestCase {
    func testTerminalContentDragDoesNotStartPaneDrag() {
        let surface = GhosttySurface()
        var dragCount = 0
        surface.onBeginPaneDrag = { _ in dragCount += 1 }

        surface.hostView.mouseDown(with: Self.mouseEvent(type: .leftMouseDown, command: true))
        surface.hostView.mouseDragged(with: Self.mouseEvent(type: .leftMouseDragged, command: true))

        XCTAssertEqual(dragCount, 0)
    }

    func testPaneHeaderDragStartsPaneDrag() {
        let header = PaneHeaderView()
        var dragCount = 0
        header.onDragStart = { _ in dragCount += 1 }

        header.mouseDown(with: Self.mouseEvent(type: .leftMouseDown))
        header.mouseDragged(with: Self.mouseEvent(type: .leftMouseDragged))

        XCTAssertEqual(dragCount, 1)
    }

    private static func mouseEvent(type: NSEvent.EventType, command: Bool = false) -> NSEvent {
        NSEvent.mouseEvent(
            with: type,
            location: NSPoint(x: 10, y: 10),
            modifierFlags: command ? .command : [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 0
        )!
    }
}
