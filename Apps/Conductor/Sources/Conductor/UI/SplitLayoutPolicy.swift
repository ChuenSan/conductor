import ConductorCore
import AppKit

enum SplitLayoutPolicy {
    static let leafMinimumLength: CGFloat = 24
    static let dividerHitOutset: CGFloat = 7
    static let dividerInvalidationOutset: CGFloat = 1
    static let fractionSyncTolerance = 0.0008
    static let dividerPositionTolerance: CGFloat = 0.5

    @MainActor
    static func availableLength(in splitView: NSSplitView) -> CGFloat {
        let total = splitView.isVertical ? splitView.bounds.width : splitView.bounds.height
        return max(1, total - splitView.dividerThickness)
    }

    @MainActor
    static func hitRect(in splitView: NSSplitView, outset: CGFloat = dividerHitOutset) -> NSRect {
        guard splitView.arrangedSubviews.count >= 2 else { return .zero }
        let firstFrame = splitView.arrangedSubviews[0].frame
        let rawRect: NSRect
        if splitView.isVertical {
            rawRect = NSRect(
                x: firstFrame.maxX,
                y: 0,
                width: splitView.dividerThickness,
                height: splitView.bounds.height
            )
        } else {
            rawRect = NSRect(
                x: 0,
                y: firstFrame.maxY,
                width: splitView.bounds.width,
                height: splitView.dividerThickness
            )
        }
        return rawRect.insetBy(dx: -outset, dy: -outset)
    }

    @MainActor
    static func invalidationRect(in splitView: NSSplitView) -> NSRect {
        hitRect(in: splitView, outset: dividerInvalidationOutset)
    }

    @MainActor
    static func pixelAligned(_ value: CGFloat, in view: NSView) -> CGFloat {
        let scale = view.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        return (value * scale).rounded(.toNearestOrAwayFromZero) / scale
    }
}

extension SplitNode {
    func minimumLength(along axis: SplitAxis, divider: CGFloat) -> CGFloat {
        switch self {
        case .leaf:
            return SplitLayoutPolicy.leafMinimumLength
        case let .split(splitAxis, first, second, _):
            if splitAxis == axis {
                return first.minimumLength(along: axis, divider: divider) +
                    second.minimumLength(along: axis, divider: divider) +
                    divider
            }
            return max(
                first.minimumLength(along: axis, divider: divider),
                second.minimumLength(along: axis, divider: divider)
            )
        }
    }
}
