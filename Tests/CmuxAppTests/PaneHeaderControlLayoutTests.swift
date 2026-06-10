@testable import CmuxApp
import XCTest

final class PaneHeaderControlLayoutTests: XCTestCase {
    func testKeepsAllControlsInsideNarrowHeader() {
        let layout = PaneHeaderControlLayout.layout(headerWidth: 84, controlCount: 5)

        XCTAssertEqual(layout.buttonFrames.count, 5)
        XCTAssertGreaterThanOrEqual(layout.buttonFrames.first?.minX ?? -1, 0)
        XCTAssertLessThanOrEqual(layout.buttonFrames.last?.maxX ?? .infinity, 84)
    }

    func testUsesFullSizeControlsWhenThereIsRoom() {
        let layout = PaneHeaderControlLayout.layout(headerWidth: 240, controlCount: 5)

        XCTAssertEqual(layout.buttonSize, 20)
        XCTAssertEqual(layout.spacing, 3)
        XCTAssertEqual(layout.trailingInset, 8)
    }

    @MainActor
    func testHeaderControlsDoNotUseSystemButtons() {
        let header = PaneHeaderView(frame: NSRect(x: 0, y: 0, width: 160, height: 24))

        XCTAssertFalse(Self.containsSystemButton(in: header))
    }

    @MainActor
    func testHeaderButtonClearsHighlightAfterClick() {
        let header = PaneHeaderView(frame: NSRect(x: 0, y: 0, width: 180, height: 24))
        header.layoutSubtreeIfNeeded()
        guard let button = Self.firstView(withToolTip: "向右分屏", in: header) else {
            XCTFail("Expected split-right header button")
            return
        }

        button.mouseEntered(with: Self.mouseEvent(type: .mouseMoved, in: button))
        button.mouseDown(with: Self.mouseEvent(type: .leftMouseDown, in: button))
        button.mouseUp(with: Self.mouseEvent(type: .leftMouseUp, in: button))

        XCTAssertEqual(button.layer?.backgroundColor?.alpha ?? 0, 0, accuracy: 0.001)
    }

    @MainActor
    func testHeaderButtonHoverUsesThemeOpacity() {
        let header = PaneHeaderView(frame: NSRect(x: 0, y: 0, width: 180, height: 24))
        header.layoutSubtreeIfNeeded()
        guard let button = Self.firstView(withToolTip: "向下分屏", in: header) else {
            XCTFail("Expected split-down header button")
            return
        }

        button.mouseEntered(with: Self.mouseEvent(type: .mouseMoved, in: button))

        XCTAssertLessThanOrEqual(button.layer?.backgroundColor?.alpha ?? 1, 0.2)
    }

    @MainActor
    private static func containsSystemButton(in view: NSView) -> Bool {
        if view is NSButton { return true }
        return view.subviews.contains { containsSystemButton(in: $0) }
    }

    @MainActor
    private static func firstView(withToolTip toolTip: String, in view: NSView) -> NSView? {
        if view.toolTip == toolTip { return view }
        for subview in view.subviews {
            if let match = firstView(withToolTip: toolTip, in: subview) { return match }
        }
        return nil
    }

    @MainActor
    private static func mouseEvent(type: NSEvent.EventType, in view: NSView) -> NSEvent {
        NSEvent.mouseEvent(
            with: type,
            location: NSPoint(x: view.bounds.midX, y: view.bounds.midY),
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 0
        )!
    }
}
