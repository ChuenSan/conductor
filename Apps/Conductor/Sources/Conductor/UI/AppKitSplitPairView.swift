import ConductorCore
import AppKit
import SwiftUI

struct AppKitSplitPairView: NSViewRepresentable {
    let axis: SplitAxis
    let fraction: Double
    let first: SplitNode
    let second: SplitNode
    let path: [SplitPathElement]
    let model: ConductorWindowModel
    let theme: TerminalTheme
    let appearance: AppearancePreferences
    let dividerThickness: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    func makeNSView(context: Context) -> ConductorSplitView {
        let splitView = ConductorSplitView()
        splitView.delegate = context.coordinator
        splitView.isVertical = axis == .horizontal
        splitView.dividerStyle = .thin
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
            theme: theme,
            appearance: appearance,
            dividerThickness: dividerThickness,
            model: model
        )

        splitView.isVertical = axis == .horizontal
        splitView.applyDividerAppearance(
            ConductorSplitDividerAppearance(
                themeID: theme.id,
                thickness: dividerThickness
            )
        )

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
        private var theme: TerminalTheme = .codexDark
        private var appearance = AppearancePreferences()
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
            theme: TerminalTheme,
            appearance: AppearancePreferences,
            dividerThickness: CGFloat,
            model: ConductorWindowModel
        ) {
            self.axis = axis
            self.fraction = clampedSplitFraction(fraction)
            self.first = first
            self.second = second
            self.path = path
            self.theme = theme
            self.appearance = appearance
            self.dividerThickness = dividerThickness
            self.model = model
        }

        func refreshHostingRoots() {
            let signature = HostingRootSignature(
                model: ObjectIdentifier(model),
                first: first,
                second: second,
                path: path,
                theme: theme,
                appearance: appearance,
                isUserDragging: isUserDragging
            )
            guard signature != hostingRootSignature else { return }
            hostingRootSignature = signature
            firstHostingView.rootView = AnyView(
                SplitNodeView(
                    node: first,
                    model: model,
                    theme: theme,
                    appearance: appearance,
                    path: path + [.first]
                )
                    .environment(\.conductorTheme, theme)
                    .environment(\.conductorFontScale, appearance.fontScale)
                    .environment(\.conductorFontFamily, appearance.fontFamily)
                    .environment(\.locale, appearance.language.locale)
                    .environment(\.conductorSplitResizeActive, isUserDragging)
            )
            secondHostingView.rootView = AnyView(
                SplitNodeView(
                    node: second,
                    model: model,
                    theme: theme,
                    appearance: appearance,
                    path: path + [.second]
                )
                    .environment(\.conductorTheme, theme)
                    .environment(\.conductorFontScale, appearance.fontScale)
                    .environment(\.conductorFontFamily, appearance.fontFamily)
                    .environment(\.locale, appearance.language.locale)
                    .environment(\.conductorSplitResizeActive, isUserDragging)
            )
        }

        private struct HostingRootSignature: Equatable {
            let model: ObjectIdentifier
            let first: SplitNode
            let second: SplitNode
            let path: [SplitPathElement]
            let theme: TerminalTheme
            let appearance: AppearancePreferences
            let isUserDragging: Bool
        }

        func syncDividerPosition(in splitView: NSSplitView) {
            guard !isUserDragging,
                  splitView.arrangedSubviews.count >= 2,
                  let targetPosition = dividerPosition(for: fraction, in: splitView) else { return }

            let current = currentDividerPosition(in: splitView)
            if let current, abs(current - targetPosition) < SplitLayoutPolicy.dividerPositionTolerance,
               let lastSyncedFraction,
               abs(lastSyncedFraction - fraction) < SplitLayoutPolicy.fractionSyncTolerance {
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
            SplitLayoutPolicy.hitRect(in: splitView)
        }

        func splitView(_ splitView: NSSplitView, additionalEffectiveRectOfDividerAt dividerIndex: Int) -> NSRect {
            guard splitView.arrangedSubviews.count >= 2 else { return .zero }
            let firstFrame = splitView.arrangedSubviews[0].frame
            let secondFrame = splitView.arrangedSubviews[1].frame
            if splitView.isVertical {
                guard firstFrame.width > 1, secondFrame.width > 1 else { return .zero }
            } else {
                guard firstFrame.height > 1, secondFrame.height > 1 else { return .zero }
            }
            return .zero
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
                  abs(pendingDragFraction - fraction) >= SplitLayoutPolicy.fractionSyncTolerance else {
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
            return SplitLayoutPolicy.hitRect(in: splitView).contains(location)
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
            SplitLayoutPolicy.availableLength(in: splitView)
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
            SplitLayoutPolicy.pixelAligned(value, in: view)
        }
    }
}

private final class EventMonitorBox: @unchecked Sendable {
    var token: Any?
}
