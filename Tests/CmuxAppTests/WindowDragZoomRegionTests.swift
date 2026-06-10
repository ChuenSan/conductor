@testable import CmuxApp
import XCTest

@MainActor
final class WindowDragZoomRegionTests: XCTestCase {
    func testDoubleClickZoomsWindow() {
        let window = SpyWindow()
        let region = WindowDragZoomRegion(frame: NSRect(x: 0, y: 0, width: 120, height: 28))
        window.contentView = region

        region.mouseDown(with: Self.mouseEvent(type: .leftMouseDown, clickCount: 2))

        XCTAssertEqual(window.zoomCallCount, 1)
    }

    func testSingleClickDoesNotZoomWindow() {
        let window = SpyWindow()
        let region = WindowDragZoomRegion(frame: NSRect(x: 0, y: 0, width: 120, height: 28))
        window.contentView = region

        region.mouseDown(with: Self.mouseEvent(type: .leftMouseDown, clickCount: 1))

        XCTAssertEqual(window.zoomCallCount, 0)
    }

    func testRegionAcceptsFirstMouse() {
        let region = WindowDragZoomRegion()

        XCTAssertTrue(region.acceptsFirstMouse(for: Self.mouseEvent(type: .leftMouseDown, clickCount: 1)))
    }

    func testRegionHasFixedIntrinsicHeightOnly() {
        let region = WindowDragZoomRegion()

        XCTAssertEqual(region.intrinsicContentSize.width, NSView.noIntrinsicMetric)
        XCTAssertEqual(region.intrinsicContentSize.height, WindowDragZoomRegion.preferredHeight)
    }

    private static func mouseEvent(type: NSEvent.EventType, clickCount: Int) -> NSEvent {
        NSEvent.mouseEvent(
            with: type,
            location: NSPoint(x: 10, y: 10),
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: clickCount,
            pressure: 0
        )!
    }
}

@MainActor
private final class SpyWindow: NSWindow {
    var zoomCallCount = 0

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: true
        )
    }

    override func zoom(_ sender: Any?) {
        zoomCallCount += 1
    }
}
