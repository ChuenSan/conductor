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
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                StableTerminalTabStrip(
                    pane: pane,
                    snapshot: snapshot,
                    model: model,
                    highlightedDropTabID: $highlightedDropTabID
                )
                .frame(minWidth: 64, maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)

                Button {
                    ConductorMotion.perform(ConductorMotion.layout) {
                        model.closePane(pane.id)
                    }
                } label: {
                    Label(L("关闭", "Close"), systemImage: "xmark")
                        .labelStyle(.iconOnly)
                        .frame(width: 19, height: 18)
                }
                .buttonStyle(.borderless)
                .controlSize(.mini)
                .foregroundStyle(.secondary)
                .disabled(!snapshot.canClosePane)
                .opacity(snapshot.canClosePane ? 1 : 0.35)
                .accessibilityLabel(L("关闭", "Close"))
                .help("\(L("关闭这个分屏", "Close this pane")) \(model.shortcutTitle(for: .closeFocusedPane, fallback: "Cmd-Shift-W"))")
            }
            .padding(.leading, 12)
            .padding(.trailing, 8)
            .frame(height: max(0, snapshot.appearance.density.paneTabRailHeight - 1))
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(ConductorTokens.Chrome.separator(dark: snapshot.theme.usesDarkChrome))
                    .frame(height: 1)
                    .opacity(isFocused ? 1 : 0.55)
            }
        }
        .background(.regularMaterial)
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
                    .fill(ConductorTokens.Chrome.dropTargetFill(dark: theme.usesDarkChrome))
                    .overlay {
                        Rectangle()
                            .stroke(ConductorTokens.Chrome.dropTargetStroke(dark: theme.usesDarkChrome), lineWidth: 1)
                    }
            } else {
                ZStack(alignment: target.alignment) {
                    Color.clear
                    Rectangle()
                        .fill(ConductorTokens.Chrome.dropTargetFill(dark: theme.usesDarkChrome))
                        .overlay {
                            Rectangle()
                                .stroke(ConductorTokens.Chrome.dropTargetStroke(dark: theme.usesDarkChrome), lineWidth: 1)
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
    @Environment(\.conductorTheme) private var theme

    var body: some View {
        RoundedRectangle(cornerRadius: ConductorTokens.Radius.terminalPane, style: .continuous)
            .stroke(color.opacity(visible ? (theme.usesDarkChrome ? ConductorTokens.Chrome.focusRingOpacityDark : ConductorTokens.Chrome.focusRingOpacity) : 0), lineWidth: 2)
            .padding(1)
    }
}

private let terminalTabDragType = UTType(exportedAs: "app.conductor.terminal-tab")
private let terminalTabDropTypes: [UTType] = [terminalTabDragType, .plainText]
private let terminalTabDragPrefix = "terminal:"

private struct StableTerminalTabStrip: View {
    let pane: PaneState
    let snapshot: TerminalPaneChromeSnapshot
    let model: ConductorWindowModel
    @Binding var highlightedDropTabID: TerminalID?

    @State private var scrollTargetID: TerminalID?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 3) {
                ForEach(snapshot.tabs) { display in
                    TerminalTabChip(
                        display: display,
                        selected: display.id == pane.selectedTabID,
                        paneFocused: snapshot.paneFocused,
                        highlighted: highlightedDropTabID == display.id,
                        paneID: pane.id,
                        model: model,
                        theme: snapshot.theme,
                        density: snapshot.appearance.density,
                        fontScale: snapshot.appearance.fontScale
                    )
                    .id(display.id)
                    .onDrag {
                        terminalTabItemProvider(for: display.id, model: model, paneID: pane.id)
                    } preview: {
                        TerminalTabChipPreview(
                            display: display,
                            theme: snapshot.theme,
                            fontScale: snapshot.appearance.fontScale
                        )
                    }
                    .onDrop(
                        of: terminalTabDropTypes,
                        delegate: TerminalTabReorderDropDelegate(
                            paneID: pane.id,
                            targetTabID: display.id,
                            model: model,
                            highlightedDropTabID: $highlightedDropTabID
                        )
                    )
                }
            }
            .scrollTargetLayout()
            .onDrop(
                of: terminalTabDropTypes,
                delegate: TerminalTabReorderDropDelegate(
                    paneID: pane.id,
                    targetTabID: nil,
                    model: model,
                    highlightedDropTabID: $highlightedDropTabID
                )
            )
        }
        .scrollPosition(id: $scrollTargetID, anchor: .center)
        .onAppear {
            scrollTargetID = pane.selectedTabID
        }
        .onChange(of: pane.selectedTabID) { _, newValue in
            scrollTargetID = newValue
        }
    }
}

private struct TerminalTabChip: View {
    let display: TerminalTabDisplayModel
    let selected: Bool
    let paneFocused: Bool
    let highlighted: Bool
    let paneID: PaneID
    let model: ConductorWindowModel
    let theme: TerminalTheme
    let density: AppearanceDensity
    let fontScale: AppearanceFontScale

    private var detailLabel: String? {
        terminalTabDetailLabel(for: display)
    }

    private var titleText: String {
        if selected, let detailLabel {
            "\(display.tab.title) · \(detailLabel)"
        } else {
            display.tab.title
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Button {
                model.selectTab(display.id, in: paneID)
            } label: {
                Label {
                    HStack(spacing: 4) {
                        Text(titleText)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        statusIcon
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } icon: {
                    Image(systemName: "terminal")
                }
            }
            .labelStyle(.titleAndIcon)
            .buttonStyle(.borderless)
            .foregroundStyle(selected ? theme.shellChromeText.opacity(0.92) : theme.shellChromeTextMuted.opacity(0.72))
            .font(.conductorSystem(size: 10.8, weight: selected ? .semibold : .medium, scale: fontScale))
            .accessibilityLabel(accessibilityTitle)

            if selected {
                Button {
                    model.closeTab(display.id, in: paneID)
                } label: {
                    Label(L("关闭终端", "Close Terminal"), systemImage: "xmark")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .controlSize(.mini)
                .accessibilityLabel(L("关闭终端", "Close Terminal"))
                .help(L("关闭终端", "Close Terminal"))
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, selected ? 4 : 8)
        .frame(width: density.paneTabWidth, height: max(18, density.paneTabHeight), alignment: .leading)
        .background(tabBackground, in: RoundedRectangle(cornerRadius: ConductorTokens.Radius.terminalTab, style: .continuous))
        .overlay {
            if highlighted {
                RoundedRectangle(cornerRadius: ConductorTokens.Radius.terminalTab, style: .continuous)
                    .stroke(ConductorTokens.Chrome.focusRing(dark: theme.usesDarkChrome), lineWidth: 1.2)
            }
        }
        .contentShape(Rectangle())
        .contextMenu {
            terminalContextMenu
        }
        .help(helpText)
    }

    private var tabBackground: Color {
        if selected {
            return theme.floatingSelectedFill.opacity(paneFocused ? 1.0 : 0.72)
        }
        if highlighted {
            return ConductorTokens.Chrome.dropTargetFill(dark: theme.usesDarkChrome)
        }
        return Color.clear
    }

    @ViewBuilder
    private var statusIcon: some View {
        if display.metadata?.progressKind != nil {
            Label(L("终端任务进行中", "Terminal task in progress"), systemImage: "arrow.triangle.2.circlepath")
                .labelStyle(.iconOnly)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(theme.floatingEmphasis.opacity(0.72))
                .accessibilityHidden(true)
        } else if display.metadata?.readonly == true {
            Label(L("只读终端", "Read-only terminal"), systemImage: "lock")
                .labelStyle(.iconOnly)
                .font(.system(size: 8.5, weight: .medium))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var terminalContextMenu: some View {
        Button(L("重命名当前终端...", "Rename Current Terminal...")) {
            perform(.renameTerminal)
        }
        if display.tab.userTitle != nil {
            Button(L("恢复终端标题", "Restore Terminal Title")) {
                perform(.restoreTerminalTitle)
            }
        }
        Button(L("复制当前终端", "Duplicate Current Terminal")) {
            perform(.duplicateTerminal)
        }
        Button(L("上下文搜索", "Context Search")) {
            perform(.showSearch)
        }
        Button(L("浏览当前目录", "Browse Current Directory")) {
            perform(.showFileManager)
        }
        .disabled(detailLabel == nil)
        Button(L("打开当前目录", "Open Current Directory")) {
            perform(.openDirectory)
        }
        .disabled(detailLabel == nil)
        Button(L("复制当前目录路径", "Copy Current Directory Path")) {
            perform(.copyDirectory)
        }
        .disabled(detailLabel == nil)

        Divider()

        Button(L("新开终端", "New Terminal")) {
            perform(.newTerminal)
        }
        Button(L("从当前目录新开终端", "New Terminal at Current Directory")) {
            perform(.newTerminalAtDirectory)
        }
        .disabled(detailLabel == nil)
        Button(L("向右分屏", "Split Right")) {
            perform(.splitRight)
        }
        .disabled(!display.workspaceCanSplit)
        Button(L("向下分屏", "Split Down")) {
            perform(.splitDown)
        }
        .disabled(!display.workspaceCanSplit)
        Button(L("关闭当前分屏", "Close Current Pane")) {
            perform(.closePane)
        }
        .disabled(display.workspacePaneCount <= 1)

        Divider()

        Button(L("关闭当前终端", "Close Current Terminal")) {
            perform(.closeTerminal)
        }
        Button(L("关闭其他终端", "Close Other Terminals")) {
            perform(.closeOtherTerminals)
        }
        .disabled(!display.canCloseOtherTabs)
        Button(L("关闭右侧终端", "Close Terminals to the Right")) {
            perform(.closeTerminalsToRight)
        }
        .disabled(!display.canCloseTabsToRight)

        Divider()

        Button(L("重命名当前工作区...", "Rename Current Workspace...")) {
            perform(.renameWorkspace)
        }
        Button(L("复制当前工作区", "Duplicate Current Workspace")) {
            perform(.duplicateWorkspace)
        }
        Button(L("关闭当前工作区", "Close Current Workspace")) {
            perform(.closeWorkspace)
        }
        .disabled(display.workspacePaneCount <= 0)
    }

    private var accessibilityTitle: String {
        var parts = [display.tab.title]
        if let detailLabel {
            parts.append(detailLabel)
        }
        if display.metadata?.readonly == true {
            parts.append(L("只读", "Read Only"))
        }
        return parts.joined(separator: ", ")
    }

    private var helpText: String {
        var parts = [display.tab.title]
        if let detailLabel {
            parts.append(detailLabel)
        }
        if display.metadata?.readonly == true {
            parts.append(L("只读", "Read Only"))
        }
        return parts.joined(separator: " · ")
    }

    private func perform(_ action: TerminalContextMenuAction) {
        _ = model.performTerminalContextMenuAction(action, terminalID: display.id)
    }
}

private struct TerminalTabChipPreview: View {
    let display: TerminalTabDisplayModel
    let theme: TerminalTheme
    let fontScale: AppearanceFontScale

    var body: some View {
        Label(display.tab.title, systemImage: "terminal")
            .font(.conductorSystem(size: 10.8, weight: .semibold, scale: fontScale))
            .foregroundStyle(theme.shellChromeText)
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: ConductorTokens.Radius.terminalTab, style: .continuous))
    }
}

private struct TerminalTabReorderDropDelegate: DropDelegate {
    let paneID: PaneID
    let targetTabID: TerminalID?
    let model: ConductorWindowModel
    @Binding var highlightedDropTabID: TerminalID?

    func validateDrop(info: DropInfo) -> Bool {
        model.hasActiveTerminalTabDrag() && terminalTabDropProvider(in: info) != nil
    }

    func dropEntered(info: DropInfo) {
        highlightedDropTabID = targetTabID
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard validateDrop(info: info) else { return nil }
        highlightedDropTabID = targetTabID
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        highlightedDropTabID = nil
    }

    func performDrop(info: DropInfo) -> Bool {
        highlightedDropTabID = nil
        guard validateDrop(info: info),
              let payloadProvider = terminalTabDropProvider(in: info) else { return false }
        payloadProvider.loadTerminalID { draggedTabID in
            guard let draggedTabID else { return }
            Task { @MainActor in
                if let targetTabID, targetTabID != draggedTabID {
                    model.moveTab(draggedTabID, before: targetTabID, in: paneID)
                } else {
                    model.moveTabToEnd(draggedTabID, in: paneID)
                }
                model.endTerminalTabDrag()
            }
        }
        return true
    }
}

@MainActor
private func terminalTabItemProvider(for terminalID: TerminalID, model: ConductorWindowModel, paneID: PaneID) -> NSItemProvider {
    model.selectTab(terminalID, in: paneID)
    model.beginTerminalTabDrag(terminalID)
    let payload = "\(terminalTabDragPrefix)\(terminalID.description)"
    let provider = NSItemProvider(object: payload as NSString)
    provider.registerDataRepresentation(forTypeIdentifier: terminalTabDragType.identifier, visibility: .all) { completion in
        completion(payload.data(using: .utf8), nil)
        return nil
    }
    return provider
}

private func terminalTabDetailLabel(for display: TerminalTabDisplayModel) -> String? {
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
