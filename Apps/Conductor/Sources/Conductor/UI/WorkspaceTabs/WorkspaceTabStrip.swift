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
    static let topInset: CGFloat = 0
    static let spacing: CGFloat = 0
    static let edgePadding: CGFloat = 0

    static func width(for availableWidth: CGFloat, count: Int) -> CGFloat {
        guard count > 0 else { return maxWidth }
        let raw = availableWidth / CGFloat(count)
        return min(max(raw, minWidth), maxWidth)
    }
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
                        chromeTab(for: entry, width: tabWidth)
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

    @ViewBuilder
    private func chromeTab(for entry: ChromeTabEntry, width: CGFloat) -> some View {
        switch entry.kind {
        case .workspace(let row):
            workspaceTabView(for: row, width: width)
                .id(WorkspaceTopTabScrollTarget.workspace(row.id))
        case .file(let fileTab):
            WorkspaceFileTopTab(
                tab: fileTab.tab,
                width: width,
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

    private func workspaceTabView(for row: WorkspaceChromeDisplayModel, width: CGFloat) -> some View {
        WorkspaceTopTab(
            row: row,
            width: width,
            appearance: appearance,
            selected: row.selected && snapshot.selectedWorkspaceFileTabID == nil && snapshot.selectedWorkspaceWebTabID == nil,
            canClose: snapshot.canCloseWorkspace,
            canCloseRight: canCloseWorkspacesToRight(of: row.id),
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
    @ViewBuilder var content: Content
    @Environment(\.conductorTheme) private var theme

    private var tabFill: Color {
        if selected {
            return theme.floatingSelectedFill
        }
        return Color.clear
    }

    var body: some View {
        content
            .frame(width: width, height: height, alignment: .leading)
            .background(tabFill, in: RoundedRectangle(cornerRadius: WorkspaceTabMetrics.cornerRadius, style: .continuous))
        .frame(width: width, height: railHeight, alignment: .center)
        .contentShape(Rectangle())
        .accessibilityIdentifier("ConductorWorkspaceTabInteractiveRegion")
    }
}

@MainActor
private func chromeTabCloseButton(
    visible: Bool,
    accessibility: String,
    tooltip: String,
    action: @escaping () -> Void
) -> some View {
    Button(action: action) {
        Label(accessibility, systemImage: "xmark")
    }
    .labelStyle(.iconOnly)
    .buttonStyle(.borderless)
    .controlSize(.mini)
    .disabled(!visible)
    .opacity(visible ? 1 : 0)
    .accessibilityLabel(accessibility)
    .help(tooltip)
}

private struct WorkspaceFileTopTab: View {
    let tab: ConductorWorkspaceFileTab
    let width: CGFloat
    let appearance: AppearancePreferences
    let selected: Bool
    let dirty: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    let onOpenExternal: () -> Void
    let onReveal: () -> Void
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorTheme) private var theme

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
            selected: selected
        ) {
            HStack(spacing: 6) {
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
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(accessibilityTitle)
                chromeTabCloseButton(
                    visible: selected,
                    accessibility: L("关闭文件", "Close File"),
                    tooltip: L("关闭文件", "Close File"),
                    action: onClose
                )
            }
            .padding(.leading, 9)
            .padding(.trailing, 5)
            .padding(.top, WorkspaceTabMetrics.topInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
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
            Label {
                Text(title)
                    .font(.conductorSystem(size: 11.3, weight: selected ? .semibold : .medium, scale: fontScale))
                    .foregroundStyle(selected ? theme.shellChromeText.opacity(0.94) : theme.shellChromeTextMuted.opacity(0.86))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } icon: {
                Image(systemName: systemImage)
                    .font(.system(size: 10.8, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(selected ? theme.shellChromeText.opacity(0.90) : theme.shellChromeTextMuted.opacity(0.70))
                    .frame(width: 15, height: 15)
            }
            .labelStyle(.titleAndIcon)
            Image(systemName: "circle.fill")
                .font(.system(size: 5.2, weight: .bold))
                .foregroundStyle(theme.floatingEmphasis.opacity(0.92))
                .frame(width: 7, height: 7)
                .opacity(dirty ? 1 : 0)
        }
    }
}

private struct WorkspaceWebTopTab: View {
    let tab: WorkspaceWebTabState
    let width: CGFloat
    let appearance: AppearancePreferences
    let selected: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    let onOpenExternal: () -> Void
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorTheme) private var theme

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
            selected: selected
        ) {
            HStack(spacing: 6) {
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
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(displayTitle)
                chromeTabCloseButton(
                    visible: selected,
                    accessibility: L("关闭网页", "Close Web Tab"),
                    tooltip: L("关闭网页", "Close Web Tab"),
                    action: onClose
                )
            }
            .padding(.leading, 9)
            .padding(.trailing, 5)
            .padding(.top, WorkspaceTabMetrics.topInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
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
            Label {
                Text(title)
                    .font(.conductorSystem(size: 11.3, weight: selected ? .semibold : .medium, scale: fontScale))
                    .foregroundStyle(selected ? theme.shellChromeText.opacity(0.94) : theme.shellChromeTextMuted.opacity(0.86))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } icon: {
                Image(systemName: systemImage)
                    .font(.system(size: 10.8, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(selected ? theme.shellChromeText.opacity(0.90) : theme.shellChromeTextMuted.opacity(0.70))
                    .frame(width: 15, height: 15)
            }
            .labelStyle(.titleAndIcon)
            Image(systemName: "circle.fill")
                .font(.system(size: 5.2, weight: .bold))
                .foregroundStyle(theme.floatingEmphasis.opacity(0.92))
                .frame(width: 7, height: 7)
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
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorTheme) private var theme

    private var activeAgentCount: Int {
        row.activeAgentCount
    }

    private var titleColor: Color {
        if selected {
            return theme.shellChromeText.opacity(0.95)
        }
        return theme.shellChromeTextMuted.opacity(0.64)
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

    private var primaryStatusLabel: WorkspaceTabStatusModel? {
        nil
    }

    private var portStatusLabel: WorkspaceTabStatusModel? {
        guard let port = row.metadata?.runningPorts.first else { return nil }
        return WorkspaceTabStatusModel(systemImage: "network", text: ":\(port)", tone: .accent)
    }

    private var healthStatusLabel: WorkspaceTabStatusModel? {
        guard let health = row.metadata?.health,
              health != "ok" else {
            return nil
        }
        return WorkspaceTabStatusModel(
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
            selected: selected || editing
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
        .help(tabAccessibilityTitle)
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
            Button(action: onSelect) {
                HStack(spacing: 6) {
                    Label {
                        Text(row.title)
                            .font(.conductorSystem(size: 11.3, weight: selected ? .semibold : .medium, scale: fontScale))
                            .foregroundStyle(titleColor)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } icon: {
                        tabGlyph(selected: selected)
                    }
                    .labelStyle(.titleAndIcon)
                    if width > 118,
                       let primaryStatusLabel,
                       selected {
                        tabStatusLabel(primaryStatusLabel)
                    }
                    if width > 158,
                       let portStatusLabel,
                       selected {
                        tabStatusLabel(portStatusLabel)
                    }
                    if let healthStatusLabel {
                        tabStatusLabel(healthStatusLabel)
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
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(tabAccessibilityTitle)
            chromeTabCloseButton(
                visible: canClose && selected,
                accessibility: L("关闭工作区", "Close Workspace"),
                tooltip: L("关闭工作区", "Close Workspace"),
                action: onClose
            )
            .opacity(canClose ? 1 : 0)
        }
    }

    private var editingContent: some View {
        Label {
            RenameTextField(
                text: $titleDraft,
                placeholder: L("工作区名称", "Workspace Name"),
                font: .conductorSystemFont(ofSize: 11.5, weight: .bold, scale: fontScale),
                textColor: NSColor(theme.shellChromeText),
                onCommit: onCommitRename,
                onCancel: onCancelRename
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        } icon: {
            tabGlyph(selected: true)
        }
        .labelStyle(.titleAndIcon)
    }

    private func tabGlyph(selected: Bool) -> some View {
        Image(systemName: WorkspaceChromeGlyph.systemName(selected: selected))
            .font(.system(size: 10.5, weight: .bold))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(selected ? theme.shellChromeText.opacity(0.86) : theme.shellChromeTextMuted.opacity(0.70))
            .frame(width: 16, height: 16)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private func tabStatusLabel(_ model: WorkspaceTabStatusModel) -> some View {
        if model.text.isEmpty {
            Label(model.accessibilityTitle, systemImage: model.systemImage)
                .labelStyle(.iconOnly)
                .font(.conductorSystem(size: 9.2, weight: .semibold, scale: fontScale))
                .foregroundStyle(statusForeground(for: model.tone))
                .frame(width: 13, height: 15)
                .accessibilityHidden(true)
        } else {
            Label {
                Text(model.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 62)
            } icon: {
                Image(systemName: model.systemImage)
                    .accessibilityHidden(true)
            }
            .labelStyle(.titleAndIcon)
            .font(.conductorSystem(size: 8.8, weight: .semibold, scale: fontScale))
            .foregroundStyle(statusForeground(for: model.tone))
            .frame(height: 15)
            .accessibilityHidden(true)
        }
    }

    private func statusForeground(for tone: WorkspaceTabStatusTone) -> Color {
        switch tone {
        case .neutral:
            return theme.shellChromeTextMuted.opacity(0.74)
        case .accent:
            return theme.floatingEmphasis.opacity(0.78)
        case .attention:
            return theme.usesDarkChrome ? Color.orange.opacity(0.94) : Color.orange.opacity(0.82)
        }
    }
}

private enum WorkspaceTabStatusTone {
    case neutral
    case accent
    case attention
}

private struct WorkspaceTabStatusModel: Equatable {
    let systemImage: String
    let text: String
    let tone: WorkspaceTabStatusTone

    var accessibilityTitle: String {
        text.isEmpty ? systemImage : text
    }
}

private struct WorkspaceTabUnreadDot: View {
    let selected: Bool
    @Environment(\.conductorTheme) private var theme

    var body: some View {
        Label(L("未读通知", "Unread notifications"), systemImage: "bell.fill")
            .labelStyle(.iconOnly)
            .font(.system(size: 8, weight: .semibold))
            .foregroundStyle(theme.floatingEmphasis.opacity(selected ? 0.74 : 0.58))
            .frame(width: 10, height: 10)
            .accessibilityHidden(true)
    }
}
