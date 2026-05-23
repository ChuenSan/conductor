import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

private func L(_ zh: String, _ en: String) -> String {
    ConductorLocalization.text(zh: zh, en: en)
}

struct FileManagerPanelRequest: Equatable, Identifiable, Sendable {
    let id = UUID()
    let rootURL: URL
    let selectedURL: URL?

    init(rootURL: URL, selectedURL: URL? = nil) {
        self.rootURL = rootURL.standardizedFileURL
        self.selectedURL = selectedURL?.standardizedFileURL
    }
}

struct FileManagerPanel: View {
    let model: ConductorWindowModel
    let request: FileManagerPanelRequest
    let searchFocusToken: Int
    let searchNextToken: Int
    let searchPreviousToken: Int
    @StateObject private var store = FileManagerPanelStore()
    @FocusState private var keyboardFocused: Bool
    @State private var searchVisible = false
    @State private var infoItem: FileManagerItem?
    @Environment(\.conductorTheme) private var theme
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorFontFamily) private var fontFamily

    var body: some View {
        let snapshot = store.displaySnapshot
        VStack(spacing: 0) {
            header
                .zIndex(1)
            divider
                .zIndex(1)
            if searchVisible || !store.searchQuery.isEmpty {
                fileTreeSearchBar(snapshot: snapshot)
                    .zIndex(1)
                divider
                    .zIndex(1)
            }
            content(snapshot: snapshot)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .zIndex(0)
            divider
            statusBar(snapshot: snapshot)
            if let message = store.operationMessage {
                divider
                operationMessageBar(message)
            }
            if store.pendingDeleteCount > 0 {
                divider
                deleteConfirmationBar(count: store.pendingDeleteCount)
            }
        }
        .background(panelBackground)
        .background {
            ConductorKeyboardShortcutBridge(autofocus: false) { event in
                handleKeyboardShortcut(event)
            }
            .frame(width: 0, height: 0)
        }
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(theme.terminalOuterStroke.opacity(theme.usesDarkChrome ? 0.42 : 0.26))
                .frame(width: 1)
        }
        .task(id: request.id) {
            await store.load(request)
            keyboardFocused = model.selectedWorkspaceFileTab == nil
        }
        .focusable()
        .focused($keyboardFocused)
        .focusEffectDisabled()
        .onTapGesture {
            keyboardFocused = true
        }
        .simultaneousGesture(TapGesture().onEnded {
            keyboardFocused = true
        })
        .onChange(of: keyboardFocused) { _, newValue in
            model.setFileManagerKeyboardFocused(newValue)
        }
        .onDisappear {
            model.setFileManagerKeyboardFocused(false)
        }
        .onMoveCommand { direction in
            switch direction {
            case .up:
                store.selectAdjacentRow(by: -1)
            case .down:
                store.selectAdjacentRow(by: 1)
            case .left:
                store.collapseSelected()
            case .right:
                Task { await store.expandSelected() }
            default:
                break
            }
        }
        .onSubmit {
            openSelectedItem()
        }
        .onDeleteCommand {
            deleteSelectedItem()
        }
        .onExitCommand {
            model.closeFileManagerPanel()
        }
        .onChange(of: searchFocusToken) { _, newValue in
            guard newValue > 0 else { return }
            keyboardFocused = true
            showSearch()
        }
        .onChange(of: searchNextToken) { _, newValue in
            guard newValue > 0 else { return }
            keyboardFocused = true
            showSearch()
            store.selectAdjacentRow(by: 1)
        }
        .onChange(of: searchPreviousToken) { _, newValue in
            guard newValue > 0 else { return }
            keyboardFocused = true
            showSearch()
            store.selectAdjacentRow(by: -1)
        }
        .onChange(of: model.selectedWorkspaceFileTab?.id) { _, newValue in
            guard newValue == nil else { return }
            keyboardFocused = true
        }
        .sheet(item: $infoItem) { item in
            FileManagerInfoSheet(item: item)
        }
    }

    private var panelBackground: Color {
        theme.usesDarkChrome
            ? theme.terminalRaisedBackground.opacity(0.96)
            : theme.terminalBackground.opacity(0.985)
    }

    private var headerBackground: Color {
        theme.usesDarkChrome
            ? theme.terminalChrome.opacity(0.44)
            : theme.terminalChrome.opacity(0.16)
    }

    private var currentFolderTitle: String {
        let url = store.currentURL ?? request.rootURL
        let name = url.lastPathComponent
        return name.isEmpty ? url.path : name
    }

    private var header: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                favoriteButton

                VStack(alignment: .leading, spacing: 1) {
                    Text(currentFolderTitle)
                        .font(.conductorSystem(size: 13.4, weight: .bold, family: fontFamily, scale: fontScale))
                        .foregroundStyle(theme.shellChromeText.opacity(0.90))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(store.sortMode.title)
                        .font(.conductorSystem(size: 9.7, weight: .semibold, family: fontFamily, scale: fontScale))
                        .foregroundStyle(theme.shellChromeText.opacity(0.42))
                        .lineLimit(1)
                }

                Spacer(minLength: 10)

                panelIconButton("xmark", help: L("关闭文件面板", "Close Files")) {
                    model.closeFileManagerPanel()
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 9)
            .padding(.bottom, 7)

            breadcrumbBar
                .padding(.horizontal, 14)
                .padding(.bottom, 7)

            HStack(spacing: 5) {
                quickAccessMenuButton
                sortMenuButton
                kindFilterMenuButton

                toolbarSeparator

                panelIconButton(store.includeHiddenFiles ? "eye" : "eye.slash", help: L("显示/隐藏隐藏文件", "Show/Hide Hidden Files")) {
                    Task { await store.setIncludeHiddenFiles(!store.includeHiddenFiles) }
                }

                panelIconButton("doc.badge.plus", help: L("新建文件", "New File")) {
                    Task { await store.createFile() }
                }

                panelIconButton("folder.badge.plus", help: L("新建文件夹", "New Folder")) {
                    Task { await store.createFolder() }
                }

                toolbarSeparator

                panelIconButton("arrow.up", help: L("上级目录", "Parent Directory"), disabled: store.currentURL == nil) {
                    Task { await store.goUp() }
                }

                panelIconButton("arrow.clockwise", help: L("刷新文件", "Refresh Files")) {
                    Task { await store.refresh() }
                }

                panelIconButton("folder", help: L("在 Finder 中显示当前目录", "Reveal Current Directory in Finder")) {
                    reveal(store.currentURL ?? request.rootURL)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(theme.shellControlFill.opacity(theme.usesDarkChrome ? 0.18 : 0.10))
        }
        .background(headerBackground)
    }

    private var quickAccessMenuButton: some View {
        Menu {
            if !store.favoriteDirectoryURLs.isEmpty {
                Section(L("收藏目录", "Favorites")) {
                    ForEach(store.favoriteDirectoryURLs, id: \.path) { url in
                        Button(url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent) {
                            Task { await store.openBreadcrumb(url) }
                        }
                    }
                }
            }
            if !store.recentFileURLs.isEmpty {
                Section(L("最近文件", "Recent Files")) {
                    ForEach(store.recentFileURLs, id: \.path) { url in
                        Button(url.lastPathComponent) {
                            openURL(url)
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "clock")
                .renderingMode(.template)
                .symbolRenderingMode(.monochrome)
                .font(toolbarIconFont)
                .foregroundStyle(toolbarIconColor)
                .frame(width: 28, height: 28)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .macNativeTooltip(L("最近和收藏", "Recent and Favorites"))
    }

    private var sortMenuButton: some View {
        Menu {
            Section(L("排序", "Sort")) {
                ForEach(FileManagerSortMode.allCases) { mode in
                    Button {
                        Task { await store.setSortMode(mode) }
                    } label: {
                        Label(mode.title, systemImage: mode == store.sortMode ? "checkmark" : "arrow.up.arrow.down")
                    }
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .renderingMode(.template)
                .symbolRenderingMode(.monochrome)
                .font(toolbarIconFont)
                .foregroundStyle(toolbarIconColor)
                .frame(width: 28, height: 28)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .macNativeTooltip(L("排序方式", "Sort"))
    }

    private var kindFilterMenuButton: some View {
        Menu {
            Section(L("类型过滤", "Kind Filter")) {
                ForEach(FileManagerKindFilter.allCases) { filter in
                    Button {
                        store.setKindFilter(filter)
                    } label: {
                        Label(filter.title, systemImage: filter == store.kindFilter ? "checkmark" : filter.systemImage)
                    }
                }
            }
        } label: {
            Image(systemName: store.kindFilter.systemImage)
                .renderingMode(.template)
                .symbolRenderingMode(.monochrome)
                .font(toolbarIconFont)
                .foregroundStyle(toolbarIconColor)
                .frame(width: 28, height: 28)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .macNativeTooltip(L("类型过滤", "Kind Filter"))
    }

    private var toolbarSeparator: some View {
        Rectangle()
            .fill(theme.shellStroke.opacity(theme.usesDarkChrome ? 0.20 : 0.26))
            .frame(width: 1, height: 18)
            .padding(.horizontal, 3)
    }

    private var toolbarIconFont: Font {
        .conductorSystem(size: toolbarIconSymbolSize, weight: .semibold, family: fontFamily, scale: fontScale)
    }

    private var toolbarIconColor: Color {
        theme.shellChromeText.opacity(toolbarIconOpacity)
    }

    private var favoriteButton: some View {
        Button {
            store.toggleFavoriteDirectory(store.currentURL ?? request.rootURL)
        } label: {
            Image(systemName: store.isFavoriteDirectory(store.currentURL ?? request.rootURL) ? "star.fill" : "folder")
                .font(.conductorSystem(size: 13, weight: .semibold, family: fontFamily, scale: fontScale))
                .foregroundStyle(store.isFavoriteDirectory(store.currentURL ?? request.rootURL) ? theme.floatingEmphasis.opacity(0.95) : theme.floatingEmphasis.opacity(0.78))
                .frame(width: 24, height: 28)
        }
        .buttonStyle(.plain)
        .macNativeTooltip(L("收藏当前目录", "Favorite Current Directory"))
    }

    private var breadcrumbBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "location")
                .font(.conductorSystem(size: 9.5, weight: .semibold, family: fontFamily, scale: fontScale))
                .foregroundStyle(theme.shellChromeText.opacity(0.42))
                .frame(width: 14)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ForEach(breadcrumbURLs, id: \.path) { url in
                        Button {
                            Task { await store.openBreadcrumb(url) }
                        } label: {
                            Text(breadcrumbTitle(for: url))
                                .font(.conductorSystem(size: 10.5, weight: .semibold, family: fontFamily, scale: fontScale))
                                .foregroundStyle(url.path == breadcrumbURLs.last?.path ? theme.shellChromeText.opacity(0.68) : theme.shellChromeText.opacity(0.44))
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .buttonStyle(.plain)
                        if url.path != breadcrumbURLs.last?.path {
                            Image(systemName: "chevron.right")
                                .font(.conductorSystem(size: 7.5, weight: .bold, family: fontFamily, scale: fontScale))
                                .foregroundStyle(theme.shellChromeText.opacity(0.25))
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(height: 24)
        .padding(.horizontal, 8)
        .background(theme.shellControlFill.opacity(theme.usesDarkChrome ? 0.20 : 0.12))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private var breadcrumbURLs: [URL] {
        let url = store.currentURL ?? request.rootURL
        let standardized = url.standardizedFileURL
        var components: [URL] = []
        var cursor = standardized
        while cursor.path != "/" {
            components.append(cursor)
            let parent = cursor.deletingLastPathComponent()
            guard parent.path != cursor.path else { break }
            cursor = parent
        }
        components.append(URL(fileURLWithPath: "/"))
        return Array(components.reversed().suffix(5))
    }

    private func breadcrumbTitle(for url: URL) -> String {
        if url.path == "/" { return "/" }
        return url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
    }

    @ViewBuilder
    private func content(snapshot: FileManagerDisplaySnapshot) -> some View {
        browser(snapshot: snapshot)
    }

    private func fileTreeSearchBar(snapshot: FileManagerDisplaySnapshot) -> some View {
        EmptyView()
    }

    private func browser(snapshot: FileManagerDisplaySnapshot) -> some View {
        FileManagerListView(
            store: store,
            model: model,
            rootURL: request.rootURL,
            infoItem: $infoItem,
            focusKeyboard: { keyboardFocused = true }
        )
    }

    private func statusBar(snapshot: FileManagerDisplaySnapshot) -> some View {
        let selectedItems = store.selectedItemsForDisplay
        return HStack(spacing: 8) {
            if store.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, store.kindFilter == .all {
                statusChip(systemImage: "list.bullet", title: L("\(snapshot.totalKnownItemCount) 项", "\(snapshot.totalKnownItemCount) items"))
            } else {
                statusChip(systemImage: "line.3.horizontal.decrease", title: L("\(snapshot.totalRowCount)/\(snapshot.totalKnownItemCount)", "\(snapshot.totalRowCount)/\(snapshot.totalKnownItemCount)"))
            }
            statusChip(systemImage: "folder", title: L("\(snapshot.displayedDirectoryCount)", "\(snapshot.displayedDirectoryCount)"))
            statusChip(systemImage: "doc", title: L("\(snapshot.displayedFileCount)", "\(snapshot.displayedFileCount)"))

            if store.kindFilter != .all {
                statusChip(systemImage: store.kindFilter.systemImage, title: store.kindFilter.title)
            }

            if !selectedItems.isEmpty {
                statusChip(systemImage: "checkmark.circle", title: selectionSummary(for: selectedItems))
            }

            Spacer(minLength: 8)

            Text((store.currentURL ?? request.rootURL).path)
                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                .foregroundStyle(theme.shellChromeText.opacity(0.42))
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(theme.shellControlFill.opacity(theme.usesDarkChrome ? 0.12 : 0.08))
    }

    private func selectionSummary(for items: [FileManagerItem]) -> String {
        guard !items.isEmpty else { return L("0 项", "0 items") }
        let selectedSize = items.compactMap(\.byteCount).reduce(Int64(0), +)
        let size = selectedSize > 0 ? " · \(ByteCountFormatter.string(fromByteCount: selectedSize, countStyle: .file))" : ""
        return L("\(items.count) 项\(size)", "\(items.count) item(s)\(size)")
    }

    private func statusChip(systemImage: String, title: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.conductorSystem(size: 9.5, weight: .semibold, family: fontFamily, scale: fontScale))
            Text(title)
                .font(.conductorSystem(size: 10.5, weight: .semibold, family: fontFamily, scale: fontScale))
                .lineLimit(1)
        }
        .foregroundStyle(theme.shellChromeText.opacity(0.50))
        .padding(.horizontal, 7)
        .frame(height: 19)
        .background(theme.floatingControlFill.opacity(theme.usesDarkChrome ? 0.26 : 0.22))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private func operationMessageBar(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.conductorSystem(size: 12, weight: .semibold, family: fontFamily, scale: fontScale))
            Text(message)
                .font(.conductorSystem(size: 11.5, weight: .semibold, family: fontFamily, scale: fontScale))
                .lineLimit(2)
            Spacer(minLength: 8)
            if store.canUndoTrash {
                Button {
                    Task {
                        let restoredPaths = await store.undoLastTrash()
                        for path in restoredPaths {
                            model.updateWorkspaceFileTabs(
                                moving: path,
                                to: URL(fileURLWithPath: path),
                                isDirectory: true
                            )
                        }
                    }
                } label: {
                    Text(L("撤销", "Undo"))
                        .font(.conductorSystem(size: 11.2, weight: .bold, family: fontFamily, scale: fontScale))
                        .padding(.horizontal, 9)
                        .frame(height: 23)
                }
                .buttonStyle(.plain)
                .background(theme.floatingSelectedFill.opacity(0.42))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            panelIconButton("xmark", help: L("关闭提示", "Dismiss Message")) {
                store.clearOperationMessage()
            }
        }
        .foregroundStyle(theme.shellChromeText.opacity(0.84))
        .padding(.horizontal, 14)
        .frame(minHeight: 38)
        .background(theme.floatingControlStrongFill.opacity(theme.usesDarkChrome ? 0.36 : 0.42))
    }

    private func deleteConfirmationBar(count: Int) -> some View {
        HStack(spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: "trash")
                    .font(.conductorSystem(size: 12, weight: .bold, family: fontFamily, scale: fontScale))
                Text(L("已标记 \(count) 项删除", "\(count) item(s) marked for delete"))
                    .font(.conductorSystem(size: 12, weight: .semibold, family: fontFamily, scale: fontScale))
                    .lineLimit(1)
            }
            .foregroundStyle(Color.white.opacity(0.94))

            Spacer(minLength: 8)

            Button {
                store.cancelPendingDeletes()
            } label: {
                Image(systemName: "xmark")
                    .font(.conductorSystem(size: 12, weight: .bold, family: fontFamily, scale: fontScale))
                    .foregroundStyle(Color.white.opacity(0.96))
                    .frame(width: 24, height: 22)
            }
            .buttonStyle(.plain)
            .macNativeTooltip(L("取消删除", "Cancel Delete"))

            Button {
                Task {
                    let deletedPaths = await store.confirmPendingDeletes()
                    model.closeWorkspaceFileTabs(matchingDeletedPaths: deletedPaths)
                }
            } label: {
                Image(systemName: "checkmark")
                    .font(.conductorSystem(size: 12, weight: .bold, family: fontFamily, scale: fontScale))
                    .foregroundStyle(Color.white.opacity(0.96))
                    .frame(width: 24, height: 22)
            }
            .buttonStyle(.plain)
            .macNativeTooltip(L("确认移到废纸篓", "Confirm Move to Trash"))
        }
        .padding(.horizontal, 14)
        .frame(height: 38)
        .background(Color.red.opacity(theme.usesDarkChrome ? 0.66 : 0.74))
    }

    private func open(_ item: FileManagerItem) {
        let flags = NSApp.currentEvent?.modifierFlags.intersection(.deviceIndependentFlagsMask) ?? []
        if flags.contains(.shift) {
            store.select(item, mode: .range)
            return
        }
        if flags.contains(.command) {
            store.select(item, mode: .toggle)
            return
        }
        if item.isDirectory {
            Task { await store.open(item) }
            return
        }
        store.select(item)
        openInWorkspace(item)
    }

    private func openInWorkspace(_ item: FileManagerItem) {
        guard !item.isDirectory else {
            Task { await store.open(item) }
            return
        }
        store.recordOpenedFile(item.url)
        model.openFileInWorkspace(item.url, rootURL: store.currentURL ?? request.rootURL)
        keyboardFocused = true
    }

    private func openURL(_ url: URL) {
        let standardized = url.standardizedFileURL
        guard FileManager.default.fileExists(atPath: standardized.path) else {
            return
        }
        store.recordOpenedFile(standardized)
        model.openFileInWorkspace(standardized, rootURL: standardized.deletingLastPathComponent())
        keyboardFocused = true
    }

    private func openSelectedItem() {
        guard let item = store.selectedItem ?? store.displayedRows.first?.item else { return }
        open(item)
    }

    private func deleteSelectedItem() {
        let items = store.selectedItems
        if !items.isEmpty {
            store.markForDelete(items)
        } else if let item = store.selectedItem {
            store.markForDelete(item)
        }
    }

    private func filePreview(item: FileManagerItem) -> some View {
        VStack(spacing: 0) {
            previewToolbar(item: item)
            divider
            filePreviewBody(
                state: store.previewState,
                rootURL: request.rootURL,
                currentURL: store.currentURL,
                theme: theme,
                terminalFontSize: model.appearance.terminalFontSize,
                fontFamily: fontFamily,
                fontScale: fontScale
            )
        }
    }

    private func previewToolbar(item: FileManagerItem) -> some View {
        HStack(spacing: 8) {
            panelIconButton("chevron.left", help: L("返回目录", "Back to Directory")) {
                store.clearSelection()
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(item.name)
                    .font(.conductorSystem(size: 12, weight: .bold, family: fontFamily, scale: fontScale))
                    .foregroundStyle(theme.shellChromeText.opacity(0.84))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(item.subtitle)
                    .font(.conductorSystem(size: 10, weight: .medium, family: fontFamily, scale: fontScale))
                    .foregroundStyle(theme.shellChromeText.opacity(0.48))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if !item.isDirectory {
                panelIconButton("rectangle.split.2x1", help: L("在工作区打开", "Open in Workspace")) {
                    openInWorkspace(item)
                }

                panelIconButton("arrow.up.forward.app", help: L("系统应用打开", "Open in System App")) {
                    NSWorkspace.shared.open(item.url)
                }
            }

            panelIconButton("terminal", help: L("插入路径到终端", "Insert Path into Terminal"), disabled: model.focusedTerminalID == nil) {
                _ = model.insertPathIntoFocusedTerminal(item.url)
            }

            panelIconButton("textformat", help: L("复制文件名", "Copy Name")) {
                copyText(item.name)
            }

            panelIconButton("doc.on.doc", help: L("复制路径", "Copy Path")) {
                copyPath(item.url)
            }

            panelIconButton("quote.bubble", help: L("复制 Shell 路径", "Copy Shell Path")) {
                copyText(shellEscapedPath(item.url.path))
            }

            panelIconButton("info.circle", help: L("显示信息", "Get Info")) {
                infoItem = item
            }

            panelIconButton("folder", help: L("在 Finder 中显示", "Reveal in Finder")) {
                reveal(item.url)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
    }

    private var divider: some View {
        Rectangle()
            .fill(theme.terminalOuterStroke.opacity(theme.usesDarkChrome ? 0.26 : 0.18))
            .frame(height: 1)
    }

    private func panelIconButton(_ systemImage: String, help: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        FileManagerPanelIconButton(
            systemImage: systemImage,
            help: help,
            size: 28,
            symbolSize: toolbarIconSymbolSize,
            iconColor: theme.shellChromeText,
            opacity: toolbarIconOpacity,
            disabledOpacity: toolbarDisabledIconOpacity,
            fontScale: fontScale,
            fontFamily: fontFamily,
            disabled: disabled,
            action: action
        )
        .frame(width: 28, height: 28)
    }

    private var toolbarIconSymbolSize: CGFloat { 12.5 }
    private var toolbarIconOpacity: CGFloat { 0.86 }
    private var toolbarDisabledIconOpacity: CGFloat { theme.usesDarkChrome ? 0.34 : 0.38 }

    private func copyPath(_ url: URL) {
        copyText(url.standardizedFileURL.path)
    }

    private func copyPaths(_ urls: [URL]) {
        copyText(urls.map { $0.standardizedFileURL.path }.joined(separator: "\n"))
    }

    private func copyText(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func relativePath(for url: URL) -> String {
        let root = request.rootURL.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path == root || path.hasPrefix(root + "/") else { return url.lastPathComponent }
        let suffix = path.dropFirst(root.count).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return suffix.isEmpty ? url.lastPathComponent : String(suffix)
    }

    private var canPaste: Bool {
        FileManagerService().fileURLsFromPasteboard().isEmpty == false
    }

    private func copyFile(_ url: URL) {
        copyFiles([url])
    }

    private func cutFile(_ url: URL) {
        cutFiles([url])
    }

    private func copyFiles(_ urls: [URL]) {
        FileManagerPasteboard.writeFiles(urls, cut: false)
    }

    private func cutFiles(_ urls: [URL]) {
        FileManagerPasteboard.writeFiles(urls, cut: true)
    }

    private func itemsForBatch(default item: FileManagerItem) -> [FileManagerItem] {
        let selected = store.selectedItems
        guard store.selectedPaths.contains(item.url.path), !selected.isEmpty else {
            return [item]
        }
        return selected
    }

    private func shellEscapedPath(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func paste(into item: FileManagerItem?) {
        let sources = FileManagerService().fileURLsFromPasteboard()
        guard !sources.isEmpty else { return }
        Task {
            let move = FileManagerPasteboard.containsCutMarker
            await store.pasteItems(sources, into: item, move: move)
            if move {
                NSPasteboard.general.clearContents()
            }
        }
    }

    private func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url.standardizedFileURL])
    }

    private func showSearch() {
        keyboardFocused = true
        searchVisible = true
    }

    private func closeSearch() {
        store.recordSearchQuery()
        searchVisible = false
        store.searchQuery = ""
    }

    private func handleKeyboardShortcut(_ event: NSEvent) -> Bool {
        guard keyboardFocused || model.selectedWorkspaceFileTab == nil else {
            return false
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let characters = event.charactersIgnoringModifiers?.lowercased() ?? ""

        if flags.contains(.command), flags.contains(.shift), event.keyCode == 36 {
            if let item = store.selectedItem {
                NSWorkspace.shared.open(item.url)
                return true
            }
            return false
        }

        if flags.contains(.command) {
            switch characters {
            case "n" where flags.contains(.shift):
                Task { await store.createFolder() }
                return true
            case "n":
                Task { await store.createFile() }
                return true
            case "r":
                Task { await store.refresh() }
                return true
            case "o":
                openSelectedItem()
                return true
            case "i":
                if let item = store.selectedItem {
                    infoItem = item
                    return true
                }
                return false
            case "c" where flags.contains(.option):
                let urls = store.selectedURLs
                if !urls.isEmpty {
                    copyPaths(urls)
                    return true
                }
                if let url = store.currentURL {
                    copyPath(url)
                    return true
                }
                return false
            case "c":
                let urls = store.selectedURLs
                guard !urls.isEmpty else { return false }
                copyFiles(urls)
                return true
            case "x":
                let urls = store.selectedURLs
                guard !urls.isEmpty else { return false }
                cutFiles(urls)
                return true
            case "v":
                paste(into: store.selectedItem)
                return true
            case "d":
                guard let item = store.selectedItem else { return false }
                Task { await store.duplicate(item) }
                return true
            default:
                if event.keyCode == 51, let item = store.selectedItem {
                    store.markForDelete(item)
                    return true
                }
                return false
            }
        }

        switch event.keyCode {
        case 36, 76:
            openSelectedItem()
            return true
        case 49:
            if let item = store.selectedItem {
                store.select(item)
            } else {
                store.selectAdjacentRow(by: 1)
            }
            return true
        case 51:
            deleteSelectedItem()
            return true
        case 53:
            if store.pendingDeleteCount > 0 {
                store.cancelPendingDeletes()
            } else if searchVisible || !store.searchQuery.isEmpty {
                closeSearch()
            } else {
                model.closeFileManagerPanel()
            }
            return true
        case 123:
            store.collapseSelected()
            return true
        case 124:
            Task { await store.expandSelected() }
            return true
        case 125:
            store.selectAdjacentRow(by: 1)
            return true
        case 126:
            store.selectAdjacentRow(by: -1)
            return true
        default:
            return false
        }
    }
}

private struct FileManagerInfoSheet: View {
    let item: FileManagerItem
    @Environment(\.dismiss) private var dismiss
    @Environment(\.conductorTheme) private var theme
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorFontFamily) private var fontFamily

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: item.isDirectory ? "folder.fill" : iconName)
                    .font(.conductorSystem(size: 32, weight: .semibold, family: fontFamily, scale: fontScale))
                    .foregroundStyle(item.isDirectory ? theme.floatingEmphasis.opacity(0.95) : theme.shellChromeText.opacity(0.68))
                    .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name)
                        .font(.conductorSystem(size: 17, weight: .bold, family: fontFamily, scale: fontScale))
                        .foregroundStyle(theme.shellChromeText.opacity(0.90))
                        .lineLimit(2)
                        .truncationMode(.middle)
                    Text(item.url.deletingLastPathComponent().path)
                        .font(.conductorSystem(size: 11, weight: .medium, family: fontFamily, scale: fontScale))
                        .foregroundStyle(theme.shellChromeText.opacity(0.48))
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                Spacer(minLength: 0)
            }

            VStack(spacing: 0) {
                infoRow(L("类型", "Kind"), item.typeLabel)
                infoRow(L("大小", "Size"), sizeLabel)
                infoRow(L("修改时间", "Modified"), dateLabel(item.modificationDate))
                infoRow(L("创建时间", "Created"), dateLabel(item.creationDate))
                infoRow(L("权限", "Permissions"), permissionLabel)
                infoRow(L("完整路径", "Full Path"), item.url.path, selectable: true)
                infoRow(L("所在目录", "Parent"), item.url.deletingLastPathComponent().path, selectable: true)
            }
            .background(theme.floatingControlFill.opacity(theme.usesDarkChrome ? 0.18 : 0.30))
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(theme.terminalOuterStroke.opacity(theme.usesDarkChrome ? 0.26 : 0.20), lineWidth: 1)
            }

            HStack(spacing: 8) {
                Button(L("复制路径", "Copy Path")) {
                    copyInfoText(item.url.path)
                }
                Button(L("复制 Shell 路径", "Copy Shell Path")) {
                    copyInfoText("'" + item.url.path.replacingOccurrences(of: "'", with: "'\\''") + "'")
                }
                Spacer()
                Button(L("完成", "Done")) {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 440)
        .background(theme.terminalBackground)
    }

    private func infoRow(_ title: String, _ value: String, selectable: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(title)
                .font(.conductorSystem(size: 11.5, weight: .semibold, family: fontFamily, scale: fontScale))
                .foregroundStyle(theme.shellChromeText.opacity(0.48))
                .frame(width: 72, alignment: .trailing)
            if selectable {
                Text(value)
                    .font(.conductorSystem(size: 11.5, weight: .medium, family: fontFamily, scale: fontScale))
                    .foregroundStyle(theme.shellChromeText.opacity(0.78))
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            } else {
                Text(value)
                    .font(.conductorSystem(size: 11.5, weight: .medium, family: fontFamily, scale: fontScale))
                    .foregroundStyle(theme.shellChromeText.opacity(0.78))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 32)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(theme.terminalOuterStroke.opacity(theme.usesDarkChrome ? 0.18 : 0.13))
                .frame(height: 1)
        }
    }

    private var sizeLabel: String {
        guard let byteCount = item.byteCount else {
            return item.isDirectory ? L("文件夹", "Folder") : L("未知", "Unknown")
        }
        return ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
    }

    private var permissionLabel: String {
        switch (item.isReadable, item.isWritable) {
        case (true, true):
            return L("可读写", "Readable and Writable")
        case (true, false):
            return L("只读", "Read Only")
        case (false, true):
            return L("仅可写", "Write Only")
        case (false, false):
            return L("不可读写", "No Read or Write Access")
        }
    }

    private var iconName: String {
        switch item.url.pathExtension.lowercased() {
        case "swift", "js", "jsx", "ts", "tsx", "rb", "py", "sh", "zsh", "bash":
            "curlybraces"
        case "json", "jsonl", "toml", "yaml", "yml", "xml":
            "doc.text"
        case "md", "txt", "log", "tex", "latex", "sty", "cls", "bib":
            "doc.plaintext"
        case "png", "jpg", "jpeg", "gif", "webp", "heic", "tiff":
            "photo"
        default:
            "doc"
        }
    }

    private func copyInfoText(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func dateLabel(_ date: Date?) -> String {
        guard let date else { return L("未知", "Unknown") }
        return Self.dateFormatter.string(from: date)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter
    }()
}
