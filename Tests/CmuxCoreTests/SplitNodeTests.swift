import XCTest
@testable import CmuxCore

final class SplitNodeTests: XCTestCase {
    func testLeafLeaves() {
        let node = SplitNode.leaf(PaneID("a"))
        XCTAssertEqual(node.leaves(), [PaneID("a")])
    }

    func testSplitLeavesAreInOrder() {
        let node = SplitNode.split(
            id: SplitID("s1"), axis: .vertical, ratio: 0.5,
            first: .leaf(PaneID("a")),
            second: .leaf(PaneID("b"))
        )
        XCTAssertEqual(node.leaves(), [PaneID("a"), PaneID("b")])
    }

    func testContains() {
        let node = SplitNode.split(
            id: SplitID("s1"), axis: .vertical, ratio: 0.5,
            first: .leaf(PaneID("a")),
            second: .leaf(PaneID("b"))
        )
        XCTAssertTrue(node.contains(PaneID("a")))
        XCTAssertFalse(node.contains(PaneID("z")))
    }

    func testEquatable() {
        let a = SplitNode.leaf(PaneID("a"))
        let b = SplitNode.leaf(PaneID("a"))
        XCTAssertEqual(a, b)
    }

    func testSplittingLeafReplacesItWithSplit() {
        let tree = SplitNode.leaf(PaneID("a"))
        let result = tree.splitting(PaneID("a"), with: PaneID("b"),
                                    axis: .vertical, ratio: 0.5, splitID: SplitID("s1"))
        XCTAssertEqual(result, .split(
            id: SplitID("s1"), axis: .vertical, ratio: 0.5,
            first: .leaf(PaneID("a")),
            second: .leaf(PaneID("b"))
        ))
    }

    func testSplittingNewPaneFirst() {
        let tree = SplitNode.leaf(PaneID("a"))
        let result = tree.splitting(PaneID("a"), with: PaneID("b"),
                                    axis: .horizontal, ratio: 0.3,
                                    splitID: SplitID("s1"), newPaneFirst: true)
        XCTAssertEqual(result, .split(
            id: SplitID("s1"), axis: .horizontal, ratio: 0.3,
            first: .leaf(PaneID("b")),
            second: .leaf(PaneID("a"))
        ))
    }

    func testSplittingDeepTarget() {
        let tree = SplitNode.split(
            id: SplitID("s1"), axis: .vertical, ratio: 0.5,
            first: .leaf(PaneID("a")),
            second: .leaf(PaneID("b"))
        )
        let result = tree.splitting(PaneID("b"), with: PaneID("c"),
                                    axis: .horizontal, ratio: 0.5, splitID: SplitID("s2"))
        XCTAssertEqual(result.leaves(), [PaneID("a"), PaneID("b"), PaneID("c")])
    }

    func testSplittingUnknownTargetIsNoOp() {
        let tree = SplitNode.leaf(PaneID("a"))
        let result = tree.splitting(PaneID("zzz"), with: PaneID("b"),
                                    axis: .vertical, ratio: 0.5, splitID: SplitID("s1"))
        XCTAssertEqual(result, tree)
    }

    func testRemovingOnlyLeafReturnsNil() {
        let tree = SplitNode.leaf(PaneID("a"))
        XCTAssertNil(tree.removing(PaneID("a")))
    }

    func testRemovingLeafCollapsesSplitToSibling() {
        let tree = SplitNode.split(
            id: SplitID("s1"), axis: .vertical, ratio: 0.5,
            first: .leaf(PaneID("a")),
            second: .leaf(PaneID("b"))
        )
        // 删掉 a，应塌缩成只剩 b 的叶子
        XCTAssertEqual(tree.removing(PaneID("a")), .leaf(PaneID("b")))
    }

    func testRemovingDeepLeafKeepsRestOfTree() {
        let tree = SplitNode.split(
            id: SplitID("s1"), axis: .vertical, ratio: 0.5,
            first: .leaf(PaneID("a")),
            second: .split(
                id: SplitID("s2"), axis: .horizontal, ratio: 0.5,
                first: .leaf(PaneID("b")),
                second: .leaf(PaneID("c"))
            )
        )
        // 删 b：内层 split 塌缩为 c，外层保留 a + c
        let result = tree.removing(PaneID("b"))
        XCTAssertEqual(result, .split(
            id: SplitID("s1"), axis: .vertical, ratio: 0.5,
            first: .leaf(PaneID("a")),
            second: .leaf(PaneID("c"))
        ))
    }

    func testRemovingUnknownLeafIsNoOp() {
        let tree = SplitNode.leaf(PaneID("a"))
        XCTAssertEqual(tree.removing(PaneID("zzz")), tree)
    }

    func testUpdatingRatioOfMatchingSplit() {
        let tree = SplitNode.split(
            id: SplitID("s1"), axis: .vertical, ratio: 0.5,
            first: .leaf(PaneID("a")),
            second: .leaf(PaneID("b"))
        )
        let result = tree.updatingRatio(of: SplitID("s1"), to: 0.7)
        XCTAssertEqual(result, .split(
            id: SplitID("s1"), axis: .vertical, ratio: 0.7,
            first: .leaf(PaneID("a")),
            second: .leaf(PaneID("b"))
        ))
    }

    func testUpdatingRatioOfNestedSplit() {
        let tree = SplitNode.split(
            id: SplitID("s1"), axis: .vertical, ratio: 0.5,
            first: .leaf(PaneID("a")),
            second: .split(
                id: SplitID("s2"), axis: .horizontal, ratio: 0.5,
                first: .leaf(PaneID("b")),
                second: .leaf(PaneID("c"))
            )
        )
        let result = tree.updatingRatio(of: SplitID("s2"), to: 0.2)
        // 外层 ratio 不变，内层变 0.2
        guard case .split(_, _, let outerRatio, _, let second) = result else {
            return XCTFail("expected split")
        }
        XCTAssertEqual(outerRatio, 0.5)
        guard case .split(_, _, let innerRatio, _, _) = second else {
            return XCTFail("expected nested split")
        }
        XCTAssertEqual(innerRatio, 0.2)
    }

    func testUpdatingRatioUnknownSplitIsNoOp() {
        let tree = SplitNode.split(
            id: SplitID("s1"), axis: .vertical, ratio: 0.5,
            first: .leaf(PaneID("a")),
            second: .leaf(PaneID("b"))
        )
        XCTAssertEqual(tree.updatingRatio(of: SplitID("zzz"), to: 0.9), tree)
    }

    private var threePaneTree: SplitNode {
        .split(
            id: SplitID("s1"), axis: .vertical, ratio: 0.5,
            first: .leaf(PaneID("a")),
            second: .split(
                id: SplitID("s2"), axis: .horizontal, ratio: 0.5,
                first: .leaf(PaneID("b")),
                second: .leaf(PaneID("c"))
            )
        )
    }

    func testPaneAfter() {
        XCTAssertEqual(threePaneTree.pane(after: PaneID("a")), PaneID("b"))
        XCTAssertEqual(threePaneTree.pane(after: PaneID("b")), PaneID("c"))
    }

    func testPaneAfterWrapsAround() {
        XCTAssertEqual(threePaneTree.pane(after: PaneID("c")), PaneID("a"))
    }

    func testPaneBeforeWrapsAround() {
        XCTAssertEqual(threePaneTree.pane(before: PaneID("a")), PaneID("c"))
        XCTAssertEqual(threePaneTree.pane(before: PaneID("b")), PaneID("a"))
    }

    func testPaneAfterUnknownReturnsNil() {
        XCTAssertNil(threePaneTree.pane(after: PaneID("zzz")))
    }

    func testPaneBeforeUnknownReturnsNil() {
        XCTAssertNil(threePaneTree.pane(before: PaneID("zzz")))
    }
}
