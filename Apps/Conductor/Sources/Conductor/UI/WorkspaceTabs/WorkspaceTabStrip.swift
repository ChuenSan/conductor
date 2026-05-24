import AppKit
import ConductorCore
import SwiftUI
import UniformTypeIdentifiers

private func withoutShellAnimation(_ action: () -> Void) {
    ConductorMotion.withoutAnimation(action)
}

private func L(_ zh: String, _ en: String) -> String {
    ConductorLocalization.text(zh: zh, en: en)
}

struct WorkspaceTabStrip: View {
    let model: ConductorWindowModel
    let snapshot: WorkspaceChromeSnapshot
    let appearance: AppearancePreferences
    @Binding var editingWorkspaceID: WorkspaceID?
    @Binding var workspaceTitleDraft: String
    let onBeginRename: (WorkspaceChromeDisplayModel) -> Void
    let onCommitRename: () -> Void
    let onCancelRename: () -> Void
    @Namespace private var selectionNamespace
    @State private var scrollTargetID: WorkspaceID?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: WorkspaceTabMetrics.spacing) {
                ForEach(snapshot.rows) { row in
                    workspaceTabView(for: row)
                        .transition(ConductorMotion.tabTransition)
                }

                if !snapshot.fileTabs.isEmpty || !snapshot.webTabs.isEmpty {
                    WorkspaceTabSectionDivider()
                    ForEach(snapshot.fileTabs) { fileTab in
                        WorkspaceFileTopTab(
                            tab: fileTab.tab,
                            appearance: appearance,
                            selected: fileTab.selected,
                            dirty: fileTab.dirty,
                            onSelect: {
                                finishWorkspaceRenameIfNeeded()
                                model.selectWorkspaceFileTab(fileTab.id)
                            },
                            onClose: {
                                withoutShellAnimation {
                                    finishWorkspaceRenameIfNeeded()
                                    model.closeWorkspaceFileTab(fileTab.tab)
                                }
                            }
                        )
                        .transition(ConductorMotion.tabTransition)
                    }
                    ForEach(snapshot.webTabs) { webTab in
                        WorkspaceWebTopTab(
                            tab: webTab.tab,
                            appearance: appearance,
                            selected: webTab.selected,
                            onSelect: {
                                finishWorkspaceRenameIfNeeded()
                                model.selectWorkspaceWebTab(webTab.id)
                            },
                            onClose: {
                                withoutShellAnimation {
                                    finishWorkspaceRenameIfNeeded()
                                    model.closeWorkspaceWebTab(webTab.tab)
                                }
                            }
                        )
                        .transition(ConductorMotion.tabTransition)
                    }
                }
            }
            .padding(.horizontal, WorkspaceTabMetrics.edgePadding)
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $scrollTargetID, anchor: .center)
        .onAppear {
            syncScrollTarget(animated: false)
        }
        .onChange(of: snapshot.selectedWorkspaceID) {
            syncScrollTarget(animated: true)
        }
        .onChange(of: snapshot.workspaceIDs) {
            syncScrollTarget(animated: true)
        }
        .frame(
            minWidth: WorkspaceTabMetrics.width(for: appearance),
            maxWidth: .infinity,
            minHeight: WorkspaceTabMetrics.height(for: appearance),
            maxHeight: WorkspaceTabMetrics.height(for: appearance),
            alignment: .leading
        )
        .clipped()
        .mask(ConductorHorizontalFadeMask())
        .animation(model.shellAnimation(ConductorMotion.list), value: snapshot.workspaceIDs)
    }

    private func syncScrollTarget(animated: Bool) {
        guard snapshot.workspaceIDs.contains(snapshot.selectedWorkspaceID) else { return }
        let update = {
            scrollTargetID = snapshot.selectedWorkspaceID
        }
        if animated {
            model.performShellMotion(ConductorMotion.scroll, update)
        } else {
            update()
        }
    }

    private func workspaceTabView(for row: WorkspaceChromeDisplayModel) -> some View {
        WorkspaceTopTab(
            row: row,
            appearance: appearance,
            active: row.selected && snapshot.selectedWorkspaceFileTabID == nil && snapshot.selectedWorkspaceWebTabID == nil,
            visuallySelected: row.selected && snapshot.selectedWorkspaceFileTabID == nil && snapshot.selectedWorkspaceWebTabID == nil,
            selectionNamespace: selectionNamespace,
            canClose: snapshot.canCloseWorkspace,
            editing: editingWorkspaceID == row.id,
            titleDraft: $workspaceTitleDraft,
            onSelect: {
                finishWorkspaceRenameIfNeeded(except: row.id)
                ConductorMotion.withoutAnimation {
                    model.activateWorkspace(row.id, source: .tabStrip)
                }
            },
            onRename: {
                ConductorMotion.perform(ConductorMotion.selection) {
                    finishWorkspaceRenameIfNeeded(except: row.id)
                    onBeginRename(row)
                }
            },
            onCommitRename: onCommitRename,
            onCancelRename: onCancelRename,
            onDuplicate: {
                ConductorMotion.perform(ConductorMotion.layout) {
                    finishWorkspaceRenameIfNeeded()
                    model.duplicateWorkspace(row.id)
                }
            },
            onClose: {
                withoutShellAnimation {
                    finishWorkspaceRenameIfNeeded()
                    model.closeWorkspace(row.id)
                }
            },
            onCloseOthers: {
                withoutShellAnimation {
                    finishWorkspaceRenameIfNeeded(except: row.id)
                    model.closeOtherWorkspaces(keeping: row.id)
                }
            },
            onCloseRight: {
                withoutShellAnimation {
                    finishWorkspaceRenameIfNeeded()
                    model.closeWorkspacesToRight(of: row.id)
                }
            }
        )
        .id(row.id)
    }

    private func finishWorkspaceRenameIfNeeded(except workspaceID: WorkspaceID? = nil) {
        guard let editingWorkspaceID,
              editingWorkspaceID != workspaceID else {
            return
        }
        onCommitRename()
    }

}

private struct WorkspaceTabSectionDivider: View {
    @Environment(\.conductorTheme) private var theme

    var body: some View {
        Rectangle()
            .fill(theme.shellStroke.opacity(theme.usesDarkChrome ? 0.45 : 0.28))
            .frame(width: 1, height: 20)
            .padding(.horizontal, 4)
    }
}

private enum WorkspaceTabMetrics {
    static func width(for appearance: AppearancePreferences) -> CGFloat {
        appearance.density.workspaceTabWidth
    }

    static func height(for appearance: AppearancePreferences) -> CGFloat {
        appearance.density.workspaceTabHeight
    }

    static let spacing: CGFloat = 4
    static let edgePadding: CGFloat = 0
}

private struct WorkspaceFileTopTab: View {
    let tab: ConductorWorkspaceFileTab
    let appearance: AppearancePreferences
    let selected: Bool
    let dirty: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    @State private var hovering = false
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorTheme) private var theme
    private let closeButtonSlotWidth: CGFloat = 21

    private var tabShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: ConductorTokens.Radius.workspaceTab, style: .continuous)
    }

    private var baseFill: Color {
        if theme.usesDarkChrome {
            return hovering ? theme.shellHoverFill.opacity(0.92) : theme.shellControlFill.opacity(0.58)
        }
        return hovering ? theme.shellHoverFill.opacity(0.86) : theme.shellControlFill.opacity(0.52)
    }

    private var selectedFill: Color {
        theme.usesDarkChrome ? theme.shellPanelStrong.opacity(0.72) : theme.shellPanelStrong.opacity(0.82)
    }

    private var tabStroke: Color {
        if selected {
            return theme.shellStroke.opacity((theme.usesDarkChrome ? 0.58 : 0.42) * appearance.chromeClarity.strokeMultiplier)
        }
        return theme.shellStroke.opacity(hovering ? 0.34 : 0.18)
    }

    private var titleColor: Color {
        selected ? theme.shellChromeText.opacity(0.94) : theme.shellChromeTextMuted.opacity(0.86)
    }

    private var fileIcon: String {
        let ext = tab.fileURL.pathExtension.lowercased()
        if ext == "md" || ext == "markdown" {
            return "doc.richtext"
        }
        if let type = UTType(filenameExtension: ext), type.conforms(to: .image) {
            return "photo"
        }
        return "doc.text"
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            Button(action: onSelect) {
                HStack(spacing: 7) {
                    Image(systemName: fileIcon)
                        .font(.system(size: 10.8, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(selected ? theme.shellChromeText.opacity(0.90) : theme.shellChromeTextMuted.opacity(0.70))
                        .frame(width: 17, height: 17)
                    Text(tab.title)
                        .font(.conductorSystem(size: 11.3, weight: .semibold, scale: fontScale))
                        .foregroundStyle(titleColor)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Circle()
                        .fill(theme.floatingEmphasis.opacity(0.92))
                        .frame(width: 5, height: 5)
                        .opacity(dirty ? 1 : 0)
                }
                .padding(.leading, 8)
                .padding(.trailing, closeButtonSlotWidth + 5)
                .frame(
                    width: WorkspaceTabMetrics.width(for: appearance),
                    height: WorkspaceTabMetrics.height(for: appearance),
                    alignment: .leading
                )
                .contentShape(tabShape)
            }
            .buttonStyle(ConductorPressButtonStyle())

            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.conductorSystem(size: 8.5, weight: .bold, scale: fontScale))
                    .foregroundStyle(titleColor.opacity(selected || hovering ? 0.74 : 0.52))
                    .frame(width: 13, height: 13)
                    .clipShape(Circle())
                    .contentShape(Rectangle())
            }
            .buttonStyle(ConductorPressButtonStyle())
            .padding(.trailing, 6)
            .accessibilityLabel(L("关闭文件", "Close File"))
            .macNativeTooltip(L("关闭文件", "Close File"))
        }
        .frame(
            width: WorkspaceTabMetrics.width(for: appearance),
            height: WorkspaceTabMetrics.height(for: appearance)
        )
        .background {
            ZStack {
                tabShape
                    .fill(baseFill)
                if selected {
                    tabShape
                        .fill(selectedFill)
                }
            }
        }
        .clipShape(tabShape)
        .overlay {
            tabShape
                .stroke(tabStroke, lineWidth: 1)
        }
        .scaleEffect(hovering && !selected ? 1.006 : 1)
        .animation(ConductorMotion.hover, value: hovering)
        .onHover { value in
            ConductorMotion.perform(ConductorMotion.hover) {
                hovering = value
            }
        }
        .contentShape(tabShape)
        .contextMenu {
            Button(L("关闭文件", "Close File")) {
                onClose()
            }
            Button(L("在访达中显示", "Reveal in Finder")) {
                NSWorkspace.shared.activateFileViewerSelecting([tab.fileURL])
            }
        }
    }
}

private struct WorkspaceWebTopTab: View {
    let tab: ConductorWorkspaceWebTab
    let appearance: AppearancePreferences
    let selected: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    @State private var hovering = false
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorTheme) private var theme
    private let closeButtonSlotWidth: CGFloat = 21

    private var tabShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: ConductorTokens.Radius.workspaceTab, style: .continuous)
    }

    private var baseFill: Color {
        if theme.usesDarkChrome {
            return hovering ? theme.shellHoverFill.opacity(0.92) : theme.shellControlFill.opacity(0.58)
        }
        return hovering ? theme.shellHoverFill.opacity(0.86) : theme.shellControlFill.opacity(0.52)
    }

    private var selectedFill: Color {
        theme.usesDarkChrome ? theme.shellPanelStrong.opacity(0.72) : theme.shellPanelStrong.opacity(0.82)
    }

    private var tabStroke: Color {
        if selected {
            return theme.shellStroke.opacity((theme.usesDarkChrome ? 0.58 : 0.42) * appearance.chromeClarity.strokeMultiplier)
        }
        return theme.shellStroke.opacity(hovering ? 0.34 : 0.18)
    }

    private var titleColor: Color {
        selected ? theme.shellChromeText.opacity(0.94) : theme.shellChromeTextMuted.opacity(0.86)
    }

    private var accessibilityTitle: String {
        L("网页 \(tab.title)", "Web \(tab.title)")
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            Button(action: onSelect) {
                HStack(spacing: 7) {
                    Image(systemName: "globe")
                        .font(.system(size: 10.8, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(selected ? theme.shellChromeText.opacity(0.90) : theme.shellChromeTextMuted.opacity(0.70))
                        .frame(width: 17, height: 17)
                    Text(tab.title)
                        .font(.conductorSystem(size: 11.3, weight: .semibold, scale: fontScale))
                        .foregroundStyle(titleColor)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.leading, 8)
                .padding(.trailing, closeButtonSlotWidth + 5)
                .frame(
                    width: WorkspaceTabMetrics.width(for: appearance),
                    height: WorkspaceTabMetrics.height(for: appearance),
                    alignment: .leading
                )
                .contentShape(tabShape)
            }
            .buttonStyle(ConductorPressButtonStyle())
            .accessibilityLabel(accessibilityTitle)

            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.conductorSystem(size: 8.5, weight: .bold, scale: fontScale))
                    .foregroundStyle(titleColor.opacity(selected || hovering ? 0.74 : 0.52))
                    .frame(width: 13, height: 13)
                    .clipShape(Circle())
                    .contentShape(Rectangle())
            }
            .buttonStyle(ConductorPressButtonStyle())
            .padding(.trailing, 6)
            .accessibilityLabel(L("关闭网页", "Close Web Page"))
            .macNativeTooltip(L("关闭网页", "Close Web Page"))
        }
        .frame(
            width: WorkspaceTabMetrics.width(for: appearance),
            height: WorkspaceTabMetrics.height(for: appearance)
        )
        .background {
            ZStack {
                tabShape
                    .fill(baseFill)
                if selected {
                    tabShape
                        .fill(selectedFill)
                }
            }
        }
        .clipShape(tabShape)
        .overlay {
            tabShape
                .stroke(tabStroke, lineWidth: 1)
        }
        .scaleEffect(hovering && !selected ? 1.006 : 1)
        .animation(ConductorMotion.hover, value: hovering)
        .onHover { value in
            ConductorMotion.perform(ConductorMotion.hover) {
                hovering = value
            }
        }
        .contentShape(tabShape)
        .contextMenu {
            Button(L("关闭网页", "Close Web Page")) {
                onClose()
            }
        }
    }
}

private struct WorkspaceTopTab: View {
    let row: WorkspaceChromeDisplayModel
    let appearance: AppearancePreferences
    let active: Bool
    let visuallySelected: Bool
    let selectionNamespace: Namespace.ID
    let canClose: Bool
    let editing: Bool
    @Binding var titleDraft: String
    let onSelect: () -> Void
    let onRename: () -> Void
    let onCommitRename: () -> Void
    let onCancelRename: () -> Void
    let onDuplicate: () -> Void
    let onClose: () -> Void
    let onCloseOthers: () -> Void
    let onCloseRight: () -> Void
    @State private var hovering = false
    @State private var renameCancelled = false
    @FocusState private var titleFieldFocused: Bool
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorTheme) private var theme
    private let closeButtonSlotWidth: CGFloat = 21

    private var selected: Bool {
        active
    }

    private var unreadCount: Int {
        row.unreadCount
    }

    private var tabShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: ConductorTokens.Radius.workspaceTab, style: .continuous)
    }

    private var baseFill: Color {
        if theme.usesDarkChrome {
            return hovering ? theme.shellHoverFill.opacity(0.92) : theme.shellControlFill.opacity(0.72)
        }
        return hovering ? theme.shellHoverFill.opacity(0.86) : theme.shellControlFill.opacity(0.62)
    }

    private var selectedFill: Color {
        theme.usesDarkChrome ? theme.shellPanelStrong.opacity(0.72) : theme.shellPanelStrong.opacity(0.82)
    }

    private var tabStroke: Color {
        if selected {
            return theme.shellStroke.opacity((theme.usesDarkChrome ? 0.58 : 0.42) * appearance.chromeClarity.strokeMultiplier)
        }
        return theme.shellStroke.opacity(hovering ? 0.34 : 0.18)
    }

    private var titleColor: Color {
        selected ? theme.shellChromeText.opacity(0.94) : theme.shellChromeTextMuted.opacity(0.86)
    }

    var body: some View {
        Group {
            if editing {
                editingTab
            } else {
                displayTab
            }
        }
        .frame(
            width: WorkspaceTabMetrics.width(for: appearance),
            height: WorkspaceTabMetrics.height(for: appearance)
        )
        .background {
            ZStack {
                tabShape
                    .fill(baseFill)
                if visuallySelected {
                    tabShape
                        .fill(selectedFill)
                        .matchedGeometryEffect(id: "workspace-tab-selection", in: selectionNamespace)
                }
            }
        }
        .clipShape(tabShape)
        .overlay {
            tabShape
                .stroke(tabStroke, lineWidth: 1)
        }
        .scaleEffect(hovering && !selected ? 1.006 : 1)
        .animation(ConductorMotion.hover, value: hovering)
        .animation(ConductorMotion.selection, value: editing)
        .animation(ConductorMotion.attention, value: unreadCount)
        .onHover { value in
            ConductorMotion.perform(ConductorMotion.hover) {
                hovering = value
            }
        }
        .contentShape(tabShape)
        .contextMenu {
            Button(L("重命名工作区...", "Rename Workspace...")) {
                onRename()
            }
            Button(L("复制工作区", "Duplicate Workspace")) {
                onDuplicate()
            }
            Divider()
            Button(L("关闭其他工作区", "Close Other Workspaces")) {
                onCloseOthers()
            }
            .disabled(!canClose)
            Button(L("关闭右侧工作区", "Close Workspaces to the Right")) {
                onCloseRight()
            }
            .disabled(!canClose)
            Divider()
            Button(L("关闭工作区", "Close Workspace")) {
                onClose()
            }
            .disabled(!canClose)
        }
    }

    private var editingTab: some View {
        HStack(spacing: 7) {
            WorkspaceTabGlyph(selected: true)
            RenameTextField(
                text: $titleDraft,
                placeholder: L("工作区名称", "Workspace Name"),
                font: .conductorSystemFont(ofSize: 11.5, weight: .bold, scale: fontScale),
                textColor: NSColor(theme.shellChromeText),
                onCommit: onCommitRename,
                onCancel: onCancelRename
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .onAppear {
                renameCancelled = false
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var displayTab: some View {
        ZStack(alignment: .trailing) {
            Button {
                onSelect()
            } label: {
                WorkspaceTopTabContent(
                    title: row.title,
                    terminalCount: row.terminalCount,
                    unreadCount: unreadCount,
                    selected: selected,
                    themeID: theme.id,
                    fontScaleID: fontScale.id
                )
                .equatable()
                .padding(.leading, 8)
                .padding(.trailing, closeButtonSlotWidth + 5)
                .frame(
                    width: WorkspaceTabMetrics.width(for: appearance),
                    height: WorkspaceTabMetrics.height(for: appearance),
                    alignment: .leading
                )
                .contentShape(tabShape)
            }
            .buttonStyle(ConductorPressButtonStyle())
            .simultaneousGesture(
                TapGesture(count: 2).onEnded {
                    guard !editing else { return }
                    onSelect()
                    onRename()
                }
            )

            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.conductorSystem(size: 8.5, weight: .bold, scale: fontScale))
                    .foregroundStyle(canClose ? titleColor.opacity(selected || hovering ? 0.74 : 0.52) : Color.clear)
                    .frame(width: 13, height: 13)
                    .clipShape(Circle())
                    .contentShape(Rectangle())
            }
            .buttonStyle(ConductorPressButtonStyle())
            .disabled(!canClose)
            .padding(.trailing, 6)
            .accessibilityLabel(L("关闭工作区", "Close Workspace"))
            .macNativeTooltip(L("关闭工作区", "Close Workspace"))
        }
    }
}

private struct WorkspaceTopTabContent: View, Equatable {
    let title: String
    let terminalCount: Int
    let unreadCount: Int
    let selected: Bool
    let themeID: String
    let fontScaleID: String
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorTheme) private var theme

    nonisolated static func == (lhs: WorkspaceTopTabContent, rhs: WorkspaceTopTabContent) -> Bool {
        lhs.title == rhs.title &&
        lhs.terminalCount == rhs.terminalCount &&
        lhs.unreadCount == rhs.unreadCount &&
        lhs.selected == rhs.selected &&
        lhs.themeID == rhs.themeID &&
        lhs.fontScaleID == rhs.fontScaleID
    }

    private var titleColor: Color {
        selected ? theme.shellChromeText.opacity(0.94) : theme.shellChromeTextMuted.opacity(0.86)
    }

    var body: some View {
        HStack(spacing: 7) {
            WorkspaceTabGlyph(selected: selected)
            Text(title)
                .font(.conductorSystem(size: 11.3, weight: .semibold, scale: fontScale))
                .foregroundStyle(titleColor)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(terminalCount)")
                .font(.conductorSystem(size: 10.2, weight: .semibold, scale: fontScale))
                .foregroundStyle(selected ? theme.shellChromeText.opacity(0.72) : theme.shellChromeTextMuted.opacity(0.70))
                .frame(minWidth: 17, minHeight: 17)
            if unreadCount > 0 {
                Text(unreadCount > 99 ? "99+" : "\(unreadCount)")
                    .font(.conductorSystem(size: 9, weight: .bold, scale: fontScale))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .frame(minWidth: 15, minHeight: 14)
                    .background(theme.floatingEmphasis.opacity(0.72))
                    .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct WorkspaceTabGlyph: View {
    let selected: Bool
    @Environment(\.conductorTheme) private var theme

    var body: some View {
        Image(systemName: WorkspaceChromeGlyph.systemName(selected: selected))
            .font(.system(size: 10.8, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(selected ? theme.shellChromeText.opacity(0.90) : theme.shellChromeTextMuted.opacity(0.70))
            .frame(width: 17, height: 17)
            .accessibilityHidden(true)
    }
}
