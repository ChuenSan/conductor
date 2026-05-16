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
                            model.setSplitFraction(path: path, fraction: base + value.translation.width / max(1, available))
                        },
                        onEnded: { _ in
                            dragStartFraction = nil
                        },
                        onDoubleClick: {
                            model.equalizeSplits()
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
                            model.setSplitFraction(path: path, fraction: base + value.translation.height / max(1, available))
                        },
                        onEnded: { _ in
                            dragStartFraction = nil
                        },
                        onDoubleClick: {
                            model.equalizeSplits()
                        }
                    )
                    .frame(height: divider)
                    SplitNodeView(node: second, model: model, path: path + [.second])
                        .frame(height: available - firstHeight)
                }
            }
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
        Rectangle()
            .fill(ConductorDesign.splitGutter)
            .overlay {
                Capsule()
                    .fill(active || hovering ? Color.accentColor.opacity(0.70) : Color.white.opacity(0.045))
                    .frame(width: axis == .horizontal ? 2 : nil, height: axis == .vertical ? 2 : nil)
                    .frame(width: axis == .horizontal ? nil : 32, height: axis == .vertical ? nil : 32)
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

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            selectedTerminal
        }
        .background(model.theme.terminalBackground)
        .overlay {
            Rectangle()
                .stroke(
                    unreadCount > 0 ? model.theme.accent.opacity(0.82) : (isFocused ? model.theme.accent.opacity(0.48) : Color.white.opacity(0.035)),
                    lineWidth: unreadCount > 0 ? 1.5 : 1
                )
                .allowsHitTesting(false)
        }
    }

    private var tabBar: some View {
        HStack(spacing: 3) {
            StableTerminalTabStrip(
                pane: pane,
                model: model,
                highlightedDropTabID: $highlightedDropTabID
            )
            .frame(minWidth: 64, maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)

            PaneBarButton(systemImage: "plus", title: "新标签", showsTitle: false, help: "新标签 Cmd-Shift-T") {
                model.newTab(in: pane.id)
            }

            PaneFocusBadge(title: "当前", active: isFocused, accent: model.theme.accent)

            PaneBarButton(
                systemImage: "xmark",
                title: "关闭",
                showsTitle: false,
                disabled: !model.workspace.canClosePane(pane.id),
                help: "关闭这个分屏 Cmd-Shift-W"
            ) {
                model.closePane(pane.id)
            }
        }
        .padding(.horizontal, 4)
        .frame(height: 25)
        .background(ConductorDesign.terminalChrome.opacity(0.98))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.055))
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
            .onTapGesture {
                model.focusPane(pane.id)
            }
        }
    }
}

private struct StableTerminalTabStrip: View {
    let pane: PaneState
    @ObservedObject var model: ConductorWindowModel
    @Binding var highlightedDropTabID: TerminalID?

    private let tabWidth: CGFloat = 112
    private let tabSpacing: CGFloat = 3

    private var tabIDs: [TerminalID] {
        pane.tabs.map(\.id)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: tabSpacing) {
                    ForEach(pane.tabs) { tab in
                        tabView(for: tab)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
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
        .frame(height: 21)
        .clipped()
    }

    private func scrollToSelectedTab(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.12)) {
            proxy.scrollTo(pane.selectedTabID, anchor: .trailing)
        }
    }

    private func tabView(for tab: TerminalTabState) -> some View {
        TerminalTabButton(
            tab: tab,
            isSelected: tab.id == pane.selectedTabID,
            isDropTarget: highlightedDropTabID == tab.id,
            metadata: model.metadataByTerminalID[tab.id],
            unreadCount: model.notifications.snapshot.unreadCount(for: tab.id),
            model: model,
            paneID: pane.id
        )
        .frame(width: tabWidth)
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
                if let targetTabID {
                    model.moveTab(draggedTabID, before: targetTabID, in: paneID)
                } else {
                    model.moveTabToEnd(draggedTabID, in: paneID)
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
        Button(action: action) {
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
            .foregroundStyle(ConductorDesign.terminalTextMuted)
            .padding(.horizontal, showsTitle ? 5 : 4)
            .frame(height: 18)
            .frame(minWidth: showsTitle ? nil : 18)
            .background(hovering ? Color.white.opacity(0.08) : (showsTitle ? Color.white.opacity(0.055) : Color.clear))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.35 : 1)
        .onHover { hovering = $0 }
        .help(help)
    }
}

private struct PaneFocusBadge: View {
    let title: String
    let active: Bool
    let accent: Color

    var body: some View {
        ViewThatFits(in: .horizontal) {
            if active {
                HStack(spacing: 4) {
                    Circle()
                        .fill(accent)
                        .frame(width: 5, height: 5)
                    Text(title)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(ConductorDesign.terminalText)
                }
            }
            Circle()
                .fill(active ? accent : ConductorDesign.terminalTextMuted.opacity(0.55))
                .frame(width: 5, height: 5)
        }
        .padding(.horizontal, active ? 5 : 3)
        .frame(height: 18)
        .background(active ? accent.opacity(0.10) : Color.clear)
        .clipShape(Capsule())
        .help(active ? "当前分屏" : "未聚焦分屏")
    }
}

private struct TerminalTabButton: View {
    let tab: TerminalTabState
    let isSelected: Bool
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
                        .foregroundStyle(isSelected ? ConductorDesign.primaryText : ConductorDesign.terminalTextMuted)
                    Text(tab.title)
                        .font(isSelected ? ConductorTokens.Typography.terminalTabSelected : ConductorTokens.Typography.terminalTab)
                        .foregroundStyle(isSelected ? ConductorDesign.primaryText : ConductorDesign.terminalTextMuted)
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

            Button {
                model.closeTab(tab.id, in: paneID)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(isSelected ? ConductorDesign.tertiaryText : ConductorDesign.terminalTextMuted)
                    .frame(width: 12, height: 12)
            }
            .buttonStyle(.plain)
            .help("关闭标签")
        }
        .padding(.leading, 7)
        .padding(.trailing, 4)
        .frame(height: 21)
        .frame(minWidth: 64, idealWidth: 94, maxWidth: 118)
        .background(isSelected ? ConductorDesign.terminalChromeSelected : (hovering ? Color.white.opacity(0.07) : Color.clear))
        .clipShape(RoundedRectangle(cornerRadius: ConductorTokens.Radius.terminalTab))
        .overlay {
            if isDropTarget {
                RoundedRectangle(cornerRadius: ConductorTokens.Radius.terminalTab)
                    .stroke(model.theme.accent.opacity(0.85), lineWidth: 1.5)
            } else if isSelected {
                RoundedRectangle(cornerRadius: ConductorTokens.Radius.terminalTab)
                    .stroke(model.theme.accent.opacity(0.24), lineWidth: 1)
            }
        }
        .shadow(
            color: isSelected ? ConductorDesign.shadow(ConductorTokens.Shadow.selectedOpacity) : .clear,
            radius: ConductorTokens.Shadow.selectedRadius,
            y: ConductorTokens.Shadow.selectedY
        )
        .onHover { hovering = $0 }
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
                beginRename()
            }
        )
        .contextMenu {
            Button("重命名标签...") {
                beginRename()
            }
            if tab.userTitle != nil {
                Button("恢复终端标题") {
                    model.clearUserTerminalTitle(tab.id)
                }
            }
            Button("复制标签") {
                model.duplicateTab(tab.id, in: paneID)
            }
            Divider()
            Button("关闭标签") {
                model.closeTab(tab.id, in: paneID)
            }
            Button("关闭其他标签") {
                model.selectTab(tab.id, in: paneID)
                model.closeOtherTabs(in: paneID)
            }
            .disabled(!model.workspace.canCloseOtherTabs(in: paneID))
            Button("关闭右侧标签") {
                model.selectTab(tab.id, in: paneID)
                model.closeTabsToRight(in: paneID)
            }
            .disabled(!model.workspace.canCloseTabsToRight(of: tab.id, in: paneID))
            Divider()
            Button("标签左移") {
                model.selectTab(tab.id, in: paneID)
                model.moveSelectedTabLeft()
            }
            .disabled(tabIndex == nil || tabIndex == 0)
            Button("标签右移") {
                model.selectTab(tab.id, in: paneID)
                model.moveSelectedTabRight()
            }
            .disabled(tabIndex == nil || tabIndex == tabCount - 1)
            Divider()
            Button("移动到下一个分屏") {
                model.selectTab(tab.id, in: paneID)
                model.moveSelectedTabToNextPane()
            }
            .disabled(!canMoveTargetTabToNextPane)
            Button("移动到右侧新分屏") {
                model.selectTab(tab.id, in: paneID)
                model.moveSelectedTabToNewSplit(.right)
            }
            .disabled(!canMoveTargetTabToNewSplit)
            Button("移动到下方新分屏") {
                model.selectTab(tab.id, in: paneID)
                model.moveSelectedTabToNewSplit(.down)
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
        model.renameTerminal(tab.id, title: titleDraft)
        editingTitle = false
    }

    private func cancelRename() {
        editingTitle = false
    }
}
