import ConductorCore
import Foundation

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("ConductorModelCheck failed: \(message)\n", stderr)
        exit(1)
    }
}

func requireValidWorkspace(_ workspace: WorkspaceState, _ context: String) {
    let leaves = workspace.root.leaves
    require(!leaves.isEmpty, "\(context): split tree should have at least one leaf")
    require(Set(leaves).count == leaves.count, "\(context): split tree should not duplicate panes")
    require(Set(leaves) == Set(workspace.panes.keys), "\(context): split leaves should match pane dictionary")
    require(workspace.panes[workspace.focusedPaneID] != nil, "\(context): focused pane should exist")
    for paneID in leaves {
        guard let pane = workspace.panes[paneID] else {
            return require(false, "\(context): leaf pane should exist")
        }
        require(!pane.tabs.isEmpty, "\(context): pane should always contain at least one tab")
        require(pane.tabs.contains(where: { $0.id == pane.selectedTabID }), "\(context): selected tab should exist in pane")
        require(Set(pane.tabs.map(\.id)).count == pane.tabs.count, "\(context): pane should not duplicate tabs")
    }
    if let zoomedPaneID = workspace.zoomedPaneID {
        require(workspace.panes[zoomedPaneID] != nil, "\(context): zoomed pane should exist")
    }
}

func checkRenderBudgetDefaults() {
    require(RenderBudget.smallListLimit == 100, "small render budget should be capped")
    require(RenderBudget.mediumListLimit == 250, "medium render budget should be capped")
    require(RenderBudget.largeListPreviewLimit == 1_000, "large preview budget should be bounded")
    require(RenderBudget.defaultVisibleRows == 40, "default visible row budget should match expected viewport")
    require(RenderBudget.defaultOverscanRows == 12, "default overscan budget should be bounded")
    require(RenderBudget.visibleRowWindow(defaultVisibleCount: 40, overscan: 12) == 64, "visible row window should include overscan")
}

extension SplitNode {
    func usesOnly(axis expectedAxis: SplitAxis) -> Bool {
        switch self {
        case .leaf:
            return true
        case let .split(axis, first, second, _):
            return axis == expectedAxis &&
                first.usesOnly(axis: expectedAxis) &&
                second.usesOnly(axis: expectedAxis)
        }
    }
}

func checkNewWorkspace() {
    let workspace = WorkspaceState()
    require(workspace.root.leaves.count == 1, "new workspace should start with one pane")
    require(workspace.focusedPane?.tabs.count == 1, "new workspace should start with one terminal")
    require(workspace.focusedPane?.selectedTab?.title == "zsh", "initial terminal should be zsh")
    requireValidWorkspace(workspace, "new workspace")
}

func checkNewTerminalTab() {
    var workspace = WorkspaceState()
    let paneID = workspace.focusedPaneID
    let terminalID = workspace.newTerminal(title: "server")
    require(workspace.root.leaves == [paneID], "new terminal should add a tab, not split")
    require(workspace.panes[paneID]?.tabs.map(\.title) == ["zsh", "server"], "pane should contain zsh and server tabs")
    require(workspace.panes[paneID]?.selectedTabID == terminalID, "new terminal tab should become selected")
}

func checkSplitRight() {
    var workspace = WorkspaceState()
    let originalPaneID = workspace.focusedPaneID
    guard let newPaneID = workspace.splitFocusedPane(.right, title: "agent") else {
        return require(false, "split right should be valid for a new workspace")
    }
    require(workspace.root.leaves == [originalPaneID, newPaneID], "split right should append a pane")
    require(workspace.focusedPaneID == newPaneID, "new split pane should be focused")
    guard case let .split(axis, first, second, fraction) = workspace.root else {
        return require(false, "root should be split after split right")
    }
    require(axis == .horizontal, "split right should create horizontal split")
    require(first == .leaf(originalPaneID), "original pane should stay first")
    require(second == .leaf(newPaneID), "new pane should be second")
    require(fraction == 0.5, "initial split fraction should be even")
}

func checkSplitDownNested() {
    var workspace = WorkspaceState()
    guard let rightPaneID = workspace.splitFocusedPane(.right, title: "agent"),
          let bottomPaneID = workspace.splitFocusedPane(.down, title: "logs") else {
        return require(false, "nested splits should be valid")
    }
    require(workspace.root.leaves.count == 3, "nested split should produce three panes")
    require(workspace.focusedPaneID == bottomPaneID, "bottom split should be focused")
    guard case let .split(.horizontal, _, second, _) = workspace.root,
          case let .split(axis, first, secondNested, _) = second else {
        return require(false, "right pane should become a vertical nested split")
    }
    require(axis == .vertical, "split down should create vertical split")
    require(first == .leaf(rightPaneID), "previous focused pane should stay first in nested split")
    require(secondNested == .leaf(bottomPaneID), "new pane should be second in nested split")
}

func checkWorkspaceEdgeSplitAvoidsCornerNesting() {
    var workspace = WorkspaceState()
    for index in 2...5 {
        guard workspace.splitWorkspaceEdge(.right, title: "zsh \(index)") != nil else {
            return require(false, "workspace edge split should create pane \(index)")
        }
    }

    require(workspace.root.leaves.count == 5, "workspace edge split should keep five panes")
    require(workspace.root.usesOnly(axis: .horizontal), "five right splits should become full-height columns")
    requireValidWorkspace(workspace, "workspace edge split")

    var verticalWorkspace = WorkspaceState()
    for index in 2...4 {
        guard verticalWorkspace.splitWorkspaceEdge(.down, title: "zsh \(index)") != nil else {
            return require(false, "workspace edge down split should create pane \(index)")
        }
    }
    require(verticalWorkspace.root.usesOnly(axis: .vertical), "down splits should become full-width rows")
}

func checkMixedPersistedLayoutNormalizes() {
    var workspace = WorkspaceState()
    let firstPaneID = workspace.focusedPaneID
    guard let secondPaneID = workspace.splitFocusedPane(.right, title: "two"),
          let thirdPaneID = workspace.splitFocusedPane(.down, title: "three"),
          let fourthPaneID = workspace.splitFocusedPane(.right, title: "four") else {
        return require(false, "mixed split setup should be valid")
    }
    require(workspace.root.containsMixedAxes, "setup should create mixed axes")
    workspace.normalizeMixedSplitLayout()
    require(workspace.root.leaves == [firstPaneID, secondPaneID, thirdPaneID, fourthPaneID], "normalization should preserve pane order")
    require(workspace.root.usesOnly(axis: .horizontal), "mixed persisted layout should flatten to primary axis")
    requireValidWorkspace(workspace, "normalize mixed persisted layout")
}

func checkSplitTreeReconciliationRestoresOrphanPanes() {
    var workspace = WorkspaceState()
    let firstPaneID = workspace.focusedPaneID
    guard let secondPaneID = workspace.splitFocusedPane(.right, title: "two") else {
        return require(false, "split setup should create second pane")
    }

    workspace.root = .leaf(firstPaneID)
    workspace.focusedPaneID = secondPaneID
    require(!workspace.hasCoherentSplitTree, "corrupted setup should detect orphan pane")

    workspace.reconcileSplitTreeWithPanes()
    require(workspace.hasCoherentSplitTree, "reconciliation should restore split tree coherence")
    require(Set(workspace.root.leaves) == Set([firstPaneID, secondPaneID]), "reconciliation should keep every pane visible")
    require(workspace.focusedPaneID == secondPaneID, "reconciliation should preserve valid focused pane")
    requireValidWorkspace(workspace, "reconciled split tree")
}

func checkCloseSelectedTabFocusesNearestTab() {
    var workspace = WorkspaceState()
    let paneID = workspace.focusedPaneID
    let firstTerminalID = workspace.focusedPane?.selectedTabID
    let secondTerminalID = workspace.newTerminal(title: "server")
    let result = workspace.closeTab(secondTerminalID, in: paneID)

    require(result.closedTerminalIDs == [secondTerminalID], "closing selected tab should report closed terminal")
    require(workspace.panes[paneID]?.tabs.count == 1, "pane should have one remaining tab")
    require(workspace.panes[paneID]?.selectedTabID == firstTerminalID, "nearest remaining tab should be selected")
    require(workspace.focusedPaneID == paneID, "closing tab should keep pane focused")
}

func checkCloseInactiveTabPreservesSelection() {
    var workspace = WorkspaceState()
    let paneID = workspace.focusedPaneID
    let firstTerminalID = workspace.focusedPane?.selectedTabID
    let secondTerminalID = workspace.newTerminal(title: "server")
    workspace.selectTab(firstTerminalID!, in: paneID)
    let result = workspace.closeTab(secondTerminalID, in: paneID)

    require(result.closedTerminalIDs == [secondTerminalID], "inactive tab close should report closed terminal")
    require(workspace.panes[paneID]?.selectedTabID == firstTerminalID, "inactive tab close should preserve selection")
}

func checkCloseOnlyTerminalCreatesReplacement() {
    var workspace = WorkspaceState()
    let paneID = workspace.focusedPaneID
    guard let originalTerminalID = workspace.focusedPane?.selectedTabID else {
        return require(false, "workspace should have an initial terminal")
    }
    let result = workspace.closeTab(originalTerminalID, in: paneID)

    require(result.closedTerminalIDs == [originalTerminalID], "only terminal close should report old terminal")
    require(result.replacementTerminalID != nil, "only terminal close should create replacement")
    require(workspace.root.leaves == [paneID], "only terminal close should keep same pane")
    require(workspace.panes[paneID]?.tabs.count == 1, "replacement pane should have one terminal")
    require(workspace.panes[paneID]?.selectedTabID == result.replacementTerminalID, "replacement should be selected")
}

func checkCloseLastTabInPaneCollapsesSplit() {
    var workspace = WorkspaceState()
    let originalPaneID = workspace.focusedPaneID
    guard let secondPaneID = workspace.splitFocusedPane(.right, title: "agent"),
          let secondTerminalID = workspace.panes[secondPaneID]?.selectedTabID else {
        return require(false, "split should create second pane")
    }
    let result = workspace.closeTab(secondTerminalID, in: secondPaneID)

    require(result.closedTerminalIDs == [secondTerminalID], "closing last tab in pane should close terminal")
    require(result.closedPaneIDs == [secondPaneID], "closing last tab in pane should close pane")
    require(workspace.root == .leaf(originalPaneID), "split tree should collapse to original pane")
    require(workspace.focusedPaneID == originalPaneID, "focus should move to surviving pane")
}

func checkCloseNestedPaneCollapsesOnlyParent() {
    var workspace = WorkspaceState()
    let originalPaneID = workspace.focusedPaneID
    guard let rightPaneID = workspace.splitFocusedPane(.right, title: "agent"),
          let bottomPaneID = workspace.splitFocusedPane(.down, title: "logs") else {
        return require(false, "nested split setup should be valid")
    }
    let result = workspace.closePane(bottomPaneID)

    require(result.closedPaneIDs == [bottomPaneID], "close pane should report closed pane")
    require(workspace.root.leaves == [originalPaneID, rightPaneID], "nested split should collapse to surviving panes")
    require(workspace.panes[bottomPaneID] == nil, "closed pane should be removed")
    require(workspace.panes[workspace.focusedPaneID] != nil, "focus should point to a surviving pane")
}

func checkCloseZoomedPaneClearsZoom() {
    var workspace = WorkspaceState()
    guard let zoomedPaneID = workspace.splitFocusedPane(.right, title: "agent") else {
        return require(false, "split should create zoomed candidate")
    }
    workspace.toggleZoom()
    require(workspace.zoomedPaneID == zoomedPaneID, "toggle zoom should zoom focused pane")
    _ = workspace.closePane(zoomedPaneID)

    require(!workspace.isZoomed, "closing zoomed pane should clear zoom")
    require(workspace.panes[zoomedPaneID] == nil, "closed zoomed pane should be removed")
    requireValidWorkspace(workspace, "close zoomed pane")
}

func checkCloseDifferentPaneKeepsValidZoom() {
    var workspace = WorkspaceState()
    let originalPaneID = workspace.focusedPaneID
    guard let secondPaneID = workspace.splitFocusedPane(.right, title: "agent") else {
        return require(false, "split should create second pane")
    }
    workspace.focusPane(originalPaneID)
    workspace.toggleZoom()
    require(workspace.zoomedPaneID == originalPaneID, "original pane should be zoomed")
    _ = workspace.closePane(secondPaneID)

    require(workspace.zoomedPaneID == originalPaneID, "closing different pane should keep valid zoom")
    require(workspace.visibleRoot == .leaf(originalPaneID), "visible root should remain zoomed original pane")
    requireValidWorkspace(workspace, "close non-zoomed pane with zoom")
}

func checkSplitLimit() {
    var workspace = WorkspaceState()
    while workspace.canSplit() {
        _ = workspace.splitFocusedPane(.right, title: "zsh")
    }
    let paneCount = workspace.panes.count
    let denied = workspace.splitFocusedPane(.right, title: "overflow")

    require(paneCount == WorkspaceState.defaultMaximumPaneCount, "workspace should stop at maximum pane count")
    require(denied == nil, "split beyond maximum should be denied")
    require(workspace.panes.count == paneCount, "denied split should not mutate pane count")
}

func checkAdjacentTabSelectionWraps() {
    var workspace = WorkspaceState()
    let paneID = workspace.focusedPaneID
    guard let first = workspace.focusedPane?.selectedTabID else {
        return require(false, "workspace should have initial tab")
    }
    let second = workspace.newTerminal(title: "server")
    _ = workspace.selectAdjacentTab(offset: 1, in: paneID)
    require(workspace.panes[paneID]?.selectedTabID == first, "next tab should wrap from second to first")
    _ = workspace.selectAdjacentTab(offset: -1, in: paneID)
    require(workspace.panes[paneID]?.selectedTabID == second, "previous tab should wrap from first to second")
}

func checkSplitFractionClamps() {
    var workspace = WorkspaceState()
    _ = workspace.splitFocusedPane(.right, title: "agent")
    workspace.setSplitFraction(path: [], fraction: 0.005)
    guard case let .split(_, _, _, lowFraction) = workspace.root else {
        return require(false, "root should be split")
    }
    require(lowFraction == SplitNode.minimumFraction, "low split fraction should clamp")

    workspace.setSplitFraction(path: [], fraction: 0.995)
    guard case let .split(_, _, _, highFraction) = workspace.root else {
        return require(false, "root should still be split")
    }
    require(highFraction == SplitNode.maximumFraction, "high split fraction should clamp")
}

func checkNestedSplitFractionClampsTargetPathOnly() {
    var workspace = WorkspaceState()
    guard workspace.splitFocusedPane(.right, title: "agent") != nil,
          workspace.splitFocusedPane(.down, title: "logs") != nil else {
        return require(false, "nested split setup should be valid")
    }

    workspace.setSplitFraction(path: [], fraction: 0.72)
    workspace.setSplitFraction(path: [.second], fraction: 0.005)

    guard case let .split(_, _, second, rootFraction) = workspace.root,
          case let .split(_, _, _, nestedFraction) = second else {
        return require(false, "workspace should have nested split")
    }
    require(rootFraction == 0.72, "root split fraction should stay unchanged when nested split changes")
    require(nestedFraction == SplitNode.minimumFraction, "nested split fraction should clamp at low bound")

    workspace.setSplitFraction(path: [.second], fraction: 0.99)
    guard case let .split(_, _, secondAfter, rootFractionAfter) = workspace.root,
          case let .split(_, _, _, nestedFractionAfter) = secondAfter else {
        return require(false, "workspace should still have nested split")
    }
    require(rootFractionAfter == 0.72, "root split fraction should still stay unchanged")
    require(nestedFractionAfter == SplitNode.maximumFraction, "nested split fraction should clamp at high bound")
    requireValidWorkspace(workspace, "nested split fraction clamp")
}

func checkEqualizeSplits() {
    var workspace = WorkspaceState()
    _ = workspace.splitFocusedPane(.right, title: "agent")
    _ = workspace.splitFocusedPane(.down, title: "logs")
    workspace.setSplitFraction(path: [], fraction: 0.80)
    workspace.setSplitFraction(path: [.second], fraction: 0.20)
    workspace.equalizeSplits()

    guard case let .split(_, _, second, rootFraction) = workspace.root,
          case let .split(_, _, _, nestedFraction) = second else {
        return require(false, "workspace should have nested split")
    }
    require(rootFraction == 0.5, "root split should equalize")
    require(nestedFraction == 0.5, "nested split should equalize")
}

func checkZoomUsesFocusedPaneAsVisibleRoot() {
    var workspace = WorkspaceState()
    let originalPaneID = workspace.focusedPaneID
    guard let secondPaneID = workspace.splitFocusedPane(.right, title: "agent") else {
        return require(false, "split should create second pane")
    }
    require(workspace.visibleRoot == workspace.root, "visible root should be full root before zoom")
    workspace.toggleZoom()
    require(workspace.isZoomed, "workspace should be zoomed")
    require(workspace.visibleRoot == .leaf(secondPaneID), "visible root should be focused pane while zoomed")
    workspace.focusPane(originalPaneID)
    workspace.focusAdjacentPane(.next)
    require(workspace.visibleRoot == .leaf(secondPaneID), "focus adjacent in zoom should keep zoom on focused pane")
    workspace.toggleZoom()
    require(!workspace.isZoomed, "second toggle should unzoom")
}

func checkFocusAdjacentPaneWraps() {
    var workspace = WorkspaceState()
    let firstPaneID = workspace.focusedPaneID
    guard let secondPaneID = workspace.splitFocusedPane(.right, title: "agent") else {
        return require(false, "split should create second pane")
    }
    _ = workspace.focusAdjacentPane(.next)
    require(workspace.focusedPaneID == firstPaneID, "next focus should wrap from second to first")
    _ = workspace.focusAdjacentPane(.previous)
    require(workspace.focusedPaneID == secondPaneID, "previous focus should wrap from first to second")
}

func checkDirectionalPaneFocusPrefersSplitGeometry() {
    var workspace = WorkspaceState()
    let leftPaneID = workspace.focusedPaneID
    guard let rightPaneID = workspace.splitFocusedPane(.right, title: "right"),
          let bottomRightPaneID = workspace.splitFocusedPane(.down, title: "bottom") else {
        return require(false, "nested split setup should be valid")
    }

    workspace.focusPane(leftPaneID)
    _ = workspace.focusAdjacentPane(.right)
    require(workspace.focusedPaneID == rightPaneID, "right focus should move into right split branch")

    _ = workspace.focusAdjacentPane(.down)
    require(workspace.focusedPaneID == bottomRightPaneID, "down focus should move to lower pane in vertical split")

    _ = workspace.focusAdjacentPane(.up)
    require(workspace.focusedPaneID == rightPaneID, "up focus should return to upper pane")

    _ = workspace.focusAdjacentPane(.left)
    require(workspace.focusedPaneID == leftPaneID, "left focus should return to left branch")
}

func checkResizeFocusedSplitChangesFraction() {
    var workspace = WorkspaceState()
    let firstPaneID = workspace.focusedPaneID
    guard let secondPaneID = workspace.splitFocusedPane(.right, title: "agent") else {
        return require(false, "split should create second pane")
    }
    workspace.focusPane(firstPaneID)
    workspace.resizeFocusedSplit(direction: .right, amount: 10)
    guard case let .split(_, _, _, grownFraction) = workspace.root else {
        return require(false, "root should be split")
    }
    require(grownFraction > 0.5, "resizing right from first pane should grow first pane")

    workspace.focusPane(secondPaneID)
    workspace.resizeFocusedSplit(direction: .right, amount: 10)
    guard case let .split(_, _, _, reducedFraction) = workspace.root else {
        return require(false, "root should still be split")
    }
    require(reducedFraction < grownFraction, "resizing right from second pane should shrink first pane")
}

func checkTerminalTitleUpdate() {
    var workspace = WorkspaceState()
    guard let terminalID = workspace.focusedPane?.selectedTabID else {
        return require(false, "workspace should have terminal")
    }
    let updated = workspace.updateTerminalTitle(terminalID, title: "  very-important-shell  ")
    require(updated, "title update should succeed")
    require(workspace.focusedPane?.selectedTab?.title == "very-important-shell", "title should trim whitespace")
}

func checkUserTerminalTitleIsStable() {
    var workspace = WorkspaceState()
    guard let terminalID = workspace.focusedPane?.selectedTabID else {
        return require(false, "workspace should have terminal")
    }
    require(workspace.updateTerminalTitle(terminalID, title: "api", userEdited: true), "user rename should succeed")
    require(workspace.focusedPane?.selectedTab?.title == "api", "user title should be visible")
    require(workspace.focusedPane?.selectedTab?.userTitle == "api", "user title should be marked")
    require(!workspace.updateTerminalTitle(terminalID, title: "shell-auto-title"), "automatic title should not overwrite user title")
    require(workspace.focusedPane?.selectedTab?.title == "api", "user title should stay stable")
    require(workspace.clearUserTerminalTitle(terminalID), "clearing user title should succeed")
    require(workspace.updateTerminalTitle(terminalID, title: "shell-auto-title"), "automatic title should work after clearing user title")
    require(workspace.focusedPane?.selectedTab?.title == "shell-auto-title", "automatic title should update after clearing user title")
}

func checkTerminalWorkingDirectoryUpdate() {
    var workspace = WorkspaceState()
    guard let terminalID = workspace.focusedPane?.selectedTabID else {
        return require(false, "workspace should have terminal")
    }
    let updated = workspace.updateTerminalWorkingDirectory(terminalID, workingDirectory: "  /tmp/conductor  ")
    require(updated, "working directory update should succeed")
    require(workspace.focusedPane?.selectedTab?.workingDirectory == "/tmp/conductor", "working directory should trim whitespace")
}

func checkDuplicateTabCreatesFreshTerminalID() {
    var workspace = WorkspaceState()
    let paneID = workspace.focusedPaneID
    guard let sourceID = workspace.focusedPane?.selectedTabID else {
        return require(false, "workspace should have initial tab")
    }
    require(workspace.updateTerminalTitle(sourceID, title: "api", userEdited: true), "source title should update")
    require(workspace.updateTerminalWorkingDirectory(sourceID, workingDirectory: "/tmp/api"), "source cwd should update")
    guard let duplicateID = workspace.duplicateTab(sourceID, in: paneID) else {
        return require(false, "duplicate tab should succeed")
    }
    require(duplicateID != sourceID, "duplicate tab should create fresh terminal id")
    require(workspace.panes[paneID]?.tabs.count == 2, "duplicate tab should add one tab")
    require(workspace.panes[paneID]?.selectedTabID == duplicateID, "duplicate tab should become selected")
    let duplicate = workspace.panes[paneID]?.selectedTab
    require(duplicate?.title == "api", "duplicate tab should preserve title")
    require(duplicate?.userTitle == "api", "duplicate tab should preserve user title")
    require(duplicate?.workingDirectory == "/tmp/api", "duplicate tab should preserve cwd")
    requireValidWorkspace(workspace, "duplicate tab")
}

func checkDuplicateWorkspaceCreatesFreshIDs() {
    var workspace = WorkspaceState(title: "API")
    let originalPaneID = workspace.focusedPaneID
    guard let originalTerminalID = workspace.focusedPane?.selectedTabID,
          workspace.updateTerminalTitle(originalTerminalID, title: "server", userEdited: true),
          workspace.updateTerminalWorkingDirectory(originalTerminalID, workingDirectory: "/tmp/server"),
          workspace.splitFocusedPane(.right, title: "logs") != nil else {
        return require(false, "duplicate workspace setup should be valid")
    }
    let duplicate = workspace.duplicated(title: "API 副本")
    require(duplicate.id != workspace.id, "duplicate workspace should create fresh workspace id")
    require(duplicate.title == "API 副本", "duplicate workspace should use requested title")
    require(duplicate.root.leaves.count == workspace.root.leaves.count, "duplicate workspace should preserve split shape")
    require(Set(duplicate.root.leaves).isDisjoint(with: Set(workspace.root.leaves)), "duplicate workspace should create fresh pane ids")
    let originalTerminalIDs = Set(workspace.panes.values.flatMap { $0.tabs.map(\.id) })
    let duplicateTerminalIDs = Set(duplicate.panes.values.flatMap { $0.tabs.map(\.id) })
    require(originalTerminalIDs.isDisjoint(with: duplicateTerminalIDs), "duplicate workspace should create fresh terminal ids")
    require(duplicate.panes.values.flatMap { $0.tabs.map(\.title) }.contains("server"), "duplicate workspace should preserve tab titles")
    require(duplicate.panes.values.flatMap { $0.tabs.map(\.workingDirectory) }.contains("/tmp/server"), "duplicate workspace should preserve cwd")
    require(duplicate.focusedPaneID != originalPaneID, "duplicate workspace should remap focused pane")
    requireValidWorkspace(duplicate, "duplicate workspace")
}

func checkMoveSelectedTab() {
    var workspace = WorkspaceState()
    let paneID = workspace.focusedPaneID
    let first = workspace.focusedPane!.selectedTabID
    let second = workspace.newTerminal(title: "server")
    let third = workspace.newTerminal(title: "logs")

    require(workspace.moveSelectedTab(offset: -1, in: paneID), "selected third tab should move left")
    require(workspace.panes[paneID]?.tabs.map(\.id) == [first, third, second], "third tab should move before second")
    require(workspace.moveSelectedTab(offset: -1, in: paneID), "selected third tab should move left again")
    require(workspace.panes[paneID]?.tabs.map(\.id) == [third, first, second], "third tab should move to front")
    require(!workspace.moveSelectedTab(offset: -1, in: paneID), "front tab should not move left")
}

func checkReorderTabBeforeTarget() {
    var workspace = WorkspaceState()
    let paneID = workspace.focusedPaneID
    let first = workspace.focusedPane!.selectedTabID
    let second = workspace.newTerminal(title: "server")
    let third = workspace.newTerminal(title: "logs")

    let moved = workspace.reorderTab(third, before: first, in: paneID)
    require(moved, "reorder should succeed")
    require(workspace.panes[paneID]?.tabs.map(\.id) == [third, first, second], "third tab should move before first")
    require(workspace.panes[paneID]?.selectedTabID == third, "dragged tab should become selected")
}

func checkMoveTabAcrossPanesByDrop() {
    var workspace = WorkspaceState()
    let sourcePaneID = workspace.focusedPaneID
    let first = workspace.focusedPane!.selectedTabID
    let dragged = workspace.newTerminal(title: "server")
    guard let destinationPaneID = workspace.splitFocusedPane(.right, title: "agent"),
          let target = workspace.panes[destinationPaneID]?.selectedTabID else {
        return require(false, "split should create destination pane")
    }

    let result = workspace.moveTab(dragged, before: target, in: destinationPaneID)
    require(result.movedTerminalID == dragged, "cross-pane drop should report moved tab")
    require(result.closedPaneIDs.isEmpty, "source pane with another tab should stay open")
    require(workspace.panes[sourcePaneID]?.tabs.map(\.id) == [first], "source pane should keep remaining tab")
    require(workspace.panes[destinationPaneID]?.tabs.map(\.id) == [dragged, target], "destination pane should insert before target")
    require(workspace.panes[destinationPaneID]?.selectedTabID == dragged, "dropped tab should become selected")
}

func checkMoveOnlyTabByDropClosesSourcePane() {
    var workspace = WorkspaceState()
    let sourcePaneID = workspace.focusedPaneID
    let dragged = workspace.focusedPane!.selectedTabID
    guard let destinationPaneID = workspace.splitFocusedPane(.right, title: "agent"),
          let target = workspace.panes[destinationPaneID]?.selectedTabID else {
        return require(false, "split should create destination pane")
    }

    let result = workspace.moveTab(dragged, before: target, in: destinationPaneID)
    require(result.movedTerminalID == dragged, "drop moving only source tab should report moved terminal")
    require(result.closedPaneIDs == [sourcePaneID], "drop moving only source tab should close source pane")
    require(workspace.panes[sourcePaneID] == nil, "drop source pane should be removed")
    require(workspace.root.leaves == [destinationPaneID], "drop should collapse split tree to destination")
    require(workspace.panes[destinationPaneID]?.tabs.map(\.id) == [dragged, target], "destination should insert dragged tab before target")
    require(workspace.focusedPaneID == destinationPaneID, "destination should become focused after drop")
    requireValidWorkspace(workspace, "move only tab by drop")
}

func checkInvalidDropDoesNotMutateWorkspace() {
    var workspace = WorkspaceState()
    let sourcePaneID = workspace.focusedPaneID
    let dragged = workspace.newTerminal(title: "server")
    guard let destinationPaneID = workspace.splitFocusedPane(.right, title: "agent") else {
        return require(false, "split should create destination pane")
    }
    let before = workspace
    let missingTarget = TerminalID()
    let result = workspace.moveTab(dragged, before: missingTarget, in: destinationPaneID)

    require(result.movedTerminalID == nil, "invalid drop target should not report moved terminal")
    require(result.closedPaneIDs.isEmpty, "invalid drop target should not close panes")
    require(workspace == before, "invalid drop target should not mutate workspace")
    require(workspace.panes[sourcePaneID]?.tabs.contains(where: { $0.id == dragged }) == true, "dragged tab should remain in source")
}

func checkMoveOnlyTabAcrossPanesClosesSourcePane() {
    var workspace = WorkspaceState()
    let sourcePaneID = workspace.focusedPaneID
    let moved = workspace.focusedPane!.selectedTabID
    guard let destinationPaneID = workspace.splitFocusedPane(.right, title: "agent") else {
        return require(false, "split should create destination pane")
    }

    workspace.focusPane(sourcePaneID)
    let result = workspace.moveSelectedTabToPane(destinationPaneID)
    require(result.movedTerminalID == moved, "moving only tab should report moved terminal")
    require(result.closedPaneIDs == [sourcePaneID], "moving only tab should close empty source pane")
    require(workspace.panes[sourcePaneID] == nil, "source pane should be removed")
    require(workspace.root.leaves == [destinationPaneID], "split tree should collapse to destination pane")
    require(workspace.focusedPaneID == destinationPaneID, "destination pane should become focused")
}

func checkCommandAvailability() {
    var workspace = WorkspaceState()
    require(!workspace.canClosePane(workspace.focusedPaneID), "single pane should not be closeable as a pane")
    require(!workspace.canMoveSelectedTab(offset: -1), "single tab cannot move left")
    require(!workspace.canMoveSelectedTabToNewSplit(), "single tab cannot move into a new split")

    _ = workspace.newTerminal(title: "server")
    require(workspace.canCloseOtherTabs(), "two tabs can close others")
    require(workspace.canMoveSelectedTab(offset: -1), "second selected tab can move left")
    require(workspace.canMoveSelectedTabToNewSplit(), "selected tab can move to new split when source has another tab")

    guard let first = workspace.panes[workspace.focusedPaneID]?.tabs.first?.id else {
        return require(false, "workspace should have first tab")
    }
    workspace.selectTab(first, in: workspace.focusedPaneID)
    require(workspace.canCloseTabsToRight(), "first tab can close tabs to right")
}

func checkCloseOtherTabs() {
    var workspace = WorkspaceState()
    let paneID = workspace.focusedPaneID
    let first = workspace.focusedPane!.selectedTabID
    let second = workspace.newTerminal(title: "server")
    let third = workspace.newTerminal(title: "logs")
    workspace.selectTab(second, in: paneID)
    let result = workspace.closeTabs(scope: .others, in: paneID)

    require(Set(result.closedTerminalIDs) == Set([first, third]), "close others should close non-selected tabs")
    require(workspace.panes[paneID]?.tabs.map(\.id) == [second], "only selected tab should remain")
    require(workspace.panes[paneID]?.selectedTabID == second, "selected tab should remain selected")
}

func checkCloseTabsToRight() {
    var workspace = WorkspaceState()
    let paneID = workspace.focusedPaneID
    let first = workspace.focusedPane!.selectedTabID
    let second = workspace.newTerminal(title: "server")
    let third = workspace.newTerminal(title: "logs")
    workspace.selectTab(first, in: paneID)
    let result = workspace.closeTabs(scope: .toRight, in: paneID)

    require(Set(result.closedTerminalIDs) == Set([second, third]), "close right should close tabs after selected")
    require(workspace.panes[paneID]?.tabs.map(\.id) == [first], "only leftmost selected tab should remain")
}

func checkMoveSelectedTabToNextPane() {
    var workspace = WorkspaceState()
    let firstPaneID = workspace.focusedPaneID
    let firstTerminalID = workspace.focusedPane!.selectedTabID
    let movedTerminalID = workspace.newTerminal(title: "server")
    guard let secondPaneID = workspace.splitFocusedPane(.right, title: "agent") else {
        return require(false, "split should create second pane")
    }
    workspace.focusPane(firstPaneID)
    workspace.selectTab(movedTerminalID, in: firstPaneID)
    let result = workspace.moveSelectedTabToNextPane()

    require(result.movedTerminalID == movedTerminalID, "move to next pane should report moved terminal")
    require(workspace.panes[firstPaneID]?.tabs.map(\.id) == [firstTerminalID], "source pane should keep remaining tab")
    require(workspace.panes[secondPaneID]?.tabs.last?.id == movedTerminalID, "destination pane should receive moved tab")
    require(workspace.panes[secondPaneID]?.selectedTabID == movedTerminalID, "moved tab should be selected in destination")
    require(workspace.focusedPaneID == secondPaneID, "destination pane should become focused")
}

func checkMoveSelectedTabToNewSplit() {
    var workspace = WorkspaceState()
    let sourcePaneID = workspace.focusedPaneID
    let firstTerminalID = workspace.focusedPane!.selectedTabID
    let movedTerminalID = workspace.newTerminal(title: "server")
    let result = workspace.moveSelectedTabToNewSplit(.right)

    require(result.movedTerminalID == movedTerminalID, "move to new split should report moved terminal")
    require(workspace.root.leaves.count == 2, "move to new split should create pane")
    require(workspace.panes[sourcePaneID]?.tabs.map(\.id) == [firstTerminalID], "source pane should keep remaining tab")
    let destinationPaneID = workspace.focusedPaneID
    require(destinationPaneID != sourcePaneID, "new pane should become focused")
    require(workspace.panes[destinationPaneID]?.tabs.map(\.id) == [movedTerminalID], "new pane should own moved tab")
}

func checkMoveInactiveTabToNewSplitPreservesSourceSelection() {
    var workspace = WorkspaceState()
    let sourcePaneID = workspace.focusedPaneID
    let firstTerminalID = workspace.focusedPane!.selectedTabID
    let movedTerminalID = workspace.newTerminal(title: "server")
    let thirdTerminalID = workspace.newTerminal(title: "logs")
    workspace.selectTab(firstTerminalID, in: sourcePaneID)

    let result = workspace.moveTabToNewSplit(movedTerminalID, .down)

    require(result.movedTerminalID == movedTerminalID, "inactive tab move to split should report moved terminal")
    require(workspace.root.leaves.count == 2, "inactive tab move should create pane")
    require(workspace.panes[sourcePaneID]?.tabs.map(\.id) == [firstTerminalID, thirdTerminalID], "source pane should remove only dragged tab")
    require(workspace.panes[sourcePaneID]?.selectedTabID == firstTerminalID, "source pane selection should not jump when moving inactive tab")
    let destinationPaneID = workspace.focusedPaneID
    require(destinationPaneID != sourcePaneID, "new pane should become focused after inactive tab move")
    require(workspace.panes[destinationPaneID]?.tabs.map(\.id) == [movedTerminalID], "new pane should own inactive moved tab")
    requireValidWorkspace(workspace, "move inactive tab to new split")
}

func checkMoveTabToNewSplitSupportsAllDropEdges() {
    for direction in [SplitDirection.left, .right, .up, .down] {
        var workspace = WorkspaceState()
        let sourcePaneID = workspace.focusedPaneID
        let firstTerminalID = workspace.focusedPane!.selectedTabID
        let movedTerminalID = workspace.newTerminal(title: direction.rawValue)

        let result = workspace.moveTabToNewSplit(movedTerminalID, direction)
        let destinationPaneID = workspace.focusedPaneID

        require(result.movedTerminalID == movedTerminalID, "drop edge \(direction.rawValue) should report moved terminal")
        require(destinationPaneID != sourcePaneID, "drop edge \(direction.rawValue) should focus new pane")
        require(workspace.panes[sourcePaneID]?.tabs.map(\.id) == [firstTerminalID], "drop edge \(direction.rawValue) should keep source tab")
        require(workspace.panes[destinationPaneID]?.tabs.map(\.id) == [movedTerminalID], "drop edge \(direction.rawValue) should own moved tab")

        guard case let .split(axis, first, second, _) = workspace.root else {
            return require(false, "drop edge \(direction.rawValue) should create split root")
        }
        require(axis == direction.axis, "drop edge \(direction.rawValue) should use expected split axis")
        let expectedFirst: SplitNode = direction.insertsBeforeFocusedPane ? .leaf(destinationPaneID) : .leaf(sourcePaneID)
        let expectedSecond: SplitNode = direction.insertsBeforeFocusedPane ? .leaf(sourcePaneID) : .leaf(destinationPaneID)
        require(first == expectedFirst, "drop edge \(direction.rawValue) should place first node correctly")
        require(second == expectedSecond, "drop edge \(direction.rawValue) should place second node correctly")
        requireValidWorkspace(workspace, "move tab to new split edge \(direction.rawValue)")
    }
}

func checkMoveTabToSplitAroundTargetPane() {
    var workspace = WorkspaceState()
    let sourcePaneID = workspace.focusedPaneID
    let firstTerminalID = workspace.focusedPane!.selectedTabID
    let movedTerminalID = workspace.newTerminal(title: "server")
    guard let targetPaneID = workspace.splitFocusedPane(.right, title: "target") else {
        return require(false, "target split should be created")
    }
    let targetTerminalID = workspace.panes[targetPaneID]!.selectedTabID

    let result = workspace.moveTabToSplit(movedTerminalID, targetPaneID: targetPaneID, .up)
    let destinationPaneID = workspace.focusedPaneID

    require(result.movedTerminalID == movedTerminalID, "target split drop should report moved terminal")
    require(workspace.panes[sourcePaneID]?.tabs.map(\.id) == [firstTerminalID], "source pane should keep remaining tab")
    require(workspace.panes[targetPaneID]?.tabs.map(\.id) == [targetTerminalID], "target pane should remain intact")
    require(workspace.panes[destinationPaneID]?.tabs.map(\.id) == [movedTerminalID], "new target-adjacent pane should own moved tab")
    guard case let .split(axis, first, second, _) = workspace.root else {
        return require(false, "target split drop should keep split root")
    }
    require(axis == .horizontal, "original root should remain horizontal")
    require(first == .leaf(sourcePaneID), "source pane should stay outside target replacement")
    require(second.leaves == [destinationPaneID, targetPaneID], "target pane should be replaced by vertical split with moved tab above")
    requireValidWorkspace(workspace, "move tab to split around target pane")
}

func checkMoveOnlyTabToSplitAroundTargetPaneClosesSource() {
    var workspace = WorkspaceState()
    let sourcePaneID = workspace.focusedPaneID
    let movedTerminalID = workspace.focusedPane!.selectedTabID
    guard let targetPaneID = workspace.splitFocusedPane(.right, title: "target") else {
        return require(false, "target split should be created")
    }

    let result = workspace.moveTabToSplit(movedTerminalID, targetPaneID: targetPaneID, .left)
    let destinationPaneID = workspace.focusedPaneID

    require(result.movedTerminalID == movedTerminalID, "only-tab target split drop should report moved terminal")
    require(result.closedPaneIDs == [sourcePaneID], "only-tab target split drop should report closed source pane")
    require(workspace.panes[sourcePaneID] == nil, "only-tab source pane should close")
    require(workspace.panes[destinationPaneID]?.tabs.map(\.id) == [movedTerminalID], "new pane should own moved tab")
    require(workspace.root.leaves == [destinationPaneID, targetPaneID], "target replacement should remain after source closes")
    requireValidWorkspace(workspace, "move only tab to split around target pane")
}

func checkContextTabMoveAvailabilityUsesTargetTabPane() {
    var workspace = WorkspaceState()
    let sourcePaneID = workspace.focusedPaneID
    _ = workspace.newTerminal(title: "server")
    guard let destinationPaneID = workspace.splitFocusedPane(.right, title: "agent") else {
        return require(false, "split should create destination pane")
    }

    workspace.focusPane(destinationPaneID)
    require(workspace.canMoveSelectedTabToNextPane(), "single tab in existing split can move to next pane")
    require(!workspace.canMoveSelectedTabToNewSplit(), "single tab cannot move into a new split")

    workspace.focusPane(sourcePaneID)
    require(workspace.canMoveSelectedTabToNextPane(), "multi-tab source can move selected tab to next pane")
    require(workspace.canMoveSelectedTabToNewSplit(), "multi-tab source can move selected tab to a new split")
    requireValidWorkspace(workspace, "context tab move availability")
}

func checkMoveTabToEndInSamePane() {
    var workspace = WorkspaceState()
    let paneID = workspace.focusedPaneID
    let first = workspace.focusedPane!.selectedTabID
    let second = workspace.newTerminal(title: "server")
    let third = workspace.newTerminal(title: "logs")

    let result = workspace.moveTab(first, in: paneID)
    require(result.movedTerminalID == first, "move to end should report moved tab")
    require(workspace.panes[paneID]?.tabs.map(\.id) == [second, third, first], "first tab should move to end")
    require(workspace.panes[paneID]?.selectedTabID == first, "moved tab should become selected")
    requireValidWorkspace(workspace, "move tab to end in same pane")
}

func checkRapidTabSwitchingKeepsStableStructure() {
    var workspace = WorkspaceState()
    let paneID = workspace.focusedPaneID
    for index in 1...12 {
        workspace.newTerminal(title: "tab-\(index)")
    }
    let expectedTabs = workspace.panes[paneID]!.tabs.map(\.id)

    for iteration in 0..<500 {
        _ = workspace.selectAdjacentTab(offset: iteration.isMultiple(of: 2) ? 1 : -1, in: paneID)
        require(workspace.panes[paneID]?.tabs.map(\.id) == expectedTabs, "rapid tab switching should not reorder tabs")
        requireValidWorkspace(workspace, "rapid tab switching \(iteration)")
    }
}

func checkComplexWorkspaceStressMaintainsInvariants() {
    var workspace = WorkspaceState()
    let sourcePaneID = workspace.focusedPaneID
    for index in 1...5 {
        _ = workspace.newTerminal(title: "seed-\(index)")
    }
    while workspace.canSplit() {
        workspace.focusPane(sourcePaneID)
        guard workspace.canMoveSelectedTabToNewSplit() else { break }
        _ = workspace.moveSelectedTabToNewSplit(workspace.root.leaves.count.isMultiple(of: 2) ? .right : .down)
        requireValidWorkspace(workspace, "stress split")
    }
    require(workspace.panes.count == WorkspaceState.defaultMaximumPaneCount, "stress should reach maximum pane count")

    for paneID in workspace.root.leaves {
        workspace.focusPane(paneID)
        _ = workspace.newTerminal(title: "extra")
        requireValidWorkspace(workspace, "stress add tab")
    }

    for _ in 0..<40 {
        _ = workspace.selectAdjacentTab(offset: 1)
        workspace.moveSelectedTabToNextPane()
        workspace.focusAdjacentPane(.next)
        workspace.resizeFocusedSplit(direction: .right, amount: 5)
        requireValidWorkspace(workspace, "stress move/focus/resize")
    }

    workspace.equalizeSplits()
    workspace.toggleZoom()
    requireValidWorkspace(workspace, "stress zoom")
    workspace.toggleZoom()

    while workspace.root.leaves.count > 1 {
        let paneID = workspace.focusedPaneID
        _ = workspace.closePane(paneID)
        requireValidWorkspace(workspace, "stress close pane")
    }
    require(workspace.panes.count == 1, "stress should end with one pane")
    requireValidWorkspace(workspace, "stress final")
}

func checkAgentIntegrationCatalog() {
    guard let codex = AgentIntegrationCatalog.definition(named: "codex") else {
        return require(false, "agent catalog should include Codex")
    }
    require(codex.binaryName == "codex", "Codex integration should resolve codex binary")
    require(codex.configDirectoryEnvironmentOverride == "CODEX_HOME", "Codex integration should respect CODEX_HOME")
    require(codex.lifecycleEvents.contains(where: { $0.agentEvent == "UserPromptSubmit" }), "Codex should define prompt submit lifecycle")
    require(codex.feedEvents.contains("PreToolUse"), "Codex should define feed bridge events")

    guard let claude = AgentIntegrationCatalog.definition(named: "cc") else {
        return require(false, "agent catalog should resolve Claude alias")
    }
    require(claude.id == "claude", "Claude alias should resolve built-in Claude integration")

    guard let rovo = AgentIntegrationCatalog.definition(named: "rovo") else {
        return require(false, "agent catalog should resolve Rovo alias")
    }
    require(rovo.id == "rovodev", "Rovo alias should resolve Rovo Dev integration")
    require(AgentIntegrationCatalog.definition(named: "unknown-agent") == nil, "unknown agent should not resolve")
}

func checkSearchMatcherRanking() {
    let candidates = [
        ConductorSearchCandidate(id: "contains", title: "Current Directory Open", subtitle: "Finder", keywords: ["folder"]),
        ConductorSearchCandidate(id: "prefix", title: "Open File Manager", subtitle: "Files", keywords: ["browser"]),
        ConductorSearchCandidate(id: "exact", title: "Open", subtitle: "Exact command", keywords: []),
        ConductorSearchCandidate(id: "path", title: "README.md", subtitle: "/Users/me/project/Documentation/README.md", keywords: [])
    ]
    let results = ConductorSearchMatcher.results(for: "open", in: candidates)
    require(results.map(\.candidate.id).prefix(3) == ["exact", "prefix", "contains"], "search ranking should prefer exact then prefix then contains")

    let pathResults = ConductorSearchMatcher.results(for: "project readme", in: candidates)
    require(pathResults.first?.candidate.id == "path", "multi-token search should match across title and path fields")
}

func checkSearchSelection() {
    let enabled = ConductorSearchCandidate(id: "enabled", title: "Enabled", subtitle: "", keywords: [])
    let disabled = ConductorSearchCandidate(id: "disabled", title: "Disabled", subtitle: "", keywords: [], isEnabled: false, disabledReason: "Not available")
    let other = ConductorSearchCandidate(id: "other", title: "Other", subtitle: "", keywords: [])
    let results = ConductorSearchMatcher.results(for: "", in: [disabled, enabled, other])

    require(ConductorSearchSelection.resolvedSelection(currentID: nil, results: results) == "enabled", "selection should start at first enabled result")
    require(ConductorSearchSelection.move(currentID: "enabled", by: 1, results: results, wraps: true) == "other", "selection should move to next enabled result")
    require(ConductorSearchSelection.move(currentID: "other", by: 1, results: results, wraps: true) == "enabled", "selection should wrap over disabled results")
    require(ConductorSearchSelection.resolvedSelection(currentID: "other", results: results) == "other", "selection should preserve a still-visible enabled result")
}

func checkWebAddressResolver() {
    let resolver = WebAddressResolver()

    require(resolver.resolve("https://example.com")?.absoluteString == "https://example.com", "https URL should pass through")
    require(resolver.resolve("http://127.0.0.1:8080")?.absoluteString == "http://127.0.0.1:8080", "http loopback URL should pass through")
    require(resolver.resolve("localhost:3000")?.absoluteString == "http://localhost:3000", "localhost host should default to http")
    require(resolver.resolve("localhost/docs")?.absoluteString == "http://localhost/docs", "localhost paths should default to http")
    require(resolver.resolve("127.0.0.1:5173")?.absoluteString == "http://127.0.0.1:5173", "loopback host should default to http")
    require(resolver.resolve("127.0.0.1/status")?.absoluteString == "http://127.0.0.1/status", "loopback paths should default to http")
    require(resolver.resolve("[::1]:9000")?.absoluteString == "http://[::1]:9000", "IPv6 loopback should default to http")
    require(resolver.resolve("3000")?.absoluteString == "http://localhost:3000", "bare ports should open localhost")
    require(resolver.resolve(":5173")?.absoluteString == "http://localhost:5173", "colon-prefixed ports should open localhost")
    require(resolver.resolve("github.com/openai/codex")?.absoluteString == "https://github.com/openai/codex", "bare domain path should default to https")
    require(resolver.resolve("swift webkit tabs")?.absoluteString == "https://duckduckgo.com/?q=swift%20webkit%20tabs", "phrases should become DuckDuckGo search URLs")
    require(resolver.resolve("   ") == nil, "blank input should not resolve")
}

func checkWorkspaceWebTabList() {
    var list = WorkspaceWebTabList()
    let first = list.append(url: URL(string: "https://example.com")!, title: "Example")
    let second = list.append(url: nil, title: nil)

    require(list.tabs.map(\.id) == [first, second], "append should preserve order")
    require(list.selectedTabID == second, "append should select new tab")

    list.update(first) { tab in
        tab.title = "Docs"
        tab.url = URL(string: "https://docs.example.com")!
        tab.isLoading = true
        tab.estimatedProgress = 0.5
        tab.canGoBack = true
    }
    require(list.tabs.first?.displayTitle == "Docs", "title update should apply")
    require(list.tabs.first?.hostDisplay == "docs.example.com", "host display should prefer host")
    require(list.tabs.first?.estimatedProgress == 0.5, "progress should update")

    list.select(first)
    let closeSelected = list.close(first, fallbackFileTabID: "file.swift", fallbackTerminalID: TerminalID(UUID()))
    require(closeSelected.closedTabID == first, "close should report closed tab")
    require(closeSelected.nextContentSelection == .web(second), "closing first selected tab should select nearest web tab")

    let terminalID = TerminalID(UUID())
    _ = list.close(second, fallbackFileTabID: "file.swift", fallbackTerminalID: terminalID)
    require(list.tabs.isEmpty, "closing last web tab should empty list")
    require(list.selectedTabID == nil, "closing last web tab should clear web selection")

    let emptyClose = list.close(WebTabID(), fallbackFileTabID: "file.swift", fallbackTerminalID: terminalID)
    require(emptyClose.nextContentSelection == .file("file.swift"), "missing web close should fall back to provided file")
}

checkRenderBudgetDefaults()
checkNewWorkspace()
checkNewTerminalTab()
checkSplitRight()
checkSplitDownNested()
checkWorkspaceEdgeSplitAvoidsCornerNesting()
checkMixedPersistedLayoutNormalizes()
checkSplitTreeReconciliationRestoresOrphanPanes()
checkCloseSelectedTabFocusesNearestTab()
checkCloseInactiveTabPreservesSelection()
checkCloseOnlyTerminalCreatesReplacement()
checkCloseLastTabInPaneCollapsesSplit()
checkCloseNestedPaneCollapsesOnlyParent()
checkCloseZoomedPaneClearsZoom()
checkCloseDifferentPaneKeepsValidZoom()
checkSplitLimit()
checkAdjacentTabSelectionWraps()
checkSplitFractionClamps()
checkNestedSplitFractionClampsTargetPathOnly()
checkEqualizeSplits()
checkZoomUsesFocusedPaneAsVisibleRoot()
checkFocusAdjacentPaneWraps()
checkDirectionalPaneFocusPrefersSplitGeometry()
checkResizeFocusedSplitChangesFraction()
checkTerminalTitleUpdate()
checkUserTerminalTitleIsStable()
checkTerminalWorkingDirectoryUpdate()
checkDuplicateTabCreatesFreshTerminalID()
checkDuplicateWorkspaceCreatesFreshIDs()
checkMoveSelectedTab()
checkReorderTabBeforeTarget()
checkMoveTabAcrossPanesByDrop()
checkMoveOnlyTabByDropClosesSourcePane()
checkInvalidDropDoesNotMutateWorkspace()
checkMoveOnlyTabAcrossPanesClosesSourcePane()
checkCommandAvailability()
checkCloseOtherTabs()
checkCloseTabsToRight()
checkMoveSelectedTabToNextPane()
checkMoveSelectedTabToNewSplit()
checkMoveInactiveTabToNewSplitPreservesSourceSelection()
checkMoveTabToNewSplitSupportsAllDropEdges()
checkMoveTabToSplitAroundTargetPane()
checkMoveOnlyTabToSplitAroundTargetPaneClosesSource()
checkContextTabMoveAvailabilityUsesTargetTabPane()
checkMoveTabToEndInSamePane()
checkRapidTabSwitchingKeepsStableStructure()
checkComplexWorkspaceStressMaintainsInvariants()
checkAgentIntegrationCatalog()
checkSearchMatcherRanking()
checkSearchSelection()
checkWebAddressResolver()
checkWorkspaceWebTabList()
print("ConductorModelCheck passed")
