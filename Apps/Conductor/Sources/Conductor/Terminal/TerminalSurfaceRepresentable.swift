import AppKit
import QuartzCore
import SwiftUI

struct TerminalSurfaceRepresentable: NSViewRepresentable {
    let surface: TerminalSurface
    let theme: TerminalTheme
    let isFocused: Bool
    var suspendsGeometrySync = false

    func makeNSView(context: Context) -> TerminalSurfaceContainerView {
        let container = TerminalSurfaceContainerView()
        container.setSurface(surface, theme: theme, focused: isFocused, suspendsGeometrySync: suspendsGeometrySync)
        return container
    }

    func updateNSView(_ nsView: TerminalSurfaceContainerView, context: Context) {
        nsView.setSurface(surface, theme: theme, focused: isFocused, suspendsGeometrySync: suspendsGeometrySync)
    }
}

@MainActor
final class TerminalSurfaceContainerView: NSView {
    private static let scrollToBottomThreshold: CGFloat = 5

    private let scrollView = TerminalSurfaceScrollView()
    private let documentView = NSView(frame: .zero)
    private var currentSurface: TerminalSurface?
    private var currentTheme: TerminalTheme?
    private var currentFocused = false
    private var currentSuspendsGeometrySync = false
    private var wantsTerminalFocus = false
    private var pendingGeometrySync = false
    private var pendingGeometryForce = false
    private var isLiveScrolling = false
    private var lastSentRow: Int?
    private var userScrolledAwayFromBottom = false
    private var pendingExplicitWheelScroll = false
    private var allowExplicitScrollbarSync = false
    private nonisolated(unsafe) var surfaceObservers: [NSObjectProtocol] = []
    private nonisolated(unsafe) var scrollObservers: [NSObjectProtocol] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        clipsToBounds = true
        layer?.masksToBounds = true
        configureLayerForTerminalHosting(layer)
        configureScrollView()
        addSubview(scrollView)
        installScrollObservers()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        surfaceObservers.forEach { NotificationCenter.default.removeObserver($0) }
        scrollObservers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    func setSurface(_ surface: TerminalSurface, theme: TerminalTheme, focused: Bool, suspendsGeometrySync: Bool) {
        let surfaceChanged = currentSurface !== surface
        let focusChanged = currentFocused != focused
        let geometrySyncResumed = currentSuspendsGeometrySync && !suspendsGeometrySync
        wantsTerminalFocus = focused
        currentFocused = focused
        currentSuspendsGeometrySync = suspendsGeometrySync
        if surfaceChanged {
            let signpost = ConductorSignpost.begin("surface-host-swap")
            defer { ConductorSignpost.end("surface-host-swap", signpost) }
            currentSurface?.setFocused(false)
            currentSurface?.hostView.removeFromSuperview()
            removeSurfaceObservers()
            currentSurface = surface
            currentTheme = nil
            lastSentRow = nil
            userScrolledAwayFromBottom = false
            pendingExplicitWheelScroll = false
            allowExplicitScrollbarSync = false
            scrollView.terminalHostView = surface.hostView
            installHostView(surface.hostView)
            installSurfaceObservers(surface)
            ConductorLog.terminal.info("Visible terminal host swapped to \(surface.id.description)")
        }
        surface.hostView.suspendsGeometrySync = suspendsGeometrySync
        synchronizeHostedViewFrame(force: surfaceChanged)

        let themeChanged = currentTheme != theme
        if surfaceChanged || themeChanged {
            surface.applyTheme(theme)
        }
        currentTheme = theme
        if !suspendsGeometrySync {
            surface.attachIfPossible()
        }
        surface.setFocused(focused)
        resignFocusIfNeeded(for: surface)
        restoreFocusIfNeeded()
        if geometrySyncResumed {
            syncCurrentSurface(force: false)
        } else if !suspendsGeometrySync && (surfaceChanged || themeChanged || focusChanged) {
            schedulePostLayoutGeometrySync(for: surface, force: surfaceChanged || themeChanged)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        synchronizeHostedViewFrame(force: true)
        syncCurrentSurface(force: true)
        if !currentSuspendsGeometrySync {
            currentSurface?.attachIfPossible()
        }
        restoreFocusIfNeeded()
    }

    override func layout() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        super.layout()
        scrollView.frame = bounds
        synchronizeHostedViewFrame(force: false)
        CATransaction.commit()
    }

    override func setFrameSize(_ newSize: NSSize) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        super.setFrameSize(newSize)
        scrollView.frame = bounds
        synchronizeHostedViewFrame(force: false)
        CATransaction.commit()
    }

    override func setBoundsSize(_ newSize: NSSize) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        super.setBoundsSize(newSize)
        scrollView.frame = bounds
        synchronizeHostedViewFrame(force: false)
        CATransaction.commit()
    }

    private func configureScrollView() {
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = false
        scrollView.usesPredominantAxisScrolling = true
        scrollView.scrollerStyle = .overlay
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear
        scrollView.contentView.clipsToBounds = true
        scrollView.contentView.drawsBackground = false
        scrollView.contentView.backgroundColor = .clear
        scrollView.contentView.postsBoundsChangedNotifications = true
        scrollView.documentView = documentView
    }

    private func installScrollObservers() {
        scrollObservers.append(NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.synchronizeSurfaceView()
            }
        })
        scrollObservers.append(NotificationCenter.default.addObserver(
            forName: NSScrollView.willStartLiveScrollNotification,
            object: scrollView,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.isLiveScrolling = true
            }
        })
        scrollObservers.append(NotificationCenter.default.addObserver(
            forName: NSScrollView.didLiveScrollNotification,
            object: scrollView,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleLiveScroll()
            }
        })
        scrollObservers.append(NotificationCenter.default.addObserver(
            forName: NSScrollView.didEndLiveScrollNotification,
            object: scrollView,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.isLiveScrolling = false
                self?.handleLiveScroll()
            }
        })
        scrollObservers.append(NotificationCenter.default.addObserver(
            forName: NSScroller.preferredScrollerStyleDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.synchronizeHostedViewFrame(force: true)
            }
        })
    }

    private func installSurfaceObservers(_ surface: TerminalSurface) {
        surfaceObservers.append(NotificationCenter.default.addObserver(
            forName: .terminalSurfaceDidUpdateScrollbar,
            object: surface,
            queue: .main
        ) { [weak self] notification in
            let scrollbar = notification.userInfo?["scrollbar"] as? TerminalScrollbarState
            Task { @MainActor in
                guard let scrollbar else { return }
                self?.handleScrollbarUpdate(scrollbar)
            }
        })
        surfaceObservers.append(NotificationCenter.default.addObserver(
            forName: .terminalSurfaceDidUpdateCellSize,
            object: surface,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.synchronizeScrollView()
            }
        })
        surfaceObservers.append(NotificationCenter.default.addObserver(
            forName: .terminalSurfaceDidReceiveWheelScroll,
            object: surface,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.pendingExplicitWheelScroll = true
            }
        })
    }

    private func removeSurfaceObservers() {
        surfaceObservers.forEach { NotificationCenter.default.removeObserver($0) }
        surfaceObservers.removeAll(keepingCapacity: true)
    }

    private func installHostView(_ hostView: TerminalHostView) {
        hostView.removeFromSuperview()
        hostView.translatesAutoresizingMaskIntoConstraints = true
        hostView.autoresizingMask = [.width, .height]
        hostView.clipsToBounds = true
        hostView.frame = NSRect(origin: .zero, size: scrollView.bounds.size)
        hostView.bounds = NSRect(origin: .zero, size: scrollView.bounds.size)
        documentView.addSubview(hostView)
        hostView.suspendsGeometrySync = currentSuspendsGeometrySync
    }

    @discardableResult
    private func synchronizeHostedViewFrame(force: Bool) -> Bool {
        guard let currentSurface else { return false }
        synchronizeScrollbarAppearance()
        let targetDocumentHeight = documentHeight()
        if force || abs(documentView.frame.height - targetDocumentHeight) > 0.5 {
            documentView.frame.size.height = targetDocumentHeight
        }
        if force || abs(documentView.frame.width - scrollView.bounds.width) > 0.5 {
            documentView.frame.size.width = scrollView.bounds.width
        }

        let targetFrame = NSRect(origin: currentSurface.hostView.frame.origin, size: scrollView.bounds.size)
        let targetBounds = NSRect(origin: .zero, size: targetFrame.size)
        var geometryChanged = false
        if force || !rectApproximatelyEqual(currentSurface.hostView.frame, targetFrame) {
            currentSurface.hostView.frame = targetFrame
            geometryChanged = true
        }
        if force || !rectApproximatelyEqual(currentSurface.hostView.bounds, targetBounds) {
            currentSurface.hostView.bounds = targetBounds
            geometryChanged = true
        }
        if geometryChanged, !currentSuspendsGeometrySync {
            schedulePostLayoutGeometrySync(for: currentSurface, force: force)
        }
        synchronizeScrollView()
        synchronizeSurfaceView()
        return geometryChanged
    }

    private func syncCurrentSurface(force: Bool, layoutNow: Bool = true) {
        guard let currentSurface else { return }
        guard !currentSuspendsGeometrySync else { return }
        if layoutNow {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            _ = synchronizeHostedViewFrame(force: false)
            CATransaction.commit()
        }
        currentSurface.syncGeometry(force: force)
    }

    private func schedulePostLayoutGeometrySync(for surface: TerminalSurface, force: Bool) {
        pendingGeometryForce = pendingGeometryForce || force
        guard !pendingGeometrySync else { return }
        pendingGeometrySync = true
        Task { @MainActor [weak self, weak surface] in
            guard let self else {
                return
            }
            let shouldForce = self.pendingGeometryForce
            self.pendingGeometrySync = false
            self.pendingGeometryForce = false
            guard let surface,
                  self.currentSurface === surface else {
                return
            }
            self.syncCurrentSurface(force: shouldForce)
            self.restoreFocusIfNeeded()
        }
    }

    private func restoreFocusIfNeeded() {
        guard wantsTerminalFocus,
              let surface = currentSurface,
              let window,
              surface.hostView.window === window,
              window.firstResponder !== surface.hostView,
              shouldRestoreTerminalFocus(firstResponder: window.firstResponder, hostView: surface.hostView) else {
            return
        }
        window.makeFirstResponder(surface.hostView)
    }

    private func shouldRestoreTerminalFocus(firstResponder: NSResponder?, hostView: NSView) -> Bool {
        guard let firstResponder else { return true }
        guard let responderView = firstResponder as? NSView else { return false }
        if responderView === self { return true }
        if responderView === hostView || responderView.isDescendant(of: hostView) { return true }
        return false
    }

    private func resignFocusIfNeeded(for surface: TerminalSurface) {
        guard !wantsTerminalFocus,
              window?.firstResponder === surface.hostView else {
            return
        }
        window?.makeFirstResponder(nil)
    }

    private func configureLayerForTerminalHosting(_ layer: CALayer?) {
        layer?.actions = [
            "bounds": NSNull(),
            "position": NSNull(),
            "frame": NSNull(),
            "contentsScale": NSNull(),
            "backgroundColor": NSNull()
        ]
    }

    private func rectApproximatelyEqual(_ lhs: CGRect, _ rhs: CGRect, epsilon: CGFloat = 0.25) -> Bool {
        abs(lhs.origin.x - rhs.origin.x) <= epsilon &&
            abs(lhs.origin.y - rhs.origin.y) <= epsilon &&
            abs(lhs.size.width - rhs.size.width) <= epsilon &&
            abs(lhs.size.height - rhs.size.height) <= epsilon
    }

    @discardableResult
    private func synchronizeScrollbarAppearance() -> Bool {
        let shouldShowScrollBar = shouldShowTerminalScrollBar()
        let changed = scrollView.hasVerticalScroller != shouldShowScrollBar ||
            scrollView.autohidesScrollers != false ||
            scrollView.scrollerStyle != .overlay
        scrollView.hasVerticalScroller = shouldShowScrollBar
        scrollView.autohidesScrollers = false
        scrollView.scrollerStyle = .overlay
        return changed
    }

    private func shouldShowTerminalScrollBar() -> Bool {
        guard let scrollbar = currentSurface?.scrollbarState else { return true }
        return scrollbar.hasScrollback
    }

    private func documentHeight() -> CGFloat {
        let contentHeight = max(scrollView.contentSize.height, bounds.height)
        guard let surface = currentSurface,
              surface.cellSize.height > 0,
              let scrollbar = surface.scrollbarState else {
            return contentHeight
        }
        let documentGridHeight = CGFloat(scrollbar.total) * surface.cellSize.height
        let padding = contentHeight - (CGFloat(scrollbar.len) * surface.cellSize.height)
        return max(contentHeight, documentGridHeight + padding)
    }

    private func synchronizeScrollView() {
        var didChangeGeometry = false
        synchronizeScrollbarAppearance()
        let targetDocumentHeight = documentHeight()
        if abs(documentView.frame.height - targetDocumentHeight) > 0.5 {
            documentView.frame.size.height = targetDocumentHeight
            didChangeGeometry = true
        }
        if abs(documentView.frame.width - scrollView.bounds.width) > 0.5 {
            documentView.frame.size.width = scrollView.bounds.width
            didChangeGeometry = true
        }

        guard !isLiveScrolling,
              let surface = currentSurface,
              surface.cellSize.height > 0,
              let scrollbar = surface.scrollbarState else {
            if didChangeGeometry {
                scrollView.reflectScrolledClipView(scrollView.contentView)
            }
            return
        }

        let offsetY = CGFloat(scrollbar.total - scrollbar.offset - scrollbar.len) * surface.cellSize.height
        let targetOrigin = CGPoint(x: 0, y: offsetY)
        let currentOrigin = scrollView.contentView.bounds.origin
        let distanceFromBottom = documentView.frame.height - currentOrigin.y - scrollView.contentView.bounds.height
        if distanceFromBottom <= Self.scrollToBottomThreshold {
            userScrolledAwayFromBottom = false
        }

        let shouldAutoScroll = !userScrolledAwayFromBottom || allowExplicitScrollbarSync
        if shouldAutoScroll && !pointApproximatelyEqual(currentOrigin, targetOrigin) {
            scrollView.contentView.scroll(to: targetOrigin)
            didChangeGeometry = true
        }
        allowExplicitScrollbarSync = false
        if didChangeGeometry {
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }

    private func synchronizeSurfaceView() {
        guard let currentSurface else { return }
        let visibleRect = scrollView.contentView.documentVisibleRect
        let targetOrigin = visibleRect.origin
        guard !pointApproximatelyEqual(currentSurface.hostView.frame.origin, targetOrigin) else { return }
        currentSurface.hostView.frame.origin = targetOrigin
    }

    private func handleLiveScroll() {
        guard let surface = currentSurface,
              surface.cellSize.height > 0 else { return }
        let visibleRect = scrollView.contentView.documentVisibleRect
        let scrollOffset = documentView.frame.height - visibleRect.origin.y - visibleRect.height
        if scrollOffset > Self.scrollToBottomThreshold {
            userScrolledAwayFromBottom = true
        } else if scrollOffset <= 0 {
            userScrolledAwayFromBottom = false
        }
        let row = max(0, Int(scrollOffset / surface.cellSize.height))
        guard row != lastSentRow else { return }
        lastSentRow = row
        _ = surface.performBindingAction("scroll_to_row:\(row)")
    }

    private func handleScrollbarUpdate(_ scrollbar: TerminalScrollbarState) {
        let wasVisible = scrollView.hasVerticalScroller
        if pendingExplicitWheelScroll {
            userScrolledAwayFromBottom = scrollbar.offset + scrollbar.len < scrollbar.total
            allowExplicitScrollbarSync = true
            pendingExplicitWheelScroll = false
        }
        lastSentRow = Int(scrollbar.offset)
        let isVisible = shouldShowTerminalScrollBar()
        if wasVisible != isVisible {
            _ = synchronizeHostedViewFrame(force: false)
            return
        }
        synchronizeScrollView()
    }

    private func pointApproximatelyEqual(_ lhs: CGPoint, _ rhs: CGPoint, epsilon: CGFloat = 0.5) -> Bool {
        abs(lhs.x - rhs.x) <= epsilon && abs(lhs.y - rhs.y) <= epsilon
    }
}

private final class TerminalSurfaceScrollView: NSScrollView {
    weak var terminalHostView: TerminalHostView?

    override var acceptsFirstResponder: Bool { false }

    override func scrollWheel(with event: NSEvent) {
        guard let terminalHostView else {
            super.scrollWheel(with: event)
            return
        }
        if window?.firstResponder !== terminalHostView {
            window?.makeFirstResponder(terminalHostView)
        }
        terminalHostView.scrollWheel(with: event)
    }
}
