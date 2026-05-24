import AppKit
import ConductorCore
import Foundation
import SwiftUI

@MainActor
final class FileManagerPanelStore: ObservableObject {
    @Published private(set) var currentURL: URL?
    @Published private(set) var items: [FileManagerItem] = [] {
        didSet { rebuildExpandedRowsSnapshot() }
    }
    @Published private(set) var expandedDirectoryPaths: Set<String> = [] {
        didSet { rebuildExpandedRowsSnapshot(resetVisibleWindow: false) }
    }
    @Published private(set) var childItemsByDirectoryPath: [String: [FileManagerItem]] = [:] {
        didSet { rebuildExpandedRowsSnapshot(resetVisibleWindow: false) }
    }
    @Published private(set) var loadingDirectoryPaths: Set<String> = []
    @Published private(set) var directoryErrorsByPath: [String: String] = [:]
    @Published private(set) var selectedItem: FileManagerItem?
    @Published private(set) var selectedPaths: Set<String> = [] {
        didSet { rebuildSelectedItemsSnapshot() }
    }
    @Published private(set) var previewState = FilePreviewState.empty
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var operationMessage: String?
    @Published private(set) var pendingDeletePaths: Set<String> = []
    @Published var renamingPath: String?
    @Published var renamingName = ""
    @Published var searchQuery = "" {
        didSet { rebuildExpandedRowsSnapshot() }
    }
    @Published private(set) var searchHistory: [String] = []
    @Published var includeHiddenFiles = false
    @Published var sortMode: FileManagerSortMode = .name
    @Published var kindFilter: FileManagerKindFilter = .all {
        didSet { rebuildExpandedRowsSnapshot() }
    }
    @Published private(set) var recentFileURLs: [URL] = []
    @Published private(set) var favoriteDirectoryURLs: [URL] = []
    @Published private(set) var renamingFocusToken = 0
    @Published private(set) var lastTrashRecords: [FileManagerTrashRecord] = []

    private let service = FileManagerService()
    private var requestID: UUID?
    private var loadGeneration = 0
    private var previewGeneration = 0
    private var selectionAnchorPath: String?
    @Published private(set) var displaySnapshot = FileManagerDisplaySnapshot.empty
    private var expandedRowsSnapshot = FileManagerExpandedRowsSnapshot.empty
    private var selectedItemsSnapshot: [FileManagerItem] = []
    private(set) var visibleStartIndex = 0
    private(set) var visibleRowCount = RenderBudget.defaultVisibleRows
    private(set) var visibleOverscan = RenderBudget.defaultOverscanRows

    var visibleRows: [FileManagerVisibleRow] {
        displaySnapshot.rows
    }

    var displayedRows: [FileManagerVisibleRow] {
        expandedRowsSnapshot.rows
    }

    var logicalVisibleRange: Range<Int> {
        let rows = expandedRowsSnapshot.rows
        guard !rows.isEmpty else { return 0..<0 }
        let lower = min(max(0, visibleStartIndex), rows.count - 1)
        let upper = min(rows.count, lower + max(1, visibleRowCount))
        return lower..<upper
    }

    var firstLogicalVisibleItem: FileManagerItem? {
        let range = logicalVisibleRange
        guard let firstIndex = range.first else { return nil }
        return expandedRowsSnapshot.rows[firstIndex].item
    }

    var totalKnownItemCount: Int {
        expandedRowsSnapshot.totalKnownItemCount
    }

    var displayedFileCount: Int {
        expandedRowsSnapshot.displayedFileCount
    }

    var displayedDirectoryCount: Int {
        expandedRowsSnapshot.displayedDirectoryCount
    }

    private func rebuildExpandedRowsSnapshot(resetVisibleWindow: Bool = true) {
        let snapshot = FileManagerDisplaySnapshotBuilder.buildExpandedRows(
            items: items,
            expandedDirectoryPaths: expandedDirectoryPaths,
            childItemsByDirectoryPath: childItemsByDirectoryPath,
            searchQuery: searchQuery,
            kindFilter: kindFilter
        )
        guard snapshot != expandedRowsSnapshot || resetVisibleWindow else { return }
        expandedRowsSnapshot = snapshot
        if resetVisibleWindow {
            visibleStartIndex = 0
        } else {
            visibleStartIndex = min(visibleStartIndex, max(0, snapshot.rows.count - 1))
        }
        rebuildDisplaySnapshot()
        rebuildSelectedItemsSnapshot()
        reconcileSelectionWithDisplayedRows()
    }

    private func rebuildDisplaySnapshot() {
        let snapshot = FileManagerDisplaySnapshot.visibleWindow(
            rows: expandedRowsSnapshot.rows,
            totalKnownItemCount: expandedRowsSnapshot.totalKnownItemCount,
            displayedFileCount: expandedRowsSnapshot.displayedFileCount,
            displayedDirectoryCount: expandedRowsSnapshot.displayedDirectoryCount,
            startIndex: visibleStartIndex,
            visibleCount: visibleRowCount,
            overscan: visibleOverscan
        )
        guard snapshot != displaySnapshot else { return }
        displaySnapshot = snapshot
    }

    func updateVisibleWindow(
        startIndex: Int,
        visibleRowCount: Int? = nil,
        overscan: Int? = nil
    ) {
        let rowCount = max(1, visibleRowCount ?? self.visibleRowCount)
        let overscan = max(0, overscan ?? visibleOverscan)
        let clampedStart = min(max(0, startIndex), max(0, expandedRowsSnapshot.rows.count - 1))
        guard clampedStart != self.visibleStartIndex ||
            rowCount != self.visibleRowCount ||
            overscan != self.visibleOverscan else {
            return
        }
        self.visibleStartIndex = clampedStart
        self.visibleRowCount = rowCount
        self.visibleOverscan = overscan
        rebuildDisplaySnapshot()
        rebuildSelectedItemsSnapshot()
    }

    func showPreviousVisibleWindow() {
        let nextStart = max(0, logicalVisibleRange.lowerBound - visibleRowCount)
        updateVisibleWindow(startIndex: nextStart)
    }

    func showNextVisibleWindow() {
        let nextStart = min(
            max(0, expandedRowsSnapshot.rows.count - 1),
            max(displaySnapshot.visibleRange.upperBound - visibleOverscan, visibleStartIndex + visibleRowCount)
        )
        updateVisibleWindow(startIndex: nextStart)
    }

    private func ensureVisibleRow(at index: Int) {
        guard index >= 0, index < expandedRowsSnapshot.rows.count else { return }
        guard !displaySnapshot.visibleRange.contains(index) else { return }
        let centeredStart = max(0, index - visibleRowCount / 2)
        updateVisibleWindow(startIndex: centeredStart)
    }

    private func rebuildSelectedItemsSnapshot() {
        guard !selectedPaths.isEmpty else {
            if !selectedItemsSnapshot.isEmpty {
                selectedItemsSnapshot = []
            }
            return
        }
        var selected: [FileManagerItem] = []
        selected.reserveCapacity(min(expandedRowsSnapshot.rows.count, selectedPaths.count))
        for row in expandedRowsSnapshot.rows where selectedPaths.contains(row.item.url.path) {
            selected.append(row.item)
        }
        if selected != selectedItemsSnapshot {
            selectedItemsSnapshot = selected
        }
    }

    private func reconcileSelectionWithDisplayedRows() {
        guard !selectedPaths.isEmpty || selectedItem != nil else { return }
        let visiblePaths = Set(expandedRowsSnapshot.rows.map { $0.item.url.path })
        guard !visiblePaths.isEmpty else {
            clearSelectionForCurrentDisplay()
            return
        }

        let reconciledPaths = selectedPaths.intersection(visiblePaths)
        if reconciledPaths != selectedPaths {
            selectedPaths = reconciledPaths
        }

        if let selectedItem, visiblePaths.contains(selectedItem.url.path) {
            return
        }

        if let firstSelectedPath = reconciledPaths.first,
           let row = expandedRowsSnapshot.rows.first(where: { $0.item.url.path == firstSelectedPath }) {
            selectedItem = row.item
            selectionAnchorPath = row.item.url.path
            loadPreview(for: row.item.url)
            return
        }

        clearSelectionForCurrentDisplay()
    }

    private func clearSelectionForCurrentDisplay() {
        selectedItem = nil
        selectedPaths = []
        selectionAnchorPath = nil
        previewGeneration += 1
        previewState = noSelectionPreviewState()
    }

    private func noSelectionPreviewState() -> FilePreviewState {
        guard displaySnapshot.totalRowCount == 0 else { return .empty }
        return items.isEmpty
            ? .message(fileManagerL("这个目录没有可显示的文件", "This directory has no visible files"))
            : .message(fileManagerL("没有匹配的文件", "No matching files"))
    }

    private func selectItemForAction(
        _ item: FileManagerItem,
        selectedPaths paths: Set<String>? = nil,
        anchorPath: String? = nil
    ) {
        let paths = paths ?? [item.url.path]
        guard !paths.isEmpty else {
            clearSelectionForCurrentDisplay()
            return
        }
        selectedPaths = paths
        selectedItem = item
        selectionAnchorPath = anchorPath ?? item.url.path
        if let index = displayedRows.firstIndex(where: { $0.item.url.path == item.url.path }) {
            ensureVisibleRow(at: index)
        }
        operationMessage = nil
    }

    private func itemForSelection(_ paths: Set<String>, preferred item: FileManagerItem) -> FileManagerItem? {
        if paths.contains(item.url.path) {
            return item
        }
        return displayedRows.first { paths.contains($0.item.url.path) }?.item
    }

    func load(_ request: FileManagerPanelRequest) async {
        guard requestID != request.id else { return }
        requestID = request.id
        loadLocalLists()
        searchHistory = []
        await openDirectory(request.rootURL, selecting: request.selectedURL)
    }

    func refresh() async {
        guard let currentURL else { return }
        await openDirectory(
            currentURL,
            selecting: selectedItem?.url,
            preservingExpanded: expandedDirectoryPaths
        )
    }

    func goUp() async {
        guard let currentURL else { return }
        let parent = currentURL.deletingLastPathComponent().standardizedFileURL
        guard parent.path != currentURL.path else { return }
        await openDirectory(parent, selecting: currentURL)
    }

    func openBreadcrumb(_ url: URL) async {
        await openDirectory(url.standardizedFileURL, selecting: nil, preservingExpanded: [])
    }

    func select(_ item: FileManagerItem, mode: FileManagerSelectionMode = .primary) {
        switch mode {
        case .primary:
            selectItemForAction(item)
            return
        case .toggle:
            var paths = selectedPaths
            if selectedPaths.contains(item.url.path) {
                paths.remove(item.url.path)
            } else {
                paths.insert(item.url.path)
            }
            guard let activeItem = itemForSelection(paths, preferred: item) else {
                clearSelectionForCurrentDisplay()
                operationMessage = nil
                return
            }
            selectItemForAction(activeItem, selectedPaths: paths, anchorPath: item.url.path)
            return
        case .range:
            let rows = displayedRows
            let anchorPath = selectionAnchorPath ?? selectedItem?.url.path ?? item.url.path
            guard let anchorIndex = rows.firstIndex(where: { $0.item.url.path == anchorPath }),
                  let itemIndex = rows.firstIndex(where: { $0.item.url.path == item.url.path }) else {
                selectItemForAction(item)
                return
            }
            let range = min(anchorIndex, itemIndex)...max(anchorIndex, itemIndex)
            selectItemForAction(
                item,
                selectedPaths: Set(range.map { rows[$0].item.url.path }),
                anchorPath: anchorPath
            )
        }
    }

    func selectAdjacentRow(by offset: Int) {
        let rows = displayedRows
        guard !rows.isEmpty else { return }
        let currentIndex: Int
        if let selectedIndex = selectedItem.flatMap({ selected in
            rows.firstIndex { $0.item.id == selected.id }
        }) {
            currentIndex = selectedIndex
        } else if let visibleFallbackIndex = visibleFallbackIndex(for: offset) {
            currentIndex = visibleFallbackIndex
        } else {
            return
        }
        let nextIndex = min(max(currentIndex + offset, 0), rows.count - 1)
        select(rows[nextIndex].item)
    }

    private func visibleFallbackIndex(for offset: Int) -> Int? {
        let range = logicalVisibleRange
        guard !range.isEmpty else { return nil }
        if offset >= 0 {
            return max(range.lowerBound - 1, -1)
        }
        return min(range.upperBound, displayedRows.count)
    }

    func expandSelected() async {
        guard let selectedItem, selectedItem.isDirectory else { return }
        if expandedDirectoryPaths.contains(selectedItem.url.path) == false {
            await toggleDirectory(selectedItem)
        }
    }

    func collapseSelected() {
        guard let selectedItem else { return }
        if selectedItem.isDirectory, expandedDirectoryPaths.contains(selectedItem.url.path) {
            expandedDirectoryPaths.remove(selectedItem.url.path)
        } else if let parent = findItem(withPath: selectedItem.url.deletingLastPathComponent().path) {
            select(parent)
        }
    }

    func clearSelection() {
        selectedItem = nil
        selectedPaths = []
        selectionAnchorPath = nil
        previewGeneration += 1
        previewState = displaySnapshot.totalRowCount == 0
            ? .message(fileManagerL("这个目录没有可显示的文件", "This directory has no visible files"))
            : .empty
    }

    func open(_ item: FileManagerItem) async {
        if item.isDirectory {
            await toggleDirectory(item)
        } else {
            select(item)
        }
    }

    func openDirectory(_ item: FileManagerItem) async {
        guard item.isDirectory else { return }
        await openDirectory(item.url, selecting: nil)
    }

    func isExpanded(_ item: FileManagerItem) -> Bool {
        expandedDirectoryPaths.contains(item.url.path)
    }

    func isLoading(_ item: FileManagerItem) -> Bool {
        loadingDirectoryPaths.contains(item.url.path)
    }

    func toggleDirectory(_ item: FileManagerItem, selectsItem: Bool = true) async {
        guard item.isDirectory else { return }
        if selectsItem {
            selectItemForAction(item)
        }
        let path = item.url.path
        if expandedDirectoryPaths.contains(path) {
            expandedDirectoryPaths.remove(path)
            return
        }
        expandedDirectoryPaths.insert(path)
        guard childItemsByDirectoryPath[path] == nil else { return }
        await loadChildren(for: item.url)
    }

    func isPendingDelete(_ item: FileManagerItem) -> Bool {
        pendingDeletePaths.contains { path in
            path == item.url.path || path.hasPrefix(item.url.path + "/")
        }
    }

    var pendingDeleteCount: Int {
        pendingDeletePaths.count
    }

    var selectedItems: [FileManagerItem] {
        selectedItemsSnapshot
    }

    var selectedItemsForDisplay: [FileManagerItem] {
        if !selectedItemsSnapshot.isEmpty {
            return selectedItemsSnapshot
        }
        if let selectedItem {
            return [selectedItem]
        }
        return []
    }

    var selectedURLs: [URL] {
        let selected = selectedItems
        if selected.isEmpty, let selectedItem {
            return [selectedItem.url]
        }
        return selected.map(\.url)
    }

    var selectedCount: Int {
        selectedPaths.count
    }

    var canUndoTrash: Bool {
        !lastTrashRecords.isEmpty
    }

    func markForDelete(_ item: FileManagerItem) {
        markForDelete([item])
    }

    func markForDelete(_ items: [FileManagerItem]) {
        guard !items.isEmpty else { return }
        let paths = Set(items.map { $0.url.path })
        if let item = items.last {
            selectItemForAction(item, selectedPaths: paths, anchorPath: item.url.path)
        }
        for item in items {
            pendingDeletePaths.insert(item.url.path)
        }
        if let renamingPath,
           items.contains(where: { $0.url.path == renamingPath }) {
            cancelRename()
        }
        operationMessage = nil
    }

    func cancelPendingDeletes() {
        pendingDeletePaths.removeAll()
        operationMessage = nil
    }

    func clearOperationMessage() {
        operationMessage = nil
    }

    func recordSearchQuery() {
        searchHistory = []
    }

    func reuseSearchQuery(_ query: String) {
        searchQuery = query
        recordSearchQuery()
    }

    func setIncludeHiddenFiles(_ value: Bool) async {
        guard includeHiddenFiles != value else { return }
        includeHiddenFiles = value
        await refresh()
    }

    func setSortMode(_ mode: FileManagerSortMode) async {
        guard sortMode != mode else { return }
        sortMode = mode
        await refresh()
    }

    func setKindFilter(_ filter: FileManagerKindFilter) {
        guard kindFilter != filter else { return }
        kindFilter = filter
    }

    func recordOpenedFile(_ url: URL) {
        let standardized = url.standardizedFileURL
        recentFileURLs.removeAll { $0.standardizedFileURL.path == standardized.path }
        recentFileURLs.insert(standardized, at: 0)
        recentFileURLs = Array(recentFileURLs.prefix(20))
        saveURLList(recentFileURLs, key: Self.recentFilesDefaultsKey)
    }

    func toggleFavoriteDirectory(_ url: URL) {
        let directory = url.standardizedFileURL
        if favoriteDirectoryURLs.contains(where: { $0.path == directory.path }) {
            favoriteDirectoryURLs.removeAll { $0.path == directory.path }
        } else {
            favoriteDirectoryURLs.insert(directory, at: 0)
        }
        favoriteDirectoryURLs = Array(favoriteDirectoryURLs.prefix(20))
        saveURLList(favoriteDirectoryURLs, key: Self.favoriteDirectoriesDefaultsKey)
    }

    func isFavoriteDirectory(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        return favoriteDirectoryURLs.contains { $0.standardizedFileURL.path == path }
    }

    func createFile() async {
        guard let directory = targetDirectory(for: nil) else { return }
        let result = await Task.detached(priority: .userInitiated) {
            Result { try FileManagerService().createFile(in: directory) }
        }.value
        await handleCreatedItemResult(result, isDirectory: false)
    }

    func createFolder() async {
        guard let directory = targetDirectory(for: nil) else { return }
        let result = await Task.detached(priority: .userInitiated) {
            Result { try FileManagerService().createFolder(in: directory) }
        }.value
        await handleCreatedItemResult(result, isDirectory: true)
    }

    func duplicate(_ item: FileManagerItem) async {
        let result = await Task.detached(priority: .userInitiated) {
            Result { try FileManagerService().duplicateItem(at: item.url) }
        }.value
        switch result {
        case .success(let newURL):
            await refresh(selecting: newURL)
        case .failure(let error):
            operationMessage = error.localizedDescription
            NSSound.beep()
        }
    }

    func confirmPendingDeletes() async -> Set<String> {
        let itemsToDelete = pendingDeletePaths.compactMap { findItem(withPath: $0) }
        guard !itemsToDelete.isEmpty else {
            pendingDeletePaths.removeAll()
            return []
        }
        let paths = Set(itemsToDelete.map { $0.url.path })
        let result = await Task.detached(priority: .userInitiated) {
            Result {
                var records: [FileManagerTrashRecord] = []
                for item in itemsToDelete {
                    records.append(try FileManagerService().moveToTrash(item.url))
                }
                return records
            }
        }.value

        switch result {
        case .success(let records):
            if let selectedPath = selectedItem?.url.path,
               paths.contains(where: { selectedPath == $0 || selectedPath.hasPrefix($0 + "/") }) {
                selectedItem = nil
            }
            selectedPaths = selectedPaths.filter { selectedPath in
                !paths.contains { selectedPath == $0 || selectedPath.hasPrefix($0 + "/") }
            }
            selectionAnchorPath = selectedItem?.url.path
            lastTrashRecords = records
            clearTreeState(for: paths)
            pendingDeletePaths.subtract(paths)
            operationMessage = fileManagerL("已移到废纸篓。可撤销。", "Moved to Trash. Undo is available.")
            await refresh()
            return paths
        case .failure(let error):
            operationMessage = fileManagerL("移到废纸篓失败：", "Could not move to Trash: ") + error.localizedDescription
            NSSound.beep()
            return []
        }
    }

    func undoLastTrash() async -> Set<String> {
        let records = lastTrashRecords
        guard !records.isEmpty else { return [] }
        let result = await Task.detached(priority: .userInitiated) {
            Result {
                for record in records.reversed() {
                    try FileManagerService().restoreTrashRecord(record)
                }
            }
        }.value

        switch result {
        case .success:
            lastTrashRecords = []
            operationMessage = fileManagerL("已撤销删除", "Delete undone")
            let restoredPaths = Set(records.map { $0.originalURL.path })
            for record in records {
                expandedDirectoryPaths.insert(record.originalURL.deletingLastPathComponent().standardizedFileURL.path)
            }
            await refresh(selecting: records.last?.originalURL)
            return restoredPaths
        case .failure(let error):
            operationMessage = fileManagerL("撤销删除失败：", "Could not undo delete: ") + error.localizedDescription
            NSSound.beep()
            return []
        }
    }

    func beginRename(_ item: FileManagerItem) {
        selectItemForAction(item)
        renamingPath = item.url.path
        renamingName = item.name
        renamingFocusToken &+= 1
        operationMessage = nil
    }

    func cancelRename() {
        renamingPath = nil
        renamingName = ""
    }

    func commitRename(_ item: FileManagerItem) async -> FileManagerRenameResult? {
        guard renamingPath == item.url.path else { return nil }
        let oldPath = item.url.path
        let newName = renamingName
        let result = await Task.detached(priority: .userInitiated) {
            Result { try FileManagerService().renameItem(at: item.url, to: newName) }
        }.value

        switch result {
        case .success(let newURL):
            renamingPath = nil
            renamingName = ""
            if item.isDirectory {
                let wasExpanded = expandedDirectoryPaths.remove(oldPath) != nil
                childItemsByDirectoryPath.removeValue(forKey: oldPath)
                if wasExpanded {
                    expandedDirectoryPaths.insert(newURL.path)
                }
                pendingDeletePaths = pendingDeletePaths.filter { path in
                    path != oldPath && !path.hasPrefix(oldPath + "/")
                }
            } else {
                pendingDeletePaths.remove(oldPath)
            }
            await refresh(selecting: newURL)
            return FileManagerRenameResult(oldPath: oldPath, newURL: newURL, isDirectory: item.isDirectory)
        case .failure(let error):
            operationMessage = error.localizedDescription
            renamingPath = item.url.path
            renamingFocusToken &+= 1
            NSSound.beep()
            return nil
        }
    }

    func pasteItems(
        _ sourceURLs: [URL],
        into item: FileManagerItem?,
        move: Bool
    ) async {
        guard let target = targetDirectory(for: item), !sourceURLs.isEmpty else { return }
        let sourceDirectories = Set(sourceURLs.map { $0.deletingLastPathComponent().standardizedFileURL.path })
        let result = await Task.detached(priority: .userInitiated) {
            Result {
                try FileManagerService().pasteItems(
                    sourceURLs,
                    into: target,
                    move: move
                )
            }
        }.value

        switch result {
        case .success(let destinations):
            guard !destinations.isEmpty else { return }
            if move {
                let sourcePaths = Set(sourceURLs.map { $0.standardizedFileURL.path })
                clearTreeState(for: sourcePaths)
            }
            expandedDirectoryPaths.insert(target.standardizedFileURL.path)
            for path in sourceDirectories where path != target.standardizedFileURL.path {
                expandedDirectoryPaths.insert(path)
            }
            await refresh(selecting: destinations.last)
        case .failure(let error):
            operationMessage = error.localizedDescription
            NSSound.beep()
        }
    }

    private func refresh(selecting selectedURL: URL?) async {
        guard let currentURL else { return }
        await openDirectory(currentURL, selecting: selectedURL, preservingExpanded: expandedDirectoryPaths)
    }

    private func openDirectory(
        _ url: URL,
        selecting selectedURL: URL?,
        preservingExpanded rememberedExpanded: Set<String>? = nil
    ) async {
        let directoryURL = url.standardizedFileURL
        loadGeneration += 1
        let generation = loadGeneration
        isLoading = true
        errorMessage = nil
        previewState = .loading
        let includeHiddenFiles = includeHiddenFiles
        let sortMode = sortMode

        let result = await Task.detached(priority: .userInitiated) {
            Result {
                try FileManagerService().directoryItems(
                    at: directoryURL,
                    includeHidden: includeHiddenFiles,
                    sortMode: sortMode
                )
            }
        }.value

        guard generation == loadGeneration else { return }
        isLoading = false
        currentURL = directoryURL
        selectedItem = nil
        selectedPaths = []
        selectionAnchorPath = nil
        expandedDirectoryPaths = rememberedExpanded ?? []
        childItemsByDirectoryPath = [:]
        loadingDirectoryPaths = []
        directoryErrorsByPath = [:]
        pendingDeletePaths = pendingDeletePaths.filter { path in
            path == directoryURL.path || path.hasPrefix(directoryURL.path + "/")
        }

        switch result {
        case .success(let loadedItems):
            items = loadedItems
            if !expandedDirectoryPaths.isEmpty {
                for path in expandedDirectoryPaths.sorted(by: { lhs, rhs in
                    lhs.split(separator: "/").count < rhs.split(separator: "/").count
                }) {
                    if let item = findItem(withPath: path), item.isDirectory {
                        await loadChildren(for: item.url)
                    } else {
                        expandedDirectoryPaths.remove(path)
                    }
                }
            }
            let selectedPath = selectedURL?.standardizedFileURL.path
            if let selectedPath,
               let match = findDisplayedItem(withPath: selectedPath) {
                select(match)
            } else {
                clearSelectionForCurrentDisplay()
            }
        case .failure(let error):
            items = []
            selectedItem = nil
            errorMessage = error.localizedDescription
            previewState = .failed(error.localizedDescription)
        }
    }

    private func targetDirectory(for item: FileManagerItem?) -> URL? {
        if let item {
            return item.isDirectory ? item.url : item.url.deletingLastPathComponent()
        }
        if let selectedItem {
            return selectedItem.isDirectory ? selectedItem.url : selectedItem.url.deletingLastPathComponent()
        }
        return currentURL
    }

    private func findItem(withPath path: String) -> FileManagerItem? {
        if let match = items.first(where: { $0.url.path == path }) {
            return match
        }
        return childItemsByDirectoryPath.values.flatMap { $0 }.first { $0.url.path == path }
    }

    private func findDisplayedItem(withPath path: String) -> FileManagerItem? {
        displayedRows.first { $0.item.url.path == path }?.item
    }

    private func clearTreeState(for paths: Set<String>) {
        guard !paths.isEmpty else { return }
        expandedDirectoryPaths = expandedDirectoryPaths.filter { path in
            !paths.contains { deletedPath in path == deletedPath || path.hasPrefix(deletedPath + "/") }
        }
        childItemsByDirectoryPath = childItemsByDirectoryPath.filter { path, _ in
            !paths.contains { deletedPath in path == deletedPath || path.hasPrefix(deletedPath + "/") }
        }
        loadingDirectoryPaths = loadingDirectoryPaths.filter { path in
            !paths.contains { deletedPath in path == deletedPath || path.hasPrefix(deletedPath + "/") }
        }
        directoryErrorsByPath = directoryErrorsByPath.filter { path, _ in
            !paths.contains { deletedPath in path == deletedPath || path.hasPrefix(deletedPath + "/") }
        }
    }

    private func loadChildren(for url: URL) async {
        let directoryURL = url.standardizedFileURL
        let path = directoryURL.path
        let generation = loadGeneration
        directoryErrorsByPath[path] = nil
        loadingDirectoryPaths.insert(path)
        let includeHiddenFiles = includeHiddenFiles
        let sortMode = sortMode

        let result = await Task.detached(priority: .userInitiated) {
            Result {
                try FileManagerService().directoryItems(
                    at: directoryURL,
                    includeHidden: includeHiddenFiles,
                    sortMode: sortMode
                )
            }
        }.value

        guard generation == loadGeneration else { return }
        loadingDirectoryPaths.remove(path)
        switch result {
        case .success(let loadedItems):
            childItemsByDirectoryPath[path] = loadedItems
        case .failure(let error):
            childItemsByDirectoryPath[path] = []
            directoryErrorsByPath[path] = error.localizedDescription
        }
    }

    private func loadPreview(for url: URL) {
        previewGeneration += 1
        let generation = previewGeneration
        previewState = .loading
        let previewURL = url.standardizedFileURL

        Task {
            let state = await Task.detached(priority: .userInitiated) {
                FileManagerService().preview(for: previewURL)
            }.value
            guard generation == previewGeneration else { return }
            previewState = state
        }
    }

    private func handleCreatedItemResult(_ result: Result<URL, Error>, isDirectory: Bool) async {
        switch result {
        case .success(let url):
            if isDirectory {
                expandedDirectoryPaths.insert(url.deletingLastPathComponent().standardizedFileURL.path)
            }
            await refresh(selecting: url)
            if let item = findItem(withPath: url.path) {
                beginRename(item)
            }
        case .failure(let error):
            operationMessage = error.localizedDescription
            NSSound.beep()
        }
    }

    private func loadLocalLists() {
        recentFileURLs = loadURLList(key: Self.recentFilesDefaultsKey)
        favoriteDirectoryURLs = loadURLList(key: Self.favoriteDirectoriesDefaultsKey)
    }

    private func loadURLList(key: String) -> [URL] {
        UserDefaults.standard.stringArray(forKey: key)?.map { URL(fileURLWithPath: $0).standardizedFileURL } ?? []
    }

    private func saveURLList(_ urls: [URL], key: String) {
        UserDefaults.standard.set(urls.map { $0.standardizedFileURL.path }, forKey: key)
    }

    private static let recentFilesDefaultsKey = "conductor.fileManager.recentFiles"
    private static let favoriteDirectoriesDefaultsKey = "conductor.fileManager.favoriteDirectories"
    private static let searchHistoryScope = "file-tree"
}
