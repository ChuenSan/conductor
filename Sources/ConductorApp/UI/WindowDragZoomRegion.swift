import AppKit
import SwiftUI

@MainActor
final class WindowDragZoomRegion: NSView {
    static let preferredHeight: CGFloat = 24

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: Self.preferredHeight)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard event.clickCount == 2 else { return }
        window?.zoom(nil)
    }

    override func mouseDragged(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

struct WindowDragZoomArea: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowDragZoomRegion {
        WindowDragZoomRegion()
    }

    func updateNSView(_ nsView: WindowDragZoomRegion, context: Context) {}
}
