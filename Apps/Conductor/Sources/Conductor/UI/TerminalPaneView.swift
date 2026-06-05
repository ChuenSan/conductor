import ConductorCore
import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

private func L(_ zh: String, _ en: String) -> String {
    ConductorLocalization.text(zh: zh, en: en)
}

struct TerminalPaneChromeSnapshot: Equatable {
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
    init(
        pane: PaneState,
        model: ConductorWindowModel,
        theme: TerminalTheme,
        appearance: AppearancePreferences
    ) {
        let workspace = model.workspace
        let paneFocused = workspace.focusedPaneID == pane.id
        let hasNextPane = workspace.nextPaneID(after: pane.id) != nil
        let workspacePaneCount = workspace.panes.count
        let workspaceCanSplit = workspace.canSplit()
        let metadataByTerminalID = model.metadataByTerminalID

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
        self.theme = theme
        self.appearance = appearance
        self.tabs = pane.tabs.enumerated().map { index, tab in
            TerminalTabDisplayModel(
                tab: tab,
                metadata: metadataByTerminalID[tab.id],
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

struct TerminalTabDisplayModel: Identifiable, Equatable {
    var id: TerminalID { tab.id }
    let tab: TerminalTabState
    let metadata: TerminalDisplayMetadata?
    let isDragging: Bool
    let tabIndex: Int
    let tabCount: Int
    let hasNextPane: Bool
    let workspacePaneCount: Int
    let workspaceCanSplit: Bool
    let canCloseOtherTabs: Bool
    let canCloseTabsToRight: Bool
}

struct TerminalPaneView: View {
    let pane: PaneState
    let model: ConductorWindowModel
    let snapshot: TerminalPaneChromeSnapshot
    @State private var highlightedDropTabID: TerminalID?
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
        GeometryReader { proxy in
            paneContent
                .frame(width: proxy.size.width, height: proxy.size.height)
                .onDrop(
                    of: terminalTabDropTypes,
                    delegate: TerminalPaneSplitDropDelegate(
                        paneID: pane.id,
                        paneSize: proxy.size,
                        model: model
                    )
                )
        }
    }

    private var paneContent: some View {
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
                help: "\(L("关闭这个分屏", "Close this pane")) \(model.shortcutTitle(for: .closeFocusedPane, fallback: "Cmd-Shift-W"))"
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
                snapshot.theme.terminalChrome.opacity(isFocused ? 0.075 : 0.050)
                LinearGradient(
                    colors: [
                        Color.white.opacity(isFocused ? 0.006 : 0.003),
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
                    snapshot.theme.terminalOuterStroke.opacity(isFocused ? 0.22 : 0.14),
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
                    VStack(spacing: 0) {
                        if let restored = model.restoredTerminalContent(for: selected.id) {
                            RestoredTerminalContentBlock(
                                content: restored,
                                theme: snapshot.theme
                            ) {
                                model.dismissRestoredTerminalContent(for: selected.id)
                            }
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }

                        TerminalSurfaceRepresentable(
                            surface: model.surface(for: selected),
                            theme: snapshot.theme,
                            isFocused: terminalAcceptsInputFocus,
                            suspendsGeometrySync: filePanelLayoutActive
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .layoutPriority(1)
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

                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                .contentShape(Rectangle())
                .clipped()
            }
        }
    }

    private func shellAnimation(_ animation: Animation?) -> Animation? {
        snapshot.appearance.reducedMotion ? nil : animation
    }

    private func triggerFocusFlash() {
        ConductorMotion.perform(ConductorMotion.emphasized) {
            flashVisible = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + ConductorMotion.Timing.reveal) {
            ConductorMotion.perform(ConductorMotion.standard) {
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

private struct RestoredTerminalContentBlock: View {
    let content: RestoredTerminalContent
    let theme: TerminalTheme
    let dismiss: () -> Void
    @Environment(\.conductorFontScale) private var fontScale

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.conductorSystem(size: 11, weight: .semibold, scale: fontScale))
                Text(L("上次终端内容", "Previous Terminal Content"))
                    .font(.conductorSystem(size: 11, weight: .semibold, scale: fontScale))
                Spacer(minLength: 8)
                Button(action: dismiss) {
                    Image(systemName: "xmark")
                        .font(.conductorSystem(size: 10, weight: .semibold, scale: fontScale))
                }
                .buttonStyle(.plain)
                .macNativeTooltip(L("隐藏恢复内容", "Hide restored content"))
                .accessibilityLabel(L("隐藏恢复内容", "Hide restored content"))
            }
            .foregroundStyle(theme.shellChromeText.opacity(0.86))

            ScrollView {
                Text(content.text)
                    .font(.system(size: fontScale.size(11), design: .monospaced))
                    .foregroundStyle(theme.shellChromeText.opacity(0.88))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .frame(maxHeight: 160)
            .background(theme.terminalChrome.opacity(0.20))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .padding(8)
        .background(theme.terminalChrome.opacity(0.16))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(theme.terminalOuterStroke.opacity(0.20))
                .frame(height: 1)
        }
    }
}

private let terminalTabDragType = UTType(exportedAs: "app.conductor.terminal-tab")
private let terminalTabDropTypes: [UTType] = [terminalTabDragType, .plainText]
private let terminalTabPasteboardType = NSPasteboard.PasteboardType(terminalTabDragType.identifier)
private let terminalTabDragPrefix = "terminal:"

private struct StableTerminalTabStrip: NSViewRepresentable {
    let pane: PaneState
    let snapshot: TerminalPaneChromeSnapshot
    let model: ConductorWindowModel
    @Binding var highlightedDropTabID: TerminalID?

    func makeNSView(context: Context) -> NativeTerminalTabStripView {
        let view = NativeTerminalTabStripView()
        view.onHighlightedDropTabChange = { terminalID in
            highlightedDropTabID = terminalID
        }
        return view
    }

    func updateNSView(_ view: NativeTerminalTabStripView, context: Context) {
        view.onHighlightedDropTabChange = { terminalID in
            highlightedDropTabID = terminalID
        }
        view.update(
            displays: snapshot.tabs,
            selectedTabID: pane.selectedTabID,
            paneFocused: snapshot.paneFocused,
            highlightedDropTabID: highlightedDropTabID,
            paneID: pane.id,
            model: model,
            theme: snapshot.theme,
            density: snapshot.appearance.density,
            fontScale: snapshot.appearance.fontScale
        )
    }
}

private final class NativeTerminalTabStripView: NSView {
    var onHighlightedDropTabChange: ((TerminalID?) -> Void)?

    private let scrollView = NSScrollView()
    private let contentView = FlippedDocumentView()
    private var itemViews: [TerminalID: NativeTerminalTabItemView] = [:]
    private var orderedIDs: [TerminalID] = []
    private var selectedTabID: TerminalID?
    private var paneID: PaneID?
    private weak var model: ConductorWindowModel?
    private var theme: TerminalTheme = .codexDark
    private var density: AppearanceDensity = .standard
    private var fontScale: AppearanceFontScale = .standard
    private var highlightedDropTabID: TerminalID?
    private let tabSpacing: CGFloat = 3

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        wantsLayer = true
        layer?.masksToBounds = true
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.scrollerStyle = .overlay
        scrollView.documentView = contentView
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        registerForDraggedTypes([terminalTabPasteboardType])
    }

    func update(
        displays: [TerminalTabDisplayModel],
        selectedTabID: TerminalID,
        paneFocused: Bool,
        highlightedDropTabID: TerminalID?,
        paneID: PaneID,
        model: ConductorWindowModel,
        theme: TerminalTheme,
        density: AppearanceDensity,
        fontScale: AppearanceFontScale
    ) {
        self.selectedTabID = selectedTabID
        self.paneID = paneID
        self.model = model
        self.theme = theme
        self.density = density
        self.fontScale = fontScale
        self.highlightedDropTabID = highlightedDropTabID

        let nextIDs = displays.map(\.id)
        for staleID in Set(itemViews.keys).subtracting(nextIDs) {
            itemViews.removeValue(forKey: staleID)?.removeFromSuperview()
        }

        for display in displays {
            let item = itemViews[display.id] ?? makeItemView()
            itemViews[display.id] = item
            if item.superview == nil {
                contentView.addSubview(item)
            }
            item.update(
                display: display,
                selected: display.id == selectedTabID,
                paneFocused: paneFocused,
                highlighted: highlightedDropTabID == display.id,
                paneID: paneID,
                model: model,
                theme: theme,
                density: density,
                fontScale: fontScale
            )
        }

        if orderedIDs != nextIDs {
            orderedIDs = nextIDs
            needsLayout = true
        }
        layoutItemViews()
        scrollSelectedTabIntoView()
    }

    override func layout() {
        super.layout()
        layoutItemViews()
    }

    private func makeItemView() -> NativeTerminalTabItemView {
        let item = NativeTerminalTabItemView()
        item.onDragEnded = { [weak self] in
            self?.model?.endTerminalTabDrag()
        }
        return item
    }

    private func layoutItemViews() {
        let width = density.paneTabWidth
        let height = max(0, bounds.height)
        var x: CGFloat = 0

        for id in orderedIDs {
            guard let item = itemViews[id] else { continue }
            item.frame = NSRect(x: x, y: 0, width: width, height: height)
            x += width + tabSpacing
        }

        let contentWidth = max(bounds.width, max(0, x - tabSpacing))
        contentView.frame = NSRect(x: 0, y: 0, width: contentWidth, height: height)
    }

    private func scrollSelectedTabIntoView() {
        guard let selectedTabID,
              let item = itemViews[selectedTabID],
              item.superview === contentView else { return }
        contentView.scrollToVisible(item.frame.insetBy(dx: -18, dy: 0))
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        draggingUpdated(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let model,
              model.hasActiveTerminalTabDrag(),
              draggedTerminalID(from: sender.draggingPasteboard) != nil else {
            setHighlightedDropTab(nil)
            return []
        }
        setHighlightedDropTab(targetTabID(for: sender))
        return .move
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        setHighlightedDropTab(nil)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        draggedTerminalID(from: sender.draggingPasteboard) != nil
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        defer { setHighlightedDropTab(nil) }
        guard let draggedTabID = draggedTerminalID(from: sender.draggingPasteboard),
              let paneID,
              let model else { return false }
        if let targetTabID = targetTabID(for: sender), targetTabID != draggedTabID {
            model.moveTab(draggedTabID, before: targetTabID, in: paneID)
        } else {
            model.moveTabToEnd(draggedTabID, in: paneID)
        }
        model.endTerminalTabDrag()
        return true
    }

    private func targetTabID(for sender: NSDraggingInfo) -> TerminalID? {
        let point = convert(sender.draggingLocation, from: nil)
        let contentPoint = contentView.convert(point, from: self)
        for id in orderedIDs {
            guard let item = itemViews[id] else { continue }
            if item.frame.contains(contentPoint) {
                return id
            }
        }
        return nil
    }

    private func setHighlightedDropTab(_ terminalID: TerminalID?) {
        guard highlightedDropTabID != terminalID else { return }
        highlightedDropTabID = terminalID
        onHighlightedDropTabChange?(terminalID)
        for (id, item) in itemViews {
            item.setHighlighted(id == terminalID)
        }
    }
}

private final class FlippedDocumentView: NSView {
    override var isFlipped: Bool { true }
}

private final class NativeTerminalTabItemView: NSView, NSDraggingSource, NSTextFieldDelegate {
    var onDragEnded: (() -> Void)?

    private var display: TerminalTabDisplayModel?
    private var selected = false
    private var paneFocused = false
    private var highlighted = false
    private var paneID: PaneID?
    private weak var model: ConductorWindowModel?
    private var theme: TerminalTheme = .codexDark
    private var density: AppearanceDensity = .standard
    private var fontScale: AppearanceFontScale = .standard
    private var hovering = false
    private var mouseDownPoint: NSPoint?
    private var mouseDownWasOnClose = false
    private var dragStarted = false
    private var renameField: NSTextField?
    private var tracking: NSTrackingArea?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        registerForDraggedTypes([terminalTabPasteboardType])
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        registerForDraggedTypes([terminalTabPasteboardType])
    }

    func update(
        display: TerminalTabDisplayModel,
        selected: Bool,
        paneFocused: Bool,
        highlighted: Bool,
        paneID: PaneID,
        model: ConductorWindowModel,
        theme: TerminalTheme,
        density: AppearanceDensity,
        fontScale: AppearanceFontScale
    ) {
        self.display = display
        self.selected = selected
        self.paneFocused = paneFocused
        self.highlighted = highlighted
        self.paneID = paneID
        self.model = model
        self.theme = theme
        self.density = density
        self.fontScale = fontScale
        toolTip = helpText(for: display)
        needsDisplay = true
    }

    func setHighlighted(_ highlighted: Bool) {
        guard self.highlighted != highlighted else { return }
        self.highlighted = highlighted
        needsDisplay = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking {
            removeTrackingArea(tracking)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        hovering = true
        needsDisplay = true
    }

    override func mouseMoved(with event: NSEvent) {
        if !hovering {
            hovering = true
            needsDisplay = true
        }
    }

    override func mouseExited(with event: NSEvent) {
        hovering = false
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        guard display != nil else { return }
        let point = convert(event.locationInWindow, from: nil)
        window?.makeFirstResponder(self)
        mouseDownPoint = point
        mouseDownWasOnClose = closeRect.contains(point)
        dragStarted = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard !dragStarted,
              let display,
              let paneID,
              let start = mouseDownPoint else { return }
        guard !mouseDownWasOnClose else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard hypot(point.x - start.x, point.y - start.y) > 4 else { return }

        dragStarted = true
        model?.selectTab(display.id, in: paneID)
        model?.beginTerminalTabDrag(display.id)

        let pasteboardItem = NSPasteboardItem()
        let payload = "\(terminalTabDragPrefix)\(display.id.description)"
        pasteboardItem.setString(payload, forType: terminalTabPasteboardType)
        pasteboardItem.setString(payload, forType: .string)

        let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)
        draggingItem.setDraggingFrame(bounds, contents: dragPreviewImage())
        beginDraggingSession(with: [draggingItem], event: event, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            mouseDownPoint = nil
            mouseDownWasOnClose = false
            dragStarted = false
        }
        guard let display, let paneID, !dragStarted else { return }
        let point = convert(event.locationInWindow, from: nil)
        if mouseDownWasOnClose && closeRect.contains(point) {
            model?.closeTab(display.id, in: paneID)
            return
        }
        guard bounds.contains(point) else { return }
        model?.selectTab(display.id, in: paneID)
        mouseDownPoint = nil
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let display else { return }
        _ = model?.showTerminalContextMenu(terminalID: display.id, event: event, in: self)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let display else { return }

        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 0, dy: 1), xRadius: ConductorTokens.Radius.terminalTab, yRadius: ConductorTokens.Radius.terminalTab)
        fillColor.setFill()
        shape.fill()
        strokeColor.setStroke()
        shape.lineWidth = highlighted ? 1.25 : 1
        shape.stroke()

        drawIcon(in: iconRect)
        if renameField == nil {
            drawTitle(for: display)
            drawStatus(for: display)
            if hovering || selected {
                drawCloseGlyph()
            }
        }
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .move
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        mouseDownPoint = nil
        dragStarted = false
        onDragEnded?()
    }

    private var fillColor: NSColor {
        if selected {
            return NSColor(theme.shellSelectedFill.opacity(0.68))
        }
        if hovering {
            return NSColor(theme.shellHoverFill.opacity(theme.usesDarkChrome ? 0.22 : 0.12))
        }
        return .clear
    }

    private var strokeColor: NSColor {
        if highlighted {
            return NSColor(theme.floatingSelectedStroke.opacity(0.95))
        }
        if selected {
            return NSColor(theme.floatingSelectedStroke.opacity(paneFocused ? (theme.usesDarkChrome ? 0.34 : 0.30) : (theme.usesDarkChrome ? 0.22 : 0.20)))
        }
        return NSColor(theme.shellStroke.opacity(hovering ? 0.08 : 0.0))
    }

    private var iconRect: NSRect {
        NSRect(x: 8, y: (bounds.height - 13) / 2, width: 13, height: 13)
    }

    private var closeRect: NSRect {
        NSRect(x: bounds.maxX - 22, y: (bounds.height - 16) / 2, width: 16, height: 16)
    }

    private var textRect: NSRect {
        let rightInset: CGFloat = (hovering || selected) ? 30 : 12
        return NSRect(x: 26, y: 0, width: max(0, bounds.width - 26 - rightInset), height: bounds.height)
    }

    private func drawIcon(in rect: NSRect) {
        let image = NSImage(systemSymbolName: "terminal", accessibilityDescription: nil)
        image?.isTemplate = true
        let tint = selected ? NSColor(theme.shellChromeText.opacity(0.90)) : NSColor(theme.shellChromeTextMuted.opacity(0.62))
        tint.set()
        image?.draw(in: rect)
    }

    private func drawTitle(for display: TerminalTabDisplayModel) {
        let title = display.tab.title
        let titleColor = selected ? NSColor(theme.shellChromeText.opacity(0.92)) : NSColor(theme.shellChromeTextMuted.opacity(0.68))
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let titleFont = NSFont.systemFont(ofSize: fontScale.size(10.8), weight: selected ? .semibold : .medium)
        let attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: titleFont,
                .foregroundColor: titleColor,
                .paragraphStyle: paragraph
            ]
        )

        let rect = textRect
        if selected, let detail = detailLabel(for: display) {
            let detailText = " · \(detail)"
            let detailAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: fontScale.size(9.5), weight: .medium),
                .foregroundColor: NSColor(theme.shellChromeTextMuted.opacity(0.72)),
                .paragraphStyle: paragraph
            ]
            let combined = NSMutableAttributedString(attributedString: attributedTitle)
            combined.append(NSAttributedString(string: detailText, attributes: detailAttributes))
            combined.draw(in: rect.insetBy(dx: 0, dy: max(0, (rect.height - 15) / 2)))
        } else {
            attributedTitle.draw(in: rect.insetBy(dx: 0, dy: max(0, (rect.height - 15) / 2)))
        }
    }

    private func drawStatus(for display: TerminalTabDisplayModel) {
        let closeReserve: CGFloat = (hovering || selected) ? 27 : 9
        let rect = NSRect(x: bounds.maxX - closeReserve - 10, y: bounds.midY - 3, width: 6, height: 6)
        if display.metadata?.progressKind != nil {
            NSColor(theme.floatingEmphasis.opacity(0.72)).setStroke()
            let path = NSBezierPath(ovalIn: rect.insetBy(dx: -0.5, dy: -0.5))
            path.lineWidth = 1.25
            path.stroke()
        } else if display.metadata?.readonly == true {
            let image = NSImage(systemSymbolName: "lock", accessibilityDescription: nil)
            image?.isTemplate = true
            NSColor.secondaryLabelColor.set()
            image?.draw(in: NSRect(x: rect.minX - 1, y: rect.minY - 2, width: 9, height: 9))
        }
    }

    private func drawCloseGlyph() {
        let closeHovering: Bool
        if let window {
            closeHovering = closeRect.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil))
        } else {
            closeHovering = false
        }
        if closeHovering {
            NSColor(theme.shellHoverFill.opacity(theme.usesDarkChrome ? 0.44 : 0.26)).setFill()
            NSBezierPath(ovalIn: closeRect).fill()
        }
        let image = NSImage(systemSymbolName: "xmark", accessibilityDescription: nil)
        image?.isTemplate = true
        NSColor(theme.shellChromeText.opacity(0.80)).set()
        image?.draw(in: closeRect.insetBy(dx: 4, dy: 4))
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        let movement = (notification.userInfo?["NSTextMovement"] as? NSNumber)?.intValue
        let cancelled = movement == NSCancelTextMovement
        if let display, !cancelled {
            let title = renameField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !title.isEmpty {
                model?.renameTerminal(display.id, title: title)
            }
        }
        renameField?.removeFromSuperview()
        renameField = nil
        needsDisplay = true
    }

    private func detailLabel(for display: TerminalTabDisplayModel) -> String? {
        guard let workingDirectory = display.metadata?.workingDirectory?.trimmingCharacters(in: .whitespacesAndNewlines),
              !workingDirectory.isEmpty else {
            return nil
        }
        let normalized = (workingDirectory as NSString).expandingTildeInPath
        let lastComponent = (normalized as NSString).lastPathComponent
        guard !lastComponent.isEmpty,
              lastComponent != "/",
              lastComponent != display.tab.title else {
            return nil
        }
        return lastComponent
    }

    private func helpText(for display: TerminalTabDisplayModel) -> String {
        var parts = [display.tab.title]
        if let detail = detailLabel(for: display) {
            parts.append(detail)
        }
        if display.metadata?.readonly == true {
            parts.append(L("只读", "Read Only"))
        }
        return parts.joined(separator: " · ")
    }

    private func dragPreviewImage() -> NSImage {
        let image = NSImage(size: bounds.size)
        image.lockFocus()
        draw(bounds)
        image.unlockFocus()
        return image
    }
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

private func draggedTerminalID(from pasteboard: NSPasteboard) -> TerminalID? {
    if let text = pasteboard.string(forType: terminalTabPasteboardType),
       let terminalID = terminalID(fromDroppedText: text) {
        return terminalID
    }
    if let text = pasteboard.string(forType: .string),
       let terminalID = terminalID(fromDroppedText: text) {
        return terminalID
    }
    return nil
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

private struct TerminalPaneSplitDropDelegate: DropDelegate {
    let paneID: PaneID
    let paneSize: CGSize
    let model: ConductorWindowModel

    func validateDrop(info: DropInfo) -> Bool {
        guard let draggedTerminalID = model.activeTerminalTabDragID,
              terminalTabDropProvider(in: info) != nil else { return false }
        return model.canPerformTerminalTabDrop(
            draggedTerminalID,
            targetPaneID: paneID,
            target: TerminalTabDropTarget.splitTarget(for: info.location, in: paneSize)
        )
    }

    func dropEntered(info: DropInfo) {
        updateTarget(info: info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard validateDrop(info: info) else { return nil }
        updateTarget(info: info)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        model.setTerminalTabDropTarget(forPane: paneID, target: nil)
    }

    func performDrop(info: DropInfo) -> Bool {
        model.setTerminalTabDropTarget(forPane: paneID, target: nil)
        guard validateDrop(info: info),
              let payloadProvider = terminalTabDropProvider(in: info) else { return false }
        let target = TerminalTabDropTarget.splitTarget(for: info.location, in: paneSize)
        payloadProvider.loadTerminalID { draggedTabID in
            guard let draggedTabID else { return }
            Task { @MainActor in
                model.performTerminalTabDrop(draggedTabID, targetPaneID: paneID, target: target)
            }
        }
        return true
    }

    private func updateTarget(info: DropInfo) {
        guard validateDrop(info: info) else {
            model.setTerminalTabDropTarget(forPane: paneID, target: nil)
            return
        }
        model.setTerminalTabDropTarget(
            forPane: paneID,
            target: TerminalTabDropTarget.splitTarget(for: info.location, in: paneSize)
        )
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
                            .accessibilityHidden(true)
                        Text(title)
                            .font(.conductorSystem(size: 10, weight: .medium, scale: fontScale))
                            .lineLimit(1)
                    }
                }
                Image(systemName: systemImage)
                    .font(.conductorSystem(size: 10, weight: .semibold, scale: fontScale))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(hovering ? theme.shellChromeText.opacity(0.92) : theme.shellChromeTextMuted)
            .padding(.horizontal, showsTitle ? 5 : 4)
            .frame(height: 18)
            .frame(minWidth: showsTitle ? nil : 19)
            .background(hovering ? theme.shellHoverFill.opacity(0.44) : (theme.usesDarkChrome ? Color.white.opacity(showsTitle ? 0.018 : 0.0) : theme.shellControlFill.opacity(0.34)))
            .clipShape(RoundedRectangle(cornerRadius: ConductorTokens.Radius.terminalTab, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: ConductorTokens.Radius.terminalTab, style: .continuous)
                    .stroke(hovering ? theme.shellStroke.opacity(0.30) : theme.shellStroke.opacity(0.12), lineWidth: 0.6)
            }
            .contentShape(RoundedRectangle(cornerRadius: ConductorTokens.Radius.terminalTab, style: .continuous))
        }
        .buttonStyle(ConductorPressButtonStyle())
        .accessibilityLabel(showsTitle ? title : help)
        .disabled(disabled)
        .opacity(disabled ? 0.35 : 1)
        .animation(ConductorMotion.micro, value: disabled)
        .conductorHover($hovering, animation: nil)
        .macNativeTooltip(help, enabled: !showsTitle)
    }
}
