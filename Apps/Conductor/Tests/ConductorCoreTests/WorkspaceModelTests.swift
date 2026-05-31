import Testing
@testable import ConductorCore

// MARK: - Shared helpers

func requireValidWorkspace(_ workspace: WorkspaceState, _ context: String) {
    let leaves = workspace.root.leaves
    #expect(!leaves.isEmpty, "\(context): split tree should have at least one leaf")
    #expect(Set(leaves).count == leaves.count, "\(context): split tree should not duplicate panes")
    #expect(Set(leaves) == Set(workspace.panes.keys), "\(context): split leaves should match pane dictionary")
    #expect(workspace.panes[workspace.focusedPaneID] != nil, "\(context): focused pane should exist")
    for paneID in leaves {
        guard let pane = workspace.panes[paneID] else {
            Issue.record("\(context): leaf pane should exist"); return
        }
        #expect(!pane.tabs.isEmpty, "\(context): pane should always contain at least one tab")
        #expect(pane.tabs.contains(where: { $0.id == pane.selectedTabID }), "\(context): selected tab should exist in pane")
        #expect(Set(pane.tabs.map(\.id)).count == pane.tabs.count, "\(context): pane should not duplicate tabs")
    }
    if let zoomedPaneID = workspace.zoomedPaneID {
        #expect(workspace.panes[zoomedPaneID] != nil, "\(context): zoomed pane should exist")
    }
}

extension SplitNode {
    func usesOnly(axis expectedAxis: SplitAxis) -> Bool {
        switch self {
        case .leaf:
            return true
        case let .split(axis, first, second, _):
            return axis == expectedAxis && first.usesOnly(axis: expectedAxis) && second.usesOnly(axis: expectedAxis)
        }
    }
}

// MARK: - Workspace model tests

@Test func newWorkspaceStartsWithOnePane() {
    let workspace = WorkspaceState()
    #expect(workspace.root.leaves.count == 1, "new workspace should start with one pane")
    #expect(workspace.focusedPane?.tabs.count == 1, "new workspace should start with one terminal")
    #expect(workspace.focusedPane?.selectedTab?.title == "zsh", "initial terminal should be zsh")
    requireValidWorkspace(workspace, "new workspace")
}

@Test func newTerminalTab() {
    var workspace = WorkspaceState()
    let paneID = workspace.focusedPaneID
    let terminalID = workspace.newTerminal(title: "server")
    #expect(workspace.root.leaves == [paneID], "new terminal should add a tab, not split")
    #expect(workspace.panes[paneID]?.tabs.map(\.title) == ["zsh", "server"], "pane should contain zsh and server tabs")
    #expect(workspace.panes[paneID]?.selectedTabID == terminalID, "new terminal tab should become selected")
}

@Test func splitRightAppendsPane() {
    var workspace = WorkspaceState()
    let originalPaneID = workspace.focusedPaneID
    guard let newPaneID = workspace.splitFocusedPane(.right, title: "agent") else {
        Issue.record("split right should be valid for a new workspace"); return
    }
    #expect(workspace.root.leaves == [originalPaneID, newPaneID], "split right should append a pane")
    #expect(workspace.focusedPaneID == newPaneID, "new split pane should be focused")
    guard case let .split(axis, first, second, fraction) = workspace.root else {
        Issue.record("root should be split after split right"); return
    }
    #expect(axis == .horizontal, "split right should create horizontal split")
    #expect(first == .leaf(originalPaneID), "original pane should stay first")
    #expect(second == .leaf(newPaneID), "new pane should be second")
    #expect(fraction == 0.5, "initial split fraction should be even")
}

@Test func splitDownNested() {
    var workspace = WorkspaceState()
    guard let rightPaneID = workspace.splitFocusedPane(.right, title: "agent"),
          let bottomPaneID = workspace.splitFocusedPane(.down, title: "logs") else {
        Issue.record("nested splits should be valid"); return
    }
    #expect(workspace.root.leaves.count == 3, "nested split should produce three panes")
    #expect(workspace.focusedPaneID == bottomPaneID, "bottom split should be focused")
    guard case let .split(.horizontal, _, second, _) = workspace.root,
          case let .split(axis, first, secondNested, _) = second else {
        Issue.record("right pane should become a vertical nested split"); return
    }
    #expect(axis == .vertical, "split down should create vertical split")
    #expect(first == .leaf(rightPaneID), "previous focused pane should stay first in nested split")
    #expect(secondNested == .leaf(bottomPaneID), "new pane should be second in nested split")
}

@Test func workspaceEdgeSplitAvoidsCornerNesting() {
    var workspace = WorkspaceState()
    for index in 2...5 {
        guard workspace.splitWorkspaceEdge(.right, title: "zsh \(index)") != nil else {
            Issue.record("workspace edge split should create pane \(index)"); return
        }
    }

    #expect(workspace.root.leaves.count == 5, "workspace edge split should keep five panes")
    #expect(workspace.root.usesOnly(axis: .horizontal), "five right splits should become full-height columns")
    requireValidWorkspace(workspace, "workspace edge split")

    var verticalWorkspace = WorkspaceState()
    for index in 2...4 {
        guard verticalWorkspace.splitWorkspaceEdge(.down, title: "zsh \(index)") != nil else {
            Issue.record("workspace edge down split should create pane \(index)"); return
        }
    }
    #expect(verticalWorkspace.root.usesOnly(axis: .vertical), "down splits should become full-width rows")
}

@Test func mixedPersistedLayoutNormalizes() {
    var workspace = WorkspaceState()
    let firstPaneID = workspace.focusedPaneID
    guard let secondPaneID = workspace.splitFocusedPane(.right, title: "two"),
          let thirdPaneID = workspace.splitFocusedPane(.down, title: "three"),
          let fourthPaneID = workspace.splitFocusedPane(.right, title: "four") else {
        Issue.record("mixed split setup should be valid"); return
    }
    #expect(workspace.root.containsMixedAxes, "setup should create mixed axes")
    workspace.normalizeMixedSplitLayout()
    #expect(workspace.root.leaves == [firstPaneID, secondPaneID, thirdPaneID, fourthPaneID], "normalization should preserve pane order")
    #expect(workspace.root.usesOnly(axis: .horizontal), "mixed persisted layout should flatten to primary axis")
    requireValidWorkspace(workspace, "normalize mixed persisted layout")
}

@Test func splitTreeReconciliationRestoresOrphanPanes() {
    var workspace = WorkspaceState()
    let firstPaneID = workspace.focusedPaneID
    guard let secondPaneID = workspace.splitFocusedPane(.right, title: "two") else {
        Issue.record("split setup should create second pane"); return
    }

    workspace.root = .leaf(firstPaneID)
    workspace.focusedPaneID = secondPaneID
    #expect(!workspace.hasCoherentSplitTree, "corrupted setup should detect orphan pane")

    workspace.reconcileSplitTreeWithPanes()
    #expect(workspace.hasCoherentSplitTree, "reconciliation should restore split tree coherence")
    #expect(Set(workspace.root.leaves) == Set([firstPaneID, secondPaneID]), "reconciliation should keep every pane visible")
    #expect(workspace.focusedPaneID == secondPaneID, "reconciliation should preserve valid focused pane")
    requireValidWorkspace(workspace, "reconciled split tree")
}

@Test func closeSelectedTabFocusesNearestTab() {
    var workspace = WorkspaceState()
    let paneID = workspace.focusedPaneID
    let firstTerminalID = workspace.focusedPane?.selectedTabID
    let secondTerminalID = workspace.newTerminal(title: "server")
    let result = workspace.closeTab(secondTerminalID, in: paneID)

    #expect(result.closedTerminalIDs == [secondTerminalID], "closing selected tab should report closed terminal")
    #expect(workspace.panes[paneID]?.tabs.count == 1, "pane should have one remaining tab")
    #expect(workspace.panes[paneID]?.selectedTabID == firstTerminalID, "nearest remaining tab should be selected")
    #expect(workspace.focusedPaneID == paneID, "closing tab should keep pane focused")
}

@Test func closeInactiveTabPreservesSelection() {
    var workspace = WorkspaceState()
    let paneID = workspace.focusedPaneID
    let firstTerminalID = workspace.focusedPane?.selectedTabID
    let secondTerminalID = workspace.newTerminal(title: "server")
    workspace.selectTab(firstTerminalID!, in: paneID)
    let result = workspace.closeTab(secondTerminalID, in: paneID)

    #expect(result.closedTerminalIDs == [secondTerminalID], "inactive tab close should report closed terminal")
    #expect(workspace.panes[paneID]?.selectedTabID == firstTerminalID, "inactive tab close should preserve selection")
}

@Test func closeOnlyTerminalCreatesReplacement() {
    var workspace = WorkspaceState()
    let paneID = workspace.focusedPaneID
    guard let originalTerminalID = workspace.focusedPane?.selectedTabID else {
        Issue.record("workspace should have an initial terminal"); return
    }
    let result = workspace.closeTab(originalTerminalID, in: paneID)

    #expect(result.closedTerminalIDs == [originalTerminalID], "only terminal close should report old terminal")
    #expect(result.replacementTerminalID != nil, "only terminal close should create replacement")
    #expect(workspace.root.leaves == [paneID], "only terminal close should keep same pane")
    #expect(workspace.panes[paneID]?.tabs.count == 1, "replacement pane should have one terminal")
    #expect(workspace.panes[paneID]?.selectedTabID == result.replacementTerminalID, "replacement should be selected")
}

@Test func closeLastTabInPaneCollapsesSplit() {
    var workspace = WorkspaceState()
    let originalPaneID = workspace.focusedPaneID
    guard let secondPaneID = workspace.splitFocusedPane(.right, title: "agent"),
          let secondTerminalID = workspace.panes[secondPaneID]?.selectedTabID else {
        Issue.record("split should create second pane"); return
    }
    let result = workspace.closeTab(secondTerminalID, in: secondPaneID)

    #expect(result.closedTerminalIDs == [secondTerminalID], "closing last tab in pane should close terminal")
    #expect(result.closedPaneIDs == [secondPaneID], "closing last tab in pane should close pane")
    #expect(workspace.root == .leaf(originalPaneID), "split tree should collapse to original pane")
    #expect(workspace.focusedPaneID == originalPaneID, "focus should move to surviving pane")
}

@Test func closeNestedPaneCollapsesOnlyParent() {
    var workspace = WorkspaceState()
    let originalPaneID = workspace.focusedPaneID
    guard let rightPaneID = workspace.splitFocusedPane(.right, title: "agent"),
          let bottomPaneID = workspace.splitFocusedPane(.down, title: "logs") else {
        Issue.record("nested split setup should be valid"); return
    }
    let result = workspace.closePane(bottomPaneID)

    #expect(result.closedPaneIDs == [bottomPaneID], "close pane should report closed pane")
    #expect(workspace.root.leaves == [originalPaneID, rightPaneID], "nested split should collapse to surviving panes")
    #expect(workspace.panes[bottomPaneID] == nil, "closed pane should be removed")
    #expect(workspace.panes[workspace.focusedPaneID] != nil, "focus should point to a surviving pane")
}

@Test func closeZoomedPaneClearsZoom() {
    var workspace = WorkspaceState()
    guard let zoomedPaneID = workspace.splitFocusedPane(.right, title: "agent") else {
        Issue.record("split should create zoomed candidate"); return
    }
    workspace.toggleZoom()
    #expect(workspace.zoomedPaneID == zoomedPaneID, "toggle zoom should zoom focused pane")
    _ = workspace.closePane(zoomedPaneID)

    #expect(!workspace.isZoomed, "closing zoomed pane should clear zoom")
    #expect(workspace.panes[zoomedPaneID] == nil, "closed zoomed pane should be removed")
    requireValidWorkspace(workspace, "close zoomed pane")
}

@Test func closeDifferentPaneKeepsValidZoom() {
    var workspace = WorkspaceState()
    let originalPaneID = workspace.focusedPaneID
    guard let secondPaneID = workspace.splitFocusedPane(.right, title: "agent") else {
        Issue.record("split should create second pane"); return
    }
    workspace.focusPane(originalPaneID)
    workspace.toggleZoom()
    #expect(workspace.zoomedPaneID == originalPaneID, "original pane should be zoomed")
    _ = workspace.closePane(secondPaneID)

    #expect(workspace.zoomedPaneID == originalPaneID, "closing different pane should keep valid zoom")
    #expect(workspace.visibleRoot == .leaf(originalPaneID), "visible root should remain zoomed original pane")
    requireValidWorkspace(workspace, "close non-zoomed pane with zoom")
}

@Test func splitLimit() {
    var workspace = WorkspaceState()
    while workspace.canSplit() {
        _ = workspace.splitFocusedPane(.right, title: "zsh")
    }
    let paneCount = workspace.panes.count
    let denied = workspace.splitFocusedPane(.right, title: "overflow")

    #expect(paneCount == WorkspaceState.defaultMaximumPaneCount, "workspace should stop at maximum pane count")
    #expect(denied == nil, "split beyond maximum should be denied")
    #expect(workspace.panes.count == paneCount, "denied split should not mutate pane count")
}

@Test func adjacentTabSelectionWraps() {
    var workspace = WorkspaceState()
    let paneID = workspace.focusedPaneID
    guard let first = workspace.focusedPane?.selectedTabID else {
        Issue.record("workspace should have initial tab"); return
    }
    let second = workspace.newTerminal(title: "server")
    _ = workspace.selectAdjacentTab(offset: 1, in: paneID)
    #expect(workspace.panes[paneID]?.selectedTabID == first, "next tab should wrap from second to first")
    _ = workspace.selectAdjacentTab(offset: -1, in: paneID)
    #expect(workspace.panes[paneID]?.selectedTabID == second, "previous tab should wrap from first to second")
}

@Test func splitFractionClamps() {
    var workspace = WorkspaceState()
    _ = workspace.splitFocusedPane(.right, title: "agent")
    workspace.setSplitFraction(path: [], fraction: 0.005)
    guard case let .split(_, _, _, lowFraction) = workspace.root else {
        Issue.record("root should be split"); return
    }
    #expect(lowFraction == SplitNode.minimumFraction, "low split fraction should clamp")

    workspace.setSplitFraction(path: [], fraction: 0.995)
    guard case let .split(_, _, _, highFraction) = workspace.root else {
        Issue.record("root should still be split"); return
    }
    #expect(highFraction == SplitNode.maximumFraction, "high split fraction should clamp")
}

@Test func nestedSplitFractionClampsTargetPathOnly() {
    var workspace = WorkspaceState()
    guard workspace.splitFocusedPane(.right, title: "agent") != nil,
          workspace.splitFocusedPane(.down, title: "logs") != nil else {
        Issue.record("nested split setup should be valid"); return
    }

    workspace.setSplitFraction(path: [], fraction: 0.72)
    workspace.setSplitFraction(path: [.second], fraction: 0.005)

    guard case let .split(_, _, second, rootFraction) = workspace.root,
          case let .split(_, _, _, nestedFraction) = second else {
        Issue.record("workspace should have nested split"); return
    }
    #expect(rootFraction == 0.72, "root split fraction should stay unchanged when nested split changes")
    #expect(nestedFraction == SplitNode.minimumFraction, "nested split fraction should clamp at low bound")

    workspace.setSplitFraction(path: [.second], fraction: 0.99)
    guard case let .split(_, _, secondAfter, rootFractionAfter) = workspace.root,
          case let .split(_, _, _, nestedFractionAfter) = secondAfter else {
        Issue.record("workspace should still have nested split"); return
    }
    #expect(rootFractionAfter == 0.72, "root split fraction should still stay unchanged")
    #expect(nestedFractionAfter == SplitNode.maximumFraction, "nested split fraction should clamp at high bound")
    requireValidWorkspace(workspace, "nested split fraction clamp")
}

@Test func equalizeSplits() {
    var workspace = WorkspaceState()
    _ = workspace.splitFocusedPane(.right, title: "agent")
    _ = workspace.splitFocusedPane(.down, title: "logs")
    workspace.setSplitFraction(path: [], fraction: 0.80)
    workspace.setSplitFraction(path: [.second], fraction: 0.20)
    workspace.equalizeSplits()

    guard case let .split(_, _, second, rootFraction) = workspace.root,
          case let .split(_, _, _, nestedFraction) = second else {
        Issue.record("workspace should have nested split"); return
    }
    #expect(rootFraction == 0.5, "root split should equalize")
    #expect(nestedFraction == 0.5, "nested split should equalize")
}

@Test func zoomUsesFocusedPaneAsVisibleRoot() {
    var workspace = WorkspaceState()
    let originalPaneID = workspace.focusedPaneID
    guard let secondPaneID = workspace.splitFocusedPane(.right, title: "agent") else {
        Issue.record("split should create second pane"); return
    }
    #expect(workspace.visibleRoot == workspace.root, "visible root should be full root before zoom")
    workspace.toggleZoom()
    #expect(workspace.isZoomed, "workspace should be zoomed")
    #expect(workspace.visibleRoot == .leaf(secondPaneID), "visible root should be focused pane while zoomed")
    workspace.focusPane(originalPaneID)
    workspace.focusAdjacentPane(.next)
    #expect(workspace.visibleRoot == .leaf(secondPaneID), "focus adjacent in zoom should keep zoom on focused pane")
    workspace.toggleZoom()
    #expect(!workspace.isZoomed, "second toggle should unzoom")
}

@Test func focusAdjacentPaneWraps() {
    var workspace = WorkspaceState()
    let firstPaneID = workspace.focusedPaneID
    guard let secondPaneID = workspace.splitFocusedPane(.right, title: "agent") else {
        Issue.record("split should create second pane"); return
    }
    _ = workspace.focusAdjacentPane(.next)
    #expect(workspace.focusedPaneID == firstPaneID, "next focus should wrap from second to first")
    _ = workspace.focusAdjacentPane(.previous)
    #expect(workspace.focusedPaneID == secondPaneID, "previous focus should wrap from first to second")
}

@Test func directionalPaneFocusPrefersSplitGeometry() {
    var workspace = WorkspaceState()
    let leftPaneID = workspace.focusedPaneID
    guard let rightPaneID = workspace.splitFocusedPane(.right, title: "right"),
          let bottomRightPaneID = workspace.splitFocusedPane(.down, title: "bottom") else {
        Issue.record("nested split setup should be valid"); return
    }

    workspace.focusPane(leftPaneID)
    _ = workspace.focusAdjacentPane(.right)
    #expect(workspace.focusedPaneID == rightPaneID, "right focus should move into right split branch")

    _ = workspace.focusAdjacentPane(.down)
    #expect(workspace.focusedPaneID == bottomRightPaneID, "down focus should move to lower pane in vertical split")

    _ = workspace.focusAdjacentPane(.up)
    #expect(workspace.focusedPaneID == rightPaneID, "up focus should return to upper pane")

    _ = workspace.focusAdjacentPane(.left)
    #expect(workspace.focusedPaneID == leftPaneID, "left focus should return to left branch")
}

@Test func resizeFocusedSplitChangesFraction() {
    var workspace = WorkspaceState()
    let firstPaneID = workspace.focusedPaneID
    guard let secondPaneID = workspace.splitFocusedPane(.right, title: "agent") else {
        Issue.record("split should create second pane"); return
    }
    workspace.focusPane(firstPaneID)
    workspace.resizeFocusedSplit(direction: .right, amount: 10)
    guard case let .split(_, _, _, grownFraction) = workspace.root else {
        Issue.record("root should be split"); return
    }
    #expect(grownFraction > 0.5, "resizing right from first pane should grow first pane")

    workspace.focusPane(secondPaneID)
    workspace.resizeFocusedSplit(direction: .right, amount: 10)
    guard case let .split(_, _, _, reducedFraction) = workspace.root else {
        Issue.record("root should still be split"); return
    }
    #expect(reducedFraction < grownFraction, "resizing right from second pane should shrink first pane")
}

@Test func terminalTitleUpdate() {
    var workspace = WorkspaceState()
    guard let terminalID = workspace.focusedPane?.selectedTabID else {
        Issue.record("workspace should have terminal"); return
    }
    let updated = workspace.updateTerminalTitle(terminalID, title: "  very-important-shell  ")
    #expect(updated, "title update should succeed")
    #expect(workspace.focusedPane?.selectedTab?.title == "very-important-shell", "title should trim whitespace")
}

@Test func userTerminalTitleIsStable() {
    var workspace = WorkspaceState()
    guard let terminalID = workspace.focusedPane?.selectedTabID else {
        Issue.record("workspace should have terminal"); return
    }
    let renamed = workspace.updateTerminalTitle(terminalID, title: "api", userEdited: true)
    #expect(renamed, "user rename should succeed")
    #expect(workspace.focusedPane?.selectedTab?.title == "api", "user title should be visible")
    #expect(workspace.focusedPane?.selectedTab?.userTitle == "api", "user title should be marked")
    let autoOverwrite = workspace.updateTerminalTitle(terminalID, title: "shell-auto-title")
    #expect(!autoOverwrite, "automatic title should not overwrite user title")
    #expect(workspace.focusedPane?.selectedTab?.title == "api", "user title should stay stable")
    let cleared = workspace.clearUserTerminalTitle(terminalID)
    #expect(cleared, "clearing user title should succeed")
    let autoAfterClear = workspace.updateTerminalTitle(terminalID, title: "shell-auto-title")
    #expect(autoAfterClear, "automatic title should work after clearing user title")
    #expect(workspace.focusedPane?.selectedTab?.title == "shell-auto-title", "automatic title should update after clearing user title")
}

@Test func terminalWorkingDirectoryUpdate() {
    var workspace = WorkspaceState()
    guard let terminalID = workspace.focusedPane?.selectedTabID else {
        Issue.record("workspace should have terminal"); return
    }
    let updated = workspace.updateTerminalWorkingDirectory(terminalID, workingDirectory: "  /tmp/conductor  ")
    #expect(updated, "working directory update should succeed")
    #expect(workspace.focusedPane?.selectedTab?.workingDirectory == "/tmp/conductor", "working directory should trim whitespace")
}

@Test func duplicateTabCreatesFreshTerminalID() {
    var workspace = WorkspaceState()
    let paneID = workspace.focusedPaneID
    guard let sourceID = workspace.focusedPane?.selectedTabID else {
        Issue.record("workspace should have initial tab"); return
    }
    let sourceTitleUpdated = workspace.updateTerminalTitle(sourceID, title: "api", userEdited: true)
    #expect(sourceTitleUpdated, "source title should update")
    let sourceCwdUpdated = workspace.updateTerminalWorkingDirectory(sourceID, workingDirectory: "/tmp/api")
    #expect(sourceCwdUpdated, "source cwd should update")
    guard let duplicateID = workspace.duplicateTab(sourceID, in: paneID) else {
        Issue.record("duplicate tab should succeed"); return
    }
    #expect(duplicateID != sourceID, "duplicate tab should create fresh terminal id")
    #expect(workspace.panes[paneID]?.tabs.count == 2, "duplicate tab should add one tab")
    #expect(workspace.panes[paneID]?.selectedTabID == duplicateID, "duplicate tab should become selected")
    let duplicate = workspace.panes[paneID]?.selectedTab
    #expect(duplicate?.title == "api", "duplicate tab should preserve title")
    #expect(duplicate?.userTitle == "api", "duplicate tab should preserve user title")
    #expect(duplicate?.workingDirectory == "/tmp/api", "duplicate tab should preserve cwd")
    requireValidWorkspace(workspace, "duplicate tab")
}

@Test func duplicateWorkspaceCreatesFreshIDs() {
    var workspace = WorkspaceState(title: "API")
    let originalPaneID = workspace.focusedPaneID
    guard let originalTerminalID = workspace.focusedPane?.selectedTabID,
          workspace.updateTerminalTitle(originalTerminalID, title: "server", userEdited: true),
          workspace.updateTerminalWorkingDirectory(originalTerminalID, workingDirectory: "/tmp/server"),
          workspace.splitFocusedPane(.right, title: "logs") != nil else {
        Issue.record("duplicate workspace setup should be valid"); return
    }
    let duplicate = workspace.duplicated(title: "API 副本")
    #expect(duplicate.id != workspace.id, "duplicate workspace should create fresh workspace id")
    #expect(duplicate.title == "API 副本", "duplicate workspace should use requested title")
    #expect(duplicate.root.leaves.count == workspace.root.leaves.count, "duplicate workspace should preserve split shape")
    #expect(Set(duplicate.root.leaves).isDisjoint(with: Set(workspace.root.leaves)), "duplicate workspace should create fresh pane ids")
    let originalTerminalIDs = Set(workspace.panes.values.flatMap { $0.tabs.map(\.id) })
    let duplicateTerminalIDs = Set(duplicate.panes.values.flatMap { $0.tabs.map(\.id) })
    #expect(originalTerminalIDs.isDisjoint(with: duplicateTerminalIDs), "duplicate workspace should create fresh terminal ids")
    #expect(duplicate.panes.values.flatMap { $0.tabs.map(\.title) }.contains("server"), "duplicate workspace should preserve tab titles")
    #expect(duplicate.panes.values.flatMap { $0.tabs.map(\.workingDirectory) }.contains("/tmp/server"), "duplicate workspace should preserve cwd")
    #expect(duplicate.focusedPaneID != originalPaneID, "duplicate workspace should remap focused pane")
    requireValidWorkspace(duplicate, "duplicate workspace")
}

@Test func moveSelectedTab() {
    var workspace = WorkspaceState()
    let paneID = workspace.focusedPaneID
    let first = workspace.focusedPane!.selectedTabID
    let second = workspace.newTerminal(title: "server")
    let third = workspace.newTerminal(title: "logs")

    let moved1 = workspace.moveSelectedTab(offset: -1, in: paneID)
    #expect(moved1, "selected third tab should move left")
    #expect(workspace.panes[paneID]?.tabs.map(\.id) == [first, third, second], "third tab should move before second")
    let moved2 = workspace.moveSelectedTab(offset: -1, in: paneID)
    #expect(moved2, "selected third tab should move left again")
    #expect(workspace.panes[paneID]?.tabs.map(\.id) == [third, first, second], "third tab should move to front")
    let moved3 = workspace.moveSelectedTab(offset: -1, in: paneID)
    #expect(!moved3, "front tab should not move left")
}

@Test func reorderTabBeforeTarget() {
    var workspace = WorkspaceState()
    let paneID = workspace.focusedPaneID
    let first = workspace.focusedPane!.selectedTabID
    let second = workspace.newTerminal(title: "server")
    let third = workspace.newTerminal(title: "logs")

    let reordered = workspace.reorderTab(third, before: first, in: paneID)
    #expect(reordered, "reorder should succeed")
    #expect(workspace.panes[paneID]?.tabs.map(\.id) == [third, first, second], "third tab should move before first")
    #expect(workspace.panes[paneID]?.selectedTabID == third, "dragged tab should become selected")
}

@Test func moveTabAcrossPanesByDrop() {
    var workspace = WorkspaceState()
    let sourcePaneID = workspace.focusedPaneID
    let first = workspace.focusedPane!.selectedTabID
    let dragged = workspace.newTerminal(title: "server")
    guard let destinationPaneID = workspace.splitFocusedPane(.right, title: "agent"),
          let target = workspace.panes[destinationPaneID]?.selectedTabID else {
        Issue.record("split should create destination pane"); return
    }

    let result = workspace.moveTab(dragged, before: target, in: destinationPaneID)
    #expect(result.movedTerminalID == dragged, "cross-pane drop should report moved tab")
    #expect(result.closedPaneIDs.isEmpty, "source pane with another tab should stay open")
    #expect(workspace.panes[sourcePaneID]?.tabs.map(\.id) == [first], "source pane should keep remaining tab")
    #expect(workspace.panes[destinationPaneID]?.tabs.map(\.id) == [dragged, target], "destination pane should insert before target")
    #expect(workspace.panes[destinationPaneID]?.selectedTabID == dragged, "dropped tab should become selected")
}

@Test func moveOnlyTabByDropClosesSourcePane() {
    var workspace = WorkspaceState()
    let sourcePaneID = workspace.focusedPaneID
    let dragged = workspace.focusedPane!.selectedTabID
    guard let destinationPaneID = workspace.splitFocusedPane(.right, title: "agent"),
          let target = workspace.panes[destinationPaneID]?.selectedTabID else {
        Issue.record("split should create destination pane"); return
    }

    let result = workspace.moveTab(dragged, before: target, in: destinationPaneID)
    #expect(result.movedTerminalID == dragged, "drop moving only source tab should report moved terminal")
    #expect(result.closedPaneIDs == [sourcePaneID], "drop moving only source tab should close source pane")
    #expect(workspace.panes[sourcePaneID] == nil, "drop source pane should be removed")
    #expect(workspace.root.leaves == [destinationPaneID], "drop should collapse split tree to destination")
    #expect(workspace.panes[destinationPaneID]?.tabs.map(\.id) == [dragged, target], "destination should insert dragged tab before target")
    #expect(workspace.focusedPaneID == destinationPaneID, "destination should become focused after drop")
    requireValidWorkspace(workspace, "move only tab by drop")
}

@Test func invalidDropDoesNotMutateWorkspace() {
    var workspace = WorkspaceState()
    let sourcePaneID = workspace.focusedPaneID
    let dragged = workspace.newTerminal(title: "server")
    guard let destinationPaneID = workspace.splitFocusedPane(.right, title: "agent") else {
        Issue.record("split should create destination pane"); return
    }
    let before = workspace
    let missingTarget = TerminalID()
    let result = workspace.moveTab(dragged, before: missingTarget, in: destinationPaneID)

    #expect(result.movedTerminalID == nil, "invalid drop target should not report moved terminal")
    #expect(result.closedPaneIDs.isEmpty, "invalid drop target should not close panes")
    #expect(workspace == before, "invalid drop target should not mutate workspace")
    #expect(workspace.panes[sourcePaneID]?.tabs.contains(where: { $0.id == dragged }) == true, "dragged tab should remain in source")
}

@Test func moveOnlyTabAcrossPanesClosesSourcePane() {
    var workspace = WorkspaceState()
    let sourcePaneID = workspace.focusedPaneID
    let moved = workspace.focusedPane!.selectedTabID
    guard let destinationPaneID = workspace.splitFocusedPane(.right, title: "agent") else {
        Issue.record("split should create destination pane"); return
    }

    workspace.focusPane(sourcePaneID)
    let result = workspace.moveSelectedTabToPane(destinationPaneID)
    #expect(result.movedTerminalID == moved, "moving only tab should report moved terminal")
    #expect(result.closedPaneIDs == [sourcePaneID], "moving only tab should close empty source pane")
    #expect(workspace.panes[sourcePaneID] == nil, "source pane should be removed")
    #expect(workspace.root.leaves == [destinationPaneID], "split tree should collapse to destination pane")
    #expect(workspace.focusedPaneID == destinationPaneID, "destination pane should become focused")
}

@Test func commandAvailability() {
    var workspace = WorkspaceState()
    #expect(!workspace.canClosePane(workspace.focusedPaneID), "single pane should not be closeable as a pane")
    #expect(!workspace.canMoveSelectedTab(offset: -1), "single tab cannot move left")
    #expect(!workspace.canMoveSelectedTabToNewSplit(), "single tab cannot move into a new split")

    _ = workspace.newTerminal(title: "server")
    #expect(workspace.canCloseOtherTabs(), "two tabs can close others")
    #expect(workspace.canMoveSelectedTab(offset: -1), "second selected tab can move left")
    #expect(workspace.canMoveSelectedTabToNewSplit(), "selected tab can move to new split when source has another tab")

    guard let first = workspace.panes[workspace.focusedPaneID]?.tabs.first?.id else {
        Issue.record("workspace should have first tab"); return
    }
    workspace.selectTab(first, in: workspace.focusedPaneID)
    #expect(workspace.canCloseTabsToRight(), "first tab can close tabs to right")
}

@Test func closeOtherTabs() {
    var workspace = WorkspaceState()
    let paneID = workspace.focusedPaneID
    let first = workspace.focusedPane!.selectedTabID
    let second = workspace.newTerminal(title: "server")
    let third = workspace.newTerminal(title: "logs")
    workspace.selectTab(second, in: paneID)
    let result = workspace.closeTabs(scope: .others, in: paneID)

    #expect(Set(result.closedTerminalIDs) == Set([first, third]), "close others should close non-selected tabs")
    #expect(workspace.panes[paneID]?.tabs.map(\.id) == [second], "only selected tab should remain")
    #expect(workspace.panes[paneID]?.selectedTabID == second, "selected tab should remain selected")
}

@Test func closeTabsToRight() {
    var workspace = WorkspaceState()
    let paneID = workspace.focusedPaneID
    let first = workspace.focusedPane!.selectedTabID
    let second = workspace.newTerminal(title: "server")
    let third = workspace.newTerminal(title: "logs")
    workspace.selectTab(first, in: paneID)
    let result = workspace.closeTabs(scope: .toRight, in: paneID)

    #expect(Set(result.closedTerminalIDs) == Set([second, third]), "close right should close tabs after selected")
    #expect(workspace.panes[paneID]?.tabs.map(\.id) == [first], "only leftmost selected tab should remain")
}

@Test func moveSelectedTabToNextPane() {
    var workspace = WorkspaceState()
    let firstPaneID = workspace.focusedPaneID
    let firstTerminalID = workspace.focusedPane!.selectedTabID
    let movedTerminalID = workspace.newTerminal(title: "server")
    guard let secondPaneID = workspace.splitFocusedPane(.right, title: "agent") else {
        Issue.record("split should create second pane"); return
    }
    workspace.focusPane(firstPaneID)
    workspace.selectTab(movedTerminalID, in: firstPaneID)
    let result = workspace.moveSelectedTabToNextPane()

    #expect(result.movedTerminalID == movedTerminalID, "move to next pane should report moved terminal")
    #expect(workspace.panes[firstPaneID]?.tabs.map(\.id) == [firstTerminalID], "source pane should keep remaining tab")
    #expect(workspace.panes[secondPaneID]?.tabs.last?.id == movedTerminalID, "destination pane should receive moved tab")
    #expect(workspace.panes[secondPaneID]?.selectedTabID == movedTerminalID, "moved tab should be selected in destination")
    #expect(workspace.focusedPaneID == secondPaneID, "destination pane should become focused")
}

@Test func moveSelectedTabToNewSplit() {
    var workspace = WorkspaceState()
    let sourcePaneID = workspace.focusedPaneID
    let firstTerminalID = workspace.focusedPane!.selectedTabID
    let movedTerminalID = workspace.newTerminal(title: "server")
    let result = workspace.moveSelectedTabToNewSplit(.right)

    #expect(result.movedTerminalID == movedTerminalID, "move to new split should report moved terminal")
    #expect(workspace.root.leaves.count == 2, "move to new split should create pane")
    #expect(workspace.panes[sourcePaneID]?.tabs.map(\.id) == [firstTerminalID], "source pane should keep remaining tab")
    let destinationPaneID = workspace.focusedPaneID
    #expect(destinationPaneID != sourcePaneID, "new pane should become focused")
    #expect(workspace.panes[destinationPaneID]?.tabs.map(\.id) == [movedTerminalID], "new pane should own moved tab")
}

@Test func moveInactiveTabToNewSplitPreservesSourceSelection() {
    var workspace = WorkspaceState()
    let sourcePaneID = workspace.focusedPaneID
    let firstTerminalID = workspace.focusedPane!.selectedTabID
    let movedTerminalID = workspace.newTerminal(title: "server")
    let thirdTerminalID = workspace.newTerminal(title: "logs")
    workspace.selectTab(firstTerminalID, in: sourcePaneID)

    let result = workspace.moveTabToNewSplit(movedTerminalID, .down)

    #expect(result.movedTerminalID == movedTerminalID, "inactive tab move to split should report moved terminal")
    #expect(workspace.root.leaves.count == 2, "inactive tab move should create pane")
    #expect(workspace.panes[sourcePaneID]?.tabs.map(\.id) == [firstTerminalID, thirdTerminalID], "source pane should remove only dragged tab")
    #expect(workspace.panes[sourcePaneID]?.selectedTabID == firstTerminalID, "source pane selection should not jump when moving inactive tab")
    let destinationPaneID = workspace.focusedPaneID
    #expect(destinationPaneID != sourcePaneID, "new pane should become focused after inactive tab move")
    #expect(workspace.panes[destinationPaneID]?.tabs.map(\.id) == [movedTerminalID], "new pane should own inactive moved tab")
    requireValidWorkspace(workspace, "move inactive tab to new split")
}

@Test func moveTabToNewSplitSupportsAllDropEdges() {
    for direction in [SplitDirection.left, .right, .up, .down] {
        var workspace = WorkspaceState()
        let sourcePaneID = workspace.focusedPaneID
        let firstTerminalID = workspace.focusedPane!.selectedTabID
        let movedTerminalID = workspace.newTerminal(title: direction.rawValue)

        let result = workspace.moveTabToNewSplit(movedTerminalID, direction)
        let destinationPaneID = workspace.focusedPaneID

        #expect(result.movedTerminalID == movedTerminalID, "drop edge \(direction.rawValue) should report moved terminal")
        #expect(destinationPaneID != sourcePaneID, "drop edge \(direction.rawValue) should focus new pane")
        #expect(workspace.panes[sourcePaneID]?.tabs.map(\.id) == [firstTerminalID], "drop edge \(direction.rawValue) should keep source tab")
        #expect(workspace.panes[destinationPaneID]?.tabs.map(\.id) == [movedTerminalID], "drop edge \(direction.rawValue) should own moved tab")

        guard case let .split(axis, first, second, _) = workspace.root else {
            Issue.record("drop edge \(direction.rawValue) should create split root"); return
        }
        #expect(axis == direction.axis, "drop edge \(direction.rawValue) should use expected split axis")
        let expectedFirst: SplitNode = direction.insertsBeforeFocusedPane ? .leaf(destinationPaneID) : .leaf(sourcePaneID)
        let expectedSecond: SplitNode = direction.insertsBeforeFocusedPane ? .leaf(sourcePaneID) : .leaf(destinationPaneID)
        #expect(first == expectedFirst, "drop edge \(direction.rawValue) should place first node correctly")
        #expect(second == expectedSecond, "drop edge \(direction.rawValue) should place second node correctly")
        requireValidWorkspace(workspace, "move tab to new split edge \(direction.rawValue)")
    }
}

@Test func moveTabToSplitAroundTargetPane() {
    var workspace = WorkspaceState()
    let sourcePaneID = workspace.focusedPaneID
    let firstTerminalID = workspace.focusedPane!.selectedTabID
    let movedTerminalID = workspace.newTerminal(title: "server")
    guard let targetPaneID = workspace.splitFocusedPane(.right, title: "target") else {
        Issue.record("target split should be created"); return
    }
    let targetTerminalID = workspace.panes[targetPaneID]!.selectedTabID

    let result = workspace.moveTabToSplit(movedTerminalID, targetPaneID: targetPaneID, .up)
    let destinationPaneID = workspace.focusedPaneID

    #expect(result.movedTerminalID == movedTerminalID, "target split drop should report moved terminal")
    #expect(workspace.panes[sourcePaneID]?.tabs.map(\.id) == [firstTerminalID], "source pane should keep remaining tab")
    #expect(workspace.panes[targetPaneID]?.tabs.map(\.id) == [targetTerminalID], "target pane should remain intact")
    #expect(workspace.panes[destinationPaneID]?.tabs.map(\.id) == [movedTerminalID], "new target-adjacent pane should own moved tab")
    guard case let .split(axis, first, second, _) = workspace.root else {
        Issue.record("target split drop should keep split root"); return
    }
    #expect(axis == .horizontal, "original root should remain horizontal")
    #expect(first == .leaf(sourcePaneID), "source pane should stay outside target replacement")
    #expect(second.leaves == [destinationPaneID, targetPaneID], "target pane should be replaced by vertical split with moved tab above")
    requireValidWorkspace(workspace, "move tab to split around target pane")
}

@Test func moveOnlyTabToSplitAroundTargetPaneClosesSource() {
    var workspace = WorkspaceState()
    let sourcePaneID = workspace.focusedPaneID
    let movedTerminalID = workspace.focusedPane!.selectedTabID
    guard let targetPaneID = workspace.splitFocusedPane(.right, title: "target") else {
        Issue.record("target split should be created"); return
    }

    let result = workspace.moveTabToSplit(movedTerminalID, targetPaneID: targetPaneID, .left)
    let destinationPaneID = workspace.focusedPaneID

    #expect(result.movedTerminalID == movedTerminalID, "only-tab target split drop should report moved terminal")
    #expect(result.closedPaneIDs == [sourcePaneID], "only-tab target split drop should report closed source pane")
    #expect(workspace.panes[sourcePaneID] == nil, "only-tab source pane should close")
    #expect(workspace.panes[destinationPaneID]?.tabs.map(\.id) == [movedTerminalID], "new pane should own moved tab")
    #expect(workspace.root.leaves == [destinationPaneID, targetPaneID], "target replacement should remain after source closes")
    requireValidWorkspace(workspace, "move only tab to split around target pane")
}

@Test func contextTabMoveAvailabilityUsesTargetTabPane() {
    var workspace = WorkspaceState()
    let sourcePaneID = workspace.focusedPaneID
    _ = workspace.newTerminal(title: "server")
    guard let destinationPaneID = workspace.splitFocusedPane(.right, title: "agent") else {
        Issue.record("split should create destination pane"); return
    }

    workspace.focusPane(destinationPaneID)
    #expect(workspace.canMoveSelectedTabToNextPane(), "single tab in existing split can move to next pane")
    #expect(!workspace.canMoveSelectedTabToNewSplit(), "single tab cannot move into a new split")

    workspace.focusPane(sourcePaneID)
    #expect(workspace.canMoveSelectedTabToNextPane(), "multi-tab source can move selected tab to next pane")
    #expect(workspace.canMoveSelectedTabToNewSplit(), "multi-tab source can move selected tab to a new split")
    requireValidWorkspace(workspace, "context tab move availability")
}

@Test func moveTabToEndInSamePane() {
    var workspace = WorkspaceState()
    let paneID = workspace.focusedPaneID
    let first = workspace.focusedPane!.selectedTabID
    let second = workspace.newTerminal(title: "server")
    let third = workspace.newTerminal(title: "logs")

    let result = workspace.moveTab(first, in: paneID)
    #expect(result.movedTerminalID == first, "move to end should report moved tab")
    #expect(workspace.panes[paneID]?.tabs.map(\.id) == [second, third, first], "first tab should move to end")
    #expect(workspace.panes[paneID]?.selectedTabID == first, "moved tab should become selected")
    requireValidWorkspace(workspace, "move tab to end in same pane")
}

@Test func rapidTabSwitchingKeepsStableStructure() {
    var workspace = WorkspaceState()
    let paneID = workspace.focusedPaneID
    for index in 1...12 {
        workspace.newTerminal(title: "tab-\(index)")
    }
    let expectedTabs = workspace.panes[paneID]!.tabs.map(\.id)

    for iteration in 0..<500 {
        _ = workspace.selectAdjacentTab(offset: iteration.isMultiple(of: 2) ? 1 : -1, in: paneID)
        #expect(workspace.panes[paneID]?.tabs.map(\.id) == expectedTabs, "rapid tab switching should not reorder tabs")
        requireValidWorkspace(workspace, "rapid tab switching \(iteration)")
    }
}

@Test func complexWorkspaceStressMaintainsInvariants() {
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
    #expect(workspace.panes.count == WorkspaceState.defaultMaximumPaneCount, "stress should reach maximum pane count")

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
    #expect(workspace.panes.count == 1, "stress should end with one pane")
    requireValidWorkspace(workspace, "stress final")
}
