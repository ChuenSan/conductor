import ConductorCore
import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

private func L(_ zh: String, _ en: String) -> String {
    ConductorLocalization.text(zh: zh, en: en)
}

struct SplitNodeView: View {
    let node: SplitNode
    @ObservedObject var model: ConductorWindowModel
    var path: [SplitPathElement] = []

    var body: some View {
        switch node {
        case let .leaf(paneID):
            if let pane = model.workspace.panes[paneID] {
                TerminalPaneView(pane: pane, model: model)
                    .frame(minWidth: 0, minHeight: 0)
                    .clipped()
                    .transition(.identity)
            }
        case let .split(axis, first, second, fraction):
            SplitPairView(
                axis: axis,
                fraction: fraction,
                first: first,
                second: second,
                path: path,
                model: model
            )
            .transition(.identity)
        }
    }
}

private struct SplitPairView: View {
    let axis: SplitAxis
    let fraction: Double
    let first: SplitNode
    let second: SplitNode
    let path: [SplitPathElement]
    @ObservedObject var model: ConductorWindowModel
    @State private var dragStartFraction: Double?
    @State private var dragPreviewFraction: Double?

    private var isDragging: Bool {
        dragStartFraction != nil
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let divider = ConductorTokens.Space.splitGutter
            if axis == .horizontal {
                let available = max(1, size.width - divider)
                let activeFraction = dragPreviewFraction ?? fraction
                let firstMinimum = first.minimumLength(along: .horizontal, divider: divider)
                let secondMinimum = second.minimumLength(along: .horizontal, divider: divider)
                let firstWidth = splitLength(
                    fraction: activeFraction,
                    available: available,
                    firstMinimum: firstMinimum,
                    secondMinimum: secondMinimum
                )
                ZStack(alignment: .topLeading) {
                    HStack(spacing: 0) {
                        SplitNodeView(node: first, model: model, path: path + [.first])
                            .frame(width: firstWidth)
                            .clipped()
                        SplitDivider(
                            axis: axis,
                            active: dragStartFraction != nil,
                            showsIndicator: true,
                            onDragStarted: {
                                beginSplitDrag()
                            },
                            onDragChanged: { delta in
                                let base = dragStartFraction ?? fraction
                                setSplitFractionPreview(base + delta / max(1, available))
                            },
                            onDragEnded: {
                                finishSplitDrag()
                            },
                            onDoubleClick: {
                                ConductorMotion.perform(ConductorMotion.layout) {
                                    model.equalizeSplits()
                                }
                            }
                        )
                        .frame(width: divider)
                        .zIndex(2)
                        SplitNodeView(node: second, model: model, path: path + [.second])
                            .frame(width: available - firstWidth)
                            .clipped()
                    }
                }
                .clipped()
                .environment(\.conductorSplitResizeActive, isDragging)
                .transaction { transaction in
                    if isDragging {
                        transaction.disablesAnimations = true
                        transaction.animation = nil
                    }
                }
            } else {
                let available = max(1, size.height - divider)
                let activeFraction = dragPreviewFraction ?? fraction
                let firstMinimum = first.minimumLength(along: .vertical, divider: divider)
                let secondMinimum = second.minimumLength(along: .vertical, divider: divider)
                let firstHeight = splitLength(
                    fraction: activeFraction,
                    available: available,
                    firstMinimum: firstMinimum,
                    secondMinimum: secondMinimum
                )
                ZStack(alignment: .topLeading) {
                    VStack(spacing: 0) {
                        SplitNodeView(node: first, model: model, path: path + [.first])
                            .frame(height: firstHeight)
                            .clipped()
                        SplitDivider(
                            axis: axis,
                            active: dragStartFraction != nil,
                            showsIndicator: true,
                            onDragStarted: {
                                beginSplitDrag()
                            },
                            onDragChanged: { delta in
                                let base = dragStartFraction ?? fraction
                                setSplitFractionPreview(base + delta / max(1, available))
                            },
                            onDragEnded: {
                                finishSplitDrag()
                            },
                            onDoubleClick: {
                                ConductorMotion.perform(ConductorMotion.layout) {
                                    model.equalizeSplits()
                                }
                            }
                        )
                        .frame(height: divider)
                        .zIndex(2)
                        SplitNodeView(node: second, model: model, path: path + [.second])
                            .frame(height: available - firstHeight)
                            .clipped()
                    }
                }
                .clipped()
                .environment(\.conductorSplitResizeActive, isDragging)
                .transaction { transaction in
                    if isDragging {
                        transaction.disablesAnimations = true
                        transaction.animation = nil
                    }
                }
            }
        }
    }

    private func beginSplitDrag() {
        guard dragStartFraction == nil else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        transaction.animation = nil
        withTransaction(transaction) {
            dragStartFraction = fraction
            dragPreviewFraction = fraction
        }
    }

    private func setSplitFractionPreview(_ fraction: Double) {
        let nextFraction = clampedSplitFraction(fraction)
        if let dragPreviewFraction,
           abs(dragPreviewFraction - nextFraction) < 0.0001 {
            return
        }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        transaction.animation = nil
        withTransaction(transaction) {
            dragPreviewFraction = nextFraction
        }
    }

    private func finishSplitDrag() {
        let finalFraction = dragPreviewFraction
        if let finalFraction,
           abs(finalFraction - fraction) >= 0.0008 {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            transaction.animation = nil
            withTransaction(transaction) {
                model.setSplitFraction(path: path, fraction: finalFraction)
            }
        }

        var transaction = Transaction()
        transaction.disablesAnimations = true
        transaction.animation = nil
        withTransaction(transaction) {
            dragStartFraction = nil
        }
        DispatchQueue.main.async {
            var clearTransaction = Transaction()
            clearTransaction.disablesAnimations = true
            clearTransaction.animation = nil
            withTransaction(clearTransaction) {
                dragPreviewFraction = nil
            }
        }
    }

    private func clampedSplitFraction(_ fraction: Double) -> Double {
        min(0.85, max(0.15, fraction))
    }

    private func splitLength(
        fraction: Double,
        available: CGFloat,
        firstMinimum: CGFloat,
        secondMinimum: CGFloat
    ) -> CGFloat {
        let minimumSum = firstMinimum + secondMinimum
        if minimumSum >= available {
            let firstShare = firstMinimum / max(1, minimumSum)
            return pixelAligned(max(0, min(available, available * firstShare)))
        }
        let rawLength = min(
            max(firstMinimum, available * clampedSplitFraction(fraction)),
            available - secondMinimum
        )
        return pixelAligned(rawLength)
    }

    private func pixelAligned(_ value: CGFloat) -> CGFloat {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        return (value * scale).rounded(.toNearestOrAwayFromZero) / scale
    }
}

private extension SplitNode {
    static let desiredLeafMinimumWidth: CGFloat = 92
    static let desiredLeafMinimumHeight: CGFloat = 72

    func minimumLength(along axis: SplitAxis, divider: CGFloat) -> CGFloat {
        switch self {
        case .leaf:
            return axis == .horizontal ? Self.desiredLeafMinimumWidth : Self.desiredLeafMinimumHeight
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

private struct SplitDivider: View {
    let axis: SplitAxis
    let active: Bool
    var showsIndicator = true
    let onDragStarted: () -> Void
    let onDragChanged: (CGFloat) -> Void
    let onDragEnded: () -> Void
    let onDoubleClick: () -> Void
    @State private var hovering = false
    @Environment(\.conductorTheme) private var theme

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.clear)
            if showsIndicator {
                Rectangle()
                    .fill(resizeRailFill)
                    .frame(
                        width: axis == .horizontal ? 8 : nil,
                        height: axis == .vertical ? 8 : nil
                    )

                Rectangle()
                    .fill(resizeRailLine)
                    .frame(
                        width: axis == .horizontal ? (active || hovering ? 2 : 1) : nil,
                        height: axis == .vertical ? (active || hovering ? 2 : 1) : nil
                    )
            }
        }
            .contentShape(Rectangle())
            .overlay {
                SplitDividerTrackingView(
                    axis: axis,
                    onHoverChanged: { hovering = $0 },
                    onDragStarted: onDragStarted,
                    onDragChanged: onDragChanged,
                    onDragEnded: onDragEnded,
                    onDoubleClick: onDoubleClick
                )
            }
            .transaction { transaction in
                if active {
                    transaction.disablesAnimations = true
                    transaction.animation = nil
                }
            }
            .animation(active ? nil : ConductorMotion.micro, value: active)
            .animation(active ? nil : ConductorMotion.hover, value: hovering)
            .help("拖拽调整分屏")
    }

    private var resizeRailFill: Color {
        if active {
            return theme.shellControlFill.opacity(theme.usesDarkChrome ? 0.72 : 0.92)
        }
        if hovering {
            return theme.shellHoverFill.opacity(theme.usesDarkChrome ? 0.62 : 0.88)
        }
        return Color.clear
    }

    private var resizeRailLine: Color {
        if active || hovering {
            return theme.shellChromeTextMuted.opacity(theme.usesDarkChrome ? 0.82 : 0.72)
        }
        return theme.terminalOuterStroke.opacity(0.58)
    }
}

private struct SplitDragGuide: View {
    let axis: SplitAxis
    @Environment(\.conductorTheme) private var theme

    var body: some View {
        ZStack {
            Rectangle()
                .fill(theme.shellControlFill.opacity(theme.usesDarkChrome ? 0.76 : 0.92))
            Rectangle()
                .fill(theme.shellChromeTextMuted.opacity(theme.usesDarkChrome ? 0.88 : 0.76))
                .frame(
                    width: axis == .horizontal ? 2 : nil,
                    height: axis == .vertical ? 2 : nil
                )
        }
        .transaction { transaction in
            transaction.disablesAnimations = true
            transaction.animation = nil
        }
    }
}

private struct SplitDividerTrackingView: NSViewRepresentable {
    let axis: SplitAxis
    let onHoverChanged: (Bool) -> Void
    let onDragStarted: () -> Void
    let onDragChanged: (CGFloat) -> Void
    let onDragEnded: () -> Void
    let onDoubleClick: () -> Void

    func makeNSView(context: Context) -> SplitDividerTrackingNSView {
        let view = SplitDividerTrackingNSView()
        view.axis = axis
        view.onHoverChanged = onHoverChanged
        view.onDragStarted = onDragStarted
        view.onDragChanged = onDragChanged
        view.onDragEnded = onDragEnded
        view.onDoubleClick = onDoubleClick
        return view
    }

    func updateNSView(_ view: SplitDividerTrackingNSView, context: Context) {
        view.axis = axis
        view.onHoverChanged = onHoverChanged
        view.onDragStarted = onDragStarted
        view.onDragChanged = onDragChanged
        view.onDragEnded = onDragEnded
        view.onDoubleClick = onDoubleClick
        view.needsDisplay = true
    }
}

private final class SplitDividerTrackingNSView: NSView {
    var axis: SplitAxis = .horizontal {
        didSet {
            discardCursorRects()
        }
    }
    var onHoverChanged: (Bool) -> Void = { _ in }
    var onDragStarted: () -> Void = {}
    var onDragChanged: (CGFloat) -> Void = { _ in }
    var onDragEnded: () -> Void = {}
    var onDoubleClick: () -> Void = {}

    private var trackingAreaToken: NSTrackingArea?
    private var dragStartWindowLocation: NSPoint?
    private var isDragging = false

    override var acceptsFirstResponder: Bool { true }

    override func updateTrackingAreas() {
        if let trackingAreaToken {
            removeTrackingArea(trackingAreaToken)
        }
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        trackingAreaToken = trackingArea
        super.updateTrackingAreas()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: cursor)
    }

    override func mouseEntered(with event: NSEvent) {
        cursor.set()
        onHoverChanged(true)
    }

    override func mouseExited(with event: NSEvent) {
        guard !isDragging else { return }
        onHoverChanged(false)
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            onDoubleClick()
            return
        }
        window?.makeFirstResponder(self)
        cursor.set()
        isDragging = true
        dragStartWindowLocation = event.locationInWindow
        onHoverChanged(true)
        onDragStarted()
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging, let dragStartWindowLocation else { return }
        cursor.set()
        let location = event.locationInWindow
        let delta: CGFloat
        switch axis {
        case .horizontal:
            delta = location.x - dragStartWindowLocation.x
        case .vertical:
            delta = dragStartWindowLocation.y - location.y
        }
        onDragChanged(delta)
    }

    override func mouseUp(with event: NSEvent) {
        guard isDragging else { return }
        isDragging = false
        dragStartWindowLocation = nil
        onDragEnded()
        let localLocation = convert(event.locationInWindow, from: nil)
        onHoverChanged(bounds.contains(localLocation))
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            isDragging = false
            dragStartWindowLocation = nil
            onHoverChanged(false)
        }
    }

    private var cursor: NSCursor {
        axis == .horizontal ? .resizeLeftRight : .resizeUpDown
    }
}

private struct TerminalPaneView: View {
    let pane: PaneState
    @ObservedObject var model: ConductorWindowModel
    @State private var highlightedDropTabID: TerminalID?
    @State private var detachDropTarget: TerminalDetachTarget?
    @State private var flashVisible = false
    @Environment(\.conductorSplitResizeActive) private var splitResizeActive

    private var isFocused: Bool {
        model.workspace.focusedPaneID == pane.id
    }

    private var terminalAcceptsInputFocus: Bool {
        isFocused &&
            !model.commandPaletteVisible &&
            !model.settingsPanelVisible &&
            !model.workspaceOverviewVisible &&
            !model.terminalSearchVisible
    }

    private var unreadCount: Int {
        model.notifications.snapshot.unreadCount(for: pane.id)
    }

    private var paneBorderColor: Color {
        if unreadCount > 0 {
            return model.theme.accent.opacity(0.72)
        }
        return Color.clear
    }

    private var paneBorderWidth: CGFloat {
        if unreadCount > 0 {
            return 1.5
        }
        return 0
    }

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            selectedTerminal
        }
        .background(model.theme.terminalBackground)
        .overlay {
            TerminalPaneBorderOverlay(
                color: paneBorderColor,
                lineWidth: paneBorderWidth
            )
            .allowsHitTesting(false)
        }
        .overlay {
            TerminalPaneFlashOverlay(
                color: model.theme.accent,
                visible: flashVisible
            )
            .allowsHitTesting(false)
        }
        .clipped()
        .onChange(of: model.paneFlashTokens[pane.id] ?? 0) { _, token in
            guard token > 0 else { return }
            triggerFocusFlash()
        }
    }

    private var tabBar: some View {
        HStack(spacing: 4) {
            StableTerminalTabStrip(
                pane: pane,
                model: model,
                paneFocused: isFocused,
                highlightedDropTabID: $highlightedDropTabID
            )
            .frame(minWidth: 64, maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)

            PaneBarButton(
                systemImage: "xmark",
                title: L("关闭", "Close"),
                showsTitle: false,
                disabled: !model.workspace.canClosePane(pane.id),
                help: L("关闭这个分屏 Cmd-Shift-W", "Close this pane Cmd-Shift-W")
            ) {
                ConductorMotion.perform(ConductorMotion.layout) {
                    model.closePane(pane.id)
                }
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, 4)
        .frame(height: model.appearance.density.paneTabRailHeight)
        .background {
            ZStack(alignment: .bottom) {
                model.theme.terminalBackground
                model.theme.terminalChrome.opacity(isFocused ? 0.24 : 0.16)
                LinearGradient(
                    colors: [
                        Color.white.opacity(isFocused ? 0.026 : 0.014),
                        Color.clear
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
        .overlay(alignment: .bottom) {
            LinearGradient(
                colors: [
                    Color.clear,
                    model.theme.terminalOuterStroke.opacity(isFocused ? 0.48 : 0.32),
                    Color.clear
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
                .frame(height: 1)
        }
        .animation(splitResizeActive ? nil : ConductorMotion.micro, value: isFocused)
    }

    @ViewBuilder
    private var selectedTerminal: some View {
        if let selected = pane.selectedTab,
           model.workspace.panes[pane.id]?.selectedTabID == selected.id {
            GeometryReader { proxy in
                ZStack {
                    TerminalSurfaceRepresentable(
                        surface: model.surface(for: selected),
                        theme: model.theme,
                        isFocused: terminalAcceptsInputFocus,
                        suspendsGeometrySync: false
                    )
                    .background(model.theme.terminalBackground)
                    .transaction { transaction in
                        transaction.disablesAnimations = true
                        transaction.animation = nil
                    }
                    .onTapGesture {
                        ConductorMotion.perform(ConductorMotion.selection) {
                            model.focusPane(pane.id)
                        }
                    }

                    if let detachDropTarget {
                        TerminalDetachDropOverlay(target: detachDropTarget)
                            .allowsHitTesting(false)
                            .transition(.opacity)
                    }
                }
                .contentShape(Rectangle())
                .clipped()
                .onDrop(
                    of: [UTType.text],
                    delegate: TerminalDetachDropDelegate(
                        paneID: pane.id,
                        size: proxy.size,
                        target: $detachDropTarget,
                        model: model
                    )
                )
            }
        }
    }

    private func triggerFocusFlash() {
        withAnimation(ConductorMotion.emphasized) {
            flashVisible = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            withAnimation(ConductorMotion.standard) {
                flashVisible = false
            }
        }
    }
}

private enum TerminalDetachTarget: Equatable {
    case center
    case left
    case right
    case up
    case down

    var direction: SplitDirection {
        switch self {
        case .center:
            return .right
        case .left:
            return .left
        case .right:
            return .right
        case .up:
            return .up
        case .down:
            return .down
        }
    }

    var alignment: Alignment {
        switch self {
        case .center:
            return .center
        case .left:
            return .leading
        case .right:
            return .trailing
        case .up:
            return .top
        case .down:
            return .bottom
        }
    }

    var isHorizontalSplit: Bool {
        switch self {
        case .center:
            return false
        case .left, .right:
            return true
        case .up, .down:
            return false
        }
    }
}

private struct TerminalDetachDropOverlay: View {
    let target: TerminalDetachTarget
    @Environment(\.conductorTheme) private var theme

    var body: some View {
        GeometryReader { proxy in
            if target == .center {
                Rectangle()
                    .fill(theme.accent.opacity(0.10))
                    .overlay {
                        Rectangle()
                            .stroke(theme.accent.opacity(0.62), lineWidth: 1)
                    }
            } else {
                ZStack(alignment: target.alignment) {
                    Color.clear
                    Rectangle()
                        .fill(theme.accent.opacity(0.12))
                        .overlay {
                            Rectangle()
                                .stroke(theme.accent.opacity(0.72), lineWidth: 1)
                        }
                        .frame(
                            width: target.isHorizontalSplit ? max(0, proxy.size.width / 2) : nil,
                            height: target.isHorizontalSplit ? nil : max(0, proxy.size.height / 2)
                        )
                }
            }
        }
    }
}

private struct TerminalPaneBorderOverlay: View {
    let color: Color
    let lineWidth: CGFloat

    var body: some View {
        GeometryReader { proxy in
            let width = max(lineWidth, 0)
            let size = proxy.size
            if width > 0 {
                Rectangle()
                    .stroke(color, lineWidth: width)
                    .frame(width: max(0, size.width - width), height: max(0, size.height - width))
                    .position(x: size.width / 2, y: size.height / 2)
            }
        }
    }
}

private struct TerminalPaneFlashOverlay: View {
    let color: Color
    let visible: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .stroke(color.opacity(visible ? 0.86 : 0), lineWidth: 2)
            .shadow(color: color.opacity(visible ? 0.46 : 0), radius: visible ? 8 : 0)
            .padding(1)
    }
}

private struct StableTerminalTabStrip: View {
    let pane: PaneState
    @ObservedObject var model: ConductorWindowModel
    let paneFocused: Bool
    @Binding var highlightedDropTabID: TerminalID?
    @Namespace private var selectionNamespace

    private let tabSpacing: CGFloat = 4
    private let tabEdgePadding: CGFloat = 0

    private var tabIDs: [TerminalID] {
        pane.tabs.map(\.id)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: tabSpacing) {
                    ForEach(pane.tabs) { tab in
                        tabView(for: tab)
                            .transition(.identity)
                    }
                }
                .padding(.horizontal, tabEdgePadding)
            }
            .onDrop(
                of: [UTType.text],
                delegate: TerminalTabDropDelegate(
                    targetTabID: nil,
                    paneID: pane.id,
                    highlightedTabID: $highlightedDropTabID,
                    model: model
                )
            )
            .onAppear {
                scrollToSelectedTab(proxy)
            }
            .onChange(of: pane.selectedTabID) {
                scrollToSelectedTab(proxy)
            }
            .onChange(of: tabIDs) {
                scrollToSelectedTab(proxy)
            }
        }
        .frame(height: model.appearance.density.paneTabHeight)
        .clipped()
        .mask(ConductorHorizontalFadeMask())
        .transaction { transaction in
            transaction.disablesAnimations = true
            transaction.animation = nil
        }
    }

    private func scrollToSelectedTab(_ proxy: ScrollViewProxy) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            proxy.scrollTo(pane.selectedTabID, anchor: .center)
        }
    }

    private func tabView(for tab: TerminalTabState) -> some View {
        TerminalTabButton(
            tab: tab,
            isSelected: tab.id == pane.selectedTabID,
            paneFocused: paneFocused,
            isDropTarget: highlightedDropTabID == tab.id,
            metadata: model.metadataByTerminalID[tab.id],
            unreadCount: model.notifications.snapshot.unreadCount(for: tab.id),
            selectionNamespace: selectionNamespace,
            model: model,
            paneID: pane.id
        )
        .frame(width: model.appearance.density.paneTabWidth)
        .id(tab.id)
        .onDrop(
            of: [UTType.text],
            delegate: TerminalTabDropDelegate(
                targetTabID: tab.id,
                paneID: pane.id,
                highlightedTabID: $highlightedDropTabID,
                model: model
            )
        )
    }
}

private let terminalTabDragPrefix = "terminal:"

private func terminalTabDragPayload(for tabID: TerminalID) -> NSString {
    "\(terminalTabDragPrefix)\(tabID.description)" as NSString
}

private func terminalID(fromDroppedText text: String) -> TerminalID? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    let rawID = trimmed.hasPrefix(terminalTabDragPrefix)
        ? String(trimmed.dropFirst(terminalTabDragPrefix.count))
        : trimmed
    guard let uuid = UUID(uuidString: rawID) else { return nil }
    return TerminalID(uuid)
}

private func stringFromDropItem(_ item: NSSecureCoding?) -> String? {
    if let data = item as? Data {
        return String(data: data, encoding: .utf8)
    }
    if let string = item as? String {
        return string
    }
    if let nsString = item as? NSString {
        return nsString as String
    }
    return nil
}

private struct TerminalDetachDropDelegate: DropDelegate {
    let paneID: PaneID
    let size: CGSize
    @Binding var target: TerminalDetachTarget?
    let model: ConductorWindowModel

    func dropEntered(info: DropInfo) {
        target = target(for: info.location)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        target = target(for: info.location)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        target = nil
    }

    func performDrop(info: DropInfo) -> Bool {
        let resolvedTarget = target(for: info.location)
        target = nil
        guard let item = info.itemProviders(for: [UTType.text]).first else { return false }
        item.loadItem(forTypeIdentifier: UTType.text.identifier, options: nil) { item, _ in
            guard let text = stringFromDropItem(item),
                  let draggedTabID = terminalID(fromDroppedText: text) else {
                return
            }

            Task { @MainActor in
                ConductorMotion.perform(ConductorMotion.layout) {
                    if resolvedTarget == .center {
                        guard model.workspace.paneID(containing: draggedTabID) != paneID else { return }
                        model.moveTabToEnd(draggedTabID, in: paneID)
                    } else {
                        model.moveTabToSplit(draggedTabID, targetPaneID: paneID, direction: resolvedTarget.direction)
                    }
                }
            }
        }
        return true
    }

    private func target(for location: CGPoint) -> TerminalDetachTarget {
        let width = max(1, size.width)
        let height = max(1, size.height)
        let horizontalEdge = max(80, width * 0.25)
        let verticalEdge = max(80, height * 0.25)
        if location.x < horizontalEdge {
            return .left
        }
        if location.x > width - horizontalEdge {
            return .right
        }
        if location.y < verticalEdge {
            return .up
        }
        if location.y > height - verticalEdge {
            return .down
        }
        return .center
    }
}

private struct TerminalTabDropDelegate: DropDelegate {
    let targetTabID: TerminalID?
    let paneID: PaneID
    @Binding var highlightedTabID: TerminalID?
    let model: ConductorWindowModel

    func dropEntered(info: DropInfo) {
        highlightedTabID = targetTabID
    }

    func dropExited(info: DropInfo) {
        if highlightedTabID == targetTabID {
            highlightedTabID = nil
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        highlightedTabID = nil
        guard let item = info.itemProviders(for: [UTType.text]).first else { return false }
        item.loadItem(forTypeIdentifier: UTType.text.identifier, options: nil) { item, _ in
            guard let text = stringFromDropItem(item),
                  let draggedTabID = terminalID(fromDroppedText: text) else {
                return
            }

            Task { @MainActor in
                ConductorMotion.perform(ConductorMotion.layout) {
                    if let targetTabID {
                        model.moveTab(draggedTabID, before: targetTabID, in: paneID)
                    } else {
                        model.moveTabToEnd(draggedTabID, in: paneID)
                    }
                }
            }
        }
        return true
    }
}

private struct PaneBarButton: View {
    let systemImage: String
    let title: String
    var showsTitle = true
    var disabled = false
    let help: String
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorTheme) private var theme

    var body: some View {
        Button {
            action()
        } label: {
            ViewThatFits(in: .horizontal) {
                if showsTitle {
                    HStack(spacing: 4) {
                        Image(systemName: systemImage)
                            .font(.conductorSystem(size: 9.5, weight: .semibold, scale: fontScale))
                        Text(title)
                            .font(.conductorSystem(size: 10, weight: .medium, scale: fontScale))
                            .lineLimit(1)
                    }
                }
                Image(systemName: systemImage)
                    .font(.conductorSystem(size: 10, weight: .semibold, scale: fontScale))
            }
            .foregroundStyle(hovering ? theme.shellChromeText.opacity(0.92) : theme.shellChromeTextMuted)
            .padding(.horizontal, showsTitle ? 5 : 4)
            .frame(height: 18)
            .frame(minWidth: showsTitle ? nil : 19)
            .background(hovering ? theme.shellHoverFill : (theme.usesDarkChrome ? Color.white.opacity(showsTitle ? 0.050 : 0.025) : theme.shellControlFill))
            .clipShape(RoundedRectangle(cornerRadius: ConductorTokens.Radius.terminalTab, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: ConductorTokens.Radius.terminalTab, style: .continuous)
                    .stroke(hovering ? theme.shellStroke.opacity(0.72) : theme.shellStroke.opacity(0.42), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: ConductorTokens.Radius.terminalTab, style: .continuous))
        }
        .buttonStyle(ConductorPressButtonStyle())
        .disabled(disabled)
        .opacity(disabled ? 0.35 : 1)
        .animation(ConductorMotion.micro, value: disabled)
        .animation(ConductorMotion.hover, value: hovering)
        .onHover { value in
            ConductorMotion.perform(ConductorMotion.hover) {
                hovering = value
            }
        }
        .help(help)
    }
}

private struct TerminalTabButton: View {
    let tab: TerminalTabState
    let isSelected: Bool
    let paneFocused: Bool
    let isDropTarget: Bool
    let metadata: TerminalDisplayMetadata?
    let unreadCount: Int
    let selectionNamespace: Namespace.ID
    @ObservedObject var model: ConductorWindowModel
    let paneID: PaneID
    @State private var editingTitle = false
    @State private var titleDraft = ""
    @State private var hovering = false
    @State private var renameCancelled = false
    @FocusState private var titleFieldFocused: Bool
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorTheme) private var theme

    private var tabIndex: Int? {
        model.workspace.panes[paneID]?.tabs.firstIndex { $0.id == tab.id }
    }

    private var tabCount: Int {
        model.workspace.panes[paneID]?.tabs.count ?? 0
    }

    private var canMoveTargetTabToNextPane: Bool {
        guard tabIndex != nil,
              model.workspace.nextPaneID(after: paneID) != nil else {
            return false
        }
        return tabCount > 1 || model.workspace.panes.count > 1
    }

    private var canMoveTargetTabToNewSplit: Bool {
        tabIndex != nil && tabCount > 1 && model.workspace.canSplit()
    }

    private var tabFill: Color {
        hovering ? theme.shellHoverFill : (theme.usesDarkChrome ? theme.shellControlFill.opacity(0.18) : theme.shellControlFill)
    }

    private var selectedFill: Color {
        theme.shellSelectedFill.opacity(paneFocused ? (theme.usesDarkChrome ? 1.0 : 0.92) : 0.72)
    }

    private var tabStroke: Color {
        if isDropTarget {
            return theme.floatingSelectedStroke.opacity(0.95)
        }
        if isSelected {
            return theme.shellStroke.opacity(paneFocused ? 0.92 : 0.58)
        }
        return theme.shellStroke.opacity(hovering ? 0.54 : 0.32)
    }

    private var terminalDetailLabel: String? {
        guard let workingDirectory = metadata?.workingDirectory?.trimmingCharacters(in: .whitespacesAndNewlines),
              !workingDirectory.isEmpty else {
            return nil
        }
        let normalized = (workingDirectory as NSString).expandingTildeInPath
        let lastComponent = (normalized as NSString).lastPathComponent
        guard !lastComponent.isEmpty,
              lastComponent != "/",
              lastComponent != tab.title else {
            return nil
        }
        return lastComponent
    }

    private var terminalHelpText: String {
        var parts = [tab.title]
        if let terminalDetailLabel {
            parts.append(terminalDetailLabel)
        }
        if unreadCount > 0 || (metadata?.unreadCount ?? 0) > 0 {
            parts.append(L("未读", "Unread"))
        }
        if metadata?.readonly == true {
            parts.append(L("只读", "Read Only"))
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 3) {
            if editingTitle {
                Image(systemName: "terminal")
                    .font(.conductorSystem(size: 10, scale: fontScale))
                    .foregroundStyle(isSelected ? theme.shellChromeText : theme.shellChromeTextMuted)
                RenameTextField(
                    text: $titleDraft,
                    placeholder: L("标签名称", "Tab Name"),
                    font: .conductorMonospacedSystemFont(ofSize: 10.5, weight: isSelected ? .semibold : .medium, scale: fontScale),
                    textColor: NSColor(theme.shellChromeText),
                    onCommit: commitRename,
                    onCancel: cancelRename
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .onAppear {
                    renameCancelled = false
                }
            } else {
                HStack(spacing: 5) {
                    Image(systemName: "terminal")
                        .font(.conductorSystem(size: 10, scale: fontScale))
                        .foregroundStyle(isSelected ? theme.shellChromeText : theme.shellChromeTextMuted)
                    Text(tab.title)
                        .font(.conductorSystem(size: 10.5, weight: isSelected ? .semibold : .medium, scale: fontScale))
                        .foregroundStyle(isSelected ? theme.shellChromeText : theme.shellChromeTextMuted)
                        .lineLimit(1)
                        .layoutPriority(1)
                    if let terminalDetailLabel, isSelected {
                        Text("· \(terminalDetailLabel)")
                            .font(.conductorSystem(size: 9.5, weight: .medium, scale: fontScale))
                            .foregroundStyle(theme.shellChromeTextMuted.opacity(isSelected ? 0.92 : 0.78))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 2)
                    if unreadCount > 0 || (metadata?.unreadCount ?? 0) > 0 {
                        Circle()
                            .fill(theme.floatingEmphasis.opacity(0.72))
                            .frame(width: 6, height: 6)
                    } else if metadata?.progressKind != nil {
                        Circle()
                            .stroke(theme.floatingEmphasis.opacity(0.72), lineWidth: 1.25)
                            .frame(width: 7, height: 7)
                    } else if metadata?.readonly == true {
                        Image(systemName: "lock")
                            .font(.conductorSystem(size: 9, scale: fontScale))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .help(terminalHelpText)
            }

            if !editingTitle {
                Button {
                    ConductorMotion.perform(ConductorMotion.layout) {
                        model.closeTab(tab.id, in: paneID)
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.conductorSystem(size: 9, weight: .semibold, scale: fontScale))
                        .foregroundStyle(hovering || isSelected ? theme.shellChromeText.opacity(0.80) : theme.shellChromeTextMuted.opacity(0.72))
                        .frame(width: 13, height: 13)
                        .clipShape(Circle())
                }
                .buttonStyle(ConductorPressButtonStyle())
                .help(L("关闭标签", "Close Tab"))
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, 4)
        .frame(height: model.appearance.density.paneTabHeight)
        .frame(
            minWidth: 72,
            idealWidth: model.appearance.density.paneTabWidth,
            maxWidth: model.appearance.density.paneTabWidth
        )
        .background {
            let shape = RoundedRectangle(cornerRadius: ConductorTokens.Radius.terminalTab, style: .continuous)
            if isSelected {
                shape
                    .fill(selectedFill)
            } else {
                shape
                    .fill(tabFill)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: ConductorTokens.Radius.terminalTab, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ConductorTokens.Radius.terminalTab, style: .continuous)
                .stroke(tabStroke, lineWidth: isDropTarget || (isSelected && paneFocused) ? 1.35 : 1)
        }
        .animation(ConductorMotion.hover, value: hovering)
        .animation(ConductorMotion.micro, value: isDropTarget)
        .animation(ConductorMotion.selection, value: editingTitle)
        .animation(ConductorMotion.emphasized, value: unreadCount)
        .onHover { value in
            ConductorMotion.perform(ConductorMotion.hover) {
                hovering = value
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: ConductorTokens.Radius.terminalTab))
        .onTapGesture {
            model.selectTab(tab.id, in: paneID)
        }
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                guard !editingTitle else { return }
                beginRename()
            }
        )
        .onDrag {
            model.selectTab(tab.id, in: paneID)
            return NSItemProvider(object: terminalTabDragPayload(for: tab.id))
        }
        .contextMenu {
            Button(L("重命名标签...", "Rename Tab...")) {
                ConductorMotion.perform(ConductorMotion.selection) {
                    beginRename()
                }
            }
            if tab.userTitle != nil {
                Button(L("恢复终端标题", "Restore Terminal Title")) {
                    ConductorMotion.perform(ConductorMotion.selection) {
                        model.clearUserTerminalTitle(tab.id)
                    }
                }
            }
            Button(L("复制标签", "Duplicate Tab")) {
                ConductorMotion.perform(ConductorMotion.layout) {
                    model.duplicateTab(tab.id, in: paneID)
                }
            }
            Divider()
            Button(L("关闭标签", "Close Tab")) {
                ConductorMotion.perform(ConductorMotion.layout) {
                    model.closeTab(tab.id, in: paneID)
                }
            }
            Button(L("关闭其他标签", "Close Other Tabs")) {
                ConductorMotion.perform(ConductorMotion.layout) {
                    model.selectTab(tab.id, in: paneID)
                    model.closeOtherTabs(in: paneID)
                }
            }
            .disabled(!model.workspace.canCloseOtherTabs(in: paneID))
            Button(L("关闭右侧标签", "Close Tabs to the Right")) {
                ConductorMotion.perform(ConductorMotion.layout) {
                    model.selectTab(tab.id, in: paneID)
                    model.closeTabsToRight(in: paneID)
                }
            }
            .disabled(!model.workspace.canCloseTabsToRight(of: tab.id, in: paneID))
            Divider()
            Button(L("标签左移", "Move Tab Left")) {
                ConductorMotion.perform(ConductorMotion.layout) {
                    model.selectTab(tab.id, in: paneID)
                    model.moveSelectedTabLeft()
                }
            }
            .disabled(tabIndex == nil || tabIndex == 0)
            Button(L("标签右移", "Move Tab Right")) {
                ConductorMotion.perform(ConductorMotion.layout) {
                    model.selectTab(tab.id, in: paneID)
                    model.moveSelectedTabRight()
                }
            }
            .disabled(tabIndex == nil || tabIndex == tabCount - 1)
            Divider()
            Button(L("移动到下一个分屏", "Move to Next Pane")) {
                ConductorMotion.perform(ConductorMotion.layout) {
                    model.selectTab(tab.id, in: paneID)
                    model.moveSelectedTabToNextPane()
                }
            }
            .disabled(!canMoveTargetTabToNextPane)
            Button(L("移动到右侧新分屏", "Move to New Right Split")) {
                ConductorMotion.perform(ConductorMotion.layout) {
                    model.selectTab(tab.id, in: paneID)
                    model.moveSelectedTabToNewSplit(.right)
                }
            }
            .disabled(!canMoveTargetTabToNewSplit)
            Button(L("移动到下方新分屏", "Move to New Down Split")) {
                ConductorMotion.perform(ConductorMotion.layout) {
                    model.selectTab(tab.id, in: paneID)
                    model.moveSelectedTabToNewSplit(.down)
                }
            }
            .disabled(!canMoveTargetTabToNewSplit)
        }
    }

    private func beginRename() {
        titleDraft = tab.title
        renameCancelled = false
        editingTitle = true
        model.selectTab(tab.id, in: paneID)
    }

    private func commitRename() {
        ConductorMotion.perform(ConductorMotion.selection) {
            model.renameTerminal(tab.id, title: titleDraft)
            editingTitle = false
        }
    }

    private func cancelRename() {
        ConductorMotion.perform(ConductorMotion.selection) {
            editingTitle = false
        }
    }
}
