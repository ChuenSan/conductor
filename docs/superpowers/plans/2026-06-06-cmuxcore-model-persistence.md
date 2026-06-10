# CmuxCore（模型 + 持久化层）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 用纯 Swift（无 UI、无 libghostty）实现类 cmux 多终端管理器的核心数据模型（工作区 / Tab / 自由分屏树）与布局持久化层，全程 TDD，`swift test` 即可验证。

**Architecture:** 一个 SwiftPM 库 target `CmuxCore`。核心是 `SplitNode` 二叉树（叶子=终端 pane，分支=一次分屏），其上是 `Tab` / `Workspace` / `WorkspaceStore`。持久化把整棵模型树编码为带版本号的 JSON，原子写盘，读回时对损坏/缺失/版本不符做兜底。`TerminalSurface` 协议 + `FakeSurface` 测试替身在此建立终端抽象接缝（本计划不实现真终端）。

**Tech Stack:** Swift 6（SwiftPM，swift-tools-version 6.0），XCTest，Foundation（JSONEncoder/Decoder、FileManager）。平台 macOS 14+。

**范围说明（与 spec 的偏差，刻意为之）:**
- 本计划**不含** UI、`GhosttySurface`、`AppCoordinator`、键位绑定——它们依赖 libghostty 真实 API，留给 spike 之后的计划二。
- spec §11 提到“焦点移动”在模型层可测：本计划只实现**有序遍历**（next/prev pane），因为**方向性焦点（⌘⌥方向键）需要布局几何信息**（各 pane 的实际 frame），那属于 UI 层，留给计划二。
- 路径在持久化模型里以 `String`（绝对 POSIX 路径）存储，仅在 FileManager 边界转 URL，避免 file-URL 的 Codable 边角问题。

---

## File Structure

```
Package.swift
Sources/CmuxCore/
  SplitAxis.swift          # 分屏方向枚举
  Identifiers.swift        # PaneID / TabID / WorkspaceID / SplitID 值类型
  SplitNode.swift          # 分屏二叉树 + 所有树操作
  Models.swift             # Tab / Workspace / WorkspaceStore + 变更方法
  TerminalSurface.swift    # 终端抽象协议
  PersistedState.swift     # 带版本号的可序列化状态
  StateStore.swift         # 原子读写 + 损坏/缺失兜底
  CwdResolver.swift        # cwd 失效兜底链（纯函数）
Tests/CmuxCoreTests/
  SplitAxisTests.swift
  IdentifiersTests.swift
  SplitNodeTests.swift
  ModelsTests.swift
  FakeSurface.swift        # TerminalSurface 测试替身（测试辅助，非 production）
  TerminalSurfaceTests.swift
  PersistedStateTests.swift
  StateStoreTests.swift
  CwdResolverTests.swift
```

每个文件单一职责，便于独立持有与单测。`SplitNode.swift` 是最核心、最需要测试覆盖的文件。

---

## Task 1: 脚手架 SwiftPM 包 + SplitAxis

**Files:**
- Create: `Package.swift`
- Create: `Sources/CmuxCore/SplitAxis.swift`
- Test: `Tests/CmuxCoreTests/SplitAxisTests.swift`

- [ ] **Step 1: 写 Package.swift**

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CmuxCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CmuxCore", targets: ["CmuxCore"]),
    ],
    targets: [
        .target(name: "CmuxCore"),
        .testTarget(name: "CmuxCoreTests", dependencies: ["CmuxCore"]),
    ]
)
```

- [ ] **Step 2: 写第一个失败测试**

`Tests/CmuxCoreTests/SplitAxisTests.swift`:

```swift
import XCTest
@testable import CmuxCore

final class SplitAxisTests: XCTestCase {
    func testRawValues() {
        XCTAssertEqual(SplitAxis.horizontal.rawValue, "horizontal")
        XCTAssertEqual(SplitAxis.vertical.rawValue, "vertical")
    }

    func testCodableRoundTrip() throws {
        let data = try JSONEncoder().encode(SplitAxis.vertical)
        let decoded = try JSONDecoder().decode(SplitAxis.self, from: data)
        XCTAssertEqual(decoded, .vertical)
    }
}
```

- [ ] **Step 3: 跑测试，确认失败**

Run: `swift test --filter SplitAxisTests`
Expected: 编译失败，`cannot find 'SplitAxis' in scope`

- [ ] **Step 4: 实现 SplitAxis**

`Sources/CmuxCore/SplitAxis.swift`:

```swift
/// 分屏方向。horizontal = 上下分（分隔条水平），vertical = 左右分（分隔条竖直）。
public enum SplitAxis: String, Codable, Equatable {
    case horizontal
    case vertical
}
```

- [ ] **Step 5: 跑测试，确认通过**

Run: `swift test --filter SplitAxisTests`
Expected: PASS（2 个测试）

- [ ] **Step 6: 提交**

```bash
git add Package.swift Sources/CmuxCore/SplitAxis.swift Tests/CmuxCoreTests/SplitAxisTests.swift
git commit -m "feat(core): scaffold SwiftPM package + SplitAxis"
```

---

## Task 2: 标识符值类型

**Files:**
- Create: `Sources/CmuxCore/Identifiers.swift`
- Test: `Tests/CmuxCoreTests/IdentifiersTests.swift`

- [ ] **Step 1: 写失败测试**

`Tests/CmuxCoreTests/IdentifiersTests.swift`:

```swift
import XCTest
@testable import CmuxCore

final class IdentifiersTests: XCTestCase {
    func testEquality() {
        XCTAssertEqual(PaneID("a"), PaneID("a"))
        XCTAssertNotEqual(PaneID("a"), PaneID("b"))
    }

    func testUsableAsDictKey() {
        var map: [PaneID: Int] = [:]
        map[PaneID("a")] = 1
        XCTAssertEqual(map[PaneID("a")], 1)
    }

    func testCodableRoundTrip() throws {
        let id = WorkspaceID("ws-1")
        let data = try JSONEncoder().encode(id)
        let decoded = try JSONDecoder().decode(WorkspaceID.self, from: data)
        XCTAssertEqual(decoded, id)
    }
}
```

- [ ] **Step 2: 跑测试，确认失败**

Run: `swift test --filter IdentifiersTests`
Expected: 编译失败，`cannot find 'PaneID' in scope`

- [ ] **Step 3: 实现标识符**

`Sources/CmuxCore/Identifiers.swift`:

```swift
/// 一个终端 pane（分屏叶子）的稳定标识。
public struct PaneID: Hashable, Codable {
    public let value: String
    public init(_ value: String) { self.value = value }
}

/// 一个 Tab 的稳定标识。
public struct TabID: Hashable, Codable {
    public let value: String
    public init(_ value: String) { self.value = value }
}

/// 一个工作区的稳定标识。
public struct WorkspaceID: Hashable, Codable {
    public let value: String
    public init(_ value: String) { self.value = value }
}

/// 一次分屏（分隔条）的稳定标识，用于定位并调整其比例。
public struct SplitID: Hashable, Codable {
    public let value: String
    public init(_ value: String) { self.value = value }
}
```

- [ ] **Step 4: 跑测试，确认通过**

Run: `swift test --filter IdentifiersTests`
Expected: PASS（3 个测试）

- [ ] **Step 5: 提交**

```bash
git add Sources/CmuxCore/Identifiers.swift Tests/CmuxCoreTests/IdentifiersTests.swift
git commit -m "feat(core): add PaneID/TabID/WorkspaceID/SplitID value types"
```

---

## Task 3: SplitNode 树 + leaves()/contains()

**Files:**
- Create: `Sources/CmuxCore/SplitNode.swift`
- Test: `Tests/CmuxCoreTests/SplitNodeTests.swift`

- [ ] **Step 1: 写失败测试**

`Tests/CmuxCoreTests/SplitNodeTests.swift`:

```swift
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
}
```

- [ ] **Step 2: 跑测试，确认失败**

Run: `swift test --filter SplitNodeTests`
Expected: 编译失败，`cannot find 'SplitNode' in scope`

- [ ] **Step 3: 实现 SplitNode + leaves()/contains()**

`Sources/CmuxCore/SplitNode.swift`:

```swift
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
}
```

- [ ] **Step 4: 跑测试，确认通过**

Run: `swift test --filter SplitNodeTests`
Expected: PASS（4 个测试）

- [ ] **Step 5: 提交**

```bash
git add Sources/CmuxCore/SplitNode.swift Tests/CmuxCoreTests/SplitNodeTests.swift
git commit -m "feat(core): add SplitNode tree with leaves()/contains()"
```

---

## Task 4: SplitNode.splitting（插入分屏）

**Files:**
- Modify: `Sources/CmuxCore/SplitNode.swift`
- Test: `Tests/CmuxCoreTests/SplitNodeTests.swift`

- [ ] **Step 1: 追加失败测试**

在 `SplitNodeTests` 类中追加：

```swift
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
```

- [ ] **Step 2: 跑测试，确认失败**

Run: `swift test --filter SplitNodeTests`
Expected: 编译失败，`value of type 'SplitNode' has no member 'splitting'`

- [ ] **Step 3: 实现 splitting**

在 `SplitNode` 中追加方法：

```swift
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
```

- [ ] **Step 4: 跑测试，确认通过**

Run: `swift test --filter SplitNodeTests`
Expected: PASS（含新增 4 个）

- [ ] **Step 5: 提交**

```bash
git add Sources/CmuxCore/SplitNode.swift Tests/CmuxCoreTests/SplitNodeTests.swift
git commit -m "feat(core): SplitNode.splitting inserts a split at a target leaf"
```

---

## Task 5: SplitNode.removing（删除并塌缩）

**Files:**
- Modify: `Sources/CmuxCore/SplitNode.swift`
- Test: `Tests/CmuxCoreTests/SplitNodeTests.swift`

- [ ] **Step 1: 追加失败测试**

在 `SplitNodeTests` 中追加：

```swift
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
```

- [ ] **Step 2: 跑测试，确认失败**

Run: `swift test --filter SplitNodeTests`
Expected: 编译失败，`value of type 'SplitNode' has no member 'removing'`

- [ ] **Step 3: 实现 removing**

在 `SplitNode` 中追加方法：

```swift
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
```

- [ ] **Step 4: 跑测试，确认通过**

Run: `swift test --filter SplitNodeTests`
Expected: PASS（含新增 4 个）

- [ ] **Step 5: 提交**

```bash
git add Sources/CmuxCore/SplitNode.swift Tests/CmuxCoreTests/SplitNodeTests.swift
git commit -m "feat(core): SplitNode.removing deletes a pane and collapses splits"
```

---

## Task 6: SplitNode.updatingRatio（调整分隔条比例）

**Files:**
- Modify: `Sources/CmuxCore/SplitNode.swift`
- Test: `Tests/CmuxCoreTests/SplitNodeTests.swift`

- [ ] **Step 1: 追加失败测试**

在 `SplitNodeTests` 中追加：

```swift
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
```

- [ ] **Step 2: 跑测试，确认失败**

Run: `swift test --filter SplitNodeTests`
Expected: 编译失败，`value of type 'SplitNode' has no member 'updatingRatio'`

- [ ] **Step 3: 实现 updatingRatio**

在 `SplitNode` 中追加方法：

```swift
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
```

- [ ] **Step 4: 跑测试，确认通过**

Run: `swift test --filter SplitNodeTests`
Expected: PASS（含新增 3 个）

- [ ] **Step 5: 提交**

```bash
git add Sources/CmuxCore/SplitNode.swift Tests/CmuxCoreTests/SplitNodeTests.swift
git commit -m "feat(core): SplitNode.updatingRatio adjusts a divider ratio by id"
```

---

## Task 7: SplitNode 有序遍历（pane after/before）

**Files:**
- Modify: `Sources/CmuxCore/SplitNode.swift`
- Test: `Tests/CmuxCoreTests/SplitNodeTests.swift`

> 说明：这是**有序**焦点切换（按 leaves 顺序循环）。方向性（空间）焦点需要布局 frame，属于 UI 层，不在本计划。

- [ ] **Step 1: 追加失败测试**

在 `SplitNodeTests` 中追加：

```swift
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
```

- [ ] **Step 2: 跑测试，确认失败**

Run: `swift test --filter SplitNodeTests`
Expected: 编译失败，`value of type 'SplitNode' has no member 'pane(after:)'`

- [ ] **Step 3: 实现遍历**

在 `SplitNode` 中追加方法：

```swift
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
```

- [ ] **Step 4: 跑测试，确认通过**

Run: `swift test --filter SplitNodeTests`
Expected: PASS（含新增 4 个）

- [ ] **Step 5: 提交**

```bash
git add Sources/CmuxCore/SplitNode.swift Tests/CmuxCoreTests/SplitNodeTests.swift
git commit -m "feat(core): SplitNode ordered pane traversal (after/before, wrapping)"
```

---

## Task 8: Tab / Workspace / WorkspaceStore + 变更方法

**Files:**
- Create: `Sources/CmuxCore/Models.swift`
- Test: `Tests/CmuxCoreTests/ModelsTests.swift`

- [ ] **Step 1: 写失败测试**

`Tests/CmuxCoreTests/ModelsTests.swift`:

```swift
import XCTest
@testable import CmuxCore

final class ModelsTests: XCTestCase {
    func testSingleTabHasOneLeaf() {
        let tab = Tab.single(id: TabID("t1"), title: "zsh", pane: PaneID("p1"))
        XCTAssertEqual(tab.rootSplit, .leaf(PaneID("p1")))
        XCTAssertEqual(tab.activePane, PaneID("p1"))
    }

    func testWorkspaceAddTabSetsActive() {
        var ws = Workspace(id: WorkspaceID("w1"), name: "proj", path: "/tmp/proj",
                           tabs: [], activeTab: nil)
        ws.addTab(Tab.single(id: TabID("t1"), title: "zsh", pane: PaneID("p1")))
        XCTAssertEqual(ws.tabs.count, 1)
        XCTAssertEqual(ws.activeTab, TabID("t1"))
    }

    func testWorkspaceCloseActiveTabFallsBackToPrevious() {
        var ws = Workspace(id: WorkspaceID("w1"), name: "proj", path: "/tmp/proj",
                           tabs: [], activeTab: nil)
        ws.addTab(Tab.single(id: TabID("t1"), title: "a", pane: PaneID("p1")))
        ws.addTab(Tab.single(id: TabID("t2"), title: "b", pane: PaneID("p2")))
        // active 现在是 t2；关掉 t2 应回退到 t1
        ws.closeTab(TabID("t2"))
        XCTAssertEqual(ws.tabs.map(\.id), [TabID("t1")])
        XCTAssertEqual(ws.activeTab, TabID("t1"))
    }

    func testWorkspaceCloseLastTabClearsActive() {
        var ws = Workspace(id: WorkspaceID("w1"), name: "proj", path: "/tmp/proj",
                           tabs: [], activeTab: nil)
        ws.addTab(Tab.single(id: TabID("t1"), title: "a", pane: PaneID("p1")))
        ws.closeTab(TabID("t1"))
        XCTAssertTrue(ws.tabs.isEmpty)
        XCTAssertNil(ws.activeTab)
    }

    func testStoreUpsertAndActive() {
        var store = WorkspaceStore(workspaces: [], activeWorkspace: nil)
        let ws = Workspace(id: WorkspaceID("w1"), name: "proj", path: "/tmp/proj",
                           tabs: [], activeTab: nil)
        store.upsert(ws)
        XCTAssertEqual(store.workspaces.count, 1)
        XCTAssertEqual(store.activeWorkspace, WorkspaceID("w1"))
        // 再次 upsert 同 id 应替换而非新增
        var updated = ws
        updated.name = "renamed"
        store.upsert(updated)
        XCTAssertEqual(store.workspaces.count, 1)
        XCTAssertEqual(store.workspaces.first?.name, "renamed")
    }

    func testStoreRemoveWorkspaceUpdatesActive() {
        var store = WorkspaceStore(workspaces: [], activeWorkspace: nil)
        store.upsert(Workspace(id: WorkspaceID("w1"), name: "a", path: "/a", tabs: [], activeTab: nil))
        store.upsert(Workspace(id: WorkspaceID("w2"), name: "b", path: "/b", tabs: [], activeTab: nil))
        store.remove(WorkspaceID("w2"))   // active 当前是 w2
        XCTAssertEqual(store.workspaces.map(\.id), [WorkspaceID("w1")])
        XCTAssertEqual(store.activeWorkspace, WorkspaceID("w1"))
    }
}
```

- [ ] **Step 2: 跑测试，确认失败**

Run: `swift test --filter ModelsTests`
Expected: 编译失败，`cannot find 'Tab' in scope`

- [ ] **Step 3: 实现模型**

`Sources/CmuxCore/Models.swift`:

```swift
/// 工作区内的一个 Tab：持有一棵分屏树和当前焦点 pane。
public struct Tab: Codable, Equatable {
    public var id: TabID
    public var title: String
    public var rootSplit: SplitNode
    public var activePane: PaneID

    public init(id: TabID, title: String, rootSplit: SplitNode, activePane: PaneID) {
        self.id = id
        self.title = title
        self.rootSplit = rootSplit
        self.activePane = activePane
    }

    /// 便捷构造：单 pane 的 Tab。
    public static func single(id: TabID, title: String, pane: PaneID) -> Tab {
        Tab(id: id, title: title, rootSplit: .leaf(pane), activePane: pane)
    }
}

/// 绑定一个目录路径的工作区，含若干 Tab。
public struct Workspace: Codable, Equatable {
    public var id: WorkspaceID
    public var name: String
    public var path: String            // 绝对 POSIX 路径
    public var tabs: [Tab]
    public var activeTab: TabID?

    public init(id: WorkspaceID, name: String, path: String, tabs: [Tab], activeTab: TabID?) {
        self.id = id
        self.name = name
        self.path = path
        self.tabs = tabs
        self.activeTab = activeTab
    }

    /// 追加一个 Tab 并设为 active。
    public mutating func addTab(_ tab: Tab) {
        tabs.append(tab)
        activeTab = tab.id
    }

    /// 关闭指定 Tab；若它是 active，则回退到它前一个（无则后一个，再无则 nil）。
    public mutating func closeTab(_ id: TabID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let wasActive = activeTab == id
        tabs.remove(at: index)
        guard wasActive else { return }
        if tabs.isEmpty {
            activeTab = nil
        } else {
            let fallback = index > 0 ? index - 1 : 0
            activeTab = tabs[fallback].id
        }
    }
}

/// 所有工作区的容器。
public struct WorkspaceStore: Codable, Equatable {
    public var workspaces: [Workspace]
    public var activeWorkspace: WorkspaceID?

    public init(workspaces: [Workspace], activeWorkspace: WorkspaceID?) {
        self.workspaces = workspaces
        self.activeWorkspace = activeWorkspace
    }

    /// 插入或按 id 替换一个工作区；插入新工作区时将其设为 active。
    public mutating func upsert(_ workspace: Workspace) {
        if let index = workspaces.firstIndex(where: { $0.id == workspace.id }) {
            workspaces[index] = workspace
        } else {
            workspaces.append(workspace)
            activeWorkspace = workspace.id
        }
    }

    /// 移除工作区；若它是 active，则回退到第一个剩余工作区（无则 nil）。
    public mutating func remove(_ id: WorkspaceID) {
        workspaces.removeAll { $0.id == id }
        if activeWorkspace == id {
            activeWorkspace = workspaces.first?.id
        }
    }
}
```

- [ ] **Step 4: 跑测试，确认通过**

Run: `swift test --filter ModelsTests`
Expected: PASS（6 个测试）

- [ ] **Step 5: 提交**

```bash
git add Sources/CmuxCore/Models.swift Tests/CmuxCoreTests/ModelsTests.swift
git commit -m "feat(core): add Tab/Workspace/WorkspaceStore with mutations"
```

---

## Task 9: TerminalSurface 协议 + FakeSurface 替身

**Files:**
- Create: `Sources/CmuxCore/TerminalSurface.swift`
- Create: `Tests/CmuxCoreTests/FakeSurface.swift`
- Test: `Tests/CmuxCoreTests/TerminalSurfaceTests.swift`

- [ ] **Step 1: 写协议**

`Sources/CmuxCore/TerminalSurface.swift`:

```swift
import Foundation

/// 一个终端实例的抽象接口。生产实现（GhosttySurface，本计划之外）封装 libghostty；
/// 上层只依赖本协议，从而隔离 libghostty 并支持用替身测试协调逻辑。
public protocol TerminalSurface: AnyObject {
    /// 在给定工作目录启动 shell/PTY。
    func start(cwd: URL)
    /// 向终端写入输入数据。
    func write(_ data: Data)
    /// 调整终端尺寸（列、行）。
    func resize(cols: Int, rows: Int)
    /// 使该终端获得键盘焦点。
    func focus()
    /// 关闭终端并释放底层资源。
    func close()

    /// 终端标题变化（OSC）回调。
    var onTitleChange: ((String) -> Void)? { get set }
    /// 终端工作目录变化回调。
    var onCwdChange: ((URL) -> Void)? { get set }
    /// 进程退出回调，参数为退出码。
    var onExit: ((Int32) -> Void)? { get set }
}
```

- [ ] **Step 2: 写 FakeSurface 替身（测试辅助）**

`Tests/CmuxCoreTests/FakeSurface.swift`:

```swift
import Foundation
@testable import CmuxCore

/// TerminalSurface 的测试替身：记录调用，并允许测试手动触发回调。
final class FakeSurface: TerminalSurface {
    private(set) var startedCwd: URL?
    private(set) var writes: [Data] = []
    private(set) var lastResize: (cols: Int, rows: Int)?
    private(set) var focusCount = 0
    private(set) var closed = false

    var onTitleChange: ((String) -> Void)?
    var onCwdChange: ((URL) -> Void)?
    var onExit: ((Int32) -> Void)?

    func start(cwd: URL) { startedCwd = cwd }
    func write(_ data: Data) { writes.append(data) }
    func resize(cols: Int, rows: Int) { lastResize = (cols, rows) }
    func focus() { focusCount += 1 }
    func close() { closed = true }

    // 测试用：模拟底层事件
    func simulateTitleChange(_ title: String) { onTitleChange?(title) }
    func simulateCwdChange(_ url: URL) { onCwdChange?(url) }
    func simulateExit(_ code: Int32) { onExit?(code) }
}
```

- [ ] **Step 3: 写测试，确认失败**

`Tests/CmuxCoreTests/TerminalSurfaceTests.swift`:

```swift
import XCTest
import Foundation
@testable import CmuxCore

final class TerminalSurfaceTests: XCTestCase {
    func testFakeRecordsLifecycle() {
        let surface = FakeSurface()
        surface.start(cwd: URL(fileURLWithPath: "/tmp"))
        surface.write(Data([0x61]))
        surface.resize(cols: 80, rows: 24)
        surface.focus()
        surface.close()

        XCTAssertEqual(surface.startedCwd, URL(fileURLWithPath: "/tmp"))
        XCTAssertEqual(surface.writes, [Data([0x61])])
        XCTAssertEqual(surface.lastResize?.cols, 80)
        XCTAssertEqual(surface.lastResize?.rows, 24)
        XCTAssertEqual(surface.focusCount, 1)
        XCTAssertTrue(surface.closed)
    }

    func testFakeFiresCallbacks() {
        let surface = FakeSurface()
        var title: String?
        var exitCode: Int32?
        surface.onTitleChange = { title = $0 }
        surface.onExit = { exitCode = $0 }

        surface.simulateTitleChange("build running")
        surface.simulateExit(0)

        XCTAssertEqual(title, "build running")
        XCTAssertEqual(exitCode, 0)
    }
}
```

Run: `swift test --filter TerminalSurfaceTests`
Expected: 编译失败，`cannot find type 'TerminalSurface' in scope`（写完 Step 1 文件后，若仍未保存会失败）

- [ ] **Step 4: 跑测试，确认通过**

Run: `swift test --filter TerminalSurfaceTests`
Expected: PASS（2 个测试）

- [ ] **Step 5: 提交**

```bash
git add Sources/CmuxCore/TerminalSurface.swift Tests/CmuxCoreTests/FakeSurface.swift Tests/CmuxCoreTests/TerminalSurfaceTests.swift
git commit -m "feat(core): add TerminalSurface protocol + FakeSurface test double"
```

---

## Task 10: PersistedState + Codable 往返

**Files:**
- Create: `Sources/CmuxCore/PersistedState.swift`
- Test: `Tests/CmuxCoreTests/PersistedStateTests.swift`

- [ ] **Step 1: 写失败测试**

`Tests/CmuxCoreTests/PersistedStateTests.swift`:

```swift
import XCTest
@testable import CmuxCore

final class PersistedStateTests: XCTestCase {
    private func sampleStore() -> WorkspaceStore {
        let tab = Tab(
            id: TabID("t1"), title: "zsh",
            rootSplit: .split(
                id: SplitID("s1"), axis: .vertical, ratio: 0.6,
                first: .leaf(PaneID("p1")),
                second: .leaf(PaneID("p2"))
            ),
            activePane: PaneID("p1")
        )
        let ws = Workspace(id: WorkspaceID("w1"), name: "proj", path: "/tmp/proj",
                           tabs: [tab], activeTab: TabID("t1"))
        return WorkspaceStore(workspaces: [ws], activeWorkspace: WorkspaceID("w1"))
    }

    func testDefaultVersionIsCurrent() {
        let state = PersistedState(store: sampleStore())
        XCTAssertEqual(state.version, PersistedState.currentVersion)
    }

    func testRoundTripPreservesFullTree() throws {
        let original = PersistedState(store: sampleStore())
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PersistedState.self, from: data)
        XCTAssertEqual(decoded, original)
    }
}
```

- [ ] **Step 2: 跑测试，确认失败**

Run: `swift test --filter PersistedStateTests`
Expected: 编译失败，`cannot find 'PersistedState' in scope`

- [ ] **Step 3: 实现 PersistedState**

`Sources/CmuxCore/PersistedState.swift`:

```swift
/// 落盘的顶层状态：带 schema 版本号，便于将来迁移。
public struct PersistedState: Codable, Equatable {
    /// 当前 schema 版本。结构不兼容变更时递增。
    public static let currentVersion = 1

    public var version: Int
    public var store: WorkspaceStore

    public init(version: Int = PersistedState.currentVersion, store: WorkspaceStore) {
        self.version = version
        self.store = store
    }
}
```

- [ ] **Step 4: 跑测试，确认通过**

Run: `swift test --filter PersistedStateTests`
Expected: PASS（2 个测试）

- [ ] **Step 5: 提交**

```bash
git add Sources/CmuxCore/PersistedState.swift Tests/CmuxCoreTests/PersistedStateTests.swift
git commit -m "feat(core): add versioned PersistedState with Codable round-trip"
```

---

## Task 11: StateStore（原子写 + 读取兜底）

**Files:**
- Create: `Sources/CmuxCore/StateStore.swift`
- Test: `Tests/CmuxCoreTests/StateStoreTests.swift`

- [ ] **Step 1: 写失败测试**

`Tests/CmuxCoreTests/StateStoreTests.swift`:

```swift
import XCTest
@testable import CmuxCore

final class StateStoreTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cmux-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func sampleState() -> PersistedState {
        let ws = Workspace(id: WorkspaceID("w1"), name: "proj", path: "/tmp/proj",
                           tabs: [Tab.single(id: TabID("t1"), title: "zsh", pane: PaneID("p1"))],
                           activeTab: TabID("t1"))
        return PersistedState(store: WorkspaceStore(workspaces: [ws], activeWorkspace: WorkspaceID("w1")))
    }

    func testSaveThenLoadRoundTrips() throws {
        let url = dir.appendingPathComponent("state.json")
        let store = StateStore(fileURL: url)
        let state = sampleState()
        try store.save(state)

        let result = store.load()
        XCTAssertEqual(result.outcome, .loaded)
        XCTAssertEqual(result.state, state)
    }

    func testLoadMissingFileReturnsFresh() {
        let url = dir.appendingPathComponent("does-not-exist.json")
        let store = StateStore(fileURL: url)
        let result = store.load()
        XCTAssertEqual(result.outcome, .fresh)
        XCTAssertTrue(result.state.store.workspaces.isEmpty)
    }

    func testLoadCorruptFileRecoversAndBacksUp() throws {
        let url = dir.appendingPathComponent("state.json")
        try Data("not json {{{".utf8).write(to: url)
        let store = StateStore(fileURL: url)

        let result = store.load()
        XCTAssertEqual(result.outcome, .recovered)
        XCTAssertTrue(result.state.store.workspaces.isEmpty)

        // 坏文件应被备份（目录里出现一个 .corrupt-* 文件）
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertTrue(files.contains { $0.contains("corrupt") },
                      "expected a backup of the corrupt file, got \(files)")
    }

    func testLoadIncompatibleVersionRecovers() throws {
        let url = dir.appendingPathComponent("state.json")
        // 构造一个版本号远高于当前的合法 JSON
        let future = """
        {"version": 9999, "store": {"workspaces": [], "activeWorkspace": null}}
        """
        try Data(future.utf8).write(to: url)
        let store = StateStore(fileURL: url)

        let result = store.load()
        XCTAssertEqual(result.outcome, .recovered)
    }
}
```

- [ ] **Step 2: 跑测试，确认失败**

Run: `swift test --filter StateStoreTests`
Expected: 编译失败，`cannot find 'StateStore' in scope`

- [ ] **Step 3: 实现 StateStore**

`Sources/CmuxCore/StateStore.swift`:

```swift
import Foundation

/// 读写持久化状态文件。写入原子化；读取对缺失/损坏/版本不符做兜底，绝不抛给上层。
public struct StateStore {
    public enum LoadOutcome: Equatable {
        case loaded       // 成功读到兼容状态
        case fresh        // 文件不存在，返回空状态
        case recovered    // 文件损坏/版本不符，已备份坏文件并返回空状态
    }

    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// 原子写入（Foundation 的 .atomic 会先写临时文件再 rename）。
    public func save(_ state: PersistedState) throws {
        let data = try JSONEncoder().encode(state)
        try data.write(to: fileURL, options: .atomic)
    }

    /// 读取状态。返回状态 + 结果分类。损坏/版本不符时备份坏文件并返回空状态。
    public func load() -> (state: PersistedState, outcome: LoadOutcome) {
        let fresh = PersistedState(store: WorkspaceStore(workspaces: [], activeWorkspace: nil))

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return (fresh, .fresh)
        }

        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode(PersistedState.self, from: data),
              decoded.version <= PersistedState.currentVersion else {
            backupCorruptFile()
            return (fresh, .recovered)
        }

        return (decoded, .loaded)
    }

    private func backupCorruptFile() {
        let stamp = Int(Date().timeIntervalSince1970)
        let backup = fileURL.appendingPathExtension("corrupt-\(stamp)")
        try? FileManager.default.moveItem(at: fileURL, to: backup)
    }
}
```

- [ ] **Step 4: 跑测试，确认通过**

Run: `swift test --filter StateStoreTests`
Expected: PASS（4 个测试）

- [ ] **Step 5: 提交**

```bash
git add Sources/CmuxCore/StateStore.swift Tests/CmuxCoreTests/StateStoreTests.swift
git commit -m "feat(core): add StateStore with atomic save and corrupt/missing recovery"
```

---

## Task 12: CwdResolver（cwd 失效兜底链）

**Files:**
- Create: `Sources/CmuxCore/CwdResolver.swift`
- Test: `Tests/CmuxCoreTests/CwdResolverTests.swift`

- [ ] **Step 1: 写失败测试**

`Tests/CmuxCoreTests/CwdResolverTests.swift`:

```swift
import XCTest
@testable import CmuxCore

final class CwdResolverTests: XCTestCase {
    func testUsesCwdWhenItExists() {
        let result = CwdResolver.resolve(
            cwd: "/proj/sub", workspacePath: "/proj", home: "/Users/me",
            exists: { $0 == "/proj/sub" }
        )
        XCTAssertEqual(result, "/proj/sub")
    }

    func testFallsBackToWorkspaceWhenCwdMissing() {
        let result = CwdResolver.resolve(
            cwd: "/proj/sub", workspacePath: "/proj", home: "/Users/me",
            exists: { $0 == "/proj" }
        )
        XCTAssertEqual(result, "/proj")
    }

    func testFallsBackToHomeWhenBothMissing() {
        let result = CwdResolver.resolve(
            cwd: "/proj/sub", workspacePath: "/proj", home: "/Users/me",
            exists: { _ in false }
        )
        XCTAssertEqual(result, "/Users/me")
    }
}
```

- [ ] **Step 2: 跑测试，确认失败**

Run: `swift test --filter CwdResolverTests`
Expected: 编译失败，`cannot find 'CwdResolver' in scope`

- [ ] **Step 3: 实现 CwdResolver**

`Sources/CmuxCore/CwdResolver.swift`:

```swift
import Foundation

/// 恢复布局时，为一个 pane 选择实际可用的启动目录：cwd → 工作区 path → home。
/// `exists` 注入以便单测；生产用 FileManager.default.fileExists。
public enum CwdResolver {
    public static func resolve(cwd: String, workspacePath: String, home: String,
                               exists: (String) -> Bool) -> String {
        if exists(cwd) { return cwd }
        if exists(workspacePath) { return workspacePath }
        return home
    }

    /// 生产便捷入口：用真实文件系统判断。
    public static func resolve(cwd: String, workspacePath: String,
                               home: String = NSHomeDirectory()) -> String {
        resolve(cwd: cwd, workspacePath: workspacePath, home: home,
                exists: { FileManager.default.fileExists(atPath: $0) })
    }
}
```

- [ ] **Step 4: 跑测试，确认通过**

Run: `swift test --filter CwdResolverTests`
Expected: PASS（3 个测试）

- [ ] **Step 5: 跑全量测试 + 提交**

Run: `swift test`
Expected: 全部 PASS（约 35+ 个测试）

```bash
git add Sources/CmuxCore/CwdResolver.swift Tests/CmuxCoreTests/CwdResolverTests.swift
git commit -m "feat(core): add CwdResolver fallback chain (cwd -> workspace -> home)"
```

---

## Self-Review（计划作者已核对）

**1. Spec coverage（对照 spec 各节）:**
- §4 模型层（Workspace/Tab/SplitNode/PaneID/cwd）→ Tasks 2,3,8 ✓
- §5 数据模型（SplitNode 二叉树、ratio 可调持久化）→ Tasks 3–6 ✓
- §6 TerminalSurface 协议 + FakeSurface → Task 9 ✓
- §9 持久化（只存结构、版本号、原子写、cwd 兜底链）→ Tasks 10,11,12 ✓
- §11 测试（SplitNode 操作、Store 变更、序列化往返、恢复兜底、FakeSurface）→ Tasks 3–12 ✓
- **明确不在本计划**（已在范围说明声明）：UI 层(§7)、GhosttySurface(§4 桥接)、键位(§8)、错误对话框/线程切换(§10 运行时部分)、spike(§12) → 留计划二/spike 轨道。
- **对 spec 的一处修正**：§11 的“焦点移动”本计划实现为有序遍历；方向性焦点需布局几何，归 UI 层（已在范围说明记录）。

**2. Placeholder scan:** 无 TBD/TODO；每个代码步骤含完整可编译代码与确切命令/期望输出。✓

**3. Type consistency:** 跨任务核对一致 —— `SplitNode.split(id:axis:ratio:first:second:)`、`splitting(_:with:axis:ratio:splitID:newPaneFirst:)`、`removing(_:)`、`updatingRatio(of:to:)`、`pane(after:)/pane(before:)`、`Tab.single(id:title:pane:)`、`Workspace.addTab/closeTab`、`WorkspaceStore.upsert/remove`、`PersistedState(version:store:)` + `.currentVersion`、`StateStore.save/load` + `LoadOutcome{.loaded,.fresh,.recovered}`、`CwdResolver.resolve(...)`。在后续任务的测试中用法与定义一致。✓
