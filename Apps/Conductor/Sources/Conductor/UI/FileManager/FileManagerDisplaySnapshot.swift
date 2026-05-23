import Foundation
import UniformTypeIdentifiers

struct FileManagerDisplaySnapshot: Equatable {
    let rows: [FileManagerVisibleRow]
    let totalRowCount: Int
    let visibleRange: Range<Int>
    let totalKnownItemCount: Int
    let displayedFileCount: Int
    let displayedDirectoryCount: Int

    static let empty = FileManagerDisplaySnapshot(
        rows: [],
        totalRowCount: 0,
        visibleRange: 0..<0,
        totalKnownItemCount: 0,
        displayedFileCount: 0,
        displayedDirectoryCount: 0
    )

    static func visibleWindow(
        items: [FileManagerItem],
        startIndex: Int,
        visibleCount: Int,
        overscan: Int
    ) -> FileManagerDisplaySnapshot {
        let rows = items.enumerated().map { index, item in
            FileManagerVisibleRow(item: item, depth: 0, index: index)
        }
        return visibleWindow(
            rows: rows,
            totalKnownItemCount: items.count,
            displayedFileCount: items.filter { !$0.isDirectory }.count,
            displayedDirectoryCount: items.filter(\.isDirectory).count,
            startIndex: startIndex,
            visibleCount: visibleCount,
            overscan: overscan
        )
    }

    static func visibleWindow(
        rows: [FileManagerVisibleRow],
        totalKnownItemCount: Int,
        displayedFileCount: Int,
        displayedDirectoryCount: Int,
        startIndex: Int,
        visibleCount: Int,
        overscan: Int
    ) -> FileManagerDisplaySnapshot {
        guard !rows.isEmpty else {
            return FileManagerDisplaySnapshot(
                rows: [],
                totalRowCount: 0,
                visibleRange: 0..<0,
                totalKnownItemCount: totalKnownItemCount,
                displayedFileCount: displayedFileCount,
                displayedDirectoryCount: displayedDirectoryCount
            )
        }

        let clampedStart = min(max(0, startIndex), rows.count - 1)
        let lower = max(0, clampedStart - max(0, overscan))
        let upper = min(rows.count, clampedStart + max(1, visibleCount) + max(0, overscan))
        let range = lower..<upper
        return FileManagerDisplaySnapshot(
            rows: Array(rows[range]),
            totalRowCount: rows.count,
            visibleRange: range,
            totalKnownItemCount: totalKnownItemCount,
            displayedFileCount: displayedFileCount,
            displayedDirectoryCount: displayedDirectoryCount
        )
    }
}

struct FileManagerExpandedRowsSnapshot: Equatable {
    let rows: [FileManagerVisibleRow]
    let totalKnownItemCount: Int
    let displayedFileCount: Int
    let displayedDirectoryCount: Int

    static let empty = FileManagerExpandedRowsSnapshot(
        rows: [],
        totalKnownItemCount: 0,
        displayedFileCount: 0,
        displayedDirectoryCount: 0
    )
}

enum FileManagerDisplaySnapshotBuilder {
    static func buildExpandedRows(
        items: [FileManagerItem],
        expandedDirectoryPaths: Set<String>,
        childItemsByDirectoryPath: [String: [FileManagerItem]],
        searchQuery: String,
        kindFilter: FileManagerKindFilter
    ) -> FileManagerExpandedRowsSnapshot {
        RenderCounter.increment("file-manager-display-snapshot")
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let totalKnownItemCount: Int
        let rows: [FileManagerVisibleRow]

        if query.isEmpty {
            var expandedRows: [FileManagerVisibleRow] = []
            appendVisibleRows(
                for: items,
                depth: 0,
                expandedDirectoryPaths: expandedDirectoryPaths,
                childItemsByDirectoryPath: childItemsByDirectoryPath,
                into: &expandedRows
            )
            totalKnownItemCount = knownRowCount(for: items, childItemsByDirectoryPath: childItemsByDirectoryPath)
            rows = kindFilter == .all
                ? indexedRows(expandedRows)
                : indexedRows(expandedRows.filter { matchesKindFilter($0.item, kindFilter: kindFilter) })
        } else {
            var matchingRows: [FileManagerVisibleRow] = []
            totalKnownItemCount = appendKnownMatchingRows(
                for: items,
                depth: 0,
                childItemsByDirectoryPath: childItemsByDirectoryPath,
                query: query,
                kindFilter: kindFilter,
                into: &matchingRows
            )
            rows = indexedRows(matchingRows)
        }

        var displayedFileCount = 0
        var displayedDirectoryCount = 0
        for row in rows {
            if row.item.isDirectory {
                displayedDirectoryCount += 1
            } else {
                displayedFileCount += 1
            }
        }
        return FileManagerExpandedRowsSnapshot(
            rows: rows,
            totalKnownItemCount: totalKnownItemCount,
            displayedFileCount: displayedFileCount,
            displayedDirectoryCount: displayedDirectoryCount
        )
    }

    private static func appendVisibleRows(
        for items: [FileManagerItem],
        depth: Int,
        expandedDirectoryPaths: Set<String>,
        childItemsByDirectoryPath: [String: [FileManagerItem]],
        into rows: inout [FileManagerVisibleRow]
    ) {
        rows.reserveCapacity(rows.count + items.count)
        for item in items {
            rows.append(FileManagerVisibleRow(item: item, depth: depth))
            if item.isDirectory,
               expandedDirectoryPaths.contains(item.url.path),
               let children = childItemsByDirectoryPath[item.url.path] {
                appendVisibleRows(
                    for: children,
                    depth: depth + 1,
                    expandedDirectoryPaths: expandedDirectoryPaths,
                    childItemsByDirectoryPath: childItemsByDirectoryPath,
                    into: &rows
                )
            }
        }
    }

    private static func appendKnownMatchingRows(
        for items: [FileManagerItem],
        depth: Int,
        childItemsByDirectoryPath: [String: [FileManagerItem]],
        query: String,
        kindFilter: FileManagerKindFilter,
        into rows: inout [FileManagerVisibleRow]
    ) -> Int {
        rows.reserveCapacity(rows.count + items.count)
        var knownCount = 0
        for item in items {
            knownCount += 1
            if matchesKindFilter(item, kindFilter: kindFilter) &&
                (item.name.localizedCaseInsensitiveContains(query) ||
                    item.url.path.localizedCaseInsensitiveContains(query)) {
                rows.append(FileManagerVisibleRow(item: item, depth: depth))
            }
            if item.isDirectory, let children = childItemsByDirectoryPath[item.url.path] {
                knownCount += appendKnownMatchingRows(
                    for: children,
                    depth: depth + 1,
                    childItemsByDirectoryPath: childItemsByDirectoryPath,
                    query: query,
                    kindFilter: kindFilter,
                    into: &rows
                )
            }
        }
        return knownCount
    }

    private static func indexedRows(_ rows: [FileManagerVisibleRow]) -> [FileManagerVisibleRow] {
        rows.enumerated().map { index, row in
            FileManagerVisibleRow(item: row.item, depth: row.depth, index: index)
        }
    }

    private static func knownRowCount(
        for items: [FileManagerItem],
        childItemsByDirectoryPath: [String: [FileManagerItem]]
    ) -> Int {
        var count = items.count
        for item in items where item.isDirectory {
            if let children = childItemsByDirectoryPath[item.url.path] {
                count += knownRowCount(for: children, childItemsByDirectoryPath: childItemsByDirectoryPath)
            }
        }
        return count
    }

    private static func matchesKindFilter(_ item: FileManagerItem, kindFilter: FileManagerKindFilter) -> Bool {
        switch kindFilter {
        case .all:
            return true
        case .folders:
            return item.isDirectory
        case .documents:
            return !item.isDirectory && documentExtensions.contains(item.url.pathExtension.lowercased())
        case .code:
            return !item.isDirectory && codeExtensions.contains(item.url.pathExtension.lowercased())
        case .data:
            return !item.isDirectory && dataExtensions.contains(item.url.pathExtension.lowercased())
        case .images:
            if item.isDirectory { return false }
            if imageExtensions.contains(item.url.pathExtension.lowercased()) { return true }
            guard let identifier = item.contentTypeIdentifier, let type = UTType(identifier) else { return false }
            return type.conforms(to: .image)
        case .other:
            guard !item.isDirectory else { return false }
            let ext = item.url.pathExtension.lowercased()
            return !documentExtensions.contains(ext) &&
                !codeExtensions.contains(ext) &&
                !dataExtensions.contains(ext) &&
                !imageExtensions.contains(ext)
        }
    }

    private static let documentExtensions: Set<String> = [
        "adoc", "bib", "cls", "latex", "log", "markdown", "md", "mdown", "mkd",
        "out", "pdf", "rst", "stderr", "stdout", "sty", "tex", "text", "trace", "txt"
    ]
    private static let codeExtensions: Set<String> = [
        "bash", "c", "cc", "cpp", "css", "go", "h", "hpp", "html", "java", "js",
        "jsx", "kt", "kts", "m", "mm", "php", "py", "rb", "rs", "scss", "sh",
        "sql", "swift", "ts", "tsx", "zsh"
    ]
    private static let dataExtensions: Set<String> = [
        "cfg", "conf", "csv", "env", "ini", "json", "jsonl", "plist", "properties",
        "tab", "toml", "tsv", "xml", "yaml", "yml"
    ]
    private static let imageExtensions: Set<String> = [
        "apng", "avif", "bmp", "gif", "heic", "heif", "ico", "jpeg", "jpg", "png",
        "psd", "svg", "tif", "tiff", "webp"
    ]
}
