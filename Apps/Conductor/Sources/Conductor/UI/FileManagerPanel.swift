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
    @FocusState private var searchFocused: Bool
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
            panelDivider
                .zIndex(1)
            if searchVisible || !store.searchQuery.isEmpty {
                fileTreeSearchBar(snapshot: snapshot)
                    .zIndex(1)
                    .transition(ConductorMotion.rowTransition(itemCount: 1))
                panelDivider
                    .zIndex(1)
            }
            content(snapshot: snapshot)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .zIndex(0)
            panelDivider
            statusBar(snapshot: snapshot)
            if let message = store.operationMessage {
                panelDivider
                operationMessageBar(message)
                    .transition(ConductorMotion.rowTransition(itemCount: 1))
            }
            if store.pendingDeleteCount > 0 {
                panelDivider
                deleteConfirmationBar(count: store.pendingDeleteCount)
                    .transition(ConductorMotion.rowTransition(itemCount: 1))
            }
        }
        .background(.regularMaterial)
        .background {
            ConductorKeyboardShortcutBridge(autofocus: false) { event in
                handleKeyboardShortcut(event)
            }
            .frame(width: 0, height: 0)
        }
        .task(id: request.id) {
            await store.load(request)
            keyboardFocused = model.selectedWorkspaceFileTab == nil
        }
        .focusable(canReceiveKeyboardFocus)
        .focused($keyboardFocused)
        .focusEffectDisabled()
        .simultaneousGesture(TapGesture().onEnded {
            focusKeyboardIfBrowsing()
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
            if !canReceiveKeyboardFocus {
                keyboardFocused = false
            } else if newValue == nil {
                keyboardFocused = true
            }
        }
        .animation(ConductorMotion.contentSwap, value: searchVisible || !store.searchQuery.isEmpty)
        .animation(ConductorMotion.contentSwap, value: store.operationMessage)
        .animation(ConductorMotion.contentSwap, value: store.pendingDeleteCount)
        .sheet(item: $infoItem) { item in
            FileManagerInfoSheet(item: item)
        }
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

                Button {
                    model.closeFileManagerPanel()
                } label: {
                    Label(L("关闭文件面板", "Close Files"), systemImage: "xmark")
                }
                .labelStyle(.iconOnly)
                .controlSize(.small)
                .help(L("关闭文件面板", "Close Files"))
                .accessibilityLabel(L("关闭文件面板", "Close Files"))
            }
            .padding(.horizontal, 14)
            .padding(.top, 9)
            .padding(.bottom, 7)

            breadcrumbBar
                .padding(.horizontal, 14)
                .padding(.bottom, 6)

            headerToolbar
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
        }
        .background(ConductorTokens.Settings.panelChromeWash(dark: theme.usesDarkChrome))
    }

    private var headerToolbar: some View {
        HStack(spacing: 7) {
            toolbarGroup {
                quickAccessMenuButton
                sortMenuButton
                kindFilterMenuButton
            }

            toolbarGroup {
                Button {
                    Task { await store.goUp() }
                } label: {
                    Label(L("上级目录", "Parent Directory"), systemImage: "arrow.up")
                }
                .labelStyle(.iconOnly)
                .controlSize(.small)
                .disabled(store.currentURL == nil)
                .help(L("上级目录", "Parent Directory"))
                .accessibilityLabel(L("上级目录", "Parent Directory"))

                Button {
                    Task { await store.refresh() }
                } label: {
                    Label(L("刷新文件", "Refresh Files"), systemImage: "arrow.clockwise")
                }
                .labelStyle(.iconOnly)
                .controlSize(.small)
                .help(L("刷新文件", "Refresh Files"))
                .accessibilityLabel(L("刷新文件", "Refresh Files"))

                Button {
                    Task { await store.setIncludeHiddenFiles(!store.includeHiddenFiles) }
                } label: {
                    Label(L("显示/隐藏隐藏文件", "Show/Hide Hidden Files"), systemImage: store.includeHiddenFiles ? "eye" : "eye.slash")
                }
                .labelStyle(.iconOnly)
                .controlSize(.small)
                .help(L("显示/隐藏隐藏文件", "Show/Hide Hidden Files"))
                .accessibilityLabel(L("显示/隐藏隐藏文件", "Show/Hide Hidden Files"))
            }

            Spacer(minLength: 0)

            toolbarGroup {
                Button {
                    Task { await store.createFile() }
                } label: {
                    Label(L("新建文件", "New File"), systemImage: "doc.badge.plus")
                }
                .labelStyle(.iconOnly)
                .controlSize(.small)
                .help(L("新建文件", "New File"))
                .accessibilityLabel(L("新建文件", "New File"))

                Button {
                    Task { await store.createFolder() }
                } label: {
                    Label(L("新建文件夹", "New Folder"), systemImage: "folder.badge.plus")
                }
                .labelStyle(.iconOnly)
                .controlSize(.small)
                .help(L("新建文件夹", "New Folder"))
                .accessibilityLabel(L("新建文件夹", "New Folder"))

                Button {
                    reveal(store.currentURL ?? request.rootURL)
                } label: {
                    Label(L("在 Finder 中显示当前目录", "Reveal Current Directory in Finder"), systemImage: "folder")
                }
                .labelStyle(.iconOnly)
                .controlSize(.small)
                .help(L("在 Finder 中显示当前目录", "Reveal Current Directory in Finder"))
                .accessibilityLabel(L("在 Finder 中显示当前目录", "Reveal Current Directory in Finder"))
            }
        }
        .frame(height: 32)
    }

    private func toolbarGroup<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ControlGroup {
            content()
        }
        .controlGroupStyle(.automatic)
        .fixedSize(horizontal: true, vertical: false)
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
            Label(L("最近和收藏", "Recent and Favorites"), systemImage: "clock")
        }
        .labelStyle(.iconOnly)
        .menuStyle(.button)
        .controlSize(.small)
        .help(L("最近和收藏", "Recent and Favorites"))
        .accessibilityLabel(Text(L("最近和收藏", "Recent and Favorites")))
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
            Label(L("排序方式", "Sort"), systemImage: "arrow.up.arrow.down")
        }
        .labelStyle(.iconOnly)
        .menuStyle(.button)
        .controlSize(.small)
        .help(L("排序方式", "Sort"))
        .accessibilityLabel(Text(L("排序方式", "Sort")))
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
            Label(L("类型过滤", "Kind Filter"), systemImage: store.kindFilter.systemImage)
        }
        .labelStyle(.iconOnly)
        .menuStyle(.button)
        .controlSize(.small)
        .help(L("类型过滤", "Kind Filter"))
        .accessibilityLabel(Text(L("类型过滤", "Kind Filter")))
    }

    private var favoriteButton: some View {
        let isFavorite = store.isFavoriteDirectory(store.currentURL ?? request.rootURL)
        return Button {
            store.toggleFavoriteDirectory(store.currentURL ?? request.rootURL)
        } label: {
            Label(
                L("收藏当前目录", "Favorite Current Directory"),
                systemImage: isFavorite ? "star.fill" : "folder"
            )
            .font(.conductorSystem(size: 13, weight: .semibold, family: fontFamily, scale: fontScale))
            .foregroundStyle(isFavorite ? theme.floatingEmphasis.opacity(0.95) : theme.floatingEmphasis.opacity(0.78))
            .labelStyle(.iconOnly)
            .frame(width: 24, height: 28)
        }
        .buttonStyle(.borderless)
        .help(L("收藏当前目录", "Favorite Current Directory"))
        .accessibilityLabel(Text(L("收藏当前目录", "Favorite Current Directory")))
    }

    private var breadcrumbBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "location")
                .font(.conductorSystem(size: 9.5, weight: .semibold, family: fontFamily, scale: fontScale))
                .foregroundStyle(theme.shellChromeText.opacity(0.42))
                .frame(width: 14)
                .accessibilityHidden(true)

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
                        .buttonStyle(.borderless)
                        if url.path != breadcrumbURLs.last?.path {
                            Image(systemName: "chevron.right")
                                .font(.conductorSystem(size: 7.5, weight: .bold, family: fontFamily, scale: fontScale))
                                .foregroundStyle(theme.shellChromeText.opacity(0.25))
                                .accessibilityHidden(true)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(height: 24)
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
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.conductorSystem(size: 11.5, weight: .semibold, family: fontFamily, scale: fontScale))
                .foregroundStyle(theme.shellChromeText.opacity(0.46))
                .frame(width: 18)

            TextField(L("搜索文件", "Search files"), text: $store.searchQuery)
                .textFieldStyle(.roundedBorder)
                .font(.conductorSystem(size: 12, weight: .medium, family: fontFamily, scale: fontScale))
                .focused($searchFocused)
                .onSubmit {
                    store.recordSearchQuery()
                }

            if !store.searchQuery.isEmpty {
                Button {
                    store.searchQuery = ""
                    searchFocused = true
                } label: {
                    Label(L("清除搜索", "Clear Search"), systemImage: "xmark.circle.fill")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .controlSize(.small)
                .help(L("清除搜索", "Clear Search"))
                .accessibilityLabel(L("清除搜索", "Clear Search"))
            }

            Text(L("\(snapshot.totalRowCount)/\(snapshot.totalKnownItemCount)", "\(snapshot.totalRowCount)/\(snapshot.totalKnownItemCount)"))
                .font(.conductorSystem(size: 10.5, weight: .semibold, family: fontFamily, scale: fontScale))
                .foregroundStyle(theme.shellChromeText.opacity(0.42))
                .lineLimit(1)

            Button {
                closeSearch()
            } label: {
                Label(L("关闭搜索", "Close Search"), systemImage: "xmark")
            }
            .labelStyle(.iconOnly)
            .controlSize(.small)
            .help(L("关闭搜索", "Close Search"))
            .accessibilityLabel(L("关闭搜索", "Close Search"))
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(ConductorTokens.Settings.panelChromeWash(dark: theme.usesDarkChrome))
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
            Text(statusSummary(snapshot: snapshot, selectedItems: selectedItems))
                .font(.conductorSystem(size: 10.8, weight: .semibold, family: fontFamily, scale: fontScale))
                .foregroundStyle(theme.shellChromeText.opacity(0.54))
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 8)

            Text((store.currentURL ?? request.rootURL).path)
                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                .foregroundStyle(theme.shellChromeText.opacity(0.42))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(ConductorTokens.Settings.panelChromeWash(dark: theme.usesDarkChrome))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(statusBarAccessibilityLabel(snapshot: snapshot, selectedItems: selectedItems))
        .accessibilityAddTraits(.isStaticText)
    }

    private func statusBarAccessibilityLabel(snapshot: FileManagerDisplaySnapshot, selectedItems: [FileManagerItem]) -> String {
        var parts = [statusSummary(snapshot: snapshot, selectedItems: selectedItems)]
        parts.append((store.currentURL ?? request.rootURL).path)
        return parts.joined(separator: "，")
    }

    private func statusSummary(snapshot: FileManagerDisplaySnapshot, selectedItems: [FileManagerItem]) -> String {
        var parts: [String] = []
        if store.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, store.kindFilter == .all {
            parts.append(L("\(snapshot.totalKnownItemCount) 项", "\(snapshot.totalKnownItemCount) items"))
        } else {
            parts.append(L("显示 \(snapshot.totalRowCount)/\(snapshot.totalKnownItemCount) 项", "Showing \(snapshot.totalRowCount)/\(snapshot.totalKnownItemCount) items"))
        }
        parts.append(L("\(snapshot.displayedDirectoryCount) 个文件夹", "\(snapshot.displayedDirectoryCount) folders"))
        parts.append(L("\(snapshot.displayedFileCount) 个文件", "\(snapshot.displayedFileCount) files"))
        if store.kindFilter != .all {
            parts.append(store.kindFilter.title)
        }
        if !selectedItems.isEmpty {
            parts.append(L("已选 \(selectionSummary(for: selectedItems))", "Selected \(selectionSummary(for: selectedItems))"))
        }
        return parts.joined(separator: " · ")
    }

    private func selectionSummary(for items: [FileManagerItem]) -> String {
        guard !items.isEmpty else { return L("0 项", "0 items") }
        let selectedSize = items.compactMap(\.byteCount).reduce(Int64(0), +)
        let size = selectedSize > 0 ? " · \(ByteCountFormatter.string(fromByteCount: selectedSize, countStyle: .file))" : ""
        return L("\(items.count) 项\(size)", "\(items.count) item(s)\(size)")
    }

    private func operationMessageBar(_ message: String) -> some View {
        HStack(spacing: 10) {
            Label {
                Text(message)
                    .font(.conductorSystem(size: 11.5, weight: .semibold, family: fontFamily, scale: fontScale))
                    .lineLimit(2)
            } icon: {
                Image(systemName: "exclamationmark.triangle")
            }

            Spacer(minLength: 8)

            ControlGroup {
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
                        Label(L("撤销", "Undo"), systemImage: "arrow.uturn.backward")
                    }
                    .help(L("撤销", "Undo"))
                    .accessibilityLabel(L("撤销", "Undo"))
                }

                Button {
                    store.clearOperationMessage()
                } label: {
                    Label(L("关闭提示", "Dismiss Message"), systemImage: "xmark")
                }
                .help(L("关闭提示", "Dismiss Message"))
                .accessibilityLabel(L("关闭提示", "Dismiss Message"))
            }
            .controlSize(.small)
        }
        .foregroundStyle(theme.shellChromeText.opacity(0.84))
        .padding(.horizontal, 14)
        .frame(minHeight: 38)
        .background(.regularMaterial)
    }

    private func deleteConfirmationBar(count: Int) -> some View {
        GroupBox {
            HStack(spacing: 10) {
                Label {
                    Text(L("已标记 \(count) 项删除", "\(count) item(s) marked for delete"))
                        .font(.conductorSystem(size: 12, weight: .semibold, family: fontFamily, scale: fontScale))
                } icon: {
                    Image(systemName: "trash")
                }
                .lineLimit(1)

                Spacer(minLength: 8)

                Button(role: .cancel) {
                    store.cancelPendingDeletes()
                } label: {
                    Label(L("取消", "Cancel"), systemImage: "xmark")
                }
                .controlSize(.small)
                .help(L("取消删除", "Cancel Delete"))

                Button(role: .destructive) {
                    Task {
                        let deletedPaths = await store.confirmPendingDeletes()
                        model.closeWorkspaceFileTabs(matchingDeletedPaths: deletedPaths)
                    }
                } label: {
                    Label(L("确认", "Confirm"), systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .help(L("确认移到废纸篓", "Confirm Move to Trash"))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .tint(.red)
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
            Task { await store.openDirectory(item) }
            return
        }
        store.select(item)
        openInWorkspace(item)
    }

    private func openInWorkspace(_ item: FileManagerItem) {
        guard !item.isDirectory else {
            Task { await store.openDirectory(item) }
            return
        }
        store.recordOpenedFile(item.url)
        model.openFileInWorkspace(item.url, rootURL: store.currentURL ?? request.rootURL)
    }

    private func openURL(_ url: URL) {
        let standardized = url.standardizedFileURL
        guard FileManager.default.fileExists(atPath: standardized.path) else {
            return
        }
        store.recordOpenedFile(standardized)
        model.openFileInWorkspace(standardized, rootURL: standardized.deletingLastPathComponent())
    }

    private func openSelectedItem() {
        guard let item = store.selectedItem ?? store.firstLogicalVisibleItem else { return }
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

    private var panelDivider: some View {
        Rectangle()
            .fill(ConductorTokens.Settings.subtleSeparator(dark: theme.usesDarkChrome))
            .frame(height: 1)
    }

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
        Task { @MainActor in
            searchFocused = true
        }
    }

    private func closeSearch() {
        store.recordSearchQuery()
        searchVisible = false
        searchFocused = false
        store.searchQuery = ""
        focusKeyboardIfBrowsing()
    }

    private func focusKeyboardIfBrowsing() {
        guard model.selectedWorkspaceFileTab == nil else { return }
        keyboardFocused = true
    }

    private var canReceiveKeyboardFocus: Bool {
        model.selectedWorkspaceFileTab == nil || searchVisible || store.renamingPath != nil
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
                if event.keyCode == 51,
                   !store.selectedURLs.isEmpty {
                    deleteSelectedItem()
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
                Label {
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
                } icon: {
                    Image(systemName: item.isDirectory ? "folder.fill" : iconName)
                        .font(.conductorSystem(size: 32, weight: .semibold, family: fontFamily, scale: fontScale))
                        .foregroundStyle(item.isDirectory ? theme.floatingEmphasis.opacity(0.95) : theme.shellChromeText.opacity(0.68))
                        .frame(width: 42, height: 42)
                        .accessibilityHidden(true)
                }
                .labelStyle(.titleAndIcon)
                Spacer(minLength: 0)
            }

            Form {
                Section {
                    infoField(L("类型", "Kind"), item.typeLabel)
                    infoField(L("大小", "Size"), sizeLabel)
                    infoField(L("修改时间", "Modified"), dateLabel(item.modificationDate))
                    infoField(L("创建时间", "Created"), dateLabel(item.creationDate))
                    infoField(L("权限", "Permissions"), permissionLabel)
                    infoField(L("完整路径", "Full Path"), item.url.path, selectable: true)
                    infoField(L("所在目录", "Parent"), item.url.deletingLastPathComponent().path, selectable: true)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .frame(minHeight: 248)

            HStack(spacing: 8) {
                ControlGroup {
                    Button {
                        copyInfoText(item.url.path)
                    } label: {
                        Label(L("复制路径", "Copy Path"), systemImage: "doc.on.doc")
                    }
                    .help(L("复制路径", "Copy Path"))

                    Button {
                        copyInfoText("'" + item.url.path.replacingOccurrences(of: "'", with: "'\\''") + "'")
                    } label: {
                        Label(L("复制 Shell 路径", "Copy Shell Path"), systemImage: "quote.bubble")
                    }
                    .help(L("复制 Shell 路径", "Copy Shell Path"))
                }
                .controlSize(.small)

                Spacer()
                Button {
                    dismiss()
                } label: {
                    Label(L("完成", "Done"), systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .help(L("完成", "Done"))
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 440)
        .background(.regularMaterial)
    }

    private func infoField(_ title: String, _ value: String, selectable: Bool = false) -> some View {
        LabeledContent {
            if selectable {
                Text(value)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            } else {
                Text(value)
                    .lineLimit(1)
            }
        } label: {
            Text(title)
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
