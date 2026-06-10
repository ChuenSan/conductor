import AppKit
import CmuxCore

/// 把一棵 CmuxCore `SplitNode` 递归构建成 AppKit 视图：
/// 叶子 → 对应 pane 的视图（GhosttySurface 的 hostView）；分屏 → 可拖动的 `NSSplitView`。
/// 拖动分隔条会通过 `onRatioChange` 把新比例写回模型，从而不被 rebuild 重置、并可持久化。
@MainActor
enum SplitTreeBuilder {
    static func build(
        _ node: SplitNode,
        paneView: (PaneID) -> NSView,
        onRatioChange: @escaping (SplitID, Double) -> Void
    ) -> NSView {
        switch node {
        case let .leaf(pane):
            return paneView(pane)
        case let .split(id, axis, ratio, first, second):
            let split = RatioSplitView()
            split.isVertical = (axis == .vertical)
            split.dividerStyle = .thin
            split.splitID = id
            split.onRatioChange = onRatioChange
            split.delegate = split
            split.addArrangedSubview(build(first, paneView: paneView, onRatioChange: onRatioChange))
            split.addArrangedSubview(build(second, paneView: paneView, onRatioChange: onRatioChange))
            split.initialRatio = CGFloat(ratio)
            return split
        }
    }
}

/// NSSplitView 子类：首次按 ratio 设分隔位置；用户拖动后把新比例回报给模型。
/// 分隔条颜色 = 画布色 → 与卡片间隙融为一体，没有硬线（卡片靠柔阴影区分）。
final class RatioSplitView: NSSplitView, NSSplitViewDelegate {
    var initialRatio: CGFloat = 0.5
    var splitID: SplitID?
    var onRatioChange: ((SplitID, Double) -> Void)?
    private var applied = false
    private var applyingInitialRatio = false

    override var dividerColor: NSColor { NSColor(AppStyle.windowBackground) }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        restyleForCurrentTheme()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        restyleForCurrentTheme()
    }

    func restyleForCurrentTheme() {
        wantsLayer = true
        layer?.backgroundColor = NSColor(AppStyle.windowBackground).cgColor
        needsDisplay = true
        setNeedsDisplay(bounds)
    }

    override func drawDivider(in rect: NSRect) {
        NSColor(AppStyle.windowBackground).setFill()
        rect.fill()
    }

    override func layout() {
        super.layout()
        applyInitialRatioIfNeeded()
    }

    func splitViewDidResizeSubviews(_ notification: Notification) {
        guard applied, !applyingInitialRatio, let splitID, arrangedSubviews.count == 2 else { return }
        let total = splitExtent
        guard total > 1, visiblePaneCount == 2 else { return }
        let firstSize = isVertical ? arrangedSubviews[0].frame.width : arrangedSubviews[0].frame.height
        let minRatio = min(0.45, Double(minimumPaneExtent(for: total) / total))
        let ratio = max(minRatio, min(1 - minRatio, Double(firstSize / total)))
        onRatioChange?(splitID, ratio)
    }

    func splitView(_ splitView: NSSplitView, canCollapseSubview subview: NSView) -> Bool {
        false
    }

    func splitView(_ splitView: NSSplitView,
                   constrainMinCoordinate proposedMinimumPosition: CGFloat,
                   ofSubviewAt dividerIndex: Int) -> CGFloat {
        minimumPaneExtent(for: splitExtent)
    }

    func splitView(_ splitView: NSSplitView,
                   constrainMaxCoordinate proposedMaximumPosition: CGFloat,
                   ofSubviewAt dividerIndex: Int) -> CGFloat {
        splitExtent - minimumPaneExtent(for: splitExtent)
    }

    private var splitExtent: CGFloat {
        isVertical ? bounds.width : bounds.height
    }

    private var visiblePaneCount: Int {
        arrangedSubviews.filter { view in
            let extent = isVertical ? view.frame.width : view.frame.height
            return extent > 1
        }.count
    }

    private func applyInitialRatioIfNeeded() {
        guard !applied, arrangedSubviews.count == 2 else { return }
        let total = splitExtent
        guard total >= 24 else { return }

        let minExtent = minimumPaneExtent(for: total)
        let proposed = initialRatio * total
        let position = min(max(proposed, minExtent), total - minExtent)

        applyingInitialRatio = true
        setPosition(position, ofDividerAt: 0)
        adjustSubviews()
        applyingInitialRatio = false

        if visiblePaneCount == 2 {
            applied = true
        }
    }

    private func minimumPaneExtent(for total: CGFloat) -> CGFloat {
        let available = max(0, total - dividerThickness)
        guard available > 0 else { return 0 }
        return min(72, max(24, floor(available * 0.18)))
    }
}
