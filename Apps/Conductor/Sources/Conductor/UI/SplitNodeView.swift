import ConductorCore
import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SplitNodeView: View {
    let node: SplitNode
    @ObservedObject var model: ConductorWindowModel
    var path: [SplitPathElement] = []

    var body: some View {
        switch node {
        case let .leaf(paneID):
            if let pane = model.workspace.panes[paneID] {
                TerminalPaneView(pane: pane, model: model)
                    .frame(minWidth: 180, minHeight: 150)
                    .transition(.opacity.combined(with: .scale(scale: 0.985)))
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
            .transition(.opacity)
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

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let divider = ConductorTokens.Space.splitGutter
            if axis == .horizontal {
                let available = max(1, size.width - divider)
                let minPane = min(180, available / 2)
                let firstWidth = min(max(minPane, available * fraction), available - minPane)
                HStack(spacing: 0) {
                    SplitNodeView(node: first, model: model, path: path + [.first])
                        .frame(width: firstWidth)
                    SplitDivider(
                        axis: axis,
                        active: dragStartFraction != nil,
                        onChanged: { value in
                            if dragStartFraction == nil {
                                dragStartFraction = fraction
                            }
                            let base = dragStartFraction ?? fraction
                            setSplitFractionDuringDrag(base + value.translation.width / max(1, available))
                        },
                        onEnded: { _ in
                            dragStartFraction = nil
                        },
                        onDoubleClick: {
                            ConductorMotion.perform(ConductorMotion.layout) {
                                model.equalizeSplits()
                            }
                        }
                    )
                    .frame(width: divider)
                    SplitNodeView(node: second, model: model, path: path + [.second])
                        .frame(width: available - firstWidth)
                }
            } else {
                let available = max(1, size.height - divider)
                let minPane = min(150, available / 2)
                let firstHeight = min(max(minPane, available * fraction), available - minPane)
                VStack(spacing: 0) {
                    SplitNodeView(node: first, model: model, path: path + [.first])
                        .frame(height: firstHeight)
                    SplitDivider(
                        axis: axis,
                        active: dragStartFraction != nil,
                        onChanged: { value in
                            if dragStartFraction == nil {
                                dragStartFraction = fraction
                            }
                            let base = dragStartFraction ?? fraction
                            setSplitFractionDuringDrag(base + value.translation.height / max(1, available))
                        },
                        onEnded: { _ in
                            dragStartFraction = nil
                        },
                        onDoubleClick: {
                            ConductorMotion.perform(ConductorMotion.layout) {
                                model.equalizeSplits()
                            }
                        }
                    )
                    .frame(height: divider)
                    SplitNodeView(node: second, model: model, path: path + [.second])
                        .frame(height: available - firstHeight)
                }
            }
        }
    }

    private func setSplitFractionDuringDrag(_ fraction: Double) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        transaction.animation = nil
        withTransaction(transaction) {
            model.setSplitFraction(path: path, fraction: fraction)
        }
    }
}

private struct SplitDivider: View {
    let axis: SplitAxis
    let active: Bool
    let onChanged: (DragGesture.Value) -> Void
    let onEnded: (DragGesture.Value) -> Void
    let onDoubleClick: () -> Void
    @State private var hovering = false

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.black.opacity(active ? 0.34 : 0.22))
            Rectangle()
                .fill(Color.white.opacity(active ? 0.080 : 0.035))

            Capsule()
                .fill(active || hovering ? Color.accentColor.opacity(0.82) : Color.white.opacity(0.105))
                .frame(width: axis == .horizontal ? 2 : nil, height: axis == .vertical ? 2 : nil)
                .frame(width: axis == .horizontal ? nil : 34, height: axis == .vertical ? nil : 34)
        }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged(onChanged)
                    .onEnded(onEnded)
            )
            .simultaneousGesture(
                TapGesture(count: 2).onEnded(onDoubleClick)
            )
            .onHover { isHovering in
                updateCursor(hovering: isHovering)
            }
            .animation(ConductorMotion.micro, value: active)
            .animation(ConductorMotion.micro, value: hovering)
            .onDisappear {
                if hovering {
                    hovering = false
                    NSCursor.pop()
                }
            }
            .help("拖拽调整分屏")
    }

    private func updateCursor(hovering isHovering: Bool) {
        guard hovering != isHovering else { return }
        hovering = isHovering
        if isHovering {
            (axis == .horizontal ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown).push()
        } else {
            NSCursor.pop()
        }
    }
}

private struct TerminalPaneView: View {
    let pane: PaneState
    @ObservedObject var model: ConductorWindowModel
    @State private var highlightedDropTabID: TerminalID?

    private var isFocused: Bool {
        model.workspace.focusedPaneID == pane.id
    }

    private var unreadCount: Int {
        model.notifications.snapshot.unreadCount(for: pane.id)
    }

    private var paneBorderColor: Color {
        if unreadCount > 0 {
            return model.theme.accent.opacity(0.72)
        }
        return isFocused ? model.theme.accent.opacity(0.82) : Color.white.opacity(0.075)
    }

    private var paneBorderWidth: CGFloat {
        if unreadCount > 0 {
            return 1.5
        }
        return isFocused ? 1.5 : 1
    }

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            selectedTerminal
        }
        .background(model.theme.terminalBackground)
        .overlay {
            Rectangle()
                .stroke(paneBorderColor, lineWidth: paneBorderWidth)
                .overlay {
                    if isFocused {
                        Rectangle()
                            .inset(by: 2)
                            .stroke(model.theme.accent.opacity(0.22), lineWidth: 1)
                    }
                }
                .allowsHitTesting(false)
        }
        .animation(ConductorMotion.micro, value: isFocused)
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

            PaneBarButton(systemImage: "plus", title: "新标签", showsTitle: false, help: "新标签 Cmd-Shift-T") {
                ConductorMotion.perform(ConductorMotion.layout) {
                    model.newTab(in: pane.id)
                }
            }

            PaneBarButton(
                systemImage: "xmark",
                title: "关闭",
                showsTitle: false,
                disabled: !model.workspace.canClosePane(pane.id),
                help: "关闭这个分屏 Cmd-Shift-W"
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
                model.theme.terminalChrome.opacity(0.96)
                LinearGradient(
                    colors: [
                        Color.white.opacity(isFocused ? 0.075 : 0.045),
                        Color.clear
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(isFocused ? model.theme.accent.opacity(0.82) : Color.white.opacity(0.045))
                .frame(height: isFocused ? 1.5 : 1)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(isFocused ? 0.080 : 0.045))
                .frame(height: 1)
        }
    }

    @ViewBuilder
    private var selectedTerminal: some View {
        if let selected = pane.selectedTab {
            TerminalSurfaceRepresentable(
                surface: model.surface(for: selected),
                theme: model.theme,
                isFocused: isFocused
            )
            .background(model.theme.terminalBackground)
            .transaction { transaction in
                transaction.disablesAnimations = true
                transaction.animation = nil
            }
            .onTapGesture {
                ConductorMotion.perform {
                    model.focusPane(pane.id)
                }
            }
        }
    }
}

private struct StableTerminalTabStrip: View {
    let pane: PaneState
    @ObservedObject var model: ConductorWindowModel
    let paneFocused: Bool
    @Binding var highlightedDropTabID: TerminalID?

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
            let text: String?
            if let data = item as? Data {
                text = String(data: data, encoding: .utf8)
            } else if let string = item as? String {
                text = string
            } else if let nsString = item as? NSString {
                text = nsString as String
            } else {
                text = nil
            }

            guard let text,
                  let uuid = UUID(uuidString: text.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                return
            }

            Task { @MainActor in
                let draggedTabID = TerminalID(uuid)
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

    var body: some View {
        Button {
            ConductorMotion.perform(action)
        } label: {
            ViewThatFits(in: .horizontal) {
                if showsTitle {
                    HStack(spacing: 4) {
                        Image(systemName: systemImage)
                            .font(.system(size: 9.5, weight: .semibold))
                        Text(title)
                            .font(.system(size: 10, weight: .medium))
                            .lineLimit(1)
                    }
                }
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(hovering ? Color.accentColor.opacity(0.96) : ConductorDesign.terminalTextMuted)
            .padding(.horizontal, showsTitle ? 5 : 4)
            .frame(height: 18)
            .frame(minWidth: showsTitle ? nil : 19)
            .background(hovering ? Color.accentColor.opacity(0.115) : Color.white.opacity(showsTitle ? 0.050 : 0.025))
            .clipShape(RoundedRectangle(cornerRadius: ConductorTokens.Radius.terminalTab, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: ConductorTokens.Radius.terminalTab, style: .continuous)
                    .stroke(hovering ? Color.accentColor.opacity(0.34) : Color.white.opacity(0.075), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: ConductorTokens.Radius.terminalTab, style: .continuous))
        }
        .buttonStyle(ConductorPressButtonStyle())
        .disabled(disabled)
        .opacity(disabled ? 0.35 : 1)
        .animation(ConductorMotion.micro, value: disabled)
        .animation(ConductorMotion.micro, value: hovering)
        .onHover { value in
            withAnimation(ConductorMotion.micro) {
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
    @ObservedObject var model: ConductorWindowModel
    let paneID: PaneID
    @State private var editingTitle = false
    @State private var titleDraft = ""
    @State private var hovering = false
    @State private var renameCancelled = false
    @FocusState private var titleFieldFocused: Bool

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
        if isSelected {
            return paneFocused ? model.theme.accent.opacity(0.18) : Color.white.opacity(0.070)
        }
        if hovering {
            return model.theme.accent.opacity(0.075)
        }
        return Color.white.opacity(0.026)
    }

    private var tabStroke: Color {
        if isDropTarget {
            return model.theme.accent.opacity(0.88)
        }
        if isSelected {
            return paneFocused ? model.theme.accent.opacity(0.58) : Color.white.opacity(0.18)
        }
        return Color.white.opacity(hovering ? 0.13 : 0.075)
    }

    var body: some View {
        HStack(spacing: 3) {
            if editingTitle {
                Image(systemName: "terminal")
                    .font(.system(size: 10))
                    .foregroundStyle(isSelected ? ConductorDesign.primaryText : ConductorDesign.terminalText)
                RenameTextField(
                    text: $titleDraft,
                    placeholder: "标签名称",
                    font: .monospacedSystemFont(ofSize: 10.5, weight: isSelected ? .semibold : .medium),
                    textColor: NSColor.labelColor,
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
                        .font(.system(size: 10))
                        .foregroundStyle(isSelected && paneFocused ? model.theme.accent : ConductorDesign.terminalTextMuted)
                    Text(tab.title)
                        .font(isSelected ? ConductorTokens.Typography.terminalTabSelected : ConductorTokens.Typography.terminalTab)
                        .foregroundStyle(isSelected ? ConductorDesign.terminalText : ConductorDesign.terminalTextMuted)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if unreadCount > 0 || (metadata?.unreadCount ?? 0) > 0 {
                        Circle()
                            .fill(model.theme.accent)
                            .frame(width: 6, height: 6)
                    } else if metadata?.progressKind != nil {
                        Circle()
                            .stroke(model.theme.accent, lineWidth: 1.5)
                            .frame(width: 7, height: 7)
                    } else if metadata?.readonly == true {
                        Image(systemName: "lock")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(tab.title)
            }

            if !editingTitle {
                Button {
                    ConductorMotion.perform(ConductorMotion.layout) {
                        model.closeTab(tab.id, in: paneID)
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(hovering || isSelected ? ConductorDesign.terminalText.opacity(0.88) : ConductorDesign.terminalTextMuted.opacity(0.78))
                        .frame(width: 13, height: 13)
                        .background(hovering ? Color.white.opacity(0.075) : Color.clear)
                        .clipShape(Circle())
                }
                .buttonStyle(ConductorPressButtonStyle())
                .help("关闭标签")
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
        .background(tabFill)
        .clipShape(RoundedRectangle(cornerRadius: ConductorTokens.Radius.terminalTab, style: .continuous))
        .overlay(alignment: .bottom) {
            if isSelected {
                Rectangle()
                    .fill(paneFocused ? model.theme.accent.opacity(0.96) : Color.white.opacity(0.30))
                    .frame(height: 2)
                    .padding(.horizontal, 8)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: ConductorTokens.Radius.terminalTab, style: .continuous)
                .stroke(tabStroke, lineWidth: isDropTarget || isSelected ? 1.2 : 1)
        }
        .animation(nil, value: isSelected)
        .animation(ConductorMotion.micro, value: hovering)
        .animation(ConductorMotion.micro, value: isDropTarget)
        .animation(ConductorMotion.standard, value: editingTitle)
        .animation(ConductorMotion.emphasized, value: unreadCount)
        .animation(ConductorMotion.standard, value: metadata?.progressKind)
        .onHover { value in
            withAnimation(ConductorMotion.micro) {
                hovering = value
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: ConductorTokens.Radius.terminalTab))
        .simultaneousGesture(
            TapGesture(count: 1).onEnded {
                model.selectTab(tab.id, in: paneID)
            }
        )
        .onDrag {
            model.selectTab(tab.id, in: paneID)
            return NSItemProvider(object: tab.id.description as NSString)
        }
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                ConductorMotion.perform {
                    beginRename()
                }
            }
        )
        .contextMenu {
            Button("重命名标签...") {
                ConductorMotion.perform {
                    beginRename()
                }
            }
            if tab.userTitle != nil {
                Button("恢复终端标题") {
                    ConductorMotion.perform {
                        model.clearUserTerminalTitle(tab.id)
                    }
                }
            }
            Button("复制标签") {
                ConductorMotion.perform(ConductorMotion.layout) {
                    model.duplicateTab(tab.id, in: paneID)
                }
            }
            Divider()
            Button("关闭标签") {
                ConductorMotion.perform(ConductorMotion.layout) {
                    model.closeTab(tab.id, in: paneID)
                }
            }
            Button("关闭其他标签") {
                ConductorMotion.perform(ConductorMotion.layout) {
                    model.selectTab(tab.id, in: paneID)
                    model.closeOtherTabs(in: paneID)
                }
            }
            .disabled(!model.workspace.canCloseOtherTabs(in: paneID))
            Button("关闭右侧标签") {
                ConductorMotion.perform(ConductorMotion.layout) {
                    model.selectTab(tab.id, in: paneID)
                    model.closeTabsToRight(in: paneID)
                }
            }
            .disabled(!model.workspace.canCloseTabsToRight(of: tab.id, in: paneID))
            Divider()
            Button("标签左移") {
                ConductorMotion.perform(ConductorMotion.layout) {
                    model.selectTab(tab.id, in: paneID)
                    model.moveSelectedTabLeft()
                }
            }
            .disabled(tabIndex == nil || tabIndex == 0)
            Button("标签右移") {
                ConductorMotion.perform(ConductorMotion.layout) {
                    model.selectTab(tab.id, in: paneID)
                    model.moveSelectedTabRight()
                }
            }
            .disabled(tabIndex == nil || tabIndex == tabCount - 1)
            Divider()
            Button("移动到下一个分屏") {
                ConductorMotion.perform(ConductorMotion.layout) {
                    model.selectTab(tab.id, in: paneID)
                    model.moveSelectedTabToNextPane()
                }
            }
            .disabled(!canMoveTargetTabToNextPane)
            Button("移动到右侧新分屏") {
                ConductorMotion.perform(ConductorMotion.layout) {
                    model.selectTab(tab.id, in: paneID)
                    model.moveSelectedTabToNewSplit(.right)
                }
            }
            .disabled(!canMoveTargetTabToNewSplit)
            Button("移动到下方新分屏") {
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
        ConductorMotion.perform {
            model.renameTerminal(tab.id, title: titleDraft)
            editingTitle = false
        }
    }

    private func cancelRename() {
        ConductorMotion.perform {
            editingTitle = false
        }
    }
}
