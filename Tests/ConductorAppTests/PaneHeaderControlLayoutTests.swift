@testable import ConductorApp
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

    func testHoverTipLabelsMatchHeaderActions() {
        XCTAssertEqual(PaneHeaderHoverTipPresentation.label(for: .splitRight), "向右分屏")
        XCTAssertEqual(PaneHeaderHoverTipPresentation.label(for: nil), "更多操作")
    }

    func testHoverTipLabelIncludesEffectiveShortcutWhenBound() {
        XCTAssertEqual(
            PaneHeaderHoverTipPresentation.label(for: .splitRight, shortcut: "cmd+d"),
            "向右分屏  ⌘D"
        )
        XCTAssertEqual(
            PaneHeaderHoverTipPresentation.label(for: .zoom, shortcut: "cmd+enter"),
            "放大 / 还原  ⌘⏎"
        )
    }

    func testHoverTipFrameSitsAboveAnchorAndStaysHorizontallyInsideHeader() {
        let headerBounds = NSRect(x: 0, y: 0, width: 128, height: 24)
        let anchor = NSRect(x: 94, y: 2, width: 20, height: 20)
        let frame = PaneHeaderHoverTipPresentation.frame(
            for: "向右分屏",
            anchoredAt: anchor,
            in: headerBounds
        )

        XCTAssertGreaterThanOrEqual(frame.minX, headerBounds.minX + 4)
        XCTAssertLessThanOrEqual(frame.maxX, headerBounds.maxX - 4)
        XCTAssertGreaterThan(frame.minY, anchor.maxY)
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
