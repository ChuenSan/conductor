import Foundation

public enum SplitAxis: String, Codable, Sendable {
    case horizontal
    case vertical
}

public enum SplitDirection: String, Codable, Sendable {
    case left
    case right
    case up
    case down

    public var axis: SplitAxis {
        switch self {
        case .left, .right:
            .horizontal
        case .up, .down:
            .vertical
        }
    }

    public var insertsBeforeFocusedPane: Bool {
        switch self {
        case .left, .up:
            true
        case .right, .down:
            false
        }
    }
}

public enum FocusDirection: String, Codable, Sendable {
    case previous
    case next
    case left
    case right
    case up
    case down

    public var linearOffset: Int {
        switch self {
        case .previous, .left, .up:
            -1
        case .next, .right, .down:
            1
        }
    }
}

public enum ResizeSplitDirection: String, Codable, Sendable {
    case left
    case right
    case up
    case down
}

public enum SplitPathElement: String, Codable, Sendable {
    case first
    case second
}

public struct TerminalTabState: Identifiable, Equatable, Codable, Sendable {
    public let id: TerminalID
    public var title: String
    public var userTitle: String?
    public var workingDirectory: String?

    public init(id: TerminalID = TerminalID(), title: String, userTitle: String? = nil, workingDirectory: String? = nil) {
        self.id = id
        self.title = title
        self.userTitle = userTitle
        self.workingDirectory = workingDirectory
    }
}

public struct PaneState: Identifiable, Equatable, Codable, Sendable {
    public let id: PaneID
    public var tabs: [TerminalTabState]
    public var selectedTabID: TerminalID

    public init(id: PaneID = PaneID(), tabs: [TerminalTabState]) {
        precondition(!tabs.isEmpty, "PaneState requires at least one terminal tab")
        self.id = id
        self.tabs = tabs
        self.selectedTabID = tabs[0].id
    }

    public var selectedTab: TerminalTabState? {
        tabs.first { $0.id == selectedTabID }
    }
}

public struct WorkspaceCloseResult: Equatable, Sendable {
    public var closedTerminalIDs: [TerminalID]
    public var closedPaneIDs: [PaneID]
    public var replacementTerminalID: TerminalID?

    public init(
        closedTerminalIDs: [TerminalID] = [],
        closedPaneIDs: [PaneID] = [],
        replacementTerminalID: TerminalID? = nil
    ) {
        self.closedTerminalIDs = closedTerminalIDs
        self.closedPaneIDs = closedPaneIDs
        self.replacementTerminalID = replacementTerminalID
    }
}

public struct WorkspaceMoveResult: Equatable, Sendable {
    public var movedTerminalID: TerminalID?
    public var closedPaneIDs: [PaneID]

    public init(movedTerminalID: TerminalID? = nil, closedPaneIDs: [PaneID] = []) {
        self.movedTerminalID = movedTerminalID
        self.closedPaneIDs = closedPaneIDs
    }
}

public enum TabCloseScope: Equatable, Sendable {
    case selected
    case others
    case toRight
}

public indirect enum SplitNode: Equatable, Codable, Sendable {
    case leaf(PaneID)
    case split(axis: SplitAxis, first: SplitNode, second: SplitNode, fraction: Double)

    public var leaves: [PaneID] {
        switch self {
        case let .leaf(id):
            [id]
        case let .split(_, first, second, _):
            first.leaves + second.leaves
        }
    }

    public var firstLeaf: PaneID? {
        switch self {
        case let .leaf(id):
            id
        case let .split(_, first, _, _):
            first.firstLeaf
        }
    }

    public var lastLeaf: PaneID? {
        switch self {
        case let .leaf(id):
            id
        case let .split(_, _, second, _):
            second.lastLeaf
        }
    }

    public var primaryAxis: SplitAxis? {
        switch self {
        case .leaf:
            nil
        case let .split(axis, _, _, _):
            axis
        }
    }

    public var containsMixedAxes: Bool {
        switch self {
        case .leaf:
            false
        case let .split(axis, first, second, _):
            first.containsAxis(otherThan: axis) ||
                second.containsAxis(otherThan: axis) ||
                first.containsMixedAxes ||
                second.containsMixedAxes
        }
    }

    public func replacingLeaf(_ target: PaneID, with replacement: SplitNode) -> SplitNode {
        switch self {
        case let .leaf(id):
            id == target ? replacement : self
        case let .split(axis, first, second, fraction):
            .split(
                axis: axis,
                first: first.replacingLeaf(target, with: replacement),
                second: second.replacingLeaf(target, with: replacement),
                fraction: fraction
            )
        }
    }

    public func remappingLeaves(_ map: [PaneID: PaneID]) -> SplitNode {
        switch self {
        case let .leaf(id):
            .leaf(map[id] ?? id)
        case let .split(axis, first, second, fraction):
            .split(
                axis: axis,
                first: first.remappingLeaves(map),
                second: second.remappingLeaves(map),
                fraction: fraction
            )
        }
    }

    public func settingFraction(at path: ArraySlice<SplitPathElement>, to fraction: Double) -> SplitNode {
        let clampedFraction = min(0.85, max(0.15, fraction))
        guard let head = path.first else {
            switch self {
            case let .leaf(id):
                return .leaf(id)
            case let .split(axis, first, second, _):
                return .split(axis: axis, first: first, second: second, fraction: clampedFraction)
            }
        }

        switch self {
        case let .leaf(id):
            return .leaf(id)
        case let .split(axis, first, second, fraction):
            let tail = path.dropFirst()
            switch head {
            case .first:
                return .split(axis: axis, first: first.settingFraction(at: tail, to: clampedFraction), second: second, fraction: fraction)
            case .second:
                return .split(axis: axis, first: first, second: second.settingFraction(at: tail, to: clampedFraction), fraction: fraction)
            }
        }
    }

    public func equalized() -> SplitNode {
        switch self {
        case let .leaf(id):
            .leaf(id)
        case let .split(axis, first, second, _):
            .split(axis: axis, first: first.equalized(), second: second.equalized(), fraction: 0.5)
        }
    }

    public static func line(leaves: [PaneID], axis: SplitAxis) -> SplitNode? {
        guard !leaves.isEmpty else { return nil }
        return line(axis: axis, nodes: leaves.map { .leaf($0) })
    }

    private static func line(axis: SplitAxis, nodes: [SplitNode]) -> SplitNode? {
        guard let first = nodes.first else { return nil }
        guard nodes.count > 1 else { return first }
        let rest = Array(nodes.dropFirst())
        guard let second = line(axis: axis, nodes: rest) else { return first }
        return .split(
            axis: axis,
            first: first,
            second: second,
            fraction: 1.0 / Double(nodes.count)
        )
    }

    private func containsAxis(otherThan expectedAxis: SplitAxis) -> Bool {
        switch self {
        case .leaf:
            false
        case let .split(axis, first, second, _):
            axis != expectedAxis ||
                first.containsAxis(otherThan: expectedAxis) ||
                second.containsAxis(otherThan: expectedAxis)
        }
    }

    public func path(to target: PaneID) -> [SplitPathElement]? {
        switch self {
        case let .leaf(id):
            return id == target ? [] : nil
        case let .split(_, first, second, _):
            if let path = first.path(to: target) {
                return [.first] + path
            }
            if let path = second.path(to: target) {
                return [.second] + path
            }
            return nil
        }
    }

    public func directionalNeighbor(of target: PaneID, direction: FocusDirection) -> PaneID? {
        switch self {
        case .leaf:
            return nil
        case let .split(axis, first, second, _):
            let firstContains = first.leaves.contains(target)
            let secondContains = second.leaves.contains(target)

            if axis == .horizontal {
                if direction == .right, firstContains {
                    return second.firstLeaf
                }
                if direction == .left, secondContains {
                    return first.lastLeaf
                }
            }

            if axis == .vertical {
                if direction == .down, firstContains {
                    return second.firstLeaf
                }
                if direction == .up, secondContains {
                    return first.lastLeaf
                }
            }

            if firstContains {
                return first.directionalNeighbor(of: target, direction: direction)
            }
            if secondContains {
                return second.directionalNeighbor(of: target, direction: direction)
            }
            return nil
        }
    }

    public func resizingSplit(containing target: PaneID, direction: ResizeSplitDirection, amount: Double) -> SplitNode {
        switch self {
        case .leaf:
            return self
        case let .split(axis, first, second, fraction):
            let firstContains = first.leaves.contains(target)
            let secondContains = second.leaves.contains(target)
            guard firstContains || secondContains else { return self }

            let shouldAdjustHere =
                (axis == .horizontal && (direction == .left || direction == .right)) ||
                (axis == .vertical && (direction == .up || direction == .down))

            if shouldAdjustHere {
                let normalizedAmount = max(0.02, min(0.20, amount / 100.0))
                let firstGrows: Bool
                switch direction {
                case .left:
                    firstGrows = secondContains
                case .right:
                    firstGrows = firstContains
                case .up:
                    firstGrows = secondContains
                case .down:
                    firstGrows = firstContains
                }
                let nextFraction = fraction + (firstGrows ? normalizedAmount : -normalizedAmount)
                return settingFraction(at: [], to: nextFraction)
            }

            if firstContains {
                return .split(
                    axis: axis,
                    first: first.resizingSplit(containing: target, direction: direction, amount: amount),
                    second: second,
                    fraction: fraction
                )
            }

            return .split(
                axis: axis,
                first: first,
                second: second.resizingSplit(containing: target, direction: direction, amount: amount),
                fraction: fraction
            )
        }
    }

    public func removingLeaf(_ target: PaneID) -> SplitNode? {
        switch self {
        case let .leaf(id):
            return id == target ? nil : self
        case let .split(axis, first, second, fraction):
            let firstResult = first.removingLeaf(target)
            let secondResult = second.removingLeaf(target)

            switch (firstResult, secondResult) {
            case let (.some(firstNode), .some(secondNode)):
                return .split(axis: axis, first: firstNode, second: secondNode, fraction: fraction)
            case let (.some(firstNode), .none):
                return firstNode
            case let (.none, .some(secondNode)):
                return secondNode
            case (.none, .none):
                return nil
            }
        }
    }
}

public struct WorkspaceState: Identifiable, Equatable, Codable, Sendable {
    public static let defaultMaximumPaneCount = 6

    public let id: WorkspaceID
    public var title: String
    public var root: SplitNode
    public var panes: [PaneID: PaneState]
    public var focusedPaneID: PaneID
    public var zoomedPaneID: PaneID?

    public init(title: String = "正式开发") {
        let terminal = TerminalTabState(title: "zsh")
        let pane = PaneState(tabs: [terminal])
        self.id = WorkspaceID()
        self.title = title
        self.root = .leaf(pane.id)
        self.panes = [pane.id: pane]
        self.focusedPaneID = pane.id
        self.zoomedPaneID = nil
    }

    public init(
        id: WorkspaceID = WorkspaceID(),
        title: String,
        root: SplitNode,
        panes: [PaneID: PaneState],
        focusedPaneID: PaneID,
        zoomedPaneID: PaneID? = nil
    ) {
        precondition(!panes.isEmpty, "WorkspaceState requires at least one pane")
        self.id = id
        self.title = title
        self.root = root
        self.panes = panes
        self.focusedPaneID = panes[focusedPaneID] == nil ? panes.keys.sorted { $0.description < $1.description }[0] : focusedPaneID
        self.zoomedPaneID = zoomedPaneID.flatMap { panes[$0] == nil ? nil : $0 }
    }

    public var focusedPane: PaneState? {
        panes[focusedPaneID]
    }

    public var visibleRoot: SplitNode {
        if let zoomedPaneID, panes[zoomedPaneID] != nil {
            return .leaf(zoomedPaneID)
        }
        return root
    }

    public var isZoomed: Bool {
        zoomedPaneID != nil
    }

    public func paneID(containing terminalID: TerminalID) -> PaneID? {
        panes.first { _, pane in
            pane.tabs.contains { $0.id == terminalID }
        }?.key
    }

    public func nextPaneID(after paneID: PaneID, offset: Int = 1) -> PaneID? {
        let leaves = root.leaves.filter { panes[$0] != nil }
        guard leaves.count > 1, let index = leaves.firstIndex(of: paneID) else { return nil }
        let count = leaves.count
        let nextIndex = (index + offset % count + count) % count
        return leaves[nextIndex]
    }

    public func canSplit(maximumPaneCount: Int = Self.defaultMaximumPaneCount) -> Bool {
        panes.count < maximumPaneCount && panes[focusedPaneID] != nil
    }

    public func canClosePane(_ paneID: PaneID) -> Bool {
        panes[paneID] != nil && panes.count > 1
    }

    public func canCloseOtherTabs(in paneID: PaneID? = nil) -> Bool {
        let targetPaneID = paneID ?? focusedPaneID
        return (panes[targetPaneID]?.tabs.count ?? 0) > 1
    }

    public func canCloseTabsToRight(in paneID: PaneID? = nil) -> Bool {
        let targetPaneID = paneID ?? focusedPaneID
        guard let pane = panes[targetPaneID],
              let selectedIndex = pane.tabs.firstIndex(where: { $0.id == pane.selectedTabID }) else {
            return false
        }
        return selectedIndex < pane.tabs.count - 1
    }

    public func canCloseTabsToRight(of terminalID: TerminalID, in paneID: PaneID) -> Bool {
        guard let pane = panes[paneID],
              let selectedIndex = pane.tabs.firstIndex(where: { $0.id == terminalID }) else {
            return false
        }
        return selectedIndex < pane.tabs.count - 1
    }

    public func canMoveSelectedTab(offset: Int, in paneID: PaneID? = nil) -> Bool {
        let targetPaneID = paneID ?? focusedPaneID
        guard let pane = panes[targetPaneID],
              pane.tabs.count > 1,
              let currentIndex = pane.tabs.firstIndex(where: { $0.id == pane.selectedTabID }) else {
            return false
        }
        let nextIndex = max(0, min(pane.tabs.count - 1, currentIndex + offset))
        return nextIndex != currentIndex
    }

    public func canMoveSelectedTabToPane(_ destinationPaneID: PaneID) -> Bool {
        guard focusedPaneID != destinationPaneID,
              panes[destinationPaneID] != nil,
              let sourcePane = panes[focusedPaneID] else {
            return false
        }
        return sourcePane.tabs.count > 1 || panes.count > 1
    }

    public func canMoveSelectedTabToNextPane(offset: Int = 1) -> Bool {
        guard let destinationPaneID = nextPaneID(after: focusedPaneID, offset: offset) else { return false }
        return canMoveSelectedTabToPane(destinationPaneID)
    }

    public func canMoveSelectedTabToNewSplit(maximumPaneCount: Int = Self.defaultMaximumPaneCount) -> Bool {
        guard let sourcePane = panes[focusedPaneID] else { return false }
        return canSplit(maximumPaneCount: maximumPaneCount) && sourcePane.tabs.count > 1
    }

    public func canMoveTabToNewSplit(_ tabID: TerminalID, maximumPaneCount: Int = Self.defaultMaximumPaneCount) -> Bool {
        guard canSplit(maximumPaneCount: maximumPaneCount),
              let sourcePaneID = paneID(containing: tabID),
              let sourcePane = panes[sourcePaneID] else {
            return false
        }
        return sourcePane.tabs.count > 1
    }

    public func canMoveTabToSplit(
        _ tabID: TerminalID,
        targetPaneID: PaneID,
        maximumPaneCount: Int = Self.defaultMaximumPaneCount
    ) -> Bool {
        guard let sourcePaneID = paneID(containing: tabID),
              let sourcePane = panes[sourcePaneID],
              panes[targetPaneID] != nil else {
            return false
        }
        if sourcePaneID == targetPaneID {
            return canSplit(maximumPaneCount: maximumPaneCount) && sourcePane.tabs.count > 1
        }
        if sourcePane.tabs.count == 1 {
            return panes.count > 1
        }
        return canSplit(maximumPaneCount: maximumPaneCount)
    }

    public mutating func setSplitFraction(path: [SplitPathElement], fraction: Double) {
        root = root.settingFraction(at: path[...], to: fraction)
    }

    public mutating func equalizeSplits() {
        root = root.equalized()
    }

    public mutating func normalizeMixedSplitLayout() {
        guard panes.count > 2,
              root.containsMixedAxes,
              let axis = root.primaryAxis else {
            return
        }
        let validLeaves = root.leaves.filter { panes[$0] != nil }
        guard let normalizedRoot = SplitNode.line(leaves: validLeaves, axis: axis) else { return }
        root = normalizedRoot
        zoomedPaneID = nil
    }

    public mutating func toggleZoom() {
        if zoomedPaneID == focusedPaneID {
            zoomedPaneID = nil
        } else {
            zoomedPaneID = focusedPaneID
        }
    }

    @discardableResult
    public mutating func newTab(title: String = "zsh", workingDirectory: String? = nil) -> TerminalID {
        let tab = TerminalTabState(title: title, workingDirectory: workingDirectory)
        guard var pane = panes[focusedPaneID] else { return tab.id }
        pane.tabs.append(tab)
        pane.selectedTabID = tab.id
        panes[focusedPaneID] = pane
        return tab.id
    }

    @discardableResult
    public mutating func newTerminal(title: String = "zsh", workingDirectory: String? = nil) -> TerminalID {
        newTab(title: title, workingDirectory: workingDirectory)
    }

    @discardableResult
    public mutating func duplicateTab(_ terminalID: TerminalID, in paneID: PaneID) -> TerminalID? {
        guard var pane = panes[paneID],
              let index = pane.tabs.firstIndex(where: { $0.id == terminalID }) else {
            return nil
        }
        let source = pane.tabs[index]
        let duplicate = TerminalTabState(
            title: source.title,
            userTitle: source.userTitle,
            workingDirectory: source.workingDirectory
        )
        pane.tabs.insert(duplicate, at: index + 1)
        pane.selectedTabID = duplicate.id
        panes[paneID] = pane
        focusedPaneID = paneID
        return duplicate.id
    }

    public func duplicated(title duplicateTitle: String) -> WorkspaceState {
        var paneIDMap: [PaneID: PaneID] = [:]
        var terminalIDMap: [TerminalID: TerminalID] = [:]
        var duplicatedPanes: [PaneID: PaneState] = [:]

        for paneID in root.leaves where panes[paneID] != nil {
            let newPaneID = PaneID()
            paneIDMap[paneID] = newPaneID
        }

        for paneID in root.leaves {
            guard let pane = panes[paneID],
                  let newPaneID = paneIDMap[paneID] else {
                continue
            }
            let duplicatedTabs = pane.tabs.map { tab in
                let duplicate = TerminalTabState(
                    title: tab.title,
                    userTitle: tab.userTitle,
                    workingDirectory: tab.workingDirectory
                )
                terminalIDMap[tab.id] = duplicate.id
                return duplicate
            }
            var duplicatedPane = PaneState(id: newPaneID, tabs: duplicatedTabs)
            if let selectedTabID = terminalIDMap[pane.selectedTabID] {
                duplicatedPane.selectedTabID = selectedTabID
            }
            duplicatedPanes[newPaneID] = duplicatedPane
        }

        let newRoot = root.remappingLeaves(paneIDMap)
        let newFocusedPaneID = paneIDMap[focusedPaneID] ?? duplicatedPanes.keys.sorted { $0.description < $1.description }[0]
        let newZoomedPaneID = zoomedPaneID.flatMap { paneIDMap[$0] }
        return WorkspaceState(
            title: duplicateTitle,
            root: newRoot,
            panes: duplicatedPanes,
            focusedPaneID: newFocusedPaneID,
            zoomedPaneID: newZoomedPaneID
        )
    }

    @discardableResult
    public mutating func selectTab(_ terminalID: TerminalID, in paneID: PaneID) -> Bool {
        guard var pane = panes[paneID], pane.tabs.contains(where: { $0.id == terminalID }) else {
            return false
        }
        pane.selectedTabID = terminalID
        panes[paneID] = pane
        focusedPaneID = paneID
        return true
    }

    @discardableResult
    public mutating func selectAdjacentTab(offset: Int, in paneID: PaneID? = nil) -> TerminalID? {
        let targetPaneID = paneID ?? focusedPaneID
        guard var pane = panes[targetPaneID],
              let currentIndex = pane.tabs.firstIndex(where: { $0.id == pane.selectedTabID }),
              !pane.tabs.isEmpty else {
            return nil
        }
        let count = pane.tabs.count
        let nextIndex = (currentIndex + offset % count + count) % count
        pane.selectedTabID = pane.tabs[nextIndex].id
        panes[targetPaneID] = pane
        focusedPaneID = targetPaneID
        return pane.selectedTabID
    }

    @discardableResult
    public mutating func moveSelectedTab(offset: Int, in paneID: PaneID? = nil) -> Bool {
        let targetPaneID = paneID ?? focusedPaneID
        guard var pane = panes[targetPaneID],
              pane.tabs.count > 1,
              let currentIndex = pane.tabs.firstIndex(where: { $0.id == pane.selectedTabID }) else {
            return false
        }
        let nextIndex = max(0, min(pane.tabs.count - 1, currentIndex + offset))
        guard nextIndex != currentIndex else { return false }
        let tab = pane.tabs.remove(at: currentIndex)
        pane.tabs.insert(tab, at: nextIndex)
        pane.selectedTabID = tab.id
        panes[targetPaneID] = pane
        focusedPaneID = targetPaneID
        return true
    }

    @discardableResult
    public mutating func reorderTab(_ tabID: TerminalID, before targetTabID: TerminalID, in paneID: PaneID) -> Bool {
        moveTab(tabID, before: targetTabID, in: paneID).movedTerminalID != nil
    }

    @discardableResult
    public mutating func moveTab(
        _ tabID: TerminalID,
        before targetTabID: TerminalID? = nil,
        in destinationPaneID: PaneID
    ) -> WorkspaceMoveResult {
        guard let sourcePaneID = paneID(containing: tabID),
              var sourcePane = panes[sourcePaneID],
              var destinationPane = panes[destinationPaneID],
              let sourceIndex = sourcePane.tabs.firstIndex(where: { $0.id == tabID }) else {
            return WorkspaceMoveResult()
        }

        if let targetTabID, tabID == targetTabID {
            return WorkspaceMoveResult()
        }

        if sourcePaneID == destinationPaneID {
            let tab = sourcePane.tabs.remove(at: sourceIndex)
            let insertionIndex: Int
            if let targetTabID,
               let rawTargetIndex = sourcePane.tabs.firstIndex(where: { $0.id == targetTabID }) {
                insertionIndex = rawTargetIndex
            } else {
                insertionIndex = sourcePane.tabs.count
            }
            sourcePane.tabs.insert(tab, at: insertionIndex)
            sourcePane.selectedTabID = tab.id
            panes[sourcePaneID] = sourcePane
            focusedPaneID = sourcePaneID
            return WorkspaceMoveResult(movedTerminalID: tab.id)
        }

        guard targetTabID == nil || destinationPane.tabs.contains(where: { $0.id == targetTabID }) else {
            return WorkspaceMoveResult()
        }

        let tab = sourcePane.tabs.remove(at: sourceIndex)
        var closedPaneIDs: [PaneID] = []

        if sourcePane.tabs.isEmpty {
            panes.removeValue(forKey: sourcePaneID)
            root = root.removingLeaf(sourcePaneID) ?? replacementRootAfterRemovingLastPane()
            closedPaneIDs.append(sourcePaneID)
            if zoomedPaneID == sourcePaneID {
                zoomedPaneID = nil
            }
        } else {
            if sourcePane.selectedTabID == tabID {
                let replacementIndex = min(sourceIndex, sourcePane.tabs.count - 1)
                sourcePane.selectedTabID = sourcePane.tabs[replacementIndex].id
            }
            panes[sourcePaneID] = sourcePane
        }

        let insertionIndex: Int
        if let targetTabID,
           let targetIndex = destinationPane.tabs.firstIndex(where: { $0.id == targetTabID }) {
            insertionIndex = targetIndex
        } else {
            insertionIndex = destinationPane.tabs.count
        }
        destinationPane.tabs.insert(tab, at: insertionIndex)
        destinationPane.selectedTabID = tab.id
        panes[destinationPaneID] = destinationPane
        focusedPaneID = destinationPaneID
        return WorkspaceMoveResult(movedTerminalID: tab.id, closedPaneIDs: closedPaneIDs)
    }

    @discardableResult
    public mutating func moveSelectedTabToPane(_ destinationPaneID: PaneID) -> WorkspaceMoveResult {
        let sourcePaneID = focusedPaneID
        guard sourcePaneID != destinationPaneID,
              var sourcePane = panes[sourcePaneID],
              var destinationPane = panes[destinationPaneID],
              let selectedIndex = sourcePane.tabs.firstIndex(where: { $0.id == sourcePane.selectedTabID }) else {
            return WorkspaceMoveResult()
        }

        let tab = sourcePane.tabs.remove(at: selectedIndex)
        var closedPaneIDs: [PaneID] = []
        if sourcePane.tabs.isEmpty {
            panes.removeValue(forKey: sourcePaneID)
            root = root.removingLeaf(sourcePaneID) ?? replacementRootAfterRemovingLastPane()
            closedPaneIDs.append(sourcePaneID)
            if zoomedPaneID == sourcePaneID {
                zoomedPaneID = nil
            }
        } else {
            let replacementIndex = min(selectedIndex, sourcePane.tabs.count - 1)
            sourcePane.selectedTabID = sourcePane.tabs[replacementIndex].id
            panes[sourcePaneID] = sourcePane
        }
        destinationPane.tabs.append(tab)
        destinationPane.selectedTabID = tab.id
        panes[destinationPaneID] = destinationPane
        focusedPaneID = destinationPaneID
        return WorkspaceMoveResult(movedTerminalID: tab.id, closedPaneIDs: closedPaneIDs)
    }

    @discardableResult
    public mutating func moveSelectedTabToNextPane(offset: Int = 1) -> WorkspaceMoveResult {
        guard let destinationPaneID = nextPaneID(after: focusedPaneID, offset: offset) else {
            return WorkspaceMoveResult()
        }
        return moveSelectedTabToPane(destinationPaneID)
    }

    @discardableResult
    public mutating func moveSelectedTabToNewSplit(
        _ direction: SplitDirection,
        maximumPaneCount: Int = Self.defaultMaximumPaneCount
    ) -> WorkspaceMoveResult {
        guard let tabID = focusedPane?.selectedTabID else {
            return WorkspaceMoveResult()
        }
        return moveTabToNewSplit(tabID, direction, maximumPaneCount: maximumPaneCount)
    }

    @discardableResult
    public mutating func moveTabToNewSplit(
        _ tabID: TerminalID,
        _ direction: SplitDirection,
        maximumPaneCount: Int = Self.defaultMaximumPaneCount
    ) -> WorkspaceMoveResult {
        guard let sourcePaneID = paneID(containing: tabID) else {
            return WorkspaceMoveResult()
        }
        return moveTabToSplit(
            tabID,
            targetPaneID: sourcePaneID,
            direction,
            maximumPaneCount: maximumPaneCount
        )
    }

    @discardableResult
    public mutating func moveTabToSplit(
        _ tabID: TerminalID,
        targetPaneID: PaneID,
        _ direction: SplitDirection,
        maximumPaneCount: Int = Self.defaultMaximumPaneCount
    ) -> WorkspaceMoveResult {
        guard canMoveTabToSplit(tabID, targetPaneID: targetPaneID, maximumPaneCount: maximumPaneCount),
              let sourcePaneID = paneID(containing: tabID),
              var sourcePane = panes[sourcePaneID],
              let selectedIndex = sourcePane.tabs.firstIndex(where: { $0.id == tabID }) else {
            return WorkspaceMoveResult()
        }
        let tab = sourcePane.tabs.remove(at: selectedIndex)
        var closedPaneIDs: [PaneID] = []
        if sourcePane.selectedTabID == tabID, !sourcePane.tabs.isEmpty {
            let replacementIndex = min(selectedIndex, sourcePane.tabs.count - 1)
            sourcePane.selectedTabID = sourcePane.tabs[replacementIndex].id
        }
        if sourcePane.tabs.isEmpty {
            panes.removeValue(forKey: sourcePaneID)
            root = root.removingLeaf(sourcePaneID) ?? replacementRootAfterRemovingLastPane()
            closedPaneIDs.append(sourcePaneID)
            if zoomedPaneID == sourcePaneID {
                zoomedPaneID = nil
            }
        } else {
            panes[sourcePaneID] = sourcePane
        }

        let newPane = PaneState(tabs: [tab])
        let firstNode: SplitNode = direction.insertsBeforeFocusedPane ? .leaf(newPane.id) : .leaf(targetPaneID)
        let secondNode: SplitNode = direction.insertsBeforeFocusedPane ? .leaf(targetPaneID) : .leaf(newPane.id)
        root = root.replacingLeaf(
            targetPaneID,
            with: .split(axis: direction.axis, first: firstNode, second: secondNode, fraction: 0.5)
        )
        panes[newPane.id] = newPane
        focusedPaneID = newPane.id
        zoomedPaneID = nil
        return WorkspaceMoveResult(movedTerminalID: tab.id, closedPaneIDs: closedPaneIDs)
    }

    @discardableResult
    public mutating func updateTerminalTitle(_ terminalID: TerminalID, title: String, userEdited: Bool = false) -> Bool {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty,
              let paneID = paneID(containing: terminalID),
              var pane = panes[paneID],
              let tabIndex = pane.tabs.firstIndex(where: { $0.id == terminalID }) else {
            return false
        }
        if !userEdited, pane.tabs[tabIndex].userTitle != nil {
            return false
        }
        pane.tabs[tabIndex].title = String(trimmedTitle.prefix(48))
        if userEdited {
            pane.tabs[tabIndex].userTitle = pane.tabs[tabIndex].title
        }
        panes[paneID] = pane
        return true
    }

    @discardableResult
    public mutating func clearUserTerminalTitle(_ terminalID: TerminalID) -> Bool {
        guard let paneID = paneID(containing: terminalID),
              var pane = panes[paneID],
              let tabIndex = pane.tabs.firstIndex(where: { $0.id == terminalID }) else {
            return false
        }
        pane.tabs[tabIndex].userTitle = nil
        panes[paneID] = pane
        return true
    }

    @discardableResult
    public mutating func updateTerminalWorkingDirectory(_ terminalID: TerminalID, workingDirectory: String) -> Bool {
        let trimmedDirectory = workingDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDirectory.isEmpty,
              let paneID = paneID(containing: terminalID),
              var pane = panes[paneID],
              let tabIndex = pane.tabs.firstIndex(where: { $0.id == terminalID }) else {
            return false
        }
        pane.tabs[tabIndex].workingDirectory = trimmedDirectory
        panes[paneID] = pane
        return true
    }

    @discardableResult
    public mutating func focusPane(_ paneID: PaneID) -> Bool {
        guard panes[paneID] != nil else { return false }
        focusedPaneID = paneID
        return true
    }

    @discardableResult
    public mutating func focusAdjacentPane(_ direction: FocusDirection) -> PaneID? {
        if direction != .previous, direction != .next,
           let neighbor = root.directionalNeighbor(of: focusedPaneID, direction: direction),
           panes[neighbor] != nil {
            focusedPaneID = neighbor
            if zoomedPaneID != nil {
                zoomedPaneID = focusedPaneID
            }
            return focusedPaneID
        }

        let leaves = root.leaves.filter { panes[$0] != nil }
        guard leaves.count > 1,
              let currentIndex = leaves.firstIndex(of: focusedPaneID) else {
            return nil
        }
        let count = leaves.count
        let nextIndex = (currentIndex + direction.linearOffset % count + count) % count
        focusedPaneID = leaves[nextIndex]
        if zoomedPaneID != nil {
            zoomedPaneID = focusedPaneID
        }
        return focusedPaneID
    }

    public mutating func resizeFocusedSplit(direction: ResizeSplitDirection, amount: Double) {
        root = root.resizingSplit(containing: focusedPaneID, direction: direction, amount: amount)
    }

    @discardableResult
    public mutating func splitFocusedPane(
        _ direction: SplitDirection,
        title: String = "zsh",
        workingDirectory: String? = nil,
        maximumPaneCount: Int = Self.defaultMaximumPaneCount
    ) -> PaneID? {
        guard canSplit(maximumPaneCount: maximumPaneCount) else { return nil }
        let tab = TerminalTabState(title: title, workingDirectory: workingDirectory)
        let newPane = PaneState(tabs: [tab])
        let firstNode: SplitNode = direction.insertsBeforeFocusedPane ? .leaf(newPane.id) : .leaf(focusedPaneID)
        let secondNode: SplitNode = direction.insertsBeforeFocusedPane ? .leaf(focusedPaneID) : .leaf(newPane.id)
        let replacement = SplitNode.split(
            axis: direction.axis,
            first: firstNode,
            second: secondNode,
            fraction: 0.5
        )
        root = root.replacingLeaf(focusedPaneID, with: replacement)
        panes[newPane.id] = newPane
        focusedPaneID = newPane.id
        return newPane.id
    }

    @discardableResult
    public mutating func splitWorkspaceEdge(
        _ direction: SplitDirection,
        title: String = "zsh",
        workingDirectory: String? = nil,
        maximumPaneCount: Int = Self.defaultMaximumPaneCount
    ) -> PaneID? {
        guard canSplit(maximumPaneCount: maximumPaneCount) else { return nil }
        let tab = TerminalTabState(title: title, workingDirectory: workingDirectory)
        let newPane = PaneState(tabs: [tab])
        let existingLeaves = root.leaves.filter { panes[$0] != nil }
        let orderedLeaves = direction.insertsBeforeFocusedPane ? [newPane.id] + existingLeaves : existingLeaves + [newPane.id]
        guard let nextRoot = SplitNode.line(leaves: orderedLeaves, axis: direction.axis) else { return nil }
        panes[newPane.id] = newPane
        root = nextRoot
        focusedPaneID = newPane.id
        zoomedPaneID = nil
        return newPane.id
    }

    @discardableResult
    public mutating func closeTab(_ terminalID: TerminalID, in paneID: PaneID) -> WorkspaceCloseResult {
        guard var pane = panes[paneID],
              let index = pane.tabs.firstIndex(where: { $0.id == terminalID }) else {
            return WorkspaceCloseResult()
        }

        if pane.tabs.count > 1 {
            pane.tabs.remove(at: index)
            if pane.selectedTabID == terminalID {
                let nextIndex = min(index, pane.tabs.count - 1)
                pane.selectedTabID = pane.tabs[nextIndex].id
            }
            panes[paneID] = pane
            focusedPaneID = paneID
            return WorkspaceCloseResult(closedTerminalIDs: [terminalID])
        }

        if panes.count == 1 {
            let replacement = TerminalTabState(title: "zsh", workingDirectory: pane.tabs.first?.workingDirectory)
            panes[paneID] = PaneState(id: paneID, tabs: [replacement])
            focusedPaneID = paneID
            root = .leaf(paneID)
            return WorkspaceCloseResult(
                closedTerminalIDs: [terminalID],
                replacementTerminalID: replacement.id
            )
        }

        return closePane(paneID)
    }

    @discardableResult
    public mutating func closeTabs(scope: TabCloseScope, in paneID: PaneID? = nil) -> WorkspaceCloseResult {
        let targetPaneID = paneID ?? focusedPaneID
        guard var pane = panes[targetPaneID],
              let selectedIndex = pane.tabs.firstIndex(where: { $0.id == pane.selectedTabID }) else {
            return WorkspaceCloseResult()
        }

        switch scope {
        case .selected:
            return closeTab(pane.selectedTabID, in: targetPaneID)
        case .others:
            guard pane.tabs.count > 1 else { return WorkspaceCloseResult() }
            let selectedTab = pane.tabs[selectedIndex]
            let closedIDs = pane.tabs.filter { $0.id != selectedTab.id }.map(\.id)
            pane.tabs = [selectedTab]
            pane.selectedTabID = selectedTab.id
            panes[targetPaneID] = pane
            focusedPaneID = targetPaneID
            return WorkspaceCloseResult(closedTerminalIDs: closedIDs)
        case .toRight:
            guard selectedIndex < pane.tabs.count - 1 else { return WorkspaceCloseResult() }
            let closedIDs = pane.tabs[(selectedIndex + 1)...].map(\.id)
            pane.tabs.removeSubrange((selectedIndex + 1)..<pane.tabs.count)
            panes[targetPaneID] = pane
            focusedPaneID = targetPaneID
            return WorkspaceCloseResult(closedTerminalIDs: closedIDs)
        }
    }

    @discardableResult
    public mutating func closePane(_ paneID: PaneID) -> WorkspaceCloseResult {
        guard let pane = panes[paneID] else { return WorkspaceCloseResult() }
        let closedTerminals = pane.tabs.map(\.id)

        if panes.count == 1 {
            let replacement = TerminalTabState(title: "zsh", workingDirectory: pane.tabs.first?.workingDirectory)
            panes[paneID] = PaneState(id: paneID, tabs: [replacement])
            focusedPaneID = paneID
            root = .leaf(paneID)
            return WorkspaceCloseResult(
                closedTerminalIDs: closedTerminals,
                replacementTerminalID: replacement.id
            )
        }

        panes.removeValue(forKey: paneID)
        root = root.removingLeaf(paneID) ?? replacementRootAfterRemovingLastPane()
        let survivingLeaves = root.leaves.filter { panes[$0] != nil }
        focusedPaneID = survivingLeaves.first ?? panes.keys.sorted { $0.description < $1.description }.first ?? focusedPaneID
        if zoomedPaneID == paneID || zoomedPaneID.flatMap({ panes[$0] }) == nil {
            zoomedPaneID = nil
        }
        return WorkspaceCloseResult(closedTerminalIDs: closedTerminals, closedPaneIDs: [paneID])
    }

    @discardableResult
    public mutating func closeSelectedTab() -> WorkspaceCloseResult {
        guard let pane = panes[focusedPaneID] else { return WorkspaceCloseResult() }
        return closeTab(pane.selectedTabID, in: focusedPaneID)
    }

    private func replacementRootAfterRemovingLastPane() -> SplitNode {
        if let paneID = panes.keys.first {
            return .leaf(paneID)
        }
        return .leaf(focusedPaneID)
    }
}
