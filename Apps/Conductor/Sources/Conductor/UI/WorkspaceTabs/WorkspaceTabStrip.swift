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

private enum WorkspaceTopTabScrollTarget: Hashable {
    case workspace(WorkspaceID)
    case file(String)
    case web(WebTabID)
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
    @State private var scrollTargetID: WorkspaceTopTabScrollTarget?

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
                        .id(WorkspaceTopTabScrollTarget.file(fileTab.id))
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
                                    model.closeWorkspaceWebTab(webTab.id)
                                }
                            }
                        )
                        .id(WorkspaceTopTabScrollTarget.web(webTab.id))
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
        .onChange(of: snapshot.selectedWorkspaceFileTabID) {
            syncScrollTarget(animated: true)
        }
        .onChange(of: snapshot.selectedWorkspaceWebTabID) {
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
        let nextTarget: WorkspaceTopTabScrollTarget?
        if let fileID = snapshot.selectedWorkspaceFileTabID,
                  snapshot.fileTabs.contains(where: { $0.id == fileID }) {
            nextTarget = .file(fileID)
        } else if let webID = snapshot.selectedWorkspaceWebTabID,
                  snapshot.webTabs.contains(where: { $0.id == webID }) {
            nextTarget = .web(webID)
        } else if snapshot.workspaceIDs.contains(snapshot.selectedWorkspaceID) {
            nextTarget = .workspace(snapshot.selectedWorkspaceID)
        } else {
            nextTarget = nil
        }

        let update = {
            scrollTargetID = nextTarget
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
        .id(WorkspaceTopTabScrollTarget.workspace(row.id))
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
        RoundedRectangle(cornerRadius: 0.5)
            .fill(theme.shellStroke.opacity(theme.usesDarkChrome ? 0.24 : 0.15))
            .frame(width: 1, height: 14)
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

    static let spacing: CGFloat = 3
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
        if hovering {
            return theme.shellHoverFill.opacity(theme.usesDarkChrome ? 0.24 : 0.12)
        }
        return Color.clear
    }

    private var selectedFill: Color {
        theme.shellSelectedFill
    }

    private var tabStroke: Color {
        if selected {
            return theme.floatingSelectedStroke.opacity((theme.usesDarkChrome ? 0.58 : 0.48) * appearance.chromeClarity.strokeMultiplier)
        }
        return theme.shellStroke.opacity(hovering ? 0.08 : 0.0)
    }

    private var titleColor: Color {
        if selected {
            return theme.shellChromeText.opacity(0.95)
        }
        return theme.shellChromeTextMuted.opacity(hovering ? 0.88 : 0.64)
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

    private var accessibilityTitle: String {
        dirty
            ? L("文件 \(tab.title)，有未保存更改", "File \(tab.title), unsaved changes")
            : L("文件 \(tab.title)", "File \(tab.title)")
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            Button(action: onSelect) {
                WorkspaceFileTopTabContent(
                    title: tab.title,
                    systemImage: fileIcon,
                    selected: selected,
                    dirty: dirty,
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
            .accessibilityLabel(accessibilityTitle)

            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.conductorSystem(size: 8.5, weight: .bold, scale: fontScale))
                    .foregroundStyle(titleColor.opacity(selected || hovering ? 0.74 : 0.52))
                    .frame(width: 16, height: 16)
                    .background((selected || hovering) ? theme.shellHoverFill.opacity(0.52) : Color.clear)
                    .clipShape(Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(ConductorPressButtonStyle(pressedScale: 0.985, pressedOpacity: 0.96))
            .padding(.trailing, 5)
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
                        .shadow(color: Color.black.opacity(theme.usesDarkChrome ? 0.08 : 0.025), radius: 1.5, y: 0.8)
                }
            }
        }
        .clipShape(tabShape)
        .overlay {
            tabShape
                .stroke(tabStroke, lineWidth: 0.6)
        }
        .scaleEffect(hovering && !selected ? 1.002 : 1)
        .animation(ConductorMotion.hover, value: hovering)
        .conductorHover($hovering)
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

private struct WorkspaceFileTopTabContent: View, Equatable {
    let title: String
    let systemImage: String
    let selected: Bool
    let dirty: Bool
    let themeID: String
    let fontScaleID: String
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorTheme) private var theme

    nonisolated static func == (lhs: WorkspaceFileTopTabContent, rhs: WorkspaceFileTopTabContent) -> Bool {
        lhs.title == rhs.title &&
            lhs.systemImage == rhs.systemImage &&
            lhs.selected == rhs.selected &&
            lhs.dirty == rhs.dirty &&
            lhs.themeID == rhs.themeID &&
            lhs.fontScaleID == rhs.fontScaleID
    }

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.system(size: 10.8, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(selected ? theme.shellChromeText.opacity(0.90) : theme.shellChromeTextMuted.opacity(0.70))
                .frame(width: 17, height: 17)
            Text(title)
                .font(.conductorSystem(size: 11.3, weight: .semibold, scale: fontScale))
                .foregroundStyle(selected ? theme.shellChromeText.opacity(0.94) : theme.shellChromeTextMuted.opacity(0.86))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            Circle()
                .fill(theme.floatingEmphasis.opacity(0.92))
                .frame(width: 5, height: 5)
                .opacity(dirty ? 1 : 0)
        }
    }
}

private struct WorkspaceWebTopTab: View {
    let tab: WorkspaceWebTabState
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
        if hovering {
            return theme.shellHoverFill.opacity(theme.usesDarkChrome ? 0.24 : 0.12)
        }
        return Color.clear
    }

    private var selectedFill: Color {
        theme.shellSelectedFill
    }

    private var tabStroke: Color {
        if selected {
            return theme.floatingSelectedStroke.opacity((theme.usesDarkChrome ? 0.58 : 0.48) * appearance.chromeClarity.strokeMultiplier)
        }
        return theme.shellStroke.opacity(hovering ? 0.08 : 0.0)
    }

    private var titleColor: Color {
        if selected {
            return theme.shellChromeText.opacity(0.95)
        }
        return theme.shellChromeTextMuted.opacity(hovering ? 0.88 : 0.64)
    }

    private var webIcon: String {
        tab.errorMessage == nil ? "globe" : "globe.badge.chevron.backward"
    }

    private var displayTitle: String {
        let title = tab.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        if tab.url == nil,
           title?.isEmpty ?? true,
           tab.pendingAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return L("新建网页", "New Tab")
        }
        return tab.displayTitle
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            Button(action: onSelect) {
                WorkspaceWebTopTabContent(
                    title: displayTitle,
                    systemImage: webIcon,
                    selected: selected,
                    loading: tab.isLoading,
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

            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.conductorSystem(size: 8.5, weight: .bold, scale: fontScale))
                    .foregroundStyle(titleColor.opacity(selected || hovering ? 0.74 : 0.52))
                    .frame(width: 16, height: 16)
                    .background((selected || hovering) ? theme.shellHoverFill.opacity(0.52) : Color.clear)
                    .clipShape(Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(ConductorPressButtonStyle(pressedScale: 0.985, pressedOpacity: 0.96))
            .padding(.trailing, 5)
            .macNativeTooltip(L("关闭网页", "Close Web Tab"))
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
                        .shadow(color: Color.black.opacity(theme.usesDarkChrome ? 0.08 : 0.025), radius: 1.5, y: 0.8)
                }
            }
        }
        .clipShape(tabShape)
        .overlay {
            tabShape
                .stroke(tabStroke, lineWidth: 0.6)
        }
        .scaleEffect(hovering && !selected ? 1.002 : 1)
        .animation(ConductorMotion.hover, value: hovering)
        .conductorHover($hovering)
        .contentShape(tabShape)
        .contextMenu {
            Button(L("关闭网页", "Close Web Tab")) {
                onClose()
            }
            Button(L("在浏览器中打开", "Open in Browser")) {
                if let url = tab.url {
                    NSWorkspace.shared.open(url)
                }
            }
            .disabled(tab.url == nil)
        }
    }
}

private struct WorkspaceWebTopTabContent: View, Equatable {
    let title: String
    let systemImage: String
    let selected: Bool
    let loading: Bool
    let themeID: String
    let fontScaleID: String
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorTheme) private var theme

    nonisolated static func == (lhs: WorkspaceWebTopTabContent, rhs: WorkspaceWebTopTabContent) -> Bool {
        lhs.title == rhs.title &&
            lhs.systemImage == rhs.systemImage &&
            lhs.selected == rhs.selected &&
            lhs.loading == rhs.loading &&
            lhs.themeID == rhs.themeID &&
            lhs.fontScaleID == rhs.fontScaleID
    }

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.system(size: 10.8, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(selected ? theme.shellChromeText.opacity(0.90) : theme.shellChromeTextMuted.opacity(0.70))
                .frame(width: 17, height: 17)
            Text(title)
                .font(.conductorSystem(size: 11.3, weight: .semibold, scale: fontScale))
                .foregroundStyle(selected ? theme.shellChromeText.opacity(0.94) : theme.shellChromeTextMuted.opacity(0.86))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            Circle()
                .fill(theme.floatingEmphasis.opacity(0.92))
                .frame(width: 5, height: 5)
                .opacity(loading ? 1 : 0)
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

    private var activeAgentCount: Int {
        row.activeAgentCount
    }

    private var tabShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: ConductorTokens.Radius.workspaceTab, style: .continuous)
    }

    private var baseFill: Color {
        if hovering {
            return theme.shellHoverFill.opacity(theme.usesDarkChrome ? 0.24 : 0.12)
        }
        return Color.clear
    }

    private var selectedFill: Color {
        theme.shellSelectedFill
    }

    private var tabStroke: Color {
        if selected {
            return theme.floatingSelectedStroke.opacity((theme.usesDarkChrome ? 0.58 : 0.48) * appearance.chromeClarity.strokeMultiplier)
        }
        return theme.shellStroke.opacity(hovering ? 0.08 : 0.0)
    }

    private var titleColor: Color {
        if selected {
            return theme.shellChromeText.opacity(0.95)
        }
        return theme.shellChromeTextMuted.opacity(hovering ? 0.88 : 0.64)
    }

    private var tabAccessibilityTitle: String {
        let base = L("\(row.title)，\(row.terminalCount) 个终端", "\(row.title), \(row.terminalCount) terminals")
        let agentSuffix = activeAgentCount > 0 ? L("，AI 终端运行中", ", AI terminal running") : ""
        return base + agentSuffix
    }

    var body: some View {
        if editing {
            editingTab
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
                                .shadow(color: Color.black.opacity(theme.usesDarkChrome ? 0.08 : 0.025), radius: 1.5, y: 0.8)
                        }
                    }
                }
                .clipShape(tabShape)
                .overlay {
                    tabShape
                        .stroke(tabStroke, lineWidth: 0.6)
                }
                .animation(ConductorMotion.selection, value: editing)
        } else {
            NativeWorkspaceTopTab(
                row: row,
                width: WorkspaceTabMetrics.width(for: appearance),
                height: WorkspaceTabMetrics.height(for: appearance),
                selected: selected,
                canClose: canClose,
                theme: theme,
                fontScale: fontScale,
                onSelect: onSelect,
                onRename: onRename,
                onDuplicate: onDuplicate,
                onClose: onClose,
                onCloseOthers: onCloseOthers,
                onCloseRight: onCloseRight
            )
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
                    activeAgentCount: activeAgentCount,
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
            .accessibilityLabel(tabAccessibilityTitle)

            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.conductorSystem(size: 8.5, weight: .bold, scale: fontScale))
                    .foregroundStyle(canClose ? titleColor.opacity(selected || hovering ? 0.74 : 0.52) : Color.clear)
                    .frame(width: 16, height: 16)
                    .background(canClose && (selected || hovering) ? theme.shellHoverFill.opacity(0.52) : Color.clear)
                    .clipShape(Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(ConductorPressButtonStyle(pressedScale: 0.985, pressedOpacity: 0.96))
            .disabled(!canClose)
            .padding(.trailing, 5)
            .accessibilityLabel(L("关闭工作区", "Close Workspace"))
            .macNativeTooltip(L("关闭工作区", "Close Workspace"))
        }
    }
}

private struct NativeWorkspaceTopTab: NSViewRepresentable {
    let row: WorkspaceChromeDisplayModel
    let width: CGFloat
    let height: CGFloat
    let selected: Bool
    let canClose: Bool
    let theme: TerminalTheme
    let fontScale: AppearanceFontScale
    let onSelect: () -> Void
    let onRename: () -> Void
    let onDuplicate: () -> Void
    let onClose: () -> Void
    let onCloseOthers: () -> Void
    let onCloseRight: () -> Void

    func makeNSView(context: Context) -> NativeWorkspaceTopTabView {
        NativeWorkspaceTopTabView()
    }

    func updateNSView(_ view: NativeWorkspaceTopTabView, context: Context) {
        view.update(
            row: row,
            size: NSSize(width: width, height: height),
            selected: selected,
            canClose: canClose,
            theme: theme,
            fontScale: fontScale,
            onSelect: onSelect,
            onRename: onRename,
            onDuplicate: onDuplicate,
            onClose: onClose,
            onCloseOthers: onCloseOthers,
            onCloseRight: onCloseRight
        )
    }
}

private final class NativeWorkspaceTopTabView: NSView {
    private var row: WorkspaceChromeDisplayModel?
    private var targetSize = NSSize(width: 140, height: 28)
    private var selected = false
    private var canClose = true
    private var theme: TerminalTheme = .graphite
    private var fontScale: AppearanceFontScale = .standard
    private var hovering = false
    private var mouseDownOnClose = false
    private var onSelect: (() -> Void)?
    private var onRename: (() -> Void)?
    private var onDuplicate: (() -> Void)?
    private var onClose: (() -> Void)?
    private var onCloseOthers: (() -> Void)?
    private var onCloseRight: (() -> Void)?
    private var tracking: NSTrackingArea?
    private var menuController: NativeWorkspaceMenuController?
    private let agentSpinner = NSProgressIndicator()

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureView()
    }

    private func configureView() {
        wantsLayer = true
        agentSpinner.style = .spinning
        agentSpinner.controlSize = .small
        agentSpinner.isIndeterminate = true
        agentSpinner.isDisplayedWhenStopped = false
        agentSpinner.isHidden = true
        addSubview(agentSpinner)
    }

    func update(
        row: WorkspaceChromeDisplayModel,
        size: NSSize,
        selected: Bool,
        canClose: Bool,
        theme: TerminalTheme,
        fontScale: AppearanceFontScale,
        onSelect: @escaping () -> Void,
        onRename: @escaping () -> Void,
        onDuplicate: @escaping () -> Void,
        onClose: @escaping () -> Void,
        onCloseOthers: @escaping () -> Void,
        onCloseRight: @escaping () -> Void
    ) {
        self.row = row
        self.targetSize = size
        self.selected = selected
        self.canClose = canClose
        self.theme = theme
        self.fontScale = fontScale
        self.onSelect = onSelect
        self.onRename = onRename
        self.onDuplicate = onDuplicate
        self.onClose = onClose
        self.onCloseOthers = onCloseOthers
        self.onCloseRight = onCloseRight
        toolTip = tabAccessibilityTitle(for: row)
        updateAgentSpinner(for: row)
        needsDisplay = true
        needsLayout = true
    }

    override func layout() {
        super.layout()
        layoutAgentSpinner()
    }

    override var intrinsicContentSize: NSSize {
        targetSize
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
        mouseDownOnClose = canClose && closeRect.contains(convert(event.locationInWindow, from: nil))
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        defer { mouseDownOnClose = false }
        guard bounds.contains(point) else { return }
        if mouseDownOnClose && canClose && closeRect.contains(point) {
            onClose?()
        } else if !mouseDownOnClose {
            onSelect?()
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        let controller = NativeWorkspaceMenuController()
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = controller
        controller.onClose = { [weak self, weak controller] in
            guard let self, self.menuController === controller else { return }
            self.menuController = nil
        }
        menu.addItem(controller.item(title: L("重命名工作区...", "Rename Workspace..."), enabled: true) { [weak self] in self?.onRename?() })
        menu.addItem(controller.item(title: L("复制工作区", "Duplicate Workspace"), enabled: true) { [weak self] in self?.onDuplicate?() })
        menu.addItem(.separator())
        menu.addItem(controller.item(title: L("关闭其他工作区", "Close Other Workspaces"), enabled: canClose) { [weak self] in self?.onCloseOthers?() })
        menu.addItem(controller.item(title: L("关闭右侧工作区", "Close Workspaces to the Right"), enabled: canClose) { [weak self] in self?.onCloseRight?() })
        menu.addItem(.separator())
        menu.addItem(controller.item(title: L("关闭工作区", "Close Workspace"), enabled: canClose) { [weak self] in self?.onClose?() })
        menuController = controller
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let row else { return }
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 0, dy: 1), xRadius: ConductorTokens.Radius.workspaceTab, yRadius: ConductorTokens.Radius.workspaceTab)
        fillColor.setFill()
        shape.fill()
        strokeColor.setStroke()
        shape.lineWidth = 0.6
        shape.stroke()
        drawGlyph(selected: selected)
        drawTitle(row)
        if canClose && (hovering || selected) {
            drawCloseGlyph()
        }
    }

    private func updateAgentSpinner(for row: WorkspaceChromeDisplayModel) {
        if row.activeAgentCount > 0 {
            agentSpinner.isHidden = false
            agentSpinner.startAnimation(nil)
        } else {
            agentSpinner.stopAnimation(nil)
            agentSpinner.isHidden = true
        }
    }

    private func layoutAgentSpinner() {
        let side: CGFloat = 13
        agentSpinner.frame = NSRect(
            x: bounds.maxX - 43,
            y: (bounds.height - side) / 2,
            width: side,
            height: side
        )
    }

    private var closeRect: NSRect {
        NSRect(x: bounds.maxX - 22, y: (bounds.height - 16) / 2, width: 16, height: 16)
    }

    private var fillColor: NSColor {
        if selected {
            return NSColor(theme.shellSelectedFill)
        }
        if hovering {
            return NSColor(theme.shellHoverFill.opacity(theme.usesDarkChrome ? 0.24 : 0.12))
        }
        return .clear
    }

    private var strokeColor: NSColor {
        if selected {
            return NSColor(theme.floatingSelectedStroke.opacity(theme.usesDarkChrome ? 0.58 : 0.48))
        }
        return NSColor(theme.shellStroke.opacity(hovering ? 0.08 : 0))
    }

    private func drawGlyph(selected: Bool) {
        let chipRect = NSRect(x: 6, y: (bounds.height - 22) / 2, width: 22, height: 22)
        if selected {
            NSColor(theme.shellControlRaisedFill.opacity(0.84)).setFill()
            NSBezierPath(roundedRect: chipRect, xRadius: 7, yRadius: 7).fill()
        }

        let image = NSImage(systemSymbolName: WorkspaceChromeGlyph.systemName(selected: selected), accessibilityDescription: nil)
        image?.isTemplate = true
        let symbolColor = selected ? NSColor(theme.shellChromeText.opacity(0.96)) : NSColor(theme.shellChromeTextMuted.opacity(0.70))
        symbolColor.set()
        let imageRect = NSRect(x: 11, y: (bounds.height - 12) / 2, width: 12, height: 12)
        image?.withSymbolConfiguration(.init(pointSize: 11, weight: .bold))?
            .draw(in: imageRect, from: .zero, operation: .sourceAtop, fraction: 1)
    }

    private func drawTitle(_ row: WorkspaceChromeDisplayModel) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingMiddle
        let trailingReserved: CGFloat = row.activeAgentCount > 0 ? 66 : 48
        let rect = NSRect(x: 36, y: (bounds.height - 15) / 2, width: max(0, bounds.width - trailingReserved), height: 16)
        NSAttributedString(
            string: row.title,
            attributes: [
                .font: NSFont.systemFont(ofSize: fontScale.size(11.3), weight: .semibold),
                .foregroundColor: selected ? NSColor(theme.shellChromeText.opacity(0.94)) : NSColor(theme.shellChromeTextMuted.opacity(0.86)),
                .paragraphStyle: paragraph
            ]
        ).draw(in: rect)
    }

    private func drawCloseGlyph() {
        let image = NSImage(systemSymbolName: "xmark", accessibilityDescription: nil)
        image?.isTemplate = true
        NSColor(theme.shellChromeText.opacity(0.74)).set()
        image?.draw(in: closeRect.insetBy(dx: 4, dy: 4))
    }

    private func tabAccessibilityTitle(for row: WorkspaceChromeDisplayModel) -> String {
        let base = L("\(row.title)，\(row.terminalCount) 个终端", "\(row.title), \(row.terminalCount) terminals")
        let agentSuffix = row.activeAgentCount > 0 ? L("，AI 终端运行中", ", AI terminal running") : ""
        return base + agentSuffix
    }
}

private final class NativeWorkspaceMenuController: NSObject, NSMenuDelegate {
    private var nextActionTag = 1
    private var actions: [Int: () -> Void] = [:]
    var onClose: (() -> Void)?

    func item(title: String, enabled: Bool, action: @escaping () -> Void) -> NSMenuItem {
        let tag = nextActionTag
        nextActionTag += 1
        actions[tag] = action
        let item = NSMenuItem(title: title, action: #selector(performMenuAction(_:)), keyEquivalent: "")
        item.target = self
        item.tag = tag
        item.isEnabled = enabled
        return item
    }

    @objc private func performMenuAction(_ sender: NSMenuItem) {
        actions[sender.tag]?()
    }

    func menuDidClose(_ menu: NSMenu) {
        DispatchQueue.main.async { [weak self] in
            self?.onClose?()
        }
    }
}

private struct WorkspaceTopTabContent: View, Equatable {
    let title: String
    let activeAgentCount: Int
    let selected: Bool
    let themeID: String
    let fontScaleID: String
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorTheme) private var theme

    nonisolated static func == (lhs: WorkspaceTopTabContent, rhs: WorkspaceTopTabContent) -> Bool {
        lhs.title == rhs.title &&
        lhs.activeAgentCount == rhs.activeAgentCount &&
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
            if activeAgentCount > 0 {
                ProgressView()
                    .controlSize(.small)
                    .tint(theme.floatingEmphasis)
                    .scaleEffect(0.55)
                    .frame(width: 13, height: 13)
                    .accessibilityHidden(true)
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
            .font(.system(size: 11, weight: .bold))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(selected ? theme.shellChromeText.opacity(0.96) : theme.shellChromeTextMuted.opacity(0.70))
            .frame(width: 22, height: 22)
            .background(selected ? theme.shellControlRaisedFill.opacity(0.84) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .accessibilityHidden(true)
    }
}
