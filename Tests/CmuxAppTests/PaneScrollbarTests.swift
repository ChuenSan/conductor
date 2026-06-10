@testable import CmuxApp
import XCTest

@MainActor
final class PaneScrollbarTests: XCTestCase {
    func testIncomingMetricsDoNotSnapThumbWhileDragging() {
        let scrollbar = PaneScrollbar(frame: NSRect(x: 0, y: 0, width: 14, height: 200))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 14, height: 200),
            styleMask: [.borderless],
            backing: .buffered,
            defer: true
        )
        window.contentView = scrollbar
        scrollbar.setMetrics(total: 1_000, offset: 400, len: 100)
        scrollbar.layoutSubtreeIfNeeded()
        let startFrame = Self.thumbFrame(in: scrollbar)
        let startY = startFrame.midY

        scrollbar.mouseDown(with: Self.mouseEvent(type: .leftMouseDown, y: startY, in: scrollbar))
        scrollbar.mouseDragged(with: Self.mouseEvent(type: .leftMouseDragged, y: startY + 32, in: scrollbar))
        let draggedFrame = Self.thumbFrame(in: scrollbar)

        scrollbar.setMetrics(total: 1_000, offset: 400, len: 100)

        XCTAssertEqual(Self.thumbFrame(in: scrollbar).minY, draggedFrame.minY, accuracy: 0.001)
        XCTAssertNotEqual(Self.thumbFrame(in: scrollbar).minY, startFrame.minY, accuracy: 0.001)
    }

    private static func thumbFrame(in scrollbar: PaneScrollbar) -> CGRect {
        guard let frame = scrollbar.layer?.sublayers?.first?.frame else {
            XCTFail("Expected scrollbar thumb layer")
            return .zero
        }
        return frame
    }

    private static func mouseEvent(type: NSEvent.EventType, y: CGFloat, in view: NSView) -> NSEvent {
        NSEvent.mouseEvent(
            with: type,
            location: NSPoint(x: view.bounds.midX, y: y),
            modifierFlags: [],
            timestamp: 0,
            windowNumber: view.window?.windowNumber ?? 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 0
        )!
    }
}
