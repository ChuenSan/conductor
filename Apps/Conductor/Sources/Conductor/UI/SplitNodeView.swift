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
                TerminalPaneView(
                    pane: pane,
                    model: model,
                    snapshot: TerminalPaneChromeSnapshot(pane: pane, model: model)
                )
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
    let model: ConductorWindowModel

    var body: some View {
        AppKitSplitPairView(
            axis: axis,
            fraction: fraction,
            first: first,
            second: second,
            path: path,
            model: model,
            theme: model.theme,
            dividerThickness: ConductorTokens.Space.splitGutter
        )
        .transaction { transaction in
            transaction.disablesAnimations = true
            transaction.animation = nil
        }
    }
}

private struct AppKitSplitPairView: NSViewRepresentable {
    let axis: SplitAxis
    let fraction: Double
    let first: SplitNode
    let second: SplitNode
    let path: [SplitPathElement]
    let model: ConductorWindowModel
    let theme: TerminalTheme
    let dividerThickness: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    func makeNSView(context: Context) -> ConductorSplitView {
        let splitView = ConductorSplitView()
        splitView.delegate = context.coordinator
        splitView.isVertical = axis == .horizontal
        splitView.dividerStyle = .thin
        splitView.dividerThicknessOverride = dividerThickness
        splitView.onDividerDoubleClick = {
            ConductorMotion.perform(ConductorMotion.layout) {
                model.performCommand(.equalizeSplits)
            }
        }
        splitView.addArrangedSubview(context.coordinator.firstHostingView)
        splitView.addArrangedSubview(context.coordinator.secondHostingView)
        context.coordinator.attach(to: splitView)
        updateNSView(splitView, context: context)
        return splitView
    }

    func updateNSView(_ splitView: ConductorSplitView, context: Context) {
        context.coordinator.update(
            axis: axis,
            fraction: fraction,
            first: first,
            second: second,
            path: path,
            dividerThickness: dividerThickness,
            model: model
        )

        splitView.isVertical = axis == .horizontal
        splitView.dividerThicknessOverride = dividerThickness
        splitView.dividerFillColor = NSColor(theme.terminalBackground)
        splitView.dividerLineColor = NSColor(theme.terminalOuterStroke.opacity(theme.usesDarkChrome ? 0.52 : 0.42))
        splitView.activeDividerLineColor = NSColor(theme.shellChromeTextMuted.opacity(theme.usesDarkChrome ? 0.82 : 0.68))

        context.coordinator.refreshHostingRoots()

        context.coordinator.syncDividerPosition(in: splitView)
    }

    @MainActor
    final class Coordinator: NSObject, NSSplitViewDelegate {
        let firstHostingView = NSHostingView(rootView: AnyView(EmptyView()))
        let secondHostingView = NSHostingView(rootView: AnyView(EmptyView()))

        private var model: ConductorWindowModel
        private weak var splitView: ConductorSplitView?
        private var axis: SplitAxis = .horizontal
        private var fraction: Double = 0.5
        private var first: SplitNode = .leaf(PaneID())
        private var second: SplitNode = .leaf(PaneID())
        private var path: [SplitPathElement] = []
        private var dividerThickness: CGFloat = ConductorTokens.Space.splitGutter
        private var isSyncingProgrammatically = false
        private var pendingDragFraction: Double?
        private let mouseUpMonitorBox = EventMonitorBox()
        private var lastSyncedFraction: Double?
        private var hostingRootSignature: HostingRootSignature?

        fileprivate private(set) var isUserDragging = false

        init(model: ConductorWindowModel) {
            self.model = model
            super.init()
            firstHostingView.translatesAutoresizingMaskIntoConstraints = false
            secondHostingView.translatesAutoresizingMaskIntoConstraints = false
            firstHostingView.sizingOptions = [.minSize, .intrinsicContentSize]
            secondHostingView.sizingOptions = [.minSize, .intrinsicContentSize]
        }

        deinit {
            let monitorBox = mouseUpMonitorBox
            DispatchQueue.main.async {
                if let token = monitorBox.token {
                    NSEvent.removeMonitor(token)
                    monitorBox.token = nil
                }
            }
        }

        func attach(to splitView: ConductorSplitView) {
            self.splitView = splitView
        }

        func update(
            axis: SplitAxis,
            fraction: Double,
            first: SplitNode,
            second: SplitNode,
            path: [SplitPathElement],
            dividerThickness: CGFloat,
            model: ConductorWindowModel
        ) {
            self.axis = axis
            self.fraction = clampedSplitFraction(fraction)
            self.first = first
            self.second = second
            self.path = path
            self.dividerThickness = dividerThickness
            self.model = model
        }

        func refreshHostingRoots() {
            let signature = HostingRootSignature(
                model: ObjectIdentifier(model),
                first: first,
                second: second,
                path: path,
                isUserDragging: isUserDragging
            )
            guard signature != hostingRootSignature else { return }
            hostingRootSignature = signature
            firstHostingView.rootView = AnyView(
                SplitNodeView(node: first, model: model, path: path + [.first])
                    .environment(\.conductorSplitResizeActive, isUserDragging)
            )
            secondHostingView.rootView = AnyView(
                SplitNodeView(node: second, model: model, path: path + [.second])
                    .environment(\.conductorSplitResizeActive, isUserDragging)
            )
        }

        private struct HostingRootSignature: Equatable {
            let model: ObjectIdentifier
            let first: SplitNode
            let second: SplitNode
            let path: [SplitPathElement]
            let isUserDragging: Bool
        }

        func syncDividerPosition(in splitView: NSSplitView) {
            guard !isUserDragging,
                  splitView.arrangedSubviews.count >= 2,
                  let targetPosition = dividerPosition(for: fraction, in: splitView) else { return }

            let current = currentDividerPosition(in: splitView)
            if let current, abs(current - targetPosition) < 0.5,
               let lastSyncedFraction,
               abs(lastSyncedFraction - fraction) < 0.0008 {
                return
            }

            isSyncingProgrammatically = true
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            splitView.setPosition(targetPosition, ofDividerAt: 0)
            splitView.layoutSubtreeIfNeeded()
            CATransaction.commit()
            isSyncingProgrammatically = false
            lastSyncedFraction = fraction
        }

        func splitViewWillResizeSubviews(_ notification: Notification) {
            guard let splitView = notification.object as? ConductorSplitView else { return }
            guard !isSyncingProgrammatically else { return }
            guard isRealDividerDrag(in: splitView) else { return }
            beginUserDrag(in: splitView)
        }

        func splitViewDidResizeSubviews(_ notification: Notification) {
            guard let splitView = notification.object as? NSSplitView else { return }
            guard !isSyncingProgrammatically else { return }

            if isUserDragging {
                pendingDragFraction = currentFraction(in: splitView)
                return
            }

            DispatchQueue.main.async { [weak self, weak splitView] in
                guard let self, let splitView, !self.isUserDragging else { return }
                self.syncDividerPosition(in: splitView)
            }
        }

        func splitView(_ splitView: NSSplitView, canCollapseSubview subview: NSView) -> Bool {
            false
        }

        func splitView(
            _ splitView: NSSplitView,
            constrainMinCoordinate proposedMinimumPosition: CGFloat,
            ofSubviewAt dividerIndex: Int
        ) -> CGFloat {
            max(proposedMinimumPosition, firstMinimumLength())
        }

        func splitView(
            _ splitView: NSSplitView,
            constrainMaxCoordinate proposedMaximumPosition: CGFloat,
            ofSubviewAt dividerIndex: Int
        ) -> CGFloat {
            let available = splitAvailableLength(in: splitView)
            return min(proposedMaximumPosition, max(firstMinimumLength(), available - secondMinimumLength()))
        }

        func splitView(
            _ splitView: NSSplitView,
            constrainSplitPosition proposedPosition: CGFloat,
            ofSubviewAt dividerIndex: Int
        ) -> CGFloat {
            let available = splitAvailableLength(in: splitView)
            guard available > 1 else { return proposedPosition }
            return min(max(proposedPosition, firstMinimumLength()), available - secondMinimumLength())
        }

        func splitView(
            _ splitView: NSSplitView,
            effectiveRect proposedEffectiveRect: NSRect,
            forDrawnRect drawnRect: NSRect,
            ofDividerAt dividerIndex: Int
        ) -> NSRect {
            proposedEffectiveRect.union(drawnRect.insetBy(dx: -5, dy: -5))
        }

        func splitView(_ splitView: NSSplitView, additionalEffectiveRectOfDividerAt dividerIndex: Int) -> NSRect {
            guard splitView.arrangedSubviews.count >= 2 else { return .zero }
            let firstFrame = splitView.arrangedSubviews[0].frame
            let secondFrame = splitView.arrangedSubviews[1].frame
            let thickness = splitView.dividerThickness
            if splitView.isVertical {
                guard firstFrame.width > 1, secondFrame.width > 1 else { return .zero }
                return NSRect(x: firstFrame.maxX, y: 0, width: thickness, height: splitView.bounds.height)
                    .insetBy(dx: -5, dy: -5)
            }
            guard firstFrame.height > 1, secondFrame.height > 1 else { return .zero }
            return NSRect(x: 0, y: firstFrame.maxY, width: splitView.bounds.width, height: thickness)
                .insetBy(dx: -5, dy: -5)
        }

        private func beginUserDrag(in splitView: ConductorSplitView) {
            guard !isUserDragging else { return }
            isUserDragging = true
            pendingDragFraction = currentFraction(in: splitView) ?? fraction
            splitView.isDividerActive = true
            refreshHostingRoots()
            installMouseUpMonitor()
        }

        private func finishUserDrag() {
            guard isUserDragging else { return }
            isUserDragging = false
            splitView?.isDividerActive = false
            refreshHostingRoots()
            if let token = mouseUpMonitorBox.token {
                NSEvent.removeMonitor(token)
                mouseUpMonitorBox.token = nil
            }

            guard let pendingDragFraction,
                  abs(pendingDragFraction - fraction) >= 0.0008 else {
                self.pendingDragFraction = nil
                return
            }
            let committedFraction = pendingDragFraction
            self.pendingDragFraction = nil
            lastSyncedFraction = committedFraction
            ConductorMotion.withoutAnimation {
                model.setSplitFraction(path: path, fraction: committedFraction)
            }
        }

        private func installMouseUpMonitor() {
            guard mouseUpMonitorBox.token == nil else { return }
            mouseUpMonitorBox.token = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] event in
                self?.finishUserDrag()
                return event
            }
        }

        private func isRealDividerDrag(in splitView: NSSplitView) -> Bool {
            guard let event = NSApp.currentEvent,
                  event.window === splitView.window,
                  NSEvent.pressedMouseButtons & 1 == 1,
                  event.type == .leftMouseDragged || event.type == .leftMouseDown else {
                return false
            }
            let location = splitView.convert(event.locationInWindow, from: nil)
            return dividerHitRect(in: splitView).contains(location)
        }

        private func dividerHitRect(in splitView: NSSplitView) -> NSRect {
            guard splitView.arrangedSubviews.count >= 2 else { return .zero }
            let firstFrame = splitView.arrangedSubviews[0].frame
            let thickness = splitView.dividerThickness
            if splitView.isVertical {
                return NSRect(x: firstFrame.maxX, y: 0, width: thickness, height: splitView.bounds.height)
                    .insetBy(dx: -5, dy: -5)
            }
            return NSRect(x: 0, y: firstFrame.maxY, width: splitView.bounds.width, height: thickness)
                .insetBy(dx: -5, dy: -5)
        }

        private func dividerPosition(for fraction: Double, in splitView: NSSplitView) -> CGFloat? {
            let available = splitAvailableLength(in: splitView)
            guard available > 1 else { return nil }
            let minimumSum = firstMinimumLength() + secondMinimumLength()
            let rawPosition: CGFloat
            if minimumSum >= available {
                rawPosition = available * firstMinimumLength() / max(1, minimumSum)
            } else {
                rawPosition = min(
                    max(firstMinimumLength(), available * clampedSplitFraction(fraction)),
                    available - secondMinimumLength()
                )
            }
            return pixelAligned(rawPosition, in: splitView)
        }

        private func currentDividerPosition(in splitView: NSSplitView) -> CGFloat? {
            guard splitView.arrangedSubviews.count >= 2 else { return nil }
            let firstFrame = splitView.arrangedSubviews[0].frame
            let position = splitView.isVertical ? firstFrame.width : firstFrame.height
            return position > 0 ? pixelAligned(position, in: splitView) : nil
        }

        private func currentFraction(in splitView: NSSplitView) -> Double? {
            guard let position = currentDividerPosition(in: splitView) else { return nil }
            let available = splitAvailableLength(in: splitView)
            guard available > 1 else { return nil }
            return clampedSplitFraction(Double(position / available))
        }

        private func splitAvailableLength(in splitView: NSSplitView) -> CGFloat {
            let total = splitView.isVertical ? splitView.bounds.width : splitView.bounds.height
            return max(1, total - splitView.dividerThickness)
        }

        private func firstMinimumLength() -> CGFloat {
            first.minimumLength(along: axis, divider: dividerThickness)
        }

        private func secondMinimumLength() -> CGFloat {
            second.minimumLength(along: axis, divider: dividerThickness)
        }

        private func clampedSplitFraction(_ fraction: Double) -> Double {
            SplitNode.clampedFraction(fraction)
        }

        private func pixelAligned(_ value: CGFloat, in view: NSView) -> CGFloat {
            let scale = view.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
            return (value * scale).rounded(.toNearestOrAwayFromZero) / scale
        }
    }
}

private final class EventMonitorBox: @unchecked Sendable {
    var token: Any?
}

private final class ConductorSplitView: NSSplitView {
    var dividerThicknessOverride: CGFloat = ConductorTokens.Space.splitGutter {
        didSet {
            guard oldValue != dividerThicknessOverride else { return }
            needsDisplay = true
        }
    }
    var dividerFillColor: NSColor = .clear {
        didSet {
            guard oldValue != dividerFillColor else { return }
            needsDisplay = true
        }
    }
    var dividerLineColor: NSColor = .separatorColor {
        didSet {
            guard oldValue != dividerLineColor else { return }
            needsDisplay = true
        }
    }
    var activeDividerLineColor: NSColor = .controlAccentColor {
        didSet {
            guard oldValue != activeDividerLineColor else { return }
            needsDisplay = true
        }
    }
    var isDividerActive = false {
        didSet {
            guard oldValue != isDividerActive else { return }
            needsDisplay = true
        }
    }
    var onDividerDoubleClick: (() -> Void)?

    override var dividerThickness: CGFloat {
        dividerThicknessOverride
    }

    override var isOpaque: Bool {
        false
    }

    override var mouseDownCanMoveWindow: Bool {
        false
    }

    override func drawDivider(in rect: NSRect) {
        dividerFillColor.setFill()
        rect.fill()

        let lineThickness: CGFloat = isDividerActive ? 2 : 1
        let lineRect: NSRect
        if isVertical {
            lineRect = NSRect(
                x: rect.midX - lineThickness / 2,
                y: rect.minY,
                width: lineThickness,
                height: rect.height
            )
        } else {
            lineRect = NSRect(
                x: rect.minX,
                y: rect.midY - lineThickness / 2,
                width: rect.width,
                height: lineThickness
            )
        }
        (isDividerActive ? activeDividerLineColor : dividerLineColor).setFill()
        lineRect.fill()
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2,
           dividerHitRect().contains(convert(event.locationInWindow, from: nil)) {
            onDividerDoubleClick?()
            return
        }
        super.mouseDown(with: event)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            isDividerActive = false
        }
    }

    private func dividerHitRect() -> NSRect {
        guard arrangedSubviews.count >= 2 else { return .zero }
        let firstFrame = arrangedSubviews[0].frame
        if isVertical {
            return NSRect(x: firstFrame.maxX, y: 0, width: dividerThickness, height: bounds.height)
                .insetBy(dx: -5, dy: -5)
        }
        return NSRect(x: 0, y: firstFrame.maxY, width: bounds.width, height: dividerThickness)
            .insetBy(dx: -5, dy: -5)
    }
}

private extension SplitNode {
    static let desiredLeafMinimumWidth: CGFloat = 24
    static let desiredLeafMinimumHeight: CGFloat = 24

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
            .macNativeTooltip("拖拽调整分屏")
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
    }
}

private final class SplitDividerTrackingNSView: NSView {
    var axis: SplitAxis = .horizontal {
        didSet {
            guard oldValue != axis else { return }
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
        applyResizeCursor()
        onHoverChanged(true)
    }

    override func mouseExited(with event: NSEvent) {
        guard !isDragging else { return }
        onHoverChanged(false)
        restoreDefaultCursor()
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            onDoubleClick()
            return
        }
        window?.makeFirstResponder(self)
        applyResizeCursor()
        isDragging = true
        dragStartWindowLocation = event.locationInWindow
        onHoverChanged(true)
        onDragStarted()
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging, let dragStartWindowLocation else { return }
        applyResizeCursor()
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
        let hoveringAfterDrag = bounds.contains(localLocation)
        onHoverChanged(hoveringAfterDrag)
        if hoveringAfterDrag {
            applyResizeCursor()
        } else {
            restoreDefaultCursor()
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            isDragging = false
            dragStartWindowLocation = nil
            onHoverChanged(false)
            restoreDefaultCursor()
        }
    }

    private func applyResizeCursor() {
        cursor.set()
    }

    private func restoreDefaultCursor() {
        NSCursor.arrow.set()
    }

    private var cursor: NSCursor {
        axis == .horizontal ? .resizeLeftRight : .resizeUpDown
    }
}

private struct TerminalPaneChromeSnapshot: Equatable {
    let paneID: PaneID
    let selectedTabID: TerminalID
    let paneFocused: Bool
    let terminalAcceptsInputFocus: Bool
    let paneDropTarget: TerminalTabDropTarget?
    let flashToken: UInt64
    let canClosePane: Bool
    let theme: TerminalTheme
    let appearance: AppearancePreferences
    let tabs: [TerminalTabDisplayModel]
    let tabIDs: [TerminalID]

    @MainActor
    init(pane: PaneState, model: ConductorWindowModel) {
        let workspace = model.workspace
        let paneFocused = workspace.focusedPaneID == pane.id
        let hasNextPane = workspace.nextPaneID(after: pane.id) != nil
        let workspacePaneCount = workspace.panes.count
        let workspaceCanSplit = workspace.canSplit()
        let metadataByTerminalID = model.metadataByTerminalID
        let notificationSnapshot = model.notifications.snapshot

        self.paneID = pane.id
        self.selectedTabID = pane.selectedTabID
        self.paneFocused = paneFocused
        self.terminalAcceptsInputFocus = paneFocused &&
            !model.commandPaletteVisible &&
            !model.settingsPanelVisible &&
            !model.workspaceOverviewVisible &&
            !model.terminalSearchVisible
        self.paneDropTarget = model.terminalTabDropTargetByPaneID[pane.id]
        self.flashToken = model.paneFlashTokens[pane.id] ?? 0
        self.canClosePane = workspace.canClosePane(pane.id)
        self.theme = model.theme
        self.appearance = model.appearance
        self.tabs = pane.tabs.enumerated().map { index, tab in
            TerminalTabDisplayModel(
                tab: tab,
                metadata: metadataByTerminalID[tab.id],
                unreadCount: notificationSnapshot.unreadCount(for: tab.id),
                isDragging: model.isTerminalTabDragging(tab.id),
                tabIndex: index,
                tabCount: pane.tabs.count,
                hasNextPane: hasNextPane,
                workspacePaneCount: workspacePaneCount,
                workspaceCanSplit: workspaceCanSplit,
                canCloseOtherTabs: workspace.canCloseOtherTabs(in: pane.id),
                canCloseTabsToRight: workspace.canCloseTabsToRight(of: tab.id, in: pane.id)
            )
        }
        self.tabIDs = pane.tabs.map(\.id)
    }

    var terminalBackground: Color {
        theme.terminalBackground.opacity(appearance.terminalRenderer.backgroundOpacity)
    }
}

private struct TerminalTabDisplayModel: Identifiable, Equatable {
    var id: TerminalID { tab.id }
    let tab: TerminalTabState
    let metadata: TerminalDisplayMetadata?
    let unreadCount: Int
    let isDragging: Bool
    let tabIndex: Int
    let tabCount: Int
    let hasNextPane: Bool
    let workspacePaneCount: Int
    let workspaceCanSplit: Bool
    let canCloseOtherTabs: Bool
    let canCloseTabsToRight: Bool
}

private struct TerminalPaneView: View {
    let pane: PaneState
    let model: ConductorWindowModel
    let snapshot: TerminalPaneChromeSnapshot
    @State private var highlightedDropTabID: TerminalID?
    @State private var isFileDropTargeted = false
    @State private var flashVisible = false
    @Environment(\.conductorSplitResizeActive) private var splitResizeActive
    @Environment(\.conductorFilePanelLayoutActive) private var filePanelLayoutActive

    private var isFocused: Bool {
        snapshot.paneFocused
    }

    private var terminalAcceptsInputFocus: Bool {
        snapshot.terminalAcceptsInputFocus
    }

    private var paneDropTarget: TerminalTabDropTarget? {
        snapshot.paneDropTarget
    }

    private var terminalBackground: Color {
        snapshot.terminalBackground
    }

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            selectedTerminal
        }
        .background(terminalBackground)
        .overlay {
            ZStack {
                if let paneDropTarget {
                    TerminalDetachDropOverlay(target: paneDropTarget)
                        .allowsHitTesting(false)
                        .transition(ConductorMotion.dropPreviewTransition)
                }

                TerminalPaneFlashOverlay(
                    color: snapshot.theme.accent,
                    visible: flashVisible
                )
                .allowsHitTesting(false)
            }
        }
        .clipped()
        .animation(shellAnimation(ConductorMotion.dragPreview), value: paneDropTarget)
        .onChange(of: snapshot.flashToken) { _, token in
            guard token > 0 else { return }
            triggerFocusFlash()
        }
    }

    private var tabBar: some View {
        HStack(spacing: 4) {
            StableTerminalTabStrip(
                pane: pane,
                snapshot: snapshot,
                model: model,
                highlightedDropTabID: $highlightedDropTabID
            )
            .frame(minWidth: 64, maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)

            PaneBarButton(
                systemImage: "xmark",
                title: L("关闭", "Close"),
                showsTitle: false,
                disabled: !snapshot.canClosePane,
                help: L("关闭这个分屏 Cmd-Shift-W", "Close this pane Cmd-Shift-W")
            ) {
                ConductorMotion.perform(ConductorMotion.layout) {
                    model.closePane(pane.id)
                }
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .frame(height: snapshot.appearance.density.paneTabRailHeight)
        .background {
            ZStack(alignment: .bottom) {
                terminalBackground
                snapshot.theme.terminalChrome.opacity(isFocused ? 0.13 : 0.085)
                LinearGradient(
                    colors: [
                        Color.white.opacity(isFocused ? 0.010 : 0.005),
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
                    snapshot.theme.terminalOuterStroke.opacity(isFocused ? 0.30 : 0.20),
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
           snapshot.selectedTabID == selected.id {
            GeometryReader { proxy in
                ZStack {
                    TerminalSurfaceRepresentable(
                        surface: model.surface(for: selected),
                        theme: snapshot.theme,
                        isFocused: terminalAcceptsInputFocus,
                        suspendsGeometrySync: filePanelLayoutActive
                    )
                    .background(terminalBackground)
                    .transaction { transaction in
                        transaction.disablesAnimations = true
                        transaction.animation = nil
                    }
                    .onTapGesture {
                        ConductorMotion.perform(ConductorMotion.selection) {
                            model.focusPane(pane.id)
                        }
                    }

                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                .contentShape(Rectangle())
                .clipped()
                .onDrop(
                    of: terminalPaneDropTypes,
                    delegate: TerminalPaneDropDelegate(
                        selectedTerminalID: selected.id,
                        paneID: pane.id,
                        paneSize: proxy.size,
                        isFileDropTargeted: $isFileDropTargeted,
                        model: model
                    )
                )
                .overlay {
                    if isFileDropTargeted {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(snapshot.theme.accent.opacity(0.72), lineWidth: 2)
                            .padding(8)
                            .allowsHitTesting(false)
                    }
                }
            }
        }
    }

    private func shellAnimation(_ animation: Animation?) -> Animation? {
        snapshot.appearance.reducedMotion ? nil : animation
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

private extension TerminalTabDropTarget {
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

}

private func terminalTabDropTarget(for location: CGPoint, size: CGSize) -> TerminalTabDropTarget {
    let width = max(1, size.width)
    let height = max(1, size.height)
    let horizontalEdge = min(max(36, width * 0.24), width * 0.42)
    let verticalEdge = min(max(36, height * 0.24), height * 0.42)
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

private final class TerminalFileDropURLCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var urls: [URL] = []

    func append(_ url: URL) {
        lock.lock()
        urls.append(url.standardizedFileURL)
        lock.unlock()
    }

    func snapshot() -> [URL] {
        lock.lock()
        let current = urls
        lock.unlock()
        return current
    }
}

private func loadTerminalDroppedFileURLs(from providers: [NSItemProvider], completion: @escaping @MainActor ([URL]) -> Void) {
    let fileProviders = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
    guard !fileProviders.isEmpty else {
        Task { @MainActor in completion([]) }
        return
    }

    let group = DispatchGroup()
    let collector = TerminalFileDropURLCollector()
    for provider in fileProviders {
        group.enter()
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            defer { group.leave() }
            if let data = item as? Data,
               let url = URL(dataRepresentation: data, relativeTo: nil) {
                collector.append(url)
            } else if let url = item as? URL {
                collector.append(url)
            } else if let nsURL = item as? NSURL {
                collector.append(nsURL as URL)
            }
        }
    }

    group.notify(queue: .main) {
        Task { @MainActor in
            completion(collector.snapshot())
        }
    }
}

private struct TerminalDetachDropOverlay: View {
    let target: TerminalTabDropTarget
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
    let snapshot: TerminalPaneChromeSnapshot
    let model: ConductorWindowModel
    @Binding var highlightedDropTabID: TerminalID?
    @Namespace private var selectionNamespace
    @State private var scrollTargetID: TerminalID?
    @State private var visualSelectedTabID: TerminalID?

    private let tabSpacing: CGFloat = 4
    private let tabEdgePadding: CGFloat = 0

    private var tabIDs: [TerminalID] {
        snapshot.tabIDs
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: tabSpacing) {
                ForEach(snapshot.tabs) { display in
                    tabView(for: display)
                }
            }
            .padding(.horizontal, tabEdgePadding)
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $scrollTargetID, anchor: .center)
        .onDrop(
            of: terminalTabDropTypes,
            delegate: TerminalTabDropDelegate(
                targetTabID: nil,
                paneID: pane.id,
                highlightedTabID: $highlightedDropTabID,
                model: model
            )
        )
        .onAppear {
            setVisualSelection(pane.selectedTabID, animated: false)
            syncScrollTarget(animated: false)
        }
        .onChange(of: pane.selectedTabID) {
            setVisualSelection(pane.selectedTabID, animated: true)
            syncScrollTarget(animated: true)
        }
        .onChange(of: tabIDs) {
            if visualSelectedTabID == nil || !tabIDs.contains(visualSelectedTabID!) {
                setVisualSelection(pane.selectedTabID, animated: false)
            }
            syncScrollTarget(animated: true)
        }
        .frame(height: snapshot.appearance.density.paneTabHeight)
        .clipped()
        .mask(ConductorHorizontalFadeMask())
    }

    private func syncScrollTarget(animated: Bool) {
        guard tabIDs.contains(pane.selectedTabID) else { return }
        let update = {
            scrollTargetID = pane.selectedTabID
        }
        if animated {
            performShellMotion(ConductorMotion.scroll, update)
        } else {
            ConductorMotion.withoutAnimation(update)
        }
    }

    private func tabView(for display: TerminalTabDisplayModel) -> some View {
        TerminalTabButton(
            display: display,
            isSelected: display.id == pane.selectedTabID,
            visuallySelected: visualSelectedTabID == display.id,
            paneFocused: snapshot.paneFocused,
            isDropTarget: highlightedDropTabID == display.id,
            selectionNamespace: selectionNamespace,
            model: model,
            paneID: pane.id,
            density: snapshot.appearance.density,
            onVisualSelect: {
                setVisualSelection(display.id, animated: true)
            }
        )
        .frame(width: snapshot.appearance.density.paneTabWidth)
        .id(display.id)
        .onDrop(
            of: terminalTabDropTypes,
            delegate: TerminalTabDropDelegate(
                targetTabID: display.id,
                paneID: pane.id,
                highlightedTabID: $highlightedDropTabID,
                model: model
            )
        )
    }

    private func setVisualSelection(_ terminalID: TerminalID, animated: Bool) {
        let update = {
            visualSelectedTabID = terminalID
        }
        if animated {
            performShellMotion(ConductorMotion.selectionGlide, update)
        } else {
            ConductorMotion.withoutAnimation(update)
        }
    }

    private func performShellMotion(_ animation: Animation? = ConductorMotion.standard, _ action: () -> Void) {
        guard !snapshot.appearance.reducedMotion else {
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction, action)
            return
        }
        withAnimation(animation, action)
    }
}

private let terminalTabDragType = UTType(exportedAs: "app.conductor.terminal-tab")
private let terminalTabDropTypes: [UTType] = [terminalTabDragType]
private let terminalPaneDropTypes: [UTType] = [terminalTabDragType, .plainText, .fileURL]
private let terminalTabDragPrefix = "terminal:"

private func terminalTabDragPayload(for tabID: TerminalID) -> NSItemProvider {
    let payload = "\(terminalTabDragPrefix)\(tabID.description)"
    let data = Data(payload.utf8)
    let provider = NSItemProvider()
    provider.registerDataRepresentation(
        forTypeIdentifier: terminalTabDragType.identifier,
        visibility: .all
    ) { completion in
        completion(data, nil)
        return nil
    }
    provider.registerDataRepresentation(
        forTypeIdentifier: UTType.plainText.identifier,
        visibility: .all
    ) { completion in
        completion(data, nil)
        return nil
    }
    return provider
}

private struct TerminalTabDropPayloadProvider {
    let provider: NSItemProvider
    let typeIdentifier: String

    func loadTerminalID(_ completion: @escaping @Sendable (TerminalID?) -> Void) {
        provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, _ in
            let terminalID = stringFromDropItem(item).flatMap(terminalID(fromDroppedText:))
            completion(terminalID)
        }
    }
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

private func terminalTabDropProvider(in info: DropInfo) -> TerminalTabDropPayloadProvider? {
    if let provider = info.itemProviders(for: [terminalTabDragType]).first {
        return TerminalTabDropPayloadProvider(provider: provider, typeIdentifier: terminalTabDragType.identifier)
    }
    if let provider = info.itemProviders(for: [.plainText]).first {
        return TerminalTabDropPayloadProvider(provider: provider, typeIdentifier: UTType.plainText.identifier)
    }
    return nil
}

private struct TerminalPaneDropDelegate: DropDelegate {
    let selectedTerminalID: TerminalID
    let paneID: PaneID
    let paneSize: CGSize
    @Binding var isFileDropTargeted: Bool
    let model: ConductorWindowModel

    func validateDrop(info: DropInfo) -> Bool {
        hasTerminalTabPayload(info: info) || hasFilePayload(info: info)
    }

    func dropEntered(info: DropInfo) {
        updateDropTarget(info: info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        updateDropTarget(info: info)
        return DropProposal(operation: hasTerminalTabPayload(info: info) ? .move : .copy)
    }

    func dropExited(info: DropInfo) {
        clearDropTarget()
    }

    func performDrop(info: DropInfo) -> Bool {
        defer {
            clearDropTarget()
        }

        if let payloadProvider = terminalPaneTabPayloadProvider(info: info) {
            let target = terminalTabDropTarget(for: info.location, size: paneSize)
            payloadProvider.loadTerminalID { draggedTabID in
                guard let draggedTabID else { return }
                Task { @MainActor in
                    ConductorMotion.perform(ConductorMotion.layout) {
                        if target == .center {
                            guard self.model.workspace.paneID(containing: draggedTabID) != self.paneID else { return }
                            self.model.moveTabToEnd(draggedTabID, in: self.paneID)
                        } else {
                            self.model.moveTabToSplit(draggedTabID, targetPaneID: self.paneID, direction: target.direction)
                        }
                    }
                    self.model.endTerminalTabDrag()
                }
            }
            return true
        }

        let providers = info.itemProviders(for: [.fileURL])
        guard !providers.isEmpty else { return false }
        loadTerminalDroppedFileURLs(from: providers) { urls in
            for url in urls {
                _ = model.insertPathIntoTerminal(url, terminalID: selectedTerminalID)
            }
        }
        return true
    }

    private func terminalPaneTabPayloadProvider(info: DropInfo) -> TerminalTabDropPayloadProvider? {
        guard model.hasActiveTerminalTabDrag() else { return nil }
        return terminalTabDropProvider(in: info)
    }

    private func hasTerminalTabPayload(info: DropInfo) -> Bool {
        terminalPaneTabPayloadProvider(info: info) != nil
    }

    private func hasFilePayload(info: DropInfo) -> Bool {
        !info.itemProviders(for: [.fileURL]).isEmpty
    }

    private func updateDropTarget(info: DropInfo) {
        if hasTerminalTabPayload(info: info) {
            isFileDropTargeted = false
            let target = terminalTabDropTarget(for: info.location, size: paneSize)
            model.setTerminalTabDropTarget(for: selectedTerminalID, target: target)
            return
        }
        model.setTerminalTabDropTarget(for: selectedTerminalID, target: nil)
        isFileDropTargeted = hasFilePayload(info: info)
    }

    private func clearDropTarget() {
        isFileDropTargeted = false
        model.setTerminalTabDropTarget(for: selectedTerminalID, target: nil)
    }
}

private struct TerminalTabDropDelegate: DropDelegate {
    let targetTabID: TerminalID?
    let paneID: PaneID
    @Binding var highlightedTabID: TerminalID?
    let model: ConductorWindowModel

    func validateDrop(info: DropInfo) -> Bool {
        model.hasActiveTerminalTabDrag() && terminalTabDropProvider(in: info) != nil
    }

    func dropEntered(info: DropInfo) {
        guard validateDrop(info: info) else { return }
        highlightedTabID = targetTabID
    }

    func dropExited(info: DropInfo) {
        if highlightedTabID == targetTabID {
            highlightedTabID = nil
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        highlightedTabID = nil
        guard validateDrop(info: info),
              let payloadProvider = terminalTabDropProvider(in: info) else { return false }
        payloadProvider.loadTerminalID { draggedTabID in
            guard let draggedTabID else { return }
            Task { @MainActor in
                ConductorMotion.perform(ConductorMotion.layout) {
                    if let targetTabID {
                        model.moveTab(draggedTabID, before: targetTabID, in: paneID)
                    } else {
                        model.moveTabToEnd(draggedTabID, in: paneID)
                    }
                }
                model.endTerminalTabDrag()
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
        .macNativeTooltip(help, enabled: !showsTitle)
    }
}

private struct TerminalTabButton: View {
    let display: TerminalTabDisplayModel
    let isSelected: Bool
    let visuallySelected: Bool
    let paneFocused: Bool
    let isDropTarget: Bool
    let selectionNamespace: Namespace.ID
    let model: ConductorWindowModel
    let paneID: PaneID
    let density: AppearanceDensity
    let onVisualSelect: () -> Void
    @State private var editingTitle = false
    @State private var titleDraft = ""
    @State private var hovering = false
    @State private var renameCancelled = false
    @FocusState private var titleFieldFocused: Bool
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorTheme) private var theme

    private var tab: TerminalTabState {
        display.tab
    }

    private var metadata: TerminalDisplayMetadata? {
        display.metadata
    }

    private var unreadCount: Int {
        display.unreadCount
    }

    private var canMoveTargetTabToNextPane: Bool {
        guard display.hasNextPane else { return false }
        return display.tabCount > 1 || display.workspacePaneCount > 1
    }

    private var canMoveTargetTabToNewSplit: Bool {
        display.tabCount > 1 && display.workspaceCanSplit
    }

    private var tabFill: Color {
        if theme.usesDarkChrome {
            return hovering ? theme.shellHoverFill.opacity(0.88) : theme.shellControlFill.opacity(0.66)
        }
        return hovering ? theme.shellHoverFill.opacity(0.84) : theme.shellControlFill.opacity(0.58)
    }

    private var selectedFill: Color {
        theme.shellPanelStrong.opacity(paneFocused ? (theme.usesDarkChrome ? 0.66 : 0.78) : (theme.usesDarkChrome ? 0.52 : 0.64))
    }

    private var tabStroke: Color {
        if isDropTarget {
            return theme.floatingSelectedStroke.opacity(0.95)
        }
        if isSelected {
            return theme.shellStroke.opacity(paneFocused ? (theme.usesDarkChrome ? 0.56 : 0.42) : 0.34)
        }
        return theme.shellStroke.opacity(hovering ? 0.34 : 0.18)
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
                TerminalTabButtonContent(
                    title: tab.title,
                    detail: terminalDetailLabel,
                    selected: isSelected,
                    hasUnread: unreadCount > 0 || (metadata?.unreadCount ?? 0) > 0,
                    showsProgress: metadata?.progressKind != nil,
                    readonly: metadata?.readonly == true,
                    themeID: theme.id,
                    fontScaleID: fontScale.id
                )
                .equatable()
                .contentShape(Rectangle())
                .onTapGesture {
                    onVisualSelect()
                    ConductorMotion.withoutAnimation {
                        model.selectTab(tab.id, in: paneID)
                    }
                }
                .simultaneousGesture(
                    TapGesture(count: 2).onEnded {
                        guard !editingTitle else { return }
                        beginRename()
                    }
                )
            }

            if !editingTitle {
                Button {
                    ConductorMotion.withoutAnimation {
                        model.closeTab(tab.id, in: paneID)
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.conductorSystem(size: 9.5, weight: .semibold, scale: fontScale))
                        .foregroundStyle(hovering || isSelected ? theme.shellChromeText.opacity(0.80) : theme.shellChromeTextMuted.opacity(0.72))
                        .frame(width: 15, height: 15)
                        .clipShape(Circle())
                }
                .buttonStyle(ConductorPressButtonStyle())
                .macNativeTooltip(L("关闭标签", "Close Tab"))
            }
        }
        .padding(.leading, 9)
        .padding(.trailing, 5)
        .frame(height: density.paneTabHeight)
        .frame(
            minWidth: 72,
            idealWidth: density.paneTabWidth,
            maxWidth: density.paneTabWidth
        )
        .background {
            let shape = RoundedRectangle(cornerRadius: ConductorTokens.Radius.terminalTab, style: .continuous)
            ZStack {
                shape
                    .fill(tabFill)
                if visuallySelected {
                    shape
                        .fill(selectedFill)
                        .matchedGeometryEffect(id: "terminal-tab-selection", in: selectionNamespace)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: ConductorTokens.Radius.terminalTab, style: .continuous))
        .overlay {
                RoundedRectangle(cornerRadius: ConductorTokens.Radius.terminalTab, style: .continuous)
                .stroke(tabStroke, lineWidth: isDropTarget ? 1.25 : 1)
        }
        .opacity(display.isDragging ? 0.74 : 1)
        .scaleEffect(display.isDragging ? 0.986 : 1)
        .shadow(
            color: theme.usesDarkChrome ? Color.black.opacity(display.isDragging ? 0.24 : 0) : Color.black.opacity(display.isDragging ? 0.11 : 0),
            radius: display.isDragging ? 9 : 0,
            x: 0,
            y: display.isDragging ? 4 : 0
        )
        .animation(ConductorMotion.hover, value: hovering)
        .animation(ConductorMotion.micro, value: isDropTarget)
        .animation(ConductorMotion.selection, value: editingTitle)
        .animation(ConductorMotion.attention, value: unreadCount)
        .animation(ConductorMotion.dragPreview, value: display.isDragging)
        .onHover { value in
            ConductorMotion.perform(ConductorMotion.hover) {
                hovering = value
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: ConductorTokens.Radius.terminalTab))
        .onDrag {
            ConductorMotion.withoutAnimation {
                model.selectTab(tab.id, in: paneID)
            }
            model.beginTerminalTabDrag(tab.id)
            return terminalTabDragPayload(for: tab.id)
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
                    model.selectTab(tab.id, in: paneID)
                    model.performCommand(.duplicateSelectedTab)
                }
            }
            Divider()
            Button(L("关闭标签", "Close Tab")) {
                ConductorMotion.withoutAnimation {
                    model.selectTab(tab.id, in: paneID)
                    model.performCommand(.closeSelectedTab)
                }
            }
            Button(L("关闭其他标签", "Close Other Tabs")) {
                ConductorMotion.withoutAnimation {
                    model.selectTab(tab.id, in: paneID)
                    model.performCommand(.closeOtherTabs)
                }
            }
            .disabled(!display.canCloseOtherTabs)
            Button(L("关闭右侧标签", "Close Tabs to the Right")) {
                ConductorMotion.withoutAnimation {
                    model.selectTab(tab.id, in: paneID)
                    model.performCommand(.closeTabsToRight)
                }
            }
            .disabled(!display.canCloseTabsToRight)
            Divider()
            Button(L("标签左移", "Move Tab Left")) {
                ConductorMotion.perform(ConductorMotion.layout) {
                    model.selectTab(tab.id, in: paneID)
                    model.performCommand(.moveTabLeft)
                }
            }
            .disabled(display.tabIndex == 0)
            Button(L("标签右移", "Move Tab Right")) {
                ConductorMotion.perform(ConductorMotion.layout) {
                    model.selectTab(tab.id, in: paneID)
                    model.performCommand(.moveTabRight)
                }
            }
            .disabled(display.tabIndex == display.tabCount - 1)
            Divider()
            Button(L("移动到下一个分屏", "Move to Next Pane")) {
                ConductorMotion.perform(ConductorMotion.layout) {
                    model.selectTab(tab.id, in: paneID)
                    model.performCommand(.moveTabToNextPane)
                }
            }
            .disabled(!canMoveTargetTabToNextPane)
            Button(L("移动到右侧新分屏", "Move to New Right Split")) {
                ConductorMotion.perform(ConductorMotion.layout) {
                    model.selectTab(tab.id, in: paneID)
                    model.performCommand(.moveTabToNewRightSplit)
                }
            }
            .disabled(!canMoveTargetTabToNewSplit)
            Button(L("移动到下方新分屏", "Move to New Down Split")) {
                ConductorMotion.perform(ConductorMotion.layout) {
                    model.selectTab(tab.id, in: paneID)
                    model.performCommand(.moveTabToNewDownSplit)
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

private struct TerminalTabButtonContent: View, Equatable {
    let title: String
    let detail: String?
    let selected: Bool
    let hasUnread: Bool
    let showsProgress: Bool
    let readonly: Bool
    let themeID: String
    let fontScaleID: String
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorTheme) private var theme

    nonisolated static func == (lhs: TerminalTabButtonContent, rhs: TerminalTabButtonContent) -> Bool {
        lhs.title == rhs.title &&
            lhs.detail == rhs.detail &&
            lhs.selected == rhs.selected &&
            lhs.hasUnread == rhs.hasUnread &&
            lhs.showsProgress == rhs.showsProgress &&
            lhs.readonly == rhs.readonly &&
            lhs.themeID == rhs.themeID &&
            lhs.fontScaleID == rhs.fontScaleID
    }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "terminal")
                .font(.conductorSystem(size: 10.5, scale: fontScale))
                .foregroundStyle(selected ? theme.shellChromeText : theme.shellChromeTextMuted)
            Text(title)
                .font(.conductorSystem(size: 11, weight: .semibold, scale: fontScale))
                .foregroundStyle(selected ? theme.shellChromeText : theme.shellChromeTextMuted)
                .lineLimit(1)
                .layoutPriority(1)
            if let detail, selected {
                Text("· \(detail)")
                    .font(.conductorSystem(size: 9.5, weight: .medium, scale: fontScale))
                    .foregroundStyle(theme.shellChromeTextMuted.opacity(0.92))
                    .lineLimit(1)
            }
            Spacer(minLength: 2)
            if hasUnread {
                Circle()
                    .fill(theme.floatingEmphasis.opacity(0.72))
                    .frame(width: 6, height: 6)
            } else if showsProgress {
                Circle()
                    .stroke(theme.floatingEmphasis.opacity(0.72), lineWidth: 1.25)
                    .frame(width: 7, height: 7)
            } else if readonly {
                Image(systemName: "lock")
                    .font(.conductorSystem(size: 9, scale: fontScale))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
