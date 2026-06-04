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

private enum ChromeTabKind {
    case workspace(WorkspaceChromeDisplayModel)
    case file(WorkspaceFileTabDisplayModel)
    case web(WorkspaceWebTabDisplayModel)
}

private struct ChromeTabEntry: Identifiable {
    let id: String
    let kind: ChromeTabKind
    let selected: Bool
}

private enum WorkspaceTabMetrics {
    static func railHeight(for appearance: AppearancePreferences) -> CGFloat {
        appearance.density.toolbarHeight
    }

    static func height(for appearance: AppearancePreferences) -> CGFloat {
        appearance.density.workspaceTabHeight
    }

    static let minWidth: CGFloat = 56
    static let maxWidth: CGFloat = 210
    static let cornerRadius: CGFloat = 7
    static let separatorHeight: CGFloat = 16
    static let topInset: CGFloat = 0
    static let spacing: CGFloat = 0
    static let edgePadding: CGFloat = 0

    static func width(for availableWidth: CGFloat, count: Int) -> CGFloat {
        guard count > 0 else { return maxWidth }
        let raw = availableWidth / CGFloat(count)
        return min(max(raw, minWidth), maxWidth)
    }
}

private func chromeTabShape() -> some Shape {
    RoundedRectangle(cornerRadius: WorkspaceTabMetrics.cornerRadius, style: .continuous)
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
    @State private var scrollTargetID: WorkspaceTopTabScrollTarget?
    @Environment(\.conductorTheme) private var theme

    private var entries: [ChromeTabEntry] {
        var result: [ChromeTabEntry] = []
        let workspaceSelected = snapshot.selectedWorkspaceFileTabID == nil && snapshot.selectedWorkspaceWebTabID == nil
        for row in snapshot.rows {
            result.append(
                ChromeTabEntry(
                    id: "workspace-\(row.id.rawValue.uuidString)",
                    kind: .workspace(row),
                    selected: row.selected && workspaceSelected
                )
            )
        }
        for fileTab in snapshot.fileTabs {
            result.append(
                ChromeTabEntry(id: "file-\(fileTab.id)", kind: .file(fileTab), selected: fileTab.selected)
            )
        }
        for webTab in snapshot.webTabs {
            result.append(
                ChromeTabEntry(id: "web-\(webTab.id.rawValue.uuidString)", kind: .web(webTab), selected: webTab.selected)
            )
        }
        return result
    }

    var body: some View {
        let entries = entries
        GeometryReader { proxy in
            let tabWidth = WorkspaceTabMetrics.width(for: proxy.size.width, count: entries.count)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: WorkspaceTabMetrics.spacing) {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        chromeTab(for: entry, width: tabWidth, showsLeadingSeparator: showsSeparator(at: index, in: entries))
                            .transition(ConductorMotion.tabTransition)
                    }
                }
                .padding(.horizontal, WorkspaceTabMetrics.edgePadding)
                .frame(minWidth: proxy.size.width, alignment: .leading)
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $scrollTargetID, anchor: .center)
        }
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
            maxWidth: .infinity,
            minHeight: WorkspaceTabMetrics.railHeight(for: appearance),
            maxHeight: WorkspaceTabMetrics.railHeight(for: appearance),
            alignment: .leading
        )
        .animation(model.shellAnimation(ConductorMotion.list), value: snapshot.workspaceIDs)
    }

    /// A divider sits between two tabs only when neither is selected, mirroring
    /// the way Chrome hides the separator next to the active tab.
    private func showsSeparator(at index: Int, in entries: [ChromeTabEntry]) -> Bool {
        guard index > 0 else { return false }
        return !entries[index].selected && !entries[index - 1].selected
    }

    @ViewBuilder
    private func chromeTab(for entry: ChromeTabEntry, width: CGFloat, showsLeadingSeparator: Bool) -> some View {
        switch entry.kind {
        case .workspace(let row):
            workspaceTabView(for: row, width: width, showsLeadingSeparator: showsLeadingSeparator)
                .id(WorkspaceTopTabScrollTarget.workspace(row.id))
        case .file(let fileTab):
            WorkspaceFileTopTab(
                tab: fileTab.tab,
                width: width,
                appearance: appearance,
                selected: fileTab.selected,
                dirty: fileTab.dirty,
                showsLeadingSeparator: showsLeadingSeparator,
                onSelect: {
                    finishWorkspaceRenameIfNeeded()
                    model.selectWorkspaceFileTab(fileTab.id)
                },
                onClose: {
                    withoutShellAnimation {
                        finishWorkspaceRenameIfNeeded()
                        model.selectWorkspaceFileTab(fileTab.id)
                        model.performCommand(.closeSelectedTab)
                    }
                },
                onOpenExternal: {
                    finishWorkspaceRenameIfNeeded()
                    model.selectWorkspaceFileTab(fileTab.id)
                    model.performCommand(.openSelectedFileExternally)
                },
                onReveal: {
                    finishWorkspaceRenameIfNeeded()
                    model.selectWorkspaceFileTab(fileTab.id)
                    model.performCommand(.revealSelectedFileInFinder)
                }
            )
            .id(WorkspaceTopTabScrollTarget.file(fileTab.id))
            .transition(ConductorMotion.tabTransition)
        case .web(let webTab):
            WorkspaceWebTopTab(
                tab: webTab.tab,
                width: width,
                appearance: appearance,
                selected: webTab.selected,
                showsLeadingSeparator: showsLeadingSeparator,
                onSelect: {
                    finishWorkspaceRenameIfNeeded()
                    model.selectWorkspaceWebTab(webTab.id)
                },
                onClose: {
                    withoutShellAnimation {
                        finishWorkspaceRenameIfNeeded()
                        model.selectWorkspaceWebTab(webTab.id)
                        model.performCommand(.closeSelectedTab)
                    }
                },
                onOpenExternal: {
                    finishWorkspaceRenameIfNeeded()
                    model.selectWorkspaceWebTab(webTab.id)
                    model.performCommand(.openSelectedWebTabExternally)
                }
            )
            .id(WorkspaceTopTabScrollTarget.web(webTab.id))
            .transition(ConductorMotion.tabTransition)
        }
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

    private func workspaceTabView(for row: WorkspaceChromeDisplayModel, width: CGFloat, showsLeadingSeparator: Bool) -> some View {
        WorkspaceTopTab(
            row: row,
            width: width,
            appearance: appearance,
            selected: row.selected && snapshot.selectedWorkspaceFileTabID == nil && snapshot.selectedWorkspaceWebTabID == nil,
            canClose: snapshot.canCloseWorkspace,
            canCloseRight: canCloseWorkspacesToRight(of: row.id),
            editing: editingWorkspaceID == row.id,
            showsLeadingSeparator: showsLeadingSeparator,
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
                    model.activateWorkspace(row.id, source: .tabStrip)
                    model.performCommand(.duplicateWorkspace)
                }
            },
            onClose: {
                withoutShellAnimation {
                    finishWorkspaceRenameIfNeeded()
                    model.activateWorkspace(row.id, source: .tabStrip)
                    model.performCommand(.closeCurrentWorkspace)
                }
            },
            onCloseOthers: {
                withoutShellAnimation {
                    finishWorkspaceRenameIfNeeded(except: row.id)
                    model.activateWorkspace(row.id, source: .tabStrip)
                    model.performCommand(.closeOtherWorkspaces)
                }
            },
            onCloseRight: {
                withoutShellAnimation {
                    finishWorkspaceRenameIfNeeded()
                    model.activateWorkspace(row.id, source: .tabStrip)
                    model.performCommand(.closeWorkspacesToRight)
                }
            },
            onOpenRoot: {
                ConductorMotion.withoutAnimation {
                    finishWorkspaceRenameIfNeeded(except: row.id)
                    model.activateWorkspace(row.id, source: .tabStrip)
                    model.performCommand(.openCurrentWorkspaceRoot)
                }
            },
            onOpenFirstPort: {
                ConductorMotion.withoutAnimation {
                    finishWorkspaceRenameIfNeeded(except: row.id)
                    model.activateWorkspace(row.id, source: .tabStrip)
                }
                model.performCommand(.openCurrentWorkspaceFirstService)
            }
        )
        .transition(ConductorMotion.tabTransition)
    }

    private func finishWorkspaceRenameIfNeeded(except workspaceID: WorkspaceID? = nil) {
        guard let editingWorkspaceID,
              editingWorkspaceID != workspaceID else {
            return
        }
        onCommitRename()
    }

    private func canCloseWorkspacesToRight(of workspaceID: WorkspaceID) -> Bool {
        guard let index = snapshot.workspaceIDs.firstIndex(of: workspaceID) else { return false }
        return index < snapshot.workspaceIDs.count - 1
    }
}

private struct ChromeTabShell<Content: View>: View {
    let width: CGFloat
    let railHeight: CGFloat
    let height: CGFloat
    let selected: Bool
    let hovering: Bool
    let showsLeadingSeparator: Bool
    @ViewBuilder var content: Content
    @Environment(\.conductorTheme) private var theme

    private var tabShape: some Shape {
        chromeTabShape()
    }

    private var baseFill: Color {
        if hovering {
            return theme.shellHoverFill.opacity(0.64 * theme.chromeMaterial.controlOpacityBoost)
        }
        return Color.clear
    }

    private var selectedFill: Color {
        if theme == .microGlass {
            return Color.white.opacity(0.105)
        }
        return theme.shellSelectedFill.opacity(theme.usesDarkChrome ? 0.90 : 0.74)
    }

    private var topStroke: Color {
        guard selected else { return Color.clear }
        if theme == .microGlass {
            return Color.white.opacity(0.18)
        }
        return theme.usesDarkChrome
            ? Color.white.opacity(0.055)
            : theme.shellStroke.opacity(0.12)
    }

    var body: some View {
        ZStack(alignment: .leading) {
            if showsLeadingSeparator {
                RoundedRectangle(cornerRadius: 0.5)
                    .fill(theme.shellStroke.opacity(theme.usesDarkChrome ? 0.22 : 0.14))
                    .frame(width: 1, height: WorkspaceTabMetrics.separatorHeight)
                    .frame(maxHeight: .infinity, alignment: .center)
            }

            content
                .frame(width: width, height: height, alignment: .leading)
        }
        .frame(width: width, height: railHeight, alignment: .center)
        .background(alignment: .center) {
            ZStack {
                tabShape
                    .fill(baseFill)
                    .frame(width: width, height: height)
                if selected {
                    tabShape
                        .fill(selectedFill)
                        .overlay {
                            tabShape
                                .stroke(topStroke, lineWidth: 0.6)
                        }
                        .frame(width: width, height: height)
                        .shadow(
                            color: Color.black.opacity(theme.chromeMaterial.shadowOpacity),
                            radius: 5,
                            y: 1.5
                        )
                }
                if theme.chromeMaterial.highlightOpacity > 0 {
                    tabShape
                        .stroke(Color.white.opacity(theme.chromeMaterial.highlightOpacity), lineWidth: 0.5)
                        .frame(width: width, height: height)
                        .blendMode(.screen)
                }
            }
        }
        .contentShape(Rectangle())
        .accessibilityIdentifier("ConductorWorkspaceTabInteractiveRegion")
    }
}

private struct ChromeTabCloseButton: View {
    let visible: Bool
    let titleColor: Color
    let accessibility: String
    let tooltip: String
    let action: () -> Void
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorTheme) private var theme

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.conductorSystem(size: 8.5, weight: .bold, scale: fontScale))
                .foregroundStyle(titleColor.opacity(visible ? 0.74 : 0.0))
                .frame(width: 16, height: 16)
                .background(visible ? theme.shellHoverFill.opacity(0.52) : Color.clear)
                .clipShape(Circle())
                .contentShape(Circle())
        }
        .buttonStyle(ConductorPressButtonStyle(pressedScale: 0.985, pressedOpacity: 0.96))
        .disabled(!visible)
        .accessibilityLabel(accessibility)
        .macNativeTooltip(tooltip)
    }
}

private struct WorkspaceFileTopTab: View {
    let tab: ConductorWorkspaceFileTab
    let width: CGFloat
    let appearance: AppearancePreferences
    let selected: Bool
    let dirty: Bool
    let showsLeadingSeparator: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    let onOpenExternal: () -> Void
    let onReveal: () -> Void
    @State private var hovering = false
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorTheme) private var theme

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
        ChromeTabShell(
            width: width,
            railHeight: WorkspaceTabMetrics.railHeight(for: appearance),
            height: WorkspaceTabMetrics.height(for: appearance),
            selected: selected,
            hovering: hovering,
            showsLeadingSeparator: showsLeadingSeparator
        ) {
            HStack(spacing: 6) {
                WorkspaceFileTopTabContent(
                    title: tab.title,
                    systemImage: fileIcon,
                    selected: selected,
                    dirty: dirty,
                    themeID: theme.id,
                    fontScaleID: fontScale.id
                )
                .equatable()
                ChromeTabCloseButton(
                    visible: selected || hovering,
                    titleColor: titleColor,
                    accessibility: L("关闭文件", "Close File"),
                    tooltip: L("关闭文件", "Close File"),
                    action: onClose
                )
            }
            .padding(.leading, 9)
            .padding(.trailing, 5)
            .padding(.top, WorkspaceTabMetrics.topInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture(perform: onSelect)
            .accessibilityLabel(accessibilityTitle)
            .accessibilityAddTraits(.isButton)
        }
        .conductorHover($hovering)
        .contextMenu {
            Button(L("关闭文件", "Close File")) {
                onClose()
            }
            Button(L("系统应用打开", "Open in System App")) {
                onOpenExternal()
            }
            Button(L("在访达中显示", "Reveal in Finder")) {
                onReveal()
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
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 10.8, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(selected ? theme.shellChromeText.opacity(0.90) : theme.shellChromeTextMuted.opacity(0.70))
                .frame(width: 15, height: 15)
            Text(title)
                .font(.conductorSystem(size: 11.3, weight: selected ? .semibold : .medium, scale: fontScale))
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
    let width: CGFloat
    let appearance: AppearancePreferences
    let selected: Bool
    let showsLeadingSeparator: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    let onOpenExternal: () -> Void
    @State private var hovering = false
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorTheme) private var theme

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
        ChromeTabShell(
            width: width,
            railHeight: WorkspaceTabMetrics.railHeight(for: appearance),
            height: WorkspaceTabMetrics.height(for: appearance),
            selected: selected,
            hovering: hovering,
            showsLeadingSeparator: showsLeadingSeparator
        ) {
            HStack(spacing: 6) {
                WorkspaceWebTopTabContent(
                    title: displayTitle,
                    systemImage: webIcon,
                    selected: selected,
                    loading: tab.isLoading,
                    themeID: theme.id,
                    fontScaleID: fontScale.id
                )
                .equatable()
                ChromeTabCloseButton(
                    visible: selected || hovering,
                    titleColor: titleColor,
                    accessibility: L("关闭网页", "Close Web Tab"),
                    tooltip: L("关闭网页", "Close Web Tab"),
                    action: onClose
                )
            }
            .padding(.leading, 9)
            .padding(.trailing, 5)
            .padding(.top, WorkspaceTabMetrics.topInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture(perform: onSelect)
        }
        .conductorHover($hovering)
        .contextMenu {
            Button(L("关闭网页", "Close Web Tab")) {
                onClose()
            }
            Button(L("在浏览器中打开", "Open in Browser")) {
                onOpenExternal()
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
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 10.8, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(selected ? theme.shellChromeText.opacity(0.90) : theme.shellChromeTextMuted.opacity(0.70))
                .frame(width: 15, height: 15)
            Text(title)
                .font(.conductorSystem(size: 11.3, weight: selected ? .semibold : .medium, scale: fontScale))
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
    let width: CGFloat
    let appearance: AppearancePreferences
    let selected: Bool
    let canClose: Bool
    let canCloseRight: Bool
    let editing: Bool
    let showsLeadingSeparator: Bool
    @Binding var titleDraft: String
    let onSelect: () -> Void
    let onRename: () -> Void
    let onCommitRename: () -> Void
    let onCancelRename: () -> Void
    let onDuplicate: () -> Void
    let onClose: () -> Void
    let onCloseOthers: () -> Void
    let onCloseRight: () -> Void
    let onOpenRoot: () -> Void
    let onOpenFirstPort: () -> Void
    @State private var hovering = false
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorTheme) private var theme

    private var activeAgentCount: Int {
        row.activeAgentCount
    }

    private var titleColor: Color {
        if selected {
            return theme.shellChromeText.opacity(0.95)
        }
        return theme.shellChromeTextMuted.opacity(hovering ? 0.88 : 0.64)
    }

    private var tabAccessibilityTitle: String {
        let base = L("\(row.title)，\(row.terminalCount) 个终端", "\(row.title), \(row.terminalCount) terminals")
        let unreadSuffix = row.unreadCount > 0
            ? L("，\(row.unreadCount) 条未读通知", ", \(row.unreadCount) unread notifications")
            : ""
        let agentSuffix = activeAgentCount > 0 ? L("，AI 终端运行中", ", AI terminal running") : ""
        return ([base + unreadSuffix + agentSuffix] + metadataTooltipLines).joined(separator: "\n")
    }

    private var metadataTooltipLines: [String] {
        guard let metadata = row.metadata else {
            return [L("工作区元数据正在刷新", "Workspace metadata is refreshing")]
        }
        var lines: [String] = []
        if let rootPath = metadata.rootPath {
            lines.append(L("路径：\(rootPath)", "Path: \(rootPath)"))
        }
        if !metadata.runningPorts.isEmpty {
            lines.append(L("端口：\(metadata.runningPorts.map { ":\($0)" }.joined(separator: " "))", "Ports: \(metadata.runningPorts.map { ":\($0)" }.joined(separator: " "))"))
        }
        if metadata.health != "ok" {
            lines.append(L("状态：\(metadata.health)", "Health: \(metadata.health)"))
        }
        return lines
    }

    private var primaryStatusPill: WorkspaceTabStatusPillModel? {
        nil
    }

    private var portStatusPill: WorkspaceTabStatusPillModel? {
        guard let port = row.metadata?.runningPorts.first else { return nil }
        return WorkspaceTabStatusPillModel(systemImage: "network", text: ":\(port)", tone: .accent)
    }

    private var healthStatusPill: WorkspaceTabStatusPillModel? {
        guard let health = row.metadata?.health,
              health != "ok" else {
            return nil
        }
        return WorkspaceTabStatusPillModel(
            systemImage: health == "metadata_partial" ? "exclamationmark.circle.fill" : "questionmark.circle.fill",
            text: "",
            tone: .attention
        )
    }

    var body: some View {
        ChromeTabShell(
            width: width,
            railHeight: WorkspaceTabMetrics.railHeight(for: appearance),
            height: WorkspaceTabMetrics.height(for: appearance),
            selected: selected || editing,
            hovering: hovering,
            showsLeadingSeparator: showsLeadingSeparator
        ) {
            Group {
                if editing {
                    editingContent
                } else {
                    displayContent
                }
            }
            .padding(.leading, 9)
            .padding(.trailing, 5)
            .padding(.top, WorkspaceTabMetrics.topInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .conductorHover($hovering)
        .macNativeTooltip(tabAccessibilityTitle)
        .contextMenu {
            Button(L("重命名工作区...", "Rename Workspace...")) { onRename() }
            Button(L("复制工作区", "Duplicate Workspace")) { onDuplicate() }
            if row.metadata?.rootPath != nil {
                Divider()
                Button(L("在 Finder 打开根目录", "Open Root in Finder")) { onOpenRoot() }
            }
            if let port = row.metadata?.runningPorts.first {
                Button(L("打开端口 :\(port)", "Open Port :\(port)")) { onOpenFirstPort() }
            }
            Divider()
            Button(L("关闭其他工作区", "Close Other Workspaces")) { onCloseOthers() }
                .disabled(!canClose)
            Button(L("关闭右侧工作区", "Close Workspaces to the Right")) { onCloseRight() }
                .disabled(!canCloseRight)
            Divider()
            Button(L("关闭工作区", "Close Workspace")) { onClose() }
                .disabled(!canClose)
        }
    }

    private var displayContent: some View {
        HStack(spacing: 6) {
            WorkspaceTabGlyph(selected: selected)
            Text(row.title)
                .font(.conductorSystem(size: 11.3, weight: selected ? .semibold : .medium, scale: fontScale))
                .foregroundStyle(titleColor)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            if width > 118,
               let primaryStatusPill,
               selected || hovering {
                WorkspaceTabStatusPill(model: primaryStatusPill)
            }
            if width > 158,
               let portStatusPill,
               selected || hovering {
                WorkspaceTabStatusPill(model: portStatusPill)
            }
            if let healthStatusPill {
                WorkspaceTabStatusPill(model: healthStatusPill)
            }
            if row.unreadCount > 0 {
                WorkspaceTabUnreadDot(selected: selected)
            }
            if activeAgentCount > 0 {
                ProgressView()
                    .controlSize(.small)
                    .tint(theme.floatingEmphasis)
                    .scaleEffect(0.55)
                    .frame(width: 13, height: 13)
                    .accessibilityHidden(true)
            }
            ChromeTabCloseButton(
                visible: canClose && (selected || hovering),
                titleColor: titleColor,
                accessibility: L("关闭工作区", "Close Workspace"),
                tooltip: L("关闭工作区", "Close Workspace"),
                action: onClose
            )
            .opacity(canClose ? 1 : 0)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(tabAccessibilityTitle)
        .accessibilityAddTraits(.isButton)
    }

    private var editingContent: some View {
        HStack(spacing: 6) {
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
        }
    }
}

private enum WorkspaceTabStatusPillTone {
    case neutral
    case accent
    case attention
}

private struct WorkspaceTabStatusPillModel: Equatable {
    let systemImage: String
    let text: String
    let tone: WorkspaceTabStatusPillTone
}

private struct WorkspaceTabStatusPill: View {
    let model: WorkspaceTabStatusPillModel
    @Environment(\.conductorTheme) private var theme
    @Environment(\.conductorFontScale) private var fontScale

    var body: some View {
        HStack(spacing: model.text.isEmpty ? 0 : 3) {
            Image(systemName: model.systemImage)
                .font(.conductorSystem(size: model.text.isEmpty ? 9.5 : 7.5, weight: .semibold, scale: fontScale))
                .accessibilityHidden(true)
            if !model.text.isEmpty {
                Text(model.text)
                    .font(.conductorSystem(size: 8.8, weight: .semibold, scale: fontScale))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 62)
            }
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, model.text.isEmpty ? 0 : 4)
        .frame(width: model.text.isEmpty ? 15 : nil, height: 15)
        .background(background)
        .clipShape(Capsule())
        .accessibilityHidden(true)
    }

    private var foreground: Color {
        switch model.tone {
        case .neutral:
            return theme.shellChromeTextMuted.opacity(0.74)
        case .accent:
            return theme.floatingEmphasis.opacity(0.92)
        case .attention:
            return theme.usesDarkChrome ? Color.orange.opacity(0.94) : Color.orange.opacity(0.82)
        }
    }

    private var background: Color {
        switch model.tone {
        case .neutral:
            return theme.shellControlFill.opacity(theme.usesDarkChrome ? 0.30 : 0.18)
        case .accent:
            return theme.shellSelectedFill.opacity(theme.usesDarkChrome ? 0.58 : 0.44)
        case .attention:
            return Color.orange.opacity(theme.usesDarkChrome ? 0.16 : 0.10)
        }
    }
}

private struct WorkspaceTabUnreadDot: View {
    let selected: Bool
    @Environment(\.conductorTheme) private var theme

    var body: some View {
        Circle()
            .fill(theme.floatingEmphasis.opacity(selected ? 0.92 : 0.74))
            .frame(width: 5.5, height: 5.5)
            .overlay {
                Circle()
                    .stroke((selected ? Color.white.opacity(0.24) : theme.shellPanelBackground.opacity(0.70)), lineWidth: 0.8)
            }
            .shadow(color: theme.floatingEmphasis.opacity(selected ? 0.22 : 0.10), radius: 2, y: 0.5)
            .accessibilityHidden(true)
    }
}

private struct WorkspaceTabGlyph: View {
    let selected: Bool
    @Environment(\.conductorTheme) private var theme

    var body: some View {
        Image(systemName: WorkspaceChromeGlyph.systemName(selected: selected))
            .font(.system(size: 10.5, weight: .bold))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(selected ? Color.white.opacity(0.96) : theme.shellChromeTextMuted.opacity(0.70))
            .frame(width: selected ? 20 : 15, height: selected ? 20 : 15)
            .background(selected ? theme.shellControlRaisedFill.opacity(0.44) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .accessibilityHidden(true)
    }
}
