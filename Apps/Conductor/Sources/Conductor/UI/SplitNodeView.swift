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
    @ObservedObject var model: ConductorWindowModel
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
        splitView.needsDisplay = true

        context.coordinator.firstHostingView.rootView = AnyView(
            SplitNodeView(node: first, model: model, path: path + [.first])
                .environment(\.conductorSplitResizeActive, context.coordinator.isUserDragging)
        )
        context.coordinator.secondHostingView.rootView = AnyView(
            SplitNodeView(node: second, model: model, path: path + [.second])
                .environment(\.conductorSplitResizeActive, context.coordinator.isUserDragging)
        )

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
            installMouseUpMonitor()
        }

        private func finishUserDrag() {
            guard isUserDragging else { return }
            isUserDragging = false
            splitView?.isDividerActive = false
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
            min(0.85, max(0.15, fraction))
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
        didSet { needsDisplay = true }
    }
    var dividerFillColor: NSColor = .clear {
        didSet { needsDisplay = true }
    }
    var dividerLineColor: NSColor = .separatorColor {
        didSet { needsDisplay = true }
    }
    var activeDividerLineColor: NSColor = .controlAccentColor {
        didSet { needsDisplay = true }
    }
    var isDividerActive = false {
        didSet { needsDisplay = true }
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

private struct TerminalPaneView: View {
    let pane: PaneState
    @ObservedObject var model: ConductorWindowModel
    @State private var highlightedDropTabID: TerminalID?
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

    private var paneDropTarget: TerminalTabDropTarget? {
        model.terminalTabDropTargetByPaneID[pane.id]
    }

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            selectedTerminal
        }
        .background(model.theme.terminalBackground)
        .overlay {
            ZStack {
                if let paneDropTarget {
                    TerminalDetachDropOverlay(target: paneDropTarget)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }

                TerminalPaneFlashOverlay(
                    color: model.theme.accent,
                    visible: flashVisible
                )
                .allowsHitTesting(false)
            }
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
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .frame(height: model.appearance.density.paneTabRailHeight)
        .background {
            ZStack(alignment: .bottom) {
                model.theme.terminalBackground
                model.theme.terminalChrome.opacity(isFocused ? 0.18 : 0.12)
                LinearGradient(
                    colors: [
                        Color.white.opacity(isFocused ? 0.014 : 0.008),
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

            }
            .contentShape(Rectangle())
            .clipped()
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
    @ObservedObject var model: ConductorWindowModel
    let paneFocused: Bool
    @Binding var highlightedDropTabID: TerminalID?
    @Namespace private var selectionNamespace
    @State private var scrollTargetID: TerminalID?

    private let tabSpacing: CGFloat = 4
    private let tabEdgePadding: CGFloat = 0

    private var tabIDs: [TerminalID] {
        pane.tabs.map(\.id)
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: tabSpacing) {
                ForEach(pane.tabs) { tab in
                    tabView(for: tab)
                        .transition(.identity)
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
            syncScrollTarget(animated: false)
        }
        .onChange(of: pane.selectedTabID) {
            syncScrollTarget(animated: true)
        }
        .onChange(of: tabIDs) {
            syncScrollTarget(animated: true)
        }
        .frame(height: model.appearance.density.paneTabHeight)
        .clipped()
        .mask(ConductorHorizontalFadeMask())
    }

    private func syncScrollTarget(animated: Bool) {
        guard tabIDs.contains(pane.selectedTabID) else { return }
        let update = {
            scrollTargetID = pane.selectedTabID
        }
        if animated {
            model.performShellMotion(ConductorMotion.scroll, update)
        } else {
            ConductorMotion.withoutAnimation(update)
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
            of: terminalTabDropTypes,
            delegate: TerminalTabDropDelegate(
                targetTabID: tab.id,
                paneID: pane.id,
                highlightedTabID: $highlightedDropTabID,
                model: model
            )
        )
    }
}

private let terminalTabDragType = UTType(exportedAs: "app.conductor.terminal-tab")
private let terminalTabDropTypes: [UTType] = [terminalTabDragType, .text]
private let terminalTabDragPrefix = "terminal:"

private func terminalTabDragPayload(for tabID: TerminalID) -> NSItemProvider {
    let payload = "\(terminalTabDragPrefix)\(tabID.description)"
    let provider = NSItemProvider(object: payload as NSString)
    let data = Data(payload.utf8)
    provider.registerDataRepresentation(
        forTypeIdentifier: terminalTabDragType.identifier,
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
    if let provider = info.itemProviders(for: [.text]).first {
        return TerminalTabDropPayloadProvider(provider: provider, typeIdentifier: UTType.text.identifier)
    }
    return nil
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
        if theme.usesDarkChrome {
            return hovering ? theme.shellHoverFill.opacity(0.72) : theme.shellControlFill.opacity(0.12)
        }
        return hovering ? theme.shellHoverFill.opacity(0.76) : theme.shellControlFill.opacity(0.50)
    }

    private var selectedFill: Color {
        theme.shellSelectedFill.opacity(paneFocused ? (theme.usesDarkChrome ? 0.90 : 0.76) : 0.62)
    }

    private var tabStroke: Color {
        if isDropTarget {
            return theme.floatingSelectedStroke.opacity(0.95)
        }
        if isSelected {
            return theme.shellStroke.opacity(paneFocused ? (theme.usesDarkChrome ? 0.70 : 0.52) : 0.42)
        }
        return theme.shellStroke.opacity(hovering ? 0.44 : 0.24)
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
                        .font(.conductorSystem(size: 10.5, weight: .semibold, scale: fontScale))
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
                .onTapGesture {
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
                .help(terminalHelpText)
            }

            if !editingTitle {
                Button {
                    ConductorMotion.withoutAnimation {
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
                .stroke(tabStroke, lineWidth: isDropTarget ? 1.25 : 1)
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
            .disabled(!model.workspace.canCloseOtherTabs(in: paneID))
            Button(L("关闭右侧标签", "Close Tabs to the Right")) {
                ConductorMotion.withoutAnimation {
                    model.selectTab(tab.id, in: paneID)
                    model.performCommand(.closeTabsToRight)
                }
            }
            .disabled(!model.workspace.canCloseTabsToRight(of: tab.id, in: paneID))
            Divider()
            Button(L("标签左移", "Move Tab Left")) {
                ConductorMotion.perform(ConductorMotion.layout) {
                    model.selectTab(tab.id, in: paneID)
                    model.performCommand(.moveTabLeft)
                }
            }
            .disabled(tabIndex == nil || tabIndex == 0)
            Button(L("标签右移", "Move Tab Right")) {
                ConductorMotion.perform(ConductorMotion.layout) {
                    model.selectTab(tab.id, in: paneID)
                    model.performCommand(.moveTabRight)
                }
            }
            .disabled(tabIndex == nil || tabIndex == tabCount - 1)
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
