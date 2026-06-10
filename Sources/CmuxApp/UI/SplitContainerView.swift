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
        guard !applied, bounds.width > 1, bounds.height > 1 else { return }
        applied = true
        let total = isVertical ? bounds.width : bounds.height
        setPosition(initialRatio * total, ofDividerAt: 0)
    }

    func splitViewDidResizeSubviews(_ notification: Notification) {
        guard applied, let splitID, arrangedSubviews.count == 2 else { return }
        let total = isVertical ? bounds.width : bounds.height
        guard total > 1 else { return }
        let firstSize = isVertical ? arrangedSubviews[0].frame.width : arrangedSubviews[0].frame.height
        let ratio = max(0.05, min(0.95, Double(firstSize / total)))
        onRatioChange?(splitID, ratio)
    }
}
