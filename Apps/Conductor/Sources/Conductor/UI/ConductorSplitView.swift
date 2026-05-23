import AppKit

struct ConductorSplitDividerAppearance: Equatable {
    let themeID: String
    let thickness: CGFloat
    let fillColor: NSColor
    let lineColor: NSColor
    let activeLineColor: NSColor

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.themeID == rhs.themeID &&
            lhs.thickness == rhs.thickness &&
            lhs.fillColor.conductorDeviceRGBSignature == rhs.fillColor.conductorDeviceRGBSignature &&
            lhs.lineColor.conductorDeviceRGBSignature == rhs.lineColor.conductorDeviceRGBSignature &&
            lhs.activeLineColor.conductorDeviceRGBSignature == rhs.activeLineColor.conductorDeviceRGBSignature
    }
}

final class ConductorSplitView: NSSplitView {
    private var dividerAppearance = ConductorSplitDividerAppearance(
        themeID: "",
        thickness: ConductorTokens.Space.splitGutter,
        fillColor: .clear,
        lineColor: .separatorColor,
        activeLineColor: .controlAccentColor
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
        applySplitBackgroundColor(appearance.fillColor)
        if oldThickness != appearance.thickness {
            needsLayout = true
        }
        invalidateDividerDisplay()
    }

    override func drawDivider(in rect: NSRect) {
        dividerAppearance.fillColor.setFill()
        rect.fill()

        let lineThickness: CGFloat = isDividerActive ? 2 : 1
        let lineRect: NSRect
        if isVertical {
            lineRect = NSRect(
                x: rect.midX - lineThickness / 2,
                y: rect.minY,
                width: lineThickness,
                height: rect.height
            )
        } else {
            lineRect = NSRect(
                x: rect.minX,
                y: rect.midY - lineThickness / 2,
                width: rect.width,
                height: lineThickness
            )
        }
        (isDividerActive ? dividerAppearance.activeLineColor : dividerAppearance.lineColor).setFill()
        lineRect.fill()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applySplitBackgroundColor(dividerAppearance.fillColor)
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

    private func applySplitBackgroundColor(_ color: NSColor) {
        wantsLayer = true
        layer?.backgroundColor = color.conductorDeviceRGBCGColor
    }
}

private extension NSColor {
    var conductorDeviceRGBCGColor: CGColor {
        usingColorSpace(.deviceRGB)?.cgColor ?? cgColor
    }

    var conductorDeviceRGBSignature: [CGFloat] {
        guard let color = usingColorSpace(.deviceRGB) else { return [] }
        return [
            color.redComponent,
            color.greenComponent,
            color.blueComponent,
            color.alphaComponent
        ]
    }
}
