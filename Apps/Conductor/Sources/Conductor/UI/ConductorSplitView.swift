import AppKit

struct ConductorSplitDividerAppearance: Equatable {
    let themeID: String
    let thickness: CGFloat
}

final class ConductorSplitView: NSSplitView {
    private var dividerAppearance = ConductorSplitDividerAppearance(
        themeID: "",
        thickness: ConductorTokens.Space.splitGutter
    )
    var isDividerActive = false {
        didSet {
            guard oldValue != isDividerActive else { return }
            invalidateDividerDisplay()
        }
    }
    var onDividerDoubleClick: (() -> Void)?

    override var dividerThickness: CGFloat {
        dividerAppearance.thickness
    }

    override var isOpaque: Bool {
        false
    }

    override var mouseDownCanMoveWindow: Bool {
        false
    }

    func applyDividerAppearance(_ appearance: ConductorSplitDividerAppearance) {
        guard appearance != dividerAppearance else { return }
        let oldThickness = dividerAppearance.thickness
        dividerAppearance = appearance
        if oldThickness != appearance.thickness {
            needsLayout = true
        }
        invalidateDividerDisplay()
    }

    override func drawDivider(in rect: NSRect) {
        super.drawDivider(in: rect)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            isDividerActive = false
        }
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2,
           SplitLayoutPolicy.hitRect(in: self).contains(convert(event.locationInWindow, from: nil)) {
            onDividerDoubleClick?()
            return
        }
        super.mouseDown(with: event)
    }

    private func invalidateDividerDisplay() {
        setNeedsDisplay(SplitLayoutPolicy.invalidationRect(in: self))
        needsDisplay = true
    }
}
