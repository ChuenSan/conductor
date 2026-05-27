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
        self.theme = theme
        self.appearance = appearance
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

struct TerminalTabDisplayModel: Identifiable, Equatable {
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

private struct StableTerminalTabStrip: View {
    let pane: PaneState
    let snapshot: TerminalPaneChromeSnapshot
    let model: ConductorWindowModel
    @Binding var highlightedDropTabID: TerminalID?
    @Namespace private var selectionNamespace
    @State private var scrollTargetID: TerminalID?
    @State private var visualSelectedTabID: TerminalID?

    private let tabSpacing: CGFloat = 3
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
            ConductorMotion.withoutAnimation(action)
            return
        }
        ConductorMotion.perform(animation, action)
    }
}

private let terminalTabDragType = UTType(exportedAs: "app.conductor.terminal-tab")
private let terminalTabDropTypes: [UTType] = [terminalTabDragType]
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
            .background(hovering ? theme.shellHoverFill : (theme.usesDarkChrome ? Color.white.opacity(showsTitle ? 0.050 : 0.025) : theme.shellControlFill))
            .clipShape(RoundedRectangle(cornerRadius: ConductorTokens.Radius.terminalTab, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: ConductorTokens.Radius.terminalTab, style: .continuous)
                    .stroke(hovering ? theme.shellStroke.opacity(0.72) : theme.shellStroke.opacity(0.42), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: ConductorTokens.Radius.terminalTab, style: .continuous))
        }
        .buttonStyle(ConductorPressButtonStyle())
        .accessibilityLabel(showsTitle ? title : help)
        .disabled(disabled)
        .opacity(disabled ? 0.35 : 1)
        .animation(ConductorMotion.micro, value: disabled)
        .animation(ConductorMotion.hover, value: hovering)
        .conductorHover($hovering)
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
        if hovering {
            return theme.shellHoverFill.opacity(theme.usesDarkChrome ? 0.36 : 0.18)
        }
        return Color.clear
    }

    private var selectedFill: Color {
        theme.shellPanelStrong.opacity(paneFocused ? (theme.usesDarkChrome ? 0.66 : 0.78) : (theme.usesDarkChrome ? 0.52 : 0.64))
    }

    private var tabStroke: Color {
        if isDropTarget {
            return theme.floatingSelectedStroke.opacity(0.95)
        }
        if isSelected {
            return theme.shellStroke.opacity(paneFocused ? (theme.usesDarkChrome ? 0.45 : 0.28) : 0.22)
        }
        return theme.shellStroke.opacity(hovering ? 0.12 : 0.0)
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
                    .accessibilityHidden(true)
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
                TerminalTabDragHandle(
                    visible: hovering || isSelected || display.isDragging,
                    dragging: display.isDragging
                ) {
                    ConductorMotion.withoutAnimation {
                        model.selectTab(tab.id, in: paneID)
                    }
                    model.beginTerminalTabDrag(tab.id)
                    return terminalTabDragPayload(for: tab.id)
                }

                Button {
                    onVisualSelect()
                    ConductorMotion.withoutAnimation {
                        model.selectTab(tab.id, in: paneID)
                    }
                } label: {
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
                    .opacity(isSelected ? 1.0 : (hovering ? 0.90 : 0.65))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(terminalHelpText)
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
                .accessibilityLabel(L("关闭标签", "Close Tab"))
                .macNativeTooltip(L("关闭标签", "Close Tab"))
            }
        }
        .padding(.leading, editingTitle ? 9 : 3)
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
                        .shadow(color: Color.black.opacity(theme.usesDarkChrome ? 0.12 : 0.03), radius: 2.2, y: 1.0)
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
        .conductorHover($hovering)
        .contentShape(RoundedRectangle(cornerRadius: ConductorTokens.Radius.terminalTab))
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

private struct TerminalTabDragHandle: View {
    let visible: Bool
    let dragging: Bool
    let payload: () -> NSItemProvider
    @Environment(\.conductorTheme) private var theme

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(theme.shellHoverFill.opacity(visible ? (dragging ? 0.34 : 0.16) : 0.001))

            VStack(spacing: 2.6) {
                ForEach(0..<3, id: \.self) { _ in
                    HStack(spacing: 2.6) {
                        dragDot
                        dragDot
                    }
                }
            }
        }
        .frame(width: 20, height: 24)
        .foregroundStyle(theme.shellChromeTextMuted.opacity(visible ? (dragging ? 0.86 : 0.58) : 0.24))
        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .macNativeTooltip(L("拖动标签", "Drag Tab"))
        .accessibilityLabel(L("拖动标签", "Drag Tab"))
        .onDrag(payload)
        .animation(ConductorMotion.hover, value: visible)
        .animation(ConductorMotion.dragPreview, value: dragging)
    }

    private var dragDot: some View {
        Circle()
            .frame(width: 2.45, height: 2.45)
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
                .accessibilityHidden(true)
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
