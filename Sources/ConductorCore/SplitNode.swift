/// 一个 Tab 内的分屏布局，建模为二叉树。
/// - `.leaf` 是一个终端 pane。
/// - `.split` 是一次分屏：沿 `axis` 把空间按 `ratio`（first 占比，0...1）分给两个子节点。
/// 自由/嵌套分屏 = `.split` 的嵌套。Codable/Equatable 由编译器自动合成。
public indirect enum SplitNode: Codable, Equatable {
    case leaf(PaneID)
    case split(id: SplitID, axis: SplitAxis, ratio: Double, first: SplitNode, second: SplitNode)

    /// 按深度优先、从左/上到右/下的顺序返回所有 pane。
    public func leaves() -> [PaneID] {
        switch self {
        case .leaf(let pane):
            return [pane]
        case .split(_, _, _, let first, let second):
            return first.leaves() + second.leaves()
        }
    }

    /// 该子树是否包含指定 pane。
    public func contains(_ pane: PaneID) -> Bool {
        leaves().contains(pane)
    }

    /// 在 `target` 叶子处插入分屏：把该叶子替换为一个 `.split`，
    /// 其中一边是原 pane、另一边是 `newPane`。`target` 不存在时原样返回。
    public func splitting(_ target: PaneID, with newPane: PaneID,
                          axis: SplitAxis, ratio: Double, splitID: SplitID,
                          newPaneFirst: Bool = false) -> SplitNode {
        switch self {
        case .leaf(let pane):
            guard pane == target else { return self }
            let oldLeaf = SplitNode.leaf(target)
            let newLeaf = SplitNode.leaf(newPane)
            return newPaneFirst
                ? .split(id: splitID, axis: axis, ratio: ratio, first: newLeaf, second: oldLeaf)
                : .split(id: splitID, axis: axis, ratio: ratio, first: oldLeaf, second: newLeaf)
        case .split(let id, let nodeAxis, let nodeRatio, let first, let second):
            return .split(
                id: id, axis: nodeAxis, ratio: nodeRatio,
                first: first.splitting(target, with: newPane, axis: axis, ratio: ratio,
                                       splitID: splitID, newPaneFirst: newPaneFirst),
                second: second.splitting(target, with: newPane, axis: axis, ratio: ratio,
                                         splitID: splitID, newPaneFirst: newPaneFirst)
            )
        }
    }

    /// 删除指定 pane。若某个 `.split` 因此只剩一个子节点，则塌缩为那个子节点。
    /// 删除唯一的叶子时返回 nil（树变空）。pane 不存在时原样返回。
    public func removing(_ target: PaneID) -> SplitNode? {
        switch self {
        case .leaf(let pane):
            return pane == target ? nil : self
        case .split(let id, let axis, let ratio, let first, let second):
            let newFirst = first.removing(target)
            let newSecond = second.removing(target)
            // pane 全局唯一，故最多一边发生塌缩。
            if newFirst == nil { return newSecond }   // first 整体被删 → 提升 second
            if newSecond == nil { return newFirst }   // second 整体被删 → 提升 first
            return .split(id: id, axis: axis, ratio: ratio, first: newFirst!, second: newSecond!)
        }
    }

    /// 把指定 `.split` 的 ratio 改为新值，其余不变。split 不存在时原样返回。
    public func updatingRatio(of split: SplitID, to newRatio: Double) -> SplitNode {
        switch self {
        case .leaf:
            return self
        case .split(let id, let axis, let ratio, let first, let second):
            if id == split {
                return .split(id: id, axis: axis, ratio: newRatio, first: first, second: second)
            }
            return .split(
                id: id, axis: axis, ratio: ratio,
                first: first.updatingRatio(of: split, to: newRatio),
                second: second.updatingRatio(of: split, to: newRatio)
            )
        }
    }

    /// 在 leaves() 顺序中位于 `pane` 之后的 pane（末尾循环回到开头）。pane 不存在时返回 nil。
    public func pane(after pane: PaneID) -> PaneID? {
        let order = leaves()
        guard let index = order.firstIndex(of: pane) else { return nil }
        return order[(index + 1) % order.count]
    }

    /// 在 leaves() 顺序中位于 `pane` 之前的 pane（开头循环回到末尾）。pane 不存在时返回 nil。
    public func pane(before pane: PaneID) -> PaneID? {
        let order = leaves()
        guard let index = order.firstIndex(of: pane) else { return nil }
        return order[(index - 1 + order.count) % order.count]
    }

    /// 返回把该树内所有分屏比例都设为 0.5 的副本（均分面板）。
    public func withAllRatiosEqualized() -> SplitNode {
        switch self {
        case .leaf:
            return self
        case .split(let id, let axis, _, let first, let second):
            return .split(id: id, axis: axis, ratio: 0.5,
                          first: first.withAllRatiosEqualized(),
                          second: second.withAllRatiosEqualized())
        }
    }
}
