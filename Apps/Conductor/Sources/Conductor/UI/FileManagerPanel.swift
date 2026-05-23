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

private struct FileManagerItem: Equatable, Identifiable, Sendable {
    var id: String { url.path }
    let url: URL
    let name: String
    let isDirectory: Bool
    let isSymbolicLink: Bool
    let byteCount: Int64?
    let modificationDate: Date?
    let creationDate: Date?
    let isReadable: Bool
    let isWritable: Bool
    let contentTypeIdentifier: String?
    let subtitle: String
    let typeLabel: String
    let rowDetail: String
    let isLargeEditableFile: Bool
    let isUnsupportedBinaryLikeFile: Bool
}

private struct FileManagerVisibleRow: Equatable, Identifiable {
    var id: String { item.id }
    let item: FileManagerItem
    let depth: Int
}

private struct FileManagerDisplaySnapshot: Equatable {
    let rows: [FileManagerVisibleRow]
    let totalKnownItemCount: Int
    let displayedFileCount: Int
    let displayedDirectoryCount: Int

    static let empty = FileManagerDisplaySnapshot(
        rows: [],
        totalKnownItemCount: 0,
        displayedFileCount: 0,
        displayedDirectoryCount: 0
    )
}

private enum FileManagerDisplaySnapshotBuilder {
    static func build(
        items: [FileManagerItem],
        expandedDirectoryPaths: Set<String>,
        childItemsByDirectoryPath: [String: [FileManagerItem]],
        searchQuery: String,
        kindFilter: FileManagerKindFilter
    ) -> FileManagerDisplaySnapshot {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            var rows: [FileManagerVisibleRow] = []
            appendVisibleRows(
                for: items,
                depth: 0,
                expandedDirectoryPaths: expandedDirectoryPaths,
                childItemsByDirectoryPath: childItemsByDirectoryPath,
                into: &rows
            )
            let filteredRows = kindFilter == .all
                ? rows
                : rows.filter { row in
                    matchesKindFilter(row.item, kindFilter: kindFilter)
                }
            return snapshot(
                rows: filteredRows,
                totalKnownItemCount: knownRowCount(for: items, childItemsByDirectoryPath: childItemsByDirectoryPath)
            )
        }

        var rows: [FileManagerVisibleRow] = []
        let totalKnownItemCount = appendKnownMatchingRows(
            for: items,
            depth: 0,
            childItemsByDirectoryPath: childItemsByDirectoryPath,
            query: query,
            kindFilter: kindFilter,
            into: &rows
        )

        return snapshot(rows: rows, totalKnownItemCount: totalKnownItemCount)
    }

    private static func snapshot(
        rows: [FileManagerVisibleRow],
        totalKnownItemCount: Int
    ) -> FileManagerDisplaySnapshot {
        var displayedFileCount = 0
        var displayedDirectoryCount = 0
        for row in rows {
            if row.item.isDirectory {
                displayedDirectoryCount += 1
            } else {
                displayedFileCount += 1
            }
        }
        return FileManagerDisplaySnapshot(
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

private struct FileManagerRenameResult: Equatable, Sendable {
    let oldPath: String
    let newURL: URL
    let isDirectory: Bool
}

private struct FileManagerTrashRecord: Equatable, Sendable {
    let originalURL: URL
    let trashURL: URL?
    let isDirectory: Bool
}

private enum FileManagerSelectionMode {
    case primary
    case toggle
    case range
}

private struct FilePreviewTextDocument: Equatable, Sendable {
    struct Row: Equatable, Sendable, Identifiable {
        let id: Int
        let number: Int
        let text: String
    }

    let lines: [String]
    let rows: [Row]
    let lineCount: Int
    let displayedLineCount: Int
    let formatLabel: String?

    init(text: String, formatLabel: String? = nil) {
        let splitLines = text.components(separatedBy: .newlines)
        let lines = Array(splitLines.prefix(Self.maxRenderedLines))
        self.lines = lines
        self.rows = lines.enumerated().map { index, line in
            Row(id: index, number: index + 1, text: line)
        }
        self.lineCount = max(1, splitLines.count)
        self.displayedLineCount = rows.count
        self.formatLabel = formatLabel
    }

    var isLineLimited: Bool {
        displayedLineCount < lineCount
    }

    private static let maxRenderedLines = 800
}

private struct FilePreviewTableDocument: Equatable, Sendable {
    struct Row: Equatable, Sendable, Identifiable {
        let id: Int
        let index: Int
        let values: [String]
    }

    let rows: [[String]]
    let indexedRows: [Row]
    let delimiterName: String
    let sourceLineCount: Int
    let columnCount: Int

    init(rows: [[String]], delimiterName: String, sourceLineCount: Int) {
        self.rows = rows
        self.indexedRows = rows.enumerated().map { index, values in
            Row(id: index, index: index, values: values)
        }
        self.delimiterName = delimiterName
        self.sourceLineCount = sourceLineCount
        self.columnCount = rows.map(\.count).max() ?? 0
    }
}

private struct FilePreviewKeyValueDocument: Equatable, Sendable {
    struct Row: Equatable, Sendable, Identifiable {
        var id: Int { index }
        let index: Int
        let key: String
        let value: String
        let raw: String
    }

    let rows: [Row]
    let formatLabel: String
    let sourceLineCount: Int
}

private struct FilePreviewStructuredDocument: Equatable, Sendable {
    struct Row: Equatable, Sendable, Identifiable {
        let id: String
        let path: String
        let key: String
        let kind: String
        let value: String
        let depth: Int
    }

    let rows: [Row]
    let formatLabel: String
    let sourceLineCount: Int
}

private enum FilePreviewState: Equatable, Sendable {
    case empty
    case loading
    case directory(String)
    case image(URL)
    case document(URL)
    case nativePreview(URL, ConductorNativePreviewDescriptor)
    case text(FilePreviewTextDocument, truncated: Bool)
    case table(FilePreviewTableDocument, truncated: Bool)
    case keyValue(FilePreviewKeyValueDocument, truncated: Bool)
    case structured(FilePreviewStructuredDocument, truncated: Bool)
    case message(String)
    case failed(String)
}

private enum FileManagerOpenMode {
    case workspaceEditor
    case systemApplication
}

private enum FileManagerSortMode: String, CaseIterable, Identifiable {
    case name
    case modified
    case size
    case type

    var id: String { rawValue }

    var title: String {
        switch self {
        case .name:
            L("名称", "Name")
        case .modified:
            L("修改时间", "Modified")
        case .size:
            L("大小", "Size")
        case .type:
            L("类型", "Type")
        }
    }
}

private enum FileManagerKindFilter: String, CaseIterable, Identifiable {
    case all
    case folders
    case documents
    case code
    case data
    case images
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            L("全部", "All")
        case .folders:
            L("文件夹", "Folders")
        case .documents:
            L("文档", "Docs")
        case .code:
            L("代码", "Code")
        case .data:
            L("数据", "Data")
        case .images:
            L("图片", "Images")
        case .other:
            L("其他", "Other")
        }
    }

    var systemImage: String {
        switch self {
        case .all:
            "square.grid.2x2"
        case .folders:
            "folder"
        case .documents:
            "doc.text"
        case .code:
            "curlybraces"
        case .data:
            "tablecells"
        case .images:
            "photo"
        case .other:
            "ellipsis"
        }
    }
}

private enum FileManagerPasteboard {
    static let cutType = NSPasteboard.PasteboardType("com.conductor.file-cut")

    static var containsCutMarker: Bool {
        NSPasteboard.general.propertyList(forType: cutType) != nil
    }

    static func writeFile(_ url: URL, cut: Bool) {
        writeFiles([url], cut: cut)
    }

    static func writeFiles(_ urls: [URL], cut: Bool) {
        let standardizedURLs = urls.map(\.standardizedFileURL)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects(standardizedURLs.map { $0 as NSURL })
        if cut {
            NSPasteboard.general.setPropertyList(standardizedURLs.map(\.path), forType: cutType)
        }
    }
}

private struct FileManagerService {
    private let fileManager: FileManager
    private static let maxInlineTextBytes = 256 * 1024
    private static let maxTablePreviewRows = 180
    private static let maxTablePreviewColumns = 40
    private static let maxKeyValuePreviewLines = 300
    private static let maxStructuredPreviewRows = 700
    private static let maxJSONLPreviewLines = 120
    private static let maxYAMLPreviewLines = 700
    typealias ConflictResolver = (_ sourceURL: URL, _ destinationURL: URL, _ suggestedName: String) -> String?

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func directoryItems(
        at directoryURL: URL,
        includeHidden: Bool,
        sortMode: FileManagerSortMode
    ) throws -> [FileManagerItem] {
        let url = directoryURL.standardizedFileURL
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isSymbolicLinkKey,
            .isPackageKey,
            .nameKey,
            .fileSizeKey,
            .contentTypeKey,
            .contentModificationDateKey,
            .creationDateKey,
            .isReadableKey,
            .isWritableKey
        ]
        let urls = try fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsSubdirectoryDescendants]
        )
        let relativeDateFormatter = RelativeDateTimeFormatter()
        relativeDateFormatter.unitsStyle = .short

        return urls.compactMap { childURL in
            guard let values = try? childURL.resourceValues(forKeys: keys) else { return nil }
            let isDirectory = values.isDirectory == true && values.isPackage != true
            let standardizedURL = childURL.standardizedFileURL
            let byteCount = values.fileSize.map(Int64.init)
            let contentType = values.contentType
            let typeLabel = Self.typeLabel(for: standardizedURL, isDirectory: isDirectory)
            let subtitle = Self.subtitle(for: isDirectory, byteCount: byteCount)
            return FileManagerItem(
                url: standardizedURL,
                name: values.name ?? childURL.lastPathComponent,
                isDirectory: isDirectory,
                isSymbolicLink: values.isSymbolicLink == true,
                byteCount: byteCount,
                modificationDate: values.contentModificationDate,
                creationDate: values.creationDate,
                isReadable: values.isReadable ?? true,
                isWritable: values.isWritable ?? true,
                contentTypeIdentifier: contentType?.identifier,
                subtitle: subtitle,
                typeLabel: typeLabel,
                rowDetail: Self.rowDetail(
                    for: standardizedURL,
                    isDirectory: isDirectory,
                    byteCount: byteCount,
                    modificationDate: values.contentModificationDate,
                    relativeDateFormatter: relativeDateFormatter
                ),
                isLargeEditableFile: !isDirectory && (byteCount ?? 0) > 20 * 1024 * 1024,
                isUnsupportedBinaryLikeFile: Self.isUnsupportedBinaryLikeFile(
                    standardizedURL,
                    isDirectory: isDirectory,
                    contentType: contentType
                )
            )
        }
        .filter { includeHidden || !$0.name.hasPrefix(".") }
        .filter { $0.name != ".DS_Store" }
        .sorted { Self.sort($0, before: $1, mode: sortMode) }
    }

    private static func subtitle(for isDirectory: Bool, byteCount: Int64?) -> String {
        if isDirectory { return L("文件夹", "Folder") }
        guard let byteCount else { return L("文件", "File") }
        return ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
    }

    private static func typeLabel(for url: URL, isDirectory: Bool) -> String {
        if isDirectory { return L("文件夹", "Folder") }
        let ext = url.pathExtension.lowercased()
        return ext.isEmpty ? L("文件", "File") : ext.uppercased()
    }

    private static func rowDetail(
        for url: URL,
        isDirectory: Bool,
        byteCount: Int64?,
        modificationDate: Date?,
        relativeDateFormatter: RelativeDateTimeFormatter
    ) -> String {
        var parts: [String] = []
        if isDirectory {
            parts.append(L("文件夹", "Folder"))
        } else if let byteCount {
            parts.append(ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file))
        } else {
            let ext = url.pathExtension.lowercased()
            parts.append(ext.isEmpty ? L("文件", "File") : ext.uppercased())
        }
        if let modificationDate {
            parts.append(relativeDateFormatter.localizedString(for: modificationDate, relativeTo: Date()))
        }
        return parts.joined(separator: " · ")
    }

    private static func isUnsupportedBinaryLikeFile(_ url: URL, isDirectory: Bool, contentType: UTType?) -> Bool {
        guard !isDirectory else { return false }
        if textishExtensions.contains(url.pathExtension.lowercased()) {
            return false
        }
        if let contentType,
           contentType.conforms(to: .image) ||
            contentType.conforms(to: .text) ||
            contentType.conforms(to: .sourceCode) {
            return false
        }
        return true
    }

    private static let textishExtensions: Set<String> = [
        "md", "markdown", "txt", "log", "json", "jsonl", "yaml", "yml", "toml", "plist",
        "csv", "tsv", "xml", "env", "ini", "conf", "cfg", "properties", "swift", "js",
        "jsx", "ts", "tsx", "py", "rb", "sh", "zsh", "bash", "go", "rs", "java", "kt",
        "kts", "c", "cc", "cpp", "h", "hpp", "m", "mm", "html", "css", "scss", "sql"
    ]


    func createFile(in directoryURL: URL) throws -> URL {
        let directory = directoryURL.standardizedFileURL
        let destination = availableURL(baseName: "Untitled", extension: "txt", in: directory)
        guard fileManager.createFile(atPath: destination.path, contents: Data(), attributes: nil) else {
            throw NSError(domain: "ConductorFileManager", code: 500, userInfo: [
                NSLocalizedDescriptionKey: L("无法创建文件", "Could not create file")
            ])
        }
        return destination.standardizedFileURL
    }

    func createFolder(in directoryURL: URL) throws -> URL {
        let directory = directoryURL.standardizedFileURL
        let destination = availableURL(baseName: "New Folder", extension: "", in: directory)
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: false)
        return destination.standardizedFileURL
    }

    func duplicateItem(at sourceURL: URL) throws -> URL {
        let source = sourceURL.standardizedFileURL
        let directory = source.deletingLastPathComponent()
        let destination = directory.appendingPathComponent(availableCopyName(for: source.lastPathComponent, in: directory)).standardizedFileURL
        try fileManager.copyItem(at: source, to: destination)
        return destination.standardizedFileURL
    }

    func preview(for url: URL) -> FilePreviewState {
        let fileURL = url.standardizedFileURL
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .fileSizeKey, .contentTypeKey]
        guard let values = try? fileURL.resourceValues(forKeys: keys) else {
            return .failed(L("无法读取这个项目", "Could not read this item"))
        }

        if values.isDirectory == true {
            return .directory(L("双击进入文件夹，或使用上方按钮返回上级。", "Double-click to enter this folder, or use the button above to go up."))
        }

        let type = values.contentType ?? UTType(filenameExtension: fileURL.pathExtension)
        if Self.imagePreviewExtensions.contains(fileURL.pathExtension.lowercased()) ||
            type?.conforms(to: .image) == true {
            return .image(fileURL)
        }
        if let descriptor = Self.nativePreviewDescriptor(for: fileURL, type: type) {
            return .nativePreview(fileURL, descriptor)
        }
        if Self.documentViewerPreviewExtensions.contains(fileURL.pathExtension.lowercased()) {
            return .document(fileURL)
        }
        guard Self.isInlineTextPreviewType(type, extension: fileURL.pathExtension) else {
            return .message(L("这个文件类型暂不支持内联预览", "This file type cannot be previewed inline yet"))
        }

        let size = values.fileSize ?? 0
        let readLimit = min(max(size, 0), Self.maxInlineTextBytes)
        do {
            let handle = try FileHandle(forReadingFrom: fileURL)
            defer { try? handle.close() }
            let data = try handle.read(upToCount: readLimit) ?? Data()
            if data.contains(0) {
                return .message(L("二进制文件暂不支持内联预览", "Binary files cannot be previewed inline"))
            }
            let text = String(data: data, encoding: .utf8) ??
                String(data: data, encoding: .utf16) ??
                String(decoding: data, as: UTF8.self)
            let truncated = size > Self.maxInlineTextBytes
            if let table = Self.tablePreview(for: text, extension: fileURL.pathExtension) {
                return .table(table, truncated: truncated)
            }
            if let structured = Self.structuredPreview(for: text, extension: fileURL.pathExtension) {
                return .structured(structured, truncated: truncated)
            }
            if let keyValue = Self.keyValuePreview(for: text, extension: fileURL.pathExtension) {
                return .keyValue(keyValue, truncated: truncated)
            }
            return .text(Self.textDocument(for: text, extension: fileURL.pathExtension), truncated: truncated)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    func openMode(for url: URL) -> FileManagerOpenMode {
        let pathExtension = url.pathExtension.lowercased()
        if Self.imagePreviewExtensions.contains(pathExtension) {
            return .workspaceEditor
        }
        if ConductorNativePreviewClassifier.descriptor(for: UTType(filenameExtension: pathExtension), extension: pathExtension) != nil {
            return .workspaceEditor
        }
        if UTType(filenameExtension: pathExtension)?.conforms(to: .image) == true {
            return .workspaceEditor
        }
        if Self.systemApplicationExtensions.contains(pathExtension) {
            return .systemApplication
        }
        guard let type = UTType(filenameExtension: pathExtension) else {
            return .workspaceEditor
        }
        if type.conforms(to: .image) ||
            type.conforms(to: .movie) ||
            type.conforms(to: .audiovisualContent) ||
            type.conforms(to: .presentation) ||
            type.conforms(to: .spreadsheet) {
            return .systemApplication
        }
        return .workspaceEditor
    }

    private static func nativePreviewDescriptor(for url: URL, type: UTType?) -> ConductorNativePreviewDescriptor? {
        ConductorNativePreviewClassifier.descriptor(for: type, extension: url.pathExtension)
    }

    func fileURLsFromPasteboard(_ pasteboard: NSPasteboard = .general) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        guard let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL] else {
            return []
        }
        return urls.map { $0.standardizedFileURL }
    }

    func renameItem(at sourceURL: URL, to newName: String) throws -> URL {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("/") else {
            throw NSError(domain: "ConductorFileManager", code: 400, userInfo: [
                NSLocalizedDescriptionKey: L("请输入有效文件名", "Enter a valid file name")
            ])
        }
        let source = sourceURL.standardizedFileURL
        let destination = source.deletingLastPathComponent().appendingPathComponent(trimmed)
        guard source.path != destination.standardizedFileURL.path else { return source }
        guard !fileManager.fileExists(atPath: destination.path) else {
            throw NSError(domain: "ConductorFileManager", code: 409, userInfo: [
                NSLocalizedDescriptionKey: L("同名项目已存在", "An item with that name already exists")
            ])
        }
        try fileManager.moveItem(at: source, to: destination)
        return destination.standardizedFileURL
    }

    func pasteItems(
        _ sourceURLs: [URL],
        into targetDirectory: URL,
        move: Bool,
        conflictResolver: ConflictResolver? = nil
    ) throws -> [URL] {
        let directory = targetDirectory.standardizedFileURL
        let values = try directory.resourceValues(forKeys: [.isDirectoryKey])
        guard values.isDirectory == true else {
            throw NSError(domain: "ConductorFileManager", code: 400, userInfo: [
                NSLocalizedDescriptionKey: L("目标不是文件夹", "The target is not a folder")
            ])
        }

        var destinations: [URL] = []
        for sourceURL in sourceURLs.map(\.standardizedFileURL) {
            guard fileManager.fileExists(atPath: sourceURL.path) else { continue }
            if move, sourceURL.path == directory.path { continue }
            if move, isDirectory(sourceURL), directory.path.hasPrefix(sourceURL.path + "/") {
                throw NSError(domain: "ConductorFileManager", code: 409, userInfo: [
                    NSLocalizedDescriptionKey: L("不能把文件夹移动到它自己里面", "A folder cannot be moved into itself")
                ])
            }

            guard let destination = resolvedDestination(for: sourceURL, in: directory, conflictResolver: conflictResolver) else {
                continue
            }
            if sourceURL.path == destination.standardizedFileURL.path { continue }
            if move {
                try fileManager.moveItem(at: sourceURL, to: destination)
            } else {
                try fileManager.copyItem(at: sourceURL, to: destination)
            }
            destinations.append(destination.standardizedFileURL)
        }
        return destinations
    }

    func moveToTrash(_ url: URL) throws -> FileManagerTrashRecord {
        let source = url.standardizedFileURL
        let isDirectory = isDirectory(source)
        var resultingURL: NSURL?
        try fileManager.trashItem(at: source, resultingItemURL: &resultingURL)
        return FileManagerTrashRecord(
            originalURL: source,
            trashURL: (resultingURL as URL?)?.standardizedFileURL,
            isDirectory: isDirectory
        )
    }

    func restoreTrashRecord(_ record: FileManagerTrashRecord) throws {
        guard let trashURL = record.trashURL,
              fileManager.fileExists(atPath: trashURL.path) else {
            throw NSError(domain: "ConductorFileManager", code: 404, userInfo: [
                NSLocalizedDescriptionKey: L("废纸篓中的项目已经不存在，无法撤销", "The trashed item no longer exists, so undo is unavailable")
            ])
        }
        guard !fileManager.fileExists(atPath: record.originalURL.path) else {
            throw NSError(domain: "ConductorFileManager", code: 409, userInfo: [
                NSLocalizedDescriptionKey: L("原位置已经有同名项目，无法撤销", "The original location already contains an item with the same name")
            ])
        }
        try fileManager.moveItem(at: trashURL, to: record.originalURL)
    }

    private func resolvedDestination(
        for sourceURL: URL,
        in directory: URL,
        conflictResolver: ConflictResolver?
    ) -> URL? {
        let proposed = directory.appendingPathComponent(sourceURL.lastPathComponent)
        guard fileManager.fileExists(atPath: proposed.path) else { return proposed }

        let suggestedName = availableCopyName(for: sourceURL.lastPathComponent, in: directory)
        guard let conflictResolver else {
            return directory.appendingPathComponent(suggestedName)
        }
        guard let replacementName = conflictResolver(sourceURL, proposed, suggestedName)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !replacementName.isEmpty,
              !replacementName.contains("/") else {
            return nil
        }
        let candidate = directory.appendingPathComponent(replacementName)
        guard !fileManager.fileExists(atPath: candidate.path) else {
            return resolvedDestination(
                for: URL(fileURLWithPath: replacementName),
                in: directory,
                conflictResolver: conflictResolver
            )
        }
        return candidate
    }

    private func availableCopyName(for fileName: String, in directory: URL) -> String {
        let url = URL(fileURLWithPath: fileName)
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        var index = 1
        while true {
            let suffix = index == 1 ? " copy" : " copy \(index)"
            let name = ext.isEmpty ? "\(base)\(suffix)" : "\(base)\(suffix).\(ext)"
            let candidate = directory.appendingPathComponent(name)
            if !fileManager.fileExists(atPath: candidate.path) {
                return name
            }
            index += 1
        }
    }

    private func availableURL(baseName: String, extension pathExtension: String, in directory: URL) -> URL {
        var index = 0
        while true {
            let suffix = index == 0 ? "" : " \(index + 1)"
            let name = pathExtension.isEmpty ? "\(baseName)\(suffix)" : "\(baseName)\(suffix).\(pathExtension)"
            let candidate = directory.appendingPathComponent(name)
            if !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
            index += 1
        }
    }

    private static func sort(_ lhs: FileManagerItem, before rhs: FileManagerItem, mode: FileManagerSortMode) -> Bool {
        if lhs.isDirectory != rhs.isDirectory {
            return lhs.isDirectory && !rhs.isDirectory
        }
        switch mode {
        case .name:
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        case .modified:
            let left = lhs.modificationDate ?? .distantPast
            let right = rhs.modificationDate ?? .distantPast
            if left != right { return left > right }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        case .size:
            let left = lhs.byteCount ?? -1
            let right = rhs.byteCount ?? -1
            if left != right { return left > right }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        case .type:
            let typeOrder = lhs.typeLabel.localizedStandardCompare(rhs.typeLabel)
            if typeOrder != .orderedSame { return typeOrder == .orderedAscending }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    private static func textDocument(for text: String, extension pathExtension: String) -> FilePreviewTextDocument {
        switch pathExtension.lowercased() {
        case "json":
            guard let data = text.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data),
                  let prettyData = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .withoutEscapingSlashes]),
                  let prettyText = String(data: prettyData, encoding: .utf8) else {
                return FilePreviewTextDocument(text: text, formatLabel: L("JSON", "JSON"))
            }
            return FilePreviewTextDocument(text: prettyText, formatLabel: L("JSON 格式化", "Formatted JSON"))
        case "jsonl":
            return FilePreviewTextDocument(text: text, formatLabel: "JSONL")
        case "yaml", "yml":
            return FilePreviewTextDocument(text: text, formatLabel: "YAML")
        case "toml":
            return FilePreviewTextDocument(text: text, formatLabel: "TOML")
        case "plist":
            return FilePreviewTextDocument(text: text, formatLabel: "plist")
        default:
            return FilePreviewTextDocument(text: text)
        }
    }

    private static func tablePreview(for text: String, extension pathExtension: String) -> FilePreviewTableDocument? {
        let ext = pathExtension.lowercased()
        let delimiter: Character
        let delimiterName: String
        switch ext {
        case "csv":
            delimiter = ","
            delimiterName = "CSV"
        case "tsv", "tab":
            delimiter = "\t"
            delimiterName = "TSV"
        default:
            return nil
        }

        let rawLines = text.components(separatedBy: .newlines)
        let rows = rawLines
            .prefix(Self.maxTablePreviewRows)
            .map { Array(parseDelimitedLine($0, delimiter: delimiter).prefix(Self.maxTablePreviewColumns)) }
            .filter { !$0.isEmpty }
        guard !rows.isEmpty else { return nil }
        return FilePreviewTableDocument(rows: rows, delimiterName: delimiterName, sourceLineCount: rawLines.count)
    }

    private static func keyValuePreview(for text: String, extension pathExtension: String) -> FilePreviewKeyValueDocument? {
        let ext = pathExtension.lowercased()
        guard ["conf", "cfg", "env", "ini", "properties"].contains(ext) else { return nil }
        let separatorCandidates = ["=", ":"]
        let rawLines = text.components(separatedBy: .newlines)
        let rows = rawLines.prefix(Self.maxKeyValuePreviewLines).enumerated().compactMap { index, line -> FilePreviewKeyValueDocument.Row? in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty,
                  !trimmed.hasPrefix("#"),
                  !trimmed.hasPrefix(";") else { return nil }
            guard let separator = separatorCandidates
                .compactMap({ candidate -> String.Index? in line.firstIndex(of: Character(candidate)) })
                .min() else { return nil }
            let key = String(line[..<separator]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { return nil }
            return FilePreviewKeyValueDocument.Row(index: index + 1, key: key, value: value, raw: line)
        }
        guard !rows.isEmpty else { return nil }
        return FilePreviewKeyValueDocument(rows: rows, formatLabel: ext.uppercased(), sourceLineCount: rawLines.count)
    }

    private static func structuredPreview(for text: String, extension pathExtension: String) -> FilePreviewStructuredDocument? {
        let ext = pathExtension.lowercased()
        switch ext {
        case "json":
            guard let data = text.data(using: .utf8) else { return nil }
            do {
                let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
                return FilePreviewStructuredDocument(
                    rows: flattenedStructuredRows(for: object, rootPath: "$", rootKey: "$", limit: Self.maxStructuredPreviewRows),
                    formatLabel: "JSON",
                    sourceLineCount: text.components(separatedBy: .newlines).count
                )
            } catch {
                return FilePreviewStructuredDocument(
                    rows: [FilePreviewStructuredDocument.Row(
                        id: "json-error",
                        path: "$",
                        key: L("解析错误", "Parse Error"),
                        kind: L("错误", "Error"),
                        value: error.localizedDescription,
                        depth: 0
                    )],
                    formatLabel: "JSON",
                    sourceLineCount: text.components(separatedBy: .newlines).count
                )
            }
        case "jsonl":
            let lines = text.components(separatedBy: .newlines)
            var rows: [FilePreviewStructuredDocument.Row] = []
            for (index, line) in lines.prefix(Self.maxJSONLPreviewLines).enumerated() {
                guard rows.count < Self.maxStructuredPreviewRows else { break }
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { continue }
                do {
                    let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
                    rows.append(contentsOf: flattenedStructuredRows(
                        for: object,
                        rootPath: "$[\(index + 1)]",
                        rootKey: "[\(index + 1)]",
                        limit: max(1, Self.maxStructuredPreviewRows - rows.count)
                    ))
                } catch {
                    rows.append(FilePreviewStructuredDocument.Row(
                        id: "jsonl-\(index)-error",
                        path: "$[\(index + 1)]",
                        key: "[\(index + 1)]",
                        kind: L("错误", "Error"),
                        value: error.localizedDescription,
                        depth: 0
                    ))
                }
            }
            guard !rows.isEmpty else { return nil }
            return FilePreviewStructuredDocument(rows: rows, formatLabel: "JSONL", sourceLineCount: lines.count)
        case "plist":
            guard let data = text.data(using: .utf8),
                  let object = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) else {
                return nil
            }
            return FilePreviewStructuredDocument(
                rows: flattenedStructuredRows(for: object, rootPath: "$", rootKey: "$", limit: Self.maxStructuredPreviewRows),
                formatLabel: "Plist",
                sourceLineCount: text.components(separatedBy: .newlines).count
            )
        case "yaml", "yml":
            let rows = yamlStructuredRows(for: text)
            guard !rows.isEmpty else { return nil }
            return FilePreviewStructuredDocument(rows: rows, formatLabel: "YAML", sourceLineCount: text.components(separatedBy: .newlines).count)
        case "toml":
            let rows = tomlStructuredRows(for: text)
            guard !rows.isEmpty else { return nil }
            return FilePreviewStructuredDocument(rows: rows, formatLabel: "TOML", sourceLineCount: text.components(separatedBy: .newlines).count)
        default:
            return nil
        }
    }

    private static func flattenedStructuredRows(
        for value: Any,
        rootPath: String,
        rootKey: String,
        depth: Int = 0,
        limit: Int = Self.maxStructuredPreviewRows
    ) -> [FilePreviewStructuredDocument.Row] {
        var rows: [FilePreviewStructuredDocument.Row] = []

        func append(_ value: Any, key: String, path: String, depth: Int) {
            guard rows.count < limit else { return }
            let kind: String
            let displayValue: String
            if let dictionary = value as? [String: Any] {
                kind = L("对象", "Object")
                displayValue = L("\(dictionary.count) 个键", "\(dictionary.count) keys")
                rows.append(.init(id: path, path: path, key: key, kind: kind, value: displayValue, depth: depth))
                for childKey in dictionary.keys.sorted() {
                    guard let child = dictionary[childKey] else { continue }
                    append(child, key: childKey, path: "\(path).\(childKey)", depth: depth + 1)
                }
            } else if let array = value as? [Any] {
                kind = L("数组", "Array")
                displayValue = L("\(array.count) 项", "\(array.count) items")
                rows.append(.init(id: path, path: path, key: key, kind: kind, value: displayValue, depth: depth))
                for (index, child) in array.enumerated() {
                    append(child, key: "[\(index)]", path: "\(path)[\(index)]", depth: depth + 1)
                }
            } else if value is NSNull {
                rows.append(.init(id: path, path: path, key: key, kind: "Null", value: "null", depth: depth))
            } else if let bool = value as? Bool {
                rows.append(.init(id: path, path: path, key: key, kind: "Bool", value: bool ? "true" : "false", depth: depth))
            } else if let number = value as? NSNumber {
                rows.append(.init(id: path, path: path, key: key, kind: "Number", value: number.stringValue, depth: depth))
            } else {
                rows.append(.init(id: path, path: path, key: key, kind: "String", value: String(describing: value), depth: depth))
            }
        }

        append(value, key: rootKey, path: rootPath, depth: depth)
        if rows.count >= limit {
            rows.append(truncatedStructuredRow(rootPath: rootPath, limit: limit))
        }
        return rows
    }

    private static func truncatedStructuredRow(rootPath: String, limit: Int) -> FilePreviewStructuredDocument.Row {
        FilePreviewStructuredDocument.Row(
            id: "\(rootPath)-truncated-\(limit)",
            path: rootPath,
            key: L("已截断", "Truncated"),
            kind: L("提示", "Notice"),
            value: L("结构节点较多，只显示前 \(limit) 项", "Large structure; showing the first \(limit) nodes"),
            depth: 0
        )
    }

    private static func yamlStructuredRows(for text: String) -> [FilePreviewStructuredDocument.Row] {
        var stack: [(indent: Int, key: String)] = []
        var rows: [FilePreviewStructuredDocument.Row] = []
        for (lineIndex, line) in text.components(separatedBy: .newlines).prefix(Self.maxYAMLPreviewLines).enumerated() {
            guard rows.count < Self.maxStructuredPreviewRows else { break }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            let indent = line.prefix { $0 == " " }.count
            while let last = stack.last, last.indent >= indent {
                stack.removeLast()
            }

            var key: String
            var value: String
            if trimmed.hasPrefix("- ") {
                let item = String(trimmed.dropFirst(2))
                key = "[\(lineIndex + 1)]"
                value = item
            } else if let colon = trimmed.firstIndex(of: ":") {
                key = String(trimmed[..<colon]).trimmingCharacters(in: .whitespaces)
                value = String(trimmed[trimmed.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            } else {
                key = "[\(lineIndex + 1)]"
                value = trimmed
            }
            let parentPath = stack.map(\.key).joined(separator: ".")
            let path = parentPath.isEmpty ? key : "\(parentPath).\(key)"
            let kind = value.isEmpty ? L("节点", "Node") : L("值", "Value")
            rows.append(.init(id: "yaml-\(lineIndex)", path: path, key: key, kind: kind, value: value, depth: stack.count))
            if value.isEmpty {
                stack.append((indent: indent, key: key))
            }
        }
        if rows.count >= Self.maxStructuredPreviewRows {
            rows.append(truncatedStructuredRow(rootPath: "$", limit: Self.maxStructuredPreviewRows))
        }
        return rows
    }

    private static func tomlStructuredRows(for text: String) -> [FilePreviewStructuredDocument.Row] {
        var section: [String] = []
        var rows: [FilePreviewStructuredDocument.Row] = []
        for (lineIndex, line) in text.components(separatedBy: .newlines).prefix(Self.maxYAMLPreviewLines).enumerated() {
            guard rows.count < Self.maxStructuredPreviewRows else { break }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                let name = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
                section = name.split(separator: ".").map(String.init)
                rows.append(.init(id: "toml-section-\(lineIndex)", path: section.joined(separator: "."), key: name, kind: L("节", "Section"), value: "", depth: max(0, section.count - 1)))
                continue
            }
            guard let separator = trimmed.firstIndex(of: "=") else { continue }
            let key = String(trimmed[..<separator]).trimmingCharacters(in: .whitespaces)
            let value = String(trimmed[trimmed.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
            let path = (section + [key]).joined(separator: ".")
            rows.append(.init(id: "toml-\(lineIndex)", path: path, key: key, kind: L("值", "Value"), value: value, depth: section.count))
        }
        if rows.count >= Self.maxStructuredPreviewRows {
            rows.append(truncatedStructuredRow(rootPath: "$", limit: Self.maxStructuredPreviewRows))
        }
        return rows
    }

    private static func parseDelimitedLine(_ line: String, delimiter: Character) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        var iterator = line.makeIterator()
        while let character = iterator.next() {
            if character == "\"" {
                if inQuotes {
                    var lookahead = iterator
                    if lookahead.next() == "\"" {
                        _ = iterator.next()
                        current.append("\"")
                    } else {
                        inQuotes = false
                    }
                } else {
                    inQuotes = true
                }
            } else if character == delimiter && !inQuotes {
                fields.append(current)
                current = ""
            } else {
                current.append(character)
            }
        }
        fields.append(current)
        return fields
    }

    private static func isInlineTextPreviewType(_ type: UTType?, extension pathExtension: String) -> Bool {
        if type?.conforms(to: .text) == true || type?.conforms(to: .sourceCode) == true {
            return true
        }
        return textPreviewExtensions.contains(pathExtension.lowercased())
    }

    private static let textPreviewExtensions: Set<String> = [
        "adoc", "bash", "bib", "c", "cc", "cfg", "cls", "conf", "cpp", "css", "csv", "diff", "env", "err", "go", "h", "hpp", "htm",
        "html", "java", "js", "json", "jsonl", "jsx", "latex", "log", "m", "md", "mm", "out", "patch", "php",
        "plist", "properties", "py", "rb", "rs", "rst", "scss", "sh", "stderr", "stdout", "sty", "swift", "tab", "tex", "toml",
        "trace", "ts", "tsv", "tsx", "txt", "xml", "yaml", "yml", "zsh"
    ]

    private static let documentViewerPreviewExtensions: Set<String> = [
        "adoc", "bib", "cls", "latex", "log", "markdown", "md", "mdown", "mkd", "out", "rst", "stderr",
        "stdout", "sty", "tex", "text", "trace", "txt"
    ]

    private static let systemApplicationExtensions: Set<String> = [
        "apng", "avif", "bmp", "gif", "heic", "heif", "ico", "jpeg", "jpg", "png", "psd", "svg", "tif", "tiff", "webp",
        "3g2", "3gp", "avi", "m4v", "mkv", "mov", "mp4", "mpeg", "mpg", "webm", "wmv",
        "aac", "aiff", "flac", "m4a", "mp3", "ogg", "wav",
        "doc", "docx", "key", "numbers", "pages", "pdf", "ppt", "pptx", "xls", "xlsx"
    ]

    private static let imagePreviewExtensions: Set<String> = [
        "apng", "avif", "bmp", "gif", "heic", "heif", "ico", "jpeg", "jpg", "png",
        "psd", "svg", "tif", "tiff", "webp"
    ]
}

@MainActor
private final class FileManagerPanelStore: ObservableObject {
    @Published private(set) var currentURL: URL?
    @Published private(set) var items: [FileManagerItem] = [] {
        didSet { rebuildDisplaySnapshot() }
    }
    @Published private(set) var expandedDirectoryPaths: Set<String> = [] {
        didSet { rebuildDisplaySnapshot() }
    }
    @Published private(set) var childItemsByDirectoryPath: [String: [FileManagerItem]] = [:] {
        didSet { rebuildDisplaySnapshot() }
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
        didSet { rebuildDisplaySnapshot() }
    }
    @Published private(set) var searchHistory: [String] = []
    @Published var includeHiddenFiles = false
    @Published var sortMode: FileManagerSortMode = .name
    @Published var kindFilter: FileManagerKindFilter = .all {
        didSet { rebuildDisplaySnapshot() }
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
    private(set) var displaySnapshot = FileManagerDisplaySnapshot.empty
    private var selectedItemsSnapshot: [FileManagerItem] = []

    var visibleRows: [FileManagerVisibleRow] {
        displaySnapshot.rows
    }

    var displayedRows: [FileManagerVisibleRow] {
        displaySnapshot.rows
    }

    var totalKnownItemCount: Int {
        displaySnapshot.totalKnownItemCount
    }

    var displayedFileCount: Int {
        displaySnapshot.displayedFileCount
    }

    var displayedDirectoryCount: Int {
        displaySnapshot.displayedDirectoryCount
    }

    private func rebuildDisplaySnapshot() {
        let snapshot = FileManagerDisplaySnapshotBuilder.build(
            items: items,
            expandedDirectoryPaths: expandedDirectoryPaths,
            childItemsByDirectoryPath: childItemsByDirectoryPath,
            searchQuery: searchQuery,
            kindFilter: kindFilter
        )
        guard snapshot != displaySnapshot else { return }
        displaySnapshot = snapshot
        rebuildSelectedItemsSnapshot()
    }

    private func rebuildSelectedItemsSnapshot() {
        guard !selectedPaths.isEmpty else {
            if !selectedItemsSnapshot.isEmpty {
                selectedItemsSnapshot = []
            }
            return
        }
        var selected: [FileManagerItem] = []
        selected.reserveCapacity(min(displaySnapshot.rows.count, selectedPaths.count))
        for row in displaySnapshot.rows where selectedPaths.contains(row.item.url.path) {
            selected.append(row.item)
        }
        if selected != selectedItemsSnapshot {
            selectedItemsSnapshot = selected
        }
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
            selectedPaths = [item.url.path]
            selectionAnchorPath = item.url.path
        case .toggle:
            if selectedPaths.contains(item.url.path) {
                selectedPaths.remove(item.url.path)
            } else {
                selectedPaths.insert(item.url.path)
            }
            selectionAnchorPath = item.url.path
        case .range:
            let rows = displayedRows
            let anchorPath = selectionAnchorPath ?? selectedItem?.url.path ?? item.url.path
            guard let anchorIndex = rows.firstIndex(where: { $0.item.url.path == anchorPath }),
                  let itemIndex = rows.firstIndex(where: { $0.item.url.path == item.url.path }) else {
                selectedPaths = [item.url.path]
                selectionAnchorPath = item.url.path
                selectedItem = item
                operationMessage = nil
                return
            }
            let range = min(anchorIndex, itemIndex)...max(anchorIndex, itemIndex)
            selectedPaths = Set(range.map { rows[$0].item.url.path })
        }
        if selectedPaths.isEmpty {
            selectedItem = nil
        } else {
            selectedItem = item
        }
        operationMessage = nil
    }

    func selectAdjacentRow(by offset: Int) {
        let rows = displayedRows
        guard !rows.isEmpty else { return }
        let currentIndex = selectedItem.flatMap { selected in
            rows.firstIndex { $0.item.id == selected.id }
        } ?? (offset >= 0 ? -1 : rows.count)
        let nextIndex = min(max(currentIndex + offset, 0), rows.count - 1)
        select(rows[nextIndex].item)
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
        previewState = items.isEmpty
            ? .message(L("这个目录没有可显示的文件", "This directory has no visible files"))
            : .empty
    }

    func open(_ item: FileManagerItem) async {
        if item.isDirectory {
            await toggleDirectory(item)
        } else {
            select(item)
        }
    }

    func isExpanded(_ item: FileManagerItem) -> Bool {
        expandedDirectoryPaths.contains(item.url.path)
    }

    func isLoading(_ item: FileManagerItem) -> Bool {
        loadingDirectoryPaths.contains(item.url.path)
    }

    func toggleDirectory(_ item: FileManagerItem) async {
        guard item.isDirectory else { return }
        selectedItem = item
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
        selectedItem = items.last
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
        if let selectedItem, !displayedRows.contains(where: { $0.item.url.path == selectedItem.url.path }) {
            selectAdjacentRow(by: 1)
        }
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
            operationMessage = L("已移到废纸篓。可撤销。", "Moved to Trash. Undo is available.")
            await refresh()
            return paths
        case .failure(let error):
            operationMessage = L("移到废纸篓失败：", "Could not move to Trash: ") + error.localizedDescription
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
            operationMessage = L("已撤销删除", "Delete undone")
            let restoredPaths = Set(records.map { $0.originalURL.path })
            for record in records {
                expandedDirectoryPaths.insert(record.originalURL.deletingLastPathComponent().standardizedFileURL.path)
            }
            await refresh(selecting: records.last?.originalURL)
            return restoredPaths
        case .failure(let error):
            operationMessage = L("撤销删除失败：", "Could not undo delete: ") + error.localizedDescription
            NSSound.beep()
            return []
        }
    }

    func beginRename(_ item: FileManagerItem) {
        selectedItem = item
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
               let match = findItem(withPath: selectedPath) {
                select(match)
            } else {
                selectedItem = nil
                selectedPaths = []
                selectionAnchorPath = nil
                previewState = loadedItems.isEmpty
                    ? .message(L("这个目录没有可显示的文件", "This directory has no visible files"))
                    : .empty
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
            divider
            if searchVisible || !store.searchQuery.isEmpty {
                fileTreeSearchBar(snapshot: snapshot)
                divider
            }
            content(snapshot: snapshot)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                .font(.conductorSystem(size: 11, weight: .semibold, family: fontFamily, scale: fontScale))
                .foregroundStyle(theme.shellChromeText.opacity(0.62))
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
                .font(.conductorSystem(size: 11, weight: .semibold, family: fontFamily, scale: fontScale))
                .foregroundStyle(theme.shellChromeText.opacity(0.62))
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
                .font(.conductorSystem(size: 11, weight: .semibold, family: fontFamily, scale: fontScale))
                .foregroundStyle(store.kindFilter == .all ? theme.shellChromeText.opacity(0.62) : theme.floatingEmphasis.opacity(0.86))
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
        VStack(spacing: 0) {
            if store.isLoading && store.items.isEmpty {
                panelMessage(systemImage: "folder", text: L("读取中", "Loading"))
            } else if let error = store.errorMessage, store.items.isEmpty {
                panelMessage(systemImage: "exclamationmark.triangle", text: error)
            } else if store.items.isEmpty {
                panelMessage(systemImage: "folder", text: L("没有文件", "No files"))
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(snapshot.rows) { row in
                            FileManagerRowView(
                                item: row.item,
                                depth: row.depth,
                                isExpanded: store.isExpanded(row.item),
                                isLoading: store.isLoading(row.item),
                                isSelected: store.selectedPaths.contains(row.item.url.path),
                                selectedCount: store.selectedPaths.contains(row.item.url.path) ? store.selectedCount : 1,
                                isRenaming: store.renamingPath == row.item.url.path,
                                isPendingDelete: store.isPendingDelete(row.item),
                                renamingName: $store.renamingName,
                                renamingFocusToken: store.renamingFocusToken,
                                open: { open(row.item) },
                                openInWorkspace: { openInWorkspace(row.item) },
                                openInSystemApp: { NSWorkspace.shared.open(row.item.url) },
                                copyPath: { copyPaths(itemsForBatch(default: row.item).map(\.url)) },
                                copyName: { copyText(row.item.name) },
                                copyDirectoryPath: { copyPath(row.item.url.deletingLastPathComponent()) },
                                copyRelativePath: { copyText(relativePath(for: row.item.url)) },
                                copyShellPath: { copyText(shellEscapedPath(row.item.url.path)) },
                                copyFile: { copyFiles(itemsForBatch(default: row.item).map(\.url)) },
                                cutFile: { cutFiles(itemsForBatch(default: row.item).map(\.url)) },
                                paste: { paste(into: row.item) },
                                duplicate: { Task { await store.duplicate(row.item) } },
                                showInfo: { infoItem = row.item },
                                rename: { store.beginRename(row.item) },
                                commitRename: {
                                    Task {
                                        if let result = await store.commitRename(row.item) {
                                            model.updateWorkspaceFileTabs(
                                                moving: result.oldPath,
                                                to: result.newURL,
                                                isDirectory: result.isDirectory
                                            )
                                        }
                                    }
                                },
                                cancelRename: { store.cancelRename() },
                                delete: { store.markForDelete(itemsForBatch(default: row.item)) },
                                canPaste: canPaste,
                                insertPath: { _ = model.insertPathIntoFocusedTerminal(row.item.url) },
                                insertCDCommand: { _ = model.insertCDCommandIntoFocusedTerminal(row.item.url) },
                                insertListCommand: { _ = model.insertListCommandIntoFocusedTerminal(row.item.url) },
                                reveal: { reveal(row.item.url) },
                                dropFiles: { urls, move in
                                    Task { await store.pasteItems(urls, into: row.item, move: move) }
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 10)
                }
                .scrollIndicators(.visible)
            }
        }
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: nil) { providers in
            collectDroppedFileURLs(from: providers) { urls in
                guard !urls.isEmpty else { return }
                let move = NSApp.currentEvent?.modifierFlags.contains(.option) != true
                Task { await store.pasteItems(urls, into: nil, move: move) }
            }
            return true
        }
    }

    private func statusBar(snapshot: FileManagerDisplaySnapshot) -> some View {
        let selectedItems = store.selectedItemsForDisplay
        return HStack(spacing: 8) {
            if store.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, store.kindFilter == .all {
                statusChip(systemImage: "list.bullet", title: L("\(snapshot.totalKnownItemCount) 项", "\(snapshot.totalKnownItemCount) items"))
            } else {
                statusChip(systemImage: "line.3.horizontal.decrease", title: L("\(snapshot.rows.count)/\(snapshot.totalKnownItemCount)", "\(snapshot.rows.count)/\(snapshot.totalKnownItemCount)"))
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
            previewContent
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

    @ViewBuilder
    private var previewContent: some View {
        switch store.previewState {
        case .empty:
            panelMessage(systemImage: "doc.text.magnifyingglass", text: L("选择文件开始预览", "Select a file to preview"))
        case .loading:
            panelMessage(systemImage: "hourglass", text: L("读取中", "Loading"))
        case .directory(let message):
            panelMessage(systemImage: "folder", text: message)
        case .image(let url):
            ConductorAsyncImage(url: url) { image in
                GeometryReader { proxy in
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .background(theme.terminalBackground)
                }
            } placeholder: { isLoading, _ in
                panelMessage(
                    systemImage: isLoading ? "hourglass" : "photo",
                    text: isLoading ? L("正在读取图片", "Loading image") : L("图片无法读取", "Image could not be loaded")
                )
            }
        case .document(let url):
            ConductorDocumentWorkspaceView(
                fileURL: url,
                rootURL: store.currentURL ?? request.rootURL,
                title: url.lastPathComponent,
                theme: theme,
                fontSize: model.appearance.terminalFontSize,
                isActive: false,
                chromeStyle: .plain,
                layoutRevision: 0,
                searchQuery: "",
                searchRevision: 0,
                searchNextToken: 0,
                searchPreviousToken: 0,
                onSearchStatusChange: { _ in }
            )
        case .nativePreview(let url, let descriptor):
            VStack(spacing: 0) {
                HStack(spacing: 7) {
                    infoPill(descriptor.title)
                    Text(descriptor.reason)
                        .font(.conductorSystem(size: 10, weight: .semibold, family: fontFamily, scale: fontScale))
                        .foregroundStyle(theme.shellChromeText.opacity(0.48))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(theme.terminalChrome.opacity(theme.usesDarkChrome ? 0.72 : 0.64))
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(theme.terminalOuterStroke.opacity(theme.usesDarkChrome ? 0.48 : 0.35))
                        .frame(height: 1)
                }

                ConductorNativePreviewSurface(url: url, backgroundColor: NSColor(theme.terminalBackground))
                    .background(theme.terminalBackground)
            }
        case .text(let document, let truncated):
            FileManagerSourcePreview(
                document: document,
                truncated: truncated,
                theme: theme,
                fontFamily: fontFamily,
                fontScale: fontScale
            )
        case .table(let document, let truncated):
            FileManagerTablePreview(
                document: document,
                truncated: truncated,
                theme: theme,
                fontFamily: fontFamily,
                fontScale: fontScale
            )
        case .keyValue(let document, let truncated):
            FileManagerKeyValuePreview(
                document: document,
                truncated: truncated,
                theme: theme,
                fontFamily: fontFamily,
                fontScale: fontScale
            )
        case .structured(let document, let truncated):
            FileManagerStructuredPreview(
                document: document,
                truncated: truncated,
                theme: theme,
                fontFamily: fontFamily,
                fontScale: fontScale
            )
        case .message(let message):
            panelMessage(systemImage: "doc", text: message)
        case .failed(let message):
            panelMessage(systemImage: "exclamationmark.triangle", text: message)
        }
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
            symbolSize: 11,
            opacity: 0.72,
            disabled: disabled,
            action: action
        )
        .frame(width: 28, height: 28)
    }

    private func infoPill(_ title: String) -> some View {
        Text(title)
            .font(.conductorSystem(size: 10, weight: .semibold, family: fontFamily, scale: fontScale))
            .foregroundStyle(theme.shellChromeText.opacity(0.52))
            .lineLimit(1)
            .padding(.horizontal, 7)
            .frame(height: 19)
            .background(theme.floatingControlFill.opacity(0.56))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private func panelMessage(systemImage: String, text: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.conductorSystem(size: 22, weight: .medium, family: fontFamily, scale: fontScale))
                .foregroundStyle(theme.shellChromeText.opacity(0.30))
            Text(text)
                .font(.conductorSystem(size: 12, weight: .semibold, family: fontFamily, scale: fontScale))
                .foregroundStyle(theme.shellChromeText.opacity(0.52))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

private struct FileManagerSourcePreview: View {
    let document: FilePreviewTextDocument
    let truncated: Bool
    let theme: TerminalTheme
    let fontFamily: AppearanceFontFamily
    let fontScale: AppearanceFontScale

    var body: some View {
        VStack(spacing: 0) {
            sourceInfoBar
            if usesAppKitPreview {
                FileManagerSourcePreviewTextHost(
                    text: numberedText,
                    font: .conductorMonospacedSystemFont(ofSize: 12, scale: fontScale),
                    backgroundColor: NSColor(theme.terminalBackground),
                    textColor: NSColor(theme.shellChromeText.opacity(0.82)),
                    lineNumberColor: NSColor(theme.shellChromeText.opacity(0.28))
                )
                .background(theme.terminalBackground)
            } else {
                ScrollView([.vertical, .horizontal]) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(document.rows) { row in
                            SourcePreviewLine(
                                number: row.number,
                                text: row.text,
                                isHighlighted: false,
                                theme: theme
                            )
                        }
                    }
                    .padding(.vertical, 12)
                    .padding(.trailing, 18)
                }
                .scrollIndicators(.visible)
                .background(theme.terminalBackground)
            }
        }
    }

    private var usesAppKitPreview: Bool {
        document.displayedLineCount > Self.swiftUIRenderedLineLimit || truncated
    }

    private var numberedText: String {
        let width = max(3, String(document.lineCount).count)
        return document.rows
            .map { row in
                String(format: "%\(width)d  %@", row.number, row.text)
            }
            .joined(separator: "\n")
    }

    private var sourceInfoBar: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(document.formatLabel ?? L("文本预览", "Text Preview"))
                    .font(.conductorSystem(size: 12, weight: .bold, family: fontFamily, scale: fontScale))
                    .foregroundStyle(theme.shellChromeText.opacity(0.82))
                Text(sourceSubtitle)
                    .font(.conductorSystem(size: 10, weight: .semibold, family: fontFamily, scale: fontScale))
                    .foregroundStyle(theme.shellChromeText.opacity(0.45))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            infoPill(L("\(document.lineCount) 行", "\(document.lineCount) lines"))
            if document.isLineLimited { infoPill(L("前 \(document.displayedLineCount) 行", "First \(document.displayedLineCount) lines")) }
            if truncated { infoPill(L("前 256 KB", "First 256 KB")) }
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(theme.terminalChrome.opacity(theme.usesDarkChrome ? 0.46 : 0.26))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(theme.terminalOuterStroke.opacity(theme.usesDarkChrome ? 0.30 : 0.18))
                .frame(height: 1)
        }
    }

    private var sourceSubtitle: String {
        if truncated || document.isLineLimited {
            return L("轻量预览已限制读取和渲染范围，完整编辑请在工作区打开。", "Light preview is bounded; open in workspace for the full file.")
        }
        return L("轻量文本阅读器", "Lightweight text reader")
    }

    private func infoPill(_ title: String) -> some View {
        Text(title)
            .font(.conductorSystem(size: 10, weight: .semibold, family: fontFamily, scale: fontScale))
            .foregroundStyle(theme.shellChromeText.opacity(0.52))
            .lineLimit(1)
            .padding(.horizontal, 7)
            .frame(height: 19)
            .background(theme.floatingControlFill.opacity(theme.usesDarkChrome ? 0.46 : 0.34))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private static let swiftUIRenderedLineLimit = 180
}

private struct FileManagerSourcePreviewTextHost: NSViewRepresentable {
    let text: String
    let font: NSFont
    let backgroundColor: NSColor
    let textColor: NSColor
    let lineNumberColor: NSColor

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = FileManagerSourcePreviewScrollView()
        scrollView.drawsBackground = true
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.scrollerStyle = .overlay

        let textView = NSTextView(frame: scrollView.bounds)
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.usesFontPanel = false
        textView.allowsUndo = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: scrollView.contentSize.height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainerInset = NSSize(width: 16, height: 12)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        scrollView.documentView = textView
        context.coordinator.apply(text: text, to: textView)
        context.coordinator.applyConfiguration(
            to: textView,
            scrollView: scrollView,
            font: font,
            backgroundColor: backgroundColor,
            textColor: textColor,
            lineNumberColor: lineNumberColor
        )
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.applyConfiguration(
            to: textView,
            scrollView: scrollView,
            font: font,
            backgroundColor: backgroundColor,
            textColor: textColor,
            lineNumberColor: lineNumberColor
        )
        context.coordinator.apply(text: text, to: textView)
    }

    final class Coordinator {
        private var appliedText: String?
        private var appliedConfiguration: Configuration?

        @MainActor
        func apply(text: String, to textView: NSTextView) {
            guard text != appliedText else { return }
            appliedText = text
            textView.textStorage?.setAttributedString(attributedString(for: text))
        }

        @MainActor
        func applyConfiguration(
            to textView: NSTextView,
            scrollView: NSScrollView,
            font: NSFont,
            backgroundColor: NSColor,
            textColor: NSColor,
            lineNumberColor: NSColor
        ) {
            let configuration = Configuration(
                font: font,
                backgroundColor: backgroundColor,
                textColor: textColor,
                lineNumberColor: lineNumberColor
            )
            guard configuration != appliedConfiguration else { return }
            appliedConfiguration = configuration
            scrollView.backgroundColor = backgroundColor
            textView.backgroundColor = backgroundColor
            textView.font = font
            if let appliedText {
                textView.textStorage?.setAttributedString(attributedString(for: appliedText))
            }
        }

        private func attributedString(for text: String) -> NSAttributedString {
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineBreakMode = .byClipping
            let attributed = NSMutableAttributedString(
                string: text,
                attributes: [
                    .font: appliedConfiguration?.font ?? .monospacedSystemFont(ofSize: 12, weight: .regular),
                    .foregroundColor: appliedConfiguration?.textColor ?? NSColor.textColor,
                    .paragraphStyle: paragraphStyle
                ]
            )

            let lineNumberColor = appliedConfiguration?.lineNumberColor ?? NSColor.secondaryLabelColor
            let fullText = text as NSString
            var location = 0
            while location < fullText.length {
                let lineRange = fullText.lineRange(for: NSRange(location: location, length: 0))
                let line = fullText.substring(with: lineRange)
                let prefixLength = line.prefix { $0 == " " || $0.isNumber }.count
                let numberRange = NSRange(location: lineRange.location, length: min(prefixLength, lineRange.length))
                attributed.addAttribute(.foregroundColor, value: lineNumberColor, range: numberRange)
                location = NSMaxRange(lineRange)
            }
            return attributed
        }

        private struct Configuration: Equatable {
            let font: NSFont
            let backgroundColor: NSColor
            let textColor: NSColor
            let lineNumberColor: NSColor
        }
    }
}

private final class FileManagerSourcePreviewScrollView: NSScrollView {
    override var isFlipped: Bool { true }
}

private struct FileManagerTablePreview: View {
    let document: FilePreviewTableDocument
    let truncated: Bool
    let theme: TerminalTheme
    let fontFamily: AppearanceFontFamily
    let fontScale: AppearanceFontScale

    var body: some View {
        VStack(spacing: 0) {
            tableInfoBar
            if usesAppKitPreview {
                FileManagerTablePreviewHost(
                    document: document,
                    font: .conductorMonospacedSystemFont(ofSize: 11.5, scale: fontScale),
                    headerFont: .conductorMonospacedSystemFont(ofSize: 11.5, weight: .semibold, scale: fontScale),
                    lineNumberFont: .conductorMonospacedSystemFont(ofSize: 10.5, weight: .medium, scale: fontScale),
                    backgroundColor: NSColor(theme.terminalBackground),
                    textColor: NSColor(theme.shellChromeText.opacity(0.74)),
                    headerTextColor: NSColor(theme.shellChromeText.opacity(0.82)),
                    lineNumberTextColor: NSColor(theme.shellChromeText.opacity(0.34)),
                    lineNumberBackgroundColor: NSColor(theme.terminalChrome.opacity(theme.usesDarkChrome ? 0.30 : 0.18)),
                    headerBackgroundColor: NSColor(theme.floatingSelectedFill.opacity(theme.usesDarkChrome ? 0.24 : 0.18)),
                    evenCellBackgroundColor: NSColor(theme.floatingControlFill.opacity(theme.usesDarkChrome ? 0.08 : 0.12)),
                    oddCellBackgroundColor: NSColor.clear,
                    gridColor: NSColor(theme.terminalOuterStroke.opacity(theme.usesDarkChrome ? 0.22 : 0.16))
                )
                .background(theme.terminalBackground)
            } else {
                ScrollView([.vertical, .horizontal]) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(document.indexedRows) { row in
                            HStack(spacing: 0) {
                                Text("\(row.index + 1)")
                                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                                    .foregroundStyle(theme.shellChromeText.opacity(0.34))
                                    .frame(width: 38, height: 26, alignment: .trailing)
                                    .padding(.trailing, 8)
                                    .background(theme.terminalChrome.opacity(theme.usesDarkChrome ? 0.30 : 0.18))

                                ForEach(0..<document.columnCount, id: \.self) { columnIndex in
                                    Text(cell(row: row.values, columnIndex: columnIndex))
                                        .font(.system(size: 11.5, weight: row.index == 0 ? .semibold : .regular, design: .monospaced))
                                        .foregroundStyle(theme.shellChromeText.opacity(row.index == 0 ? 0.82 : 0.74))
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                        .padding(.horizontal, 8)
                                        .frame(width: Self.cellWidth, height: Self.rowHeight, alignment: .leading)
                                        .background(cellBackground(rowIndex: row.index, columnIndex: columnIndex))
                                        .overlay(alignment: .trailing) {
                                            Rectangle()
                                                .fill(theme.terminalOuterStroke.opacity(theme.usesDarkChrome ? 0.22 : 0.16))
                                                .frame(width: 1)
                                        }
                                        .contextMenu {
                                            Button(L("复制单元格", "Copy Cell")) {
                                                copyText(cell(row: row.values, columnIndex: columnIndex))
                                            }
                                            Button(L("复制行", "Copy Row")) {
                                                copyText(row.values.joined(separator: document.delimiterName == "TSV" ? "\t" : ","))
                                            }
                                        }
                                }
                            }
                            .overlay(alignment: .bottom) {
                                Rectangle()
                                    .fill(theme.terminalOuterStroke.opacity(theme.usesDarkChrome ? 0.20 : 0.14))
                                    .frame(height: 1)
                            }
                        }
                    }
                    .padding(.top, 10)
                    .padding(.bottom, 18)
                    .padding(.trailing, 18)
                }
                .background(theme.terminalBackground)
            }
        }
    }

    private var usesAppKitPreview: Bool {
        document.rows.count * max(document.columnCount, 1) > Self.swiftUICellLimit || truncated
    }

    private var tableInfoBar: some View {
        HStack(spacing: 7) {
            infoPill(document.delimiterName)
            infoPill(L("\(document.sourceLineCount) 行", "\(document.sourceLineCount) lines"))
            infoPill(L("\(document.columnCount) 列", "\(document.columnCount) columns"))
            infoPill(L("预览前 \(document.rows.count) 行", "Previewing \(document.rows.count) rows"))
            if truncated {
                infoPill(L("仅读取前 256 KB", "First 256 KB only"))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(height: 28)
        .background(theme.terminalChrome.opacity(theme.usesDarkChrome ? 0.72 : 0.64))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(theme.terminalOuterStroke.opacity(theme.usesDarkChrome ? 0.48 : 0.35))
                .frame(height: 1)
        }
    }

    private func cell(row: [String], columnIndex: Int) -> String {
        guard row.indices.contains(columnIndex) else { return "" }
        let value = row[columnIndex]
        guard value.count > 160 else { return value }
        return String(value.prefix(160)) + " ..."
    }

    private func cellBackground(rowIndex: Int, columnIndex: Int) -> Color {
        if rowIndex == 0 {
            return theme.floatingSelectedFill.opacity(theme.usesDarkChrome ? 0.24 : 0.18)
        }
        if columnIndex % 2 == 0 {
            return theme.floatingControlFill.opacity(theme.usesDarkChrome ? 0.08 : 0.12)
        }
        return Color.clear
    }

    private func copyText(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func infoPill(_ title: String) -> some View {
        Text(title)
            .font(.conductorSystem(size: 10, weight: .semibold, family: fontFamily, scale: fontScale))
            .foregroundStyle(theme.shellChromeText.opacity(0.52))
            .lineLimit(1)
            .padding(.horizontal, 7)
            .frame(height: 19)
            .background(theme.floatingControlFill.opacity(0.56))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private static let swiftUICellLimit = 600
    private static let rowHeight: CGFloat = 26
    private static let cellWidth: CGFloat = 156
}

private struct FileManagerTablePreviewHost: NSViewRepresentable {
    let document: FilePreviewTableDocument
    let font: NSFont
    let headerFont: NSFont
    let lineNumberFont: NSFont
    let backgroundColor: NSColor
    let textColor: NSColor
    let headerTextColor: NSColor
    let lineNumberTextColor: NSColor
    let lineNumberBackgroundColor: NSColor
    let headerBackgroundColor: NSColor
    let evenCellBackgroundColor: NSColor
    let oddCellBackgroundColor: NSColor
    let gridColor: NSColor

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = true
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.scrollerStyle = .overlay

        let tableView = NSTableView()
        tableView.headerView = nil
        tableView.rowHeight = Self.rowHeight
        tableView.intercellSpacing = .zero
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.selectionHighlightStyle = .none
        tableView.allowsColumnReordering = false
        tableView.allowsColumnResizing = true
        tableView.allowsMultipleSelection = false
        tableView.gridStyleMask = [.solidHorizontalGridLineMask, .solidVerticalGridLineMask]
        tableView.dataSource = context.coordinator
        tableView.delegate = context.coordinator

        let menu = NSMenu()
        menu.delegate = context.coordinator
        tableView.menu = menu

        scrollView.documentView = tableView
        context.coordinator.tableView = tableView
        context.coordinator.apply(document: document, configuration: configuration, to: tableView, scrollView: scrollView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let tableView = scrollView.documentView as? NSTableView else { return }
        context.coordinator.apply(document: document, configuration: configuration, to: tableView, scrollView: scrollView)
    }

    private var configuration: Coordinator.Configuration {
        Coordinator.Configuration(
            font: font,
            headerFont: headerFont,
            lineNumberFont: lineNumberFont,
            backgroundColor: backgroundColor,
            textColor: textColor,
            headerTextColor: headerTextColor,
            lineNumberTextColor: lineNumberTextColor,
            lineNumberBackgroundColor: lineNumberBackgroundColor,
            headerBackgroundColor: headerBackgroundColor,
            evenCellBackgroundColor: evenCellBackgroundColor,
            oddCellBackgroundColor: oddCellBackgroundColor,
            gridColor: gridColor
        )
    }

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate {
        struct Configuration: Equatable {
            let font: NSFont
            let headerFont: NSFont
            let lineNumberFont: NSFont
            let backgroundColor: NSColor
            let textColor: NSColor
            let headerTextColor: NSColor
            let lineNumberTextColor: NSColor
            let lineNumberBackgroundColor: NSColor
            let headerBackgroundColor: NSColor
            let evenCellBackgroundColor: NSColor
            let oddCellBackgroundColor: NSColor
            let gridColor: NSColor
        }

        weak var tableView: NSTableView?
        private var document = FilePreviewTableDocument(rows: [], delimiterName: "CSV", sourceLineCount: 0)
        private var appliedColumnCount = -1
        private var appliedConfiguration: Configuration?
        private var contextMenuTarget: (row: Int, column: Int)?

        @MainActor
        func apply(
            document: FilePreviewTableDocument,
            configuration: Configuration,
            to tableView: NSTableView,
            scrollView: NSScrollView
        ) {
            let columnsChanged = appliedColumnCount != document.columnCount
            let documentChanged = self.document != document
            let configurationChanged = appliedConfiguration != configuration

            self.document = document
            appliedConfiguration = configuration
            scrollView.backgroundColor = configuration.backgroundColor
            tableView.backgroundColor = configuration.backgroundColor
            tableView.gridColor = configuration.gridColor

            if columnsChanged {
                rebuildColumns(in: tableView, columnCount: document.columnCount)
                appliedColumnCount = document.columnCount
            }
            if columnsChanged || documentChanged || configurationChanged {
                tableView.reloadData()
            }
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            document.rows.count
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard row < document.rows.count,
                  let tableColumn,
                  let configuration = appliedConfiguration else {
                return nil
            }
            let identifier = tableColumn.identifier
            let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? FileManagerTableCellView ??
                FileManagerTableCellView(identifier: identifier)
            let isLineNumber = identifier.rawValue == Self.lineNumberIdentifier
            let columnIndex = columnIndex(for: identifier)
            let text: String
            if isLineNumber {
                text = "\(row + 1)"
            } else if let columnIndex {
                text = Self.cell(row: document.rows[row], columnIndex: columnIndex)
            } else {
                text = ""
            }
            cell.configure(
                text: text,
                alignment: isLineNumber ? .right : .left,
                font: isLineNumber ? configuration.lineNumberFont : (row == 0 ? configuration.headerFont : configuration.font),
                textColor: isLineNumber ? configuration.lineNumberTextColor : (row == 0 ? configuration.headerTextColor : configuration.textColor),
                backgroundColor: backgroundColor(row: row, columnIndex: columnIndex, isLineNumber: isLineNumber, configuration: configuration)
            )
            return cell
        }

        func menuNeedsUpdate(_ menu: NSMenu) {
            menu.removeAllItems()
            guard let tableView else { return }
            let row = tableView.clickedRow
            let column = tableView.clickedColumn
            guard row >= 0, row < document.rows.count, column >= 0 else { return }
            contextMenuTarget = (row, column)
            if column > 0 {
                let copyCell = NSMenuItem(title: L("复制单元格", "Copy Cell"), action: #selector(copyCell), keyEquivalent: "")
                copyCell.target = self
                menu.addItem(copyCell)
            }
            let copyRow = NSMenuItem(title: L("复制行", "Copy Row"), action: #selector(copyRow), keyEquivalent: "")
            copyRow.target = self
            menu.addItem(copyRow)
        }

        @objc private func copyCell() {
            guard let contextMenuTarget, contextMenuTarget.column > 0 else { return }
            copyText(Self.cell(row: document.rows[contextMenuTarget.row], columnIndex: contextMenuTarget.column - 1))
        }

        @objc private func copyRow() {
            guard let contextMenuTarget else { return }
            copyText(document.rows[contextMenuTarget.row].joined(separator: document.delimiterName == "TSV" ? "\t" : ","))
        }

        @MainActor
        private func rebuildColumns(in tableView: NSTableView, columnCount: Int) {
            for column in tableView.tableColumns {
                tableView.removeTableColumn(column)
            }
            let lineColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(Self.lineNumberIdentifier))
            lineColumn.width = 46
            lineColumn.minWidth = 40
            lineColumn.maxWidth = 62
            tableView.addTableColumn(lineColumn)

            for index in 0..<max(columnCount, 1) {
                let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("\(Self.columnPrefix)\(index)"))
                column.width = FileManagerTablePreviewHost.cellWidth
                column.minWidth = 92
                column.maxWidth = 420
                tableView.addTableColumn(column)
            }
        }

        private func backgroundColor(
            row: Int,
            columnIndex: Int?,
            isLineNumber: Bool,
            configuration: Configuration
        ) -> NSColor {
            if isLineNumber {
                return configuration.lineNumberBackgroundColor
            }
            if row == 0 {
                return configuration.headerBackgroundColor
            }
            guard let columnIndex else { return configuration.oddCellBackgroundColor }
            return columnIndex.isMultiple(of: 2) ? configuration.evenCellBackgroundColor : configuration.oddCellBackgroundColor
        }

        private func columnIndex(for identifier: NSUserInterfaceItemIdentifier) -> Int? {
            guard identifier.rawValue.hasPrefix(Self.columnPrefix) else { return nil }
            return Int(identifier.rawValue.dropFirst(Self.columnPrefix.count))
        }

        private func copyText(_ text: String) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }

        private static func cell(row: [String], columnIndex: Int) -> String {
            guard row.indices.contains(columnIndex) else { return "" }
            let value = row[columnIndex]
            guard value.count > 160 else { return value }
            return String(value.prefix(160)) + " ..."
        }

        private static let lineNumberIdentifier = "line"
        private static let columnPrefix = "column-"
    }

    private static let rowHeight: CGFloat = 26
    private static let cellWidth: CGFloat = 156
}

private final class FileManagerTableCellView: NSTableCellView {
    private let label = NSTextField(labelWithString: "")
    private var leadingConstraint: NSLayoutConstraint?
    private var trailingConstraint: NSLayoutConstraint?

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
        wantsLayer = true
        label.translatesAutoresizingMaskIntoConstraints = false
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.allowsExpansionToolTips = true
        addSubview(label)
        let leadingConstraint = label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8)
        let trailingConstraint = label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8)
        self.leadingConstraint = leadingConstraint
        self.trailingConstraint = trailingConstraint
        NSLayoutConstraint.activate([
            leadingConstraint,
            trailingConstraint,
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        return nil
    }

    func configure(
        text: String,
        alignment: NSTextAlignment,
        font: NSFont,
        textColor: NSColor,
        backgroundColor: NSColor,
        leadingInset: CGFloat = 8,
        trailingInset: CGFloat = 8
    ) {
        label.stringValue = text
        label.alignment = alignment
        label.font = font
        label.textColor = textColor
        leadingConstraint?.constant = leadingInset
        trailingConstraint?.constant = -trailingInset
        layer?.backgroundColor = backgroundColor.cgColor
    }
}

private struct FileManagerKeyValuePreviewHost: NSViewRepresentable {
    let document: FilePreviewKeyValueDocument
    let valueFont: NSFont
    let keyFont: NSFont
    let lineNumberFont: NSFont
    let backgroundColor: NSColor
    let valueTextColor: NSColor
    let keyTextColor: NSColor
    let lineNumberTextColor: NSColor
    let lineNumberBackgroundColor: NSColor
    let keyBackgroundColor: NSColor
    let evenValueBackgroundColor: NSColor
    let oddValueBackgroundColor: NSColor
    let gridColor: NSColor

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = true
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.scrollerStyle = .overlay

        let tableView = NSTableView()
        tableView.headerView = nil
        tableView.rowHeight = Self.rowHeight
        tableView.intercellSpacing = .zero
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.selectionHighlightStyle = .none
        tableView.allowsColumnReordering = false
        tableView.allowsColumnResizing = true
        tableView.allowsMultipleSelection = false
        tableView.gridStyleMask = [.solidHorizontalGridLineMask, .solidVerticalGridLineMask]
        tableView.dataSource = context.coordinator
        tableView.delegate = context.coordinator

        let menu = NSMenu()
        menu.delegate = context.coordinator
        tableView.menu = menu

        scrollView.documentView = tableView
        context.coordinator.tableView = tableView
        context.coordinator.apply(document: document, configuration: configuration, to: tableView, scrollView: scrollView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let tableView = scrollView.documentView as? NSTableView else { return }
        context.coordinator.apply(document: document, configuration: configuration, to: tableView, scrollView: scrollView)
    }

    private var configuration: Coordinator.Configuration {
        Coordinator.Configuration(
            valueFont: valueFont,
            keyFont: keyFont,
            lineNumberFont: lineNumberFont,
            backgroundColor: backgroundColor,
            valueTextColor: valueTextColor,
            keyTextColor: keyTextColor,
            lineNumberTextColor: lineNumberTextColor,
            lineNumberBackgroundColor: lineNumberBackgroundColor,
            keyBackgroundColor: keyBackgroundColor,
            evenValueBackgroundColor: evenValueBackgroundColor,
            oddValueBackgroundColor: oddValueBackgroundColor,
            gridColor: gridColor
        )
    }

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate {
        struct Configuration: Equatable {
            let valueFont: NSFont
            let keyFont: NSFont
            let lineNumberFont: NSFont
            let backgroundColor: NSColor
            let valueTextColor: NSColor
            let keyTextColor: NSColor
            let lineNumberTextColor: NSColor
            let lineNumberBackgroundColor: NSColor
            let keyBackgroundColor: NSColor
            let evenValueBackgroundColor: NSColor
            let oddValueBackgroundColor: NSColor
            let gridColor: NSColor
        }

        weak var tableView: NSTableView?
        private var document = FilePreviewKeyValueDocument(rows: [], formatLabel: "", sourceLineCount: 0)
        private var didBuildColumns = false
        private var appliedConfiguration: Configuration?
        private var contextMenuTargetRow: Int?

        @MainActor
        func apply(
            document: FilePreviewKeyValueDocument,
            configuration: Configuration,
            to tableView: NSTableView,
            scrollView: NSScrollView
        ) {
            let documentChanged = self.document != document
            let configurationChanged = appliedConfiguration != configuration

            self.document = document
            appliedConfiguration = configuration
            scrollView.backgroundColor = configuration.backgroundColor
            tableView.backgroundColor = configuration.backgroundColor
            tableView.gridColor = configuration.gridColor

            if !didBuildColumns {
                rebuildColumns(in: tableView)
                didBuildColumns = true
            }
            if documentChanged || configurationChanged {
                tableView.reloadData()
            }
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            document.rows.count
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard row < document.rows.count,
                  let tableColumn,
                  let configuration = appliedConfiguration else {
                return nil
            }
            let identifier = tableColumn.identifier
            let previewRow = document.rows[row]
            let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? FileManagerTableCellView ??
                FileManagerTableCellView(identifier: identifier)
            let text: String
            let font: NSFont
            let textColor: NSColor
            let backgroundColor: NSColor
            let alignment: NSTextAlignment
            switch identifier.rawValue {
            case Self.lineNumberIdentifier:
                text = "\(previewRow.index)"
                font = configuration.lineNumberFont
                textColor = configuration.lineNumberTextColor
                backgroundColor = configuration.lineNumberBackgroundColor
                alignment = .right
            case Self.keyIdentifier:
                text = previewRow.key
                font = configuration.keyFont
                textColor = configuration.keyTextColor
                backgroundColor = configuration.keyBackgroundColor
                alignment = .left
            default:
                text = Self.previewText(previewRow.value)
                font = configuration.valueFont
                textColor = configuration.valueTextColor
                backgroundColor = row.isMultiple(of: 2) ? configuration.evenValueBackgroundColor : configuration.oddValueBackgroundColor
                alignment = .left
            }
            cell.configure(
                text: text,
                alignment: alignment,
                font: font,
                textColor: textColor,
                backgroundColor: backgroundColor
            )
            return cell
        }

        func menuNeedsUpdate(_ menu: NSMenu) {
            menu.removeAllItems()
            guard let tableView else { return }
            let row = tableView.clickedRow
            guard row >= 0, row < document.rows.count else { return }
            contextMenuTargetRow = row

            let copyKey = NSMenuItem(title: L("复制 Key", "Copy Key"), action: #selector(copyKey), keyEquivalent: "")
            copyKey.target = self
            menu.addItem(copyKey)

            let copyValue = NSMenuItem(title: L("复制 Value", "Copy Value"), action: #selector(copyValue), keyEquivalent: "")
            copyValue.target = self
            menu.addItem(copyValue)

            let copyLine = NSMenuItem(title: L("复制整行", "Copy Line"), action: #selector(copyLine), keyEquivalent: "")
            copyLine.target = self
            menu.addItem(copyLine)
        }

        @objc private func copyKey() {
            guard let row = contextMenuTargetRow else { return }
            copyText(document.rows[row].key)
        }

        @objc private func copyValue() {
            guard let row = contextMenuTargetRow else { return }
            copyText(document.rows[row].value)
        }

        @objc private func copyLine() {
            guard let row = contextMenuTargetRow else { return }
            copyText(document.rows[row].raw)
        }

        @MainActor
        private func rebuildColumns(in tableView: NSTableView) {
            for column in tableView.tableColumns {
                tableView.removeTableColumn(column)
            }

            let lineColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(Self.lineNumberIdentifier))
            lineColumn.width = 46
            lineColumn.minWidth = 40
            lineColumn.maxWidth = 62
            tableView.addTableColumn(lineColumn)

            let keyColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(Self.keyIdentifier))
            keyColumn.width = 210
            keyColumn.minWidth = 120
            keyColumn.maxWidth = 360
            tableView.addTableColumn(keyColumn)

            let valueColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(Self.valueIdentifier))
            valueColumn.width = 360
            valueColumn.minWidth = 180
            valueColumn.maxWidth = 720
            tableView.addTableColumn(valueColumn)
        }

        private func copyText(_ text: String) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }

        private static func previewText(_ value: String) -> String {
            guard value.count > 240 else { return value }
            return String(value.prefix(240)) + " ..."
        }

        private static let lineNumberIdentifier = "line"
        private static let keyIdentifier = "key"
        private static let valueIdentifier = "value"
    }

    private static let rowHeight: CGFloat = 27
}

private struct FileManagerStructuredPreviewHost: NSViewRepresentable {
    let document: FilePreviewStructuredDocument
    let pathFont: NSFont
    let kindFont: NSFont
    let valueFont: NSFont
    let backgroundColor: NSColor
    let pathTextColor: NSColor
    let kindTextColor: NSColor
    let valueTextColor: NSColor
    let pathBackgroundColor: NSColor
    let evenValueBackgroundColor: NSColor
    let oddValueBackgroundColor: NSColor
    let gridColor: NSColor

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = true
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.scrollerStyle = .overlay

        let tableView = NSTableView()
        tableView.headerView = nil
        tableView.rowHeight = Self.rowHeight
        tableView.intercellSpacing = .zero
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.selectionHighlightStyle = .none
        tableView.allowsColumnReordering = false
        tableView.allowsColumnResizing = true
        tableView.allowsMultipleSelection = false
        tableView.gridStyleMask = [.solidHorizontalGridLineMask, .solidVerticalGridLineMask]
        tableView.dataSource = context.coordinator
        tableView.delegate = context.coordinator

        let menu = NSMenu()
        menu.delegate = context.coordinator
        tableView.menu = menu

        scrollView.documentView = tableView
        context.coordinator.tableView = tableView
        context.coordinator.apply(document: document, configuration: configuration, to: tableView, scrollView: scrollView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let tableView = scrollView.documentView as? NSTableView else { return }
        context.coordinator.apply(document: document, configuration: configuration, to: tableView, scrollView: scrollView)
    }

    private var configuration: Coordinator.Configuration {
        Coordinator.Configuration(
            pathFont: pathFont,
            kindFont: kindFont,
            valueFont: valueFont,
            backgroundColor: backgroundColor,
            pathTextColor: pathTextColor,
            kindTextColor: kindTextColor,
            valueTextColor: valueTextColor,
            pathBackgroundColor: pathBackgroundColor,
            evenValueBackgroundColor: evenValueBackgroundColor,
            oddValueBackgroundColor: oddValueBackgroundColor,
            gridColor: gridColor
        )
    }

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate {
        struct Configuration: Equatable {
            let pathFont: NSFont
            let kindFont: NSFont
            let valueFont: NSFont
            let backgroundColor: NSColor
            let pathTextColor: NSColor
            let kindTextColor: NSColor
            let valueTextColor: NSColor
            let pathBackgroundColor: NSColor
            let evenValueBackgroundColor: NSColor
            let oddValueBackgroundColor: NSColor
            let gridColor: NSColor
        }

        weak var tableView: NSTableView?
        private var document = FilePreviewStructuredDocument(rows: [], formatLabel: "", sourceLineCount: 0)
        private var didBuildColumns = false
        private var appliedConfiguration: Configuration?
        private var contextMenuTargetRow: Int?

        @MainActor
        func apply(
            document: FilePreviewStructuredDocument,
            configuration: Configuration,
            to tableView: NSTableView,
            scrollView: NSScrollView
        ) {
            let documentChanged = self.document != document
            let configurationChanged = appliedConfiguration != configuration

            self.document = document
            appliedConfiguration = configuration
            scrollView.backgroundColor = configuration.backgroundColor
            tableView.backgroundColor = configuration.backgroundColor
            tableView.gridColor = configuration.gridColor

            if !didBuildColumns {
                rebuildColumns(in: tableView)
                didBuildColumns = true
            }
            if documentChanged || configurationChanged {
                tableView.reloadData()
            }
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            document.rows.count
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard row < document.rows.count,
                  let tableColumn,
                  let configuration = appliedConfiguration else {
                return nil
            }
            let identifier = tableColumn.identifier
            let previewRow = document.rows[row]
            let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? FileManagerTableCellView ??
                FileManagerTableCellView(identifier: identifier)
            let text: String
            let font: NSFont
            let textColor: NSColor
            let backgroundColor: NSColor
            let leadingInset: CGFloat
            switch identifier.rawValue {
            case Self.pathIdentifier:
                text = previewRow.path
                font = configuration.pathFont
                textColor = configuration.pathTextColor
                backgroundColor = configuration.pathBackgroundColor
                leadingInset = 10 + CGFloat(min(previewRow.depth, 8)) * 16
            case Self.kindIdentifier:
                text = previewRow.kind
                font = configuration.kindFont
                textColor = configuration.kindTextColor
                backgroundColor = row.isMultiple(of: 2) ? configuration.evenValueBackgroundColor : configuration.oddValueBackgroundColor
                leadingInset = 8
            default:
                text = Self.previewText(previewRow.value.isEmpty ? " " : previewRow.value)
                font = configuration.valueFont
                textColor = configuration.valueTextColor
                backgroundColor = row.isMultiple(of: 2) ? configuration.evenValueBackgroundColor : configuration.oddValueBackgroundColor
                leadingInset = 8
            }
            cell.configure(
                text: text,
                alignment: .left,
                font: font,
                textColor: textColor,
                backgroundColor: backgroundColor,
                leadingInset: leadingInset
            )
            return cell
        }

        func menuNeedsUpdate(_ menu: NSMenu) {
            menu.removeAllItems()
            guard let tableView else { return }
            let row = tableView.clickedRow
            guard row >= 0, row < document.rows.count else { return }
            contextMenuTargetRow = row

            let copyPath = NSMenuItem(title: L("复制路径", "Copy Path"), action: #selector(copyPath), keyEquivalent: "")
            copyPath.target = self
            menu.addItem(copyPath)

            let copyKey = NSMenuItem(title: L("复制键", "Copy Key"), action: #selector(copyKey), keyEquivalent: "")
            copyKey.target = self
            menu.addItem(copyKey)

            let copyValue = NSMenuItem(title: L("复制值", "Copy Value"), action: #selector(copyValue), keyEquivalent: "")
            copyValue.target = self
            menu.addItem(copyValue)

            let copyPathAndValue = NSMenuItem(title: L("复制路径和值", "Copy Path and Value"), action: #selector(copyPathAndValue), keyEquivalent: "")
            copyPathAndValue.target = self
            menu.addItem(copyPathAndValue)
        }

        @objc private func copyPath() {
            guard let row = contextMenuTargetRow else { return }
            copyText(document.rows[row].path)
        }

        @objc private func copyKey() {
            guard let row = contextMenuTargetRow else { return }
            copyText(document.rows[row].key)
        }

        @objc private func copyValue() {
            guard let row = contextMenuTargetRow else { return }
            copyText(document.rows[row].value)
        }

        @objc private func copyPathAndValue() {
            guard let row = contextMenuTargetRow else { return }
            let previewRow = document.rows[row]
            copyText("\(previewRow.path) = \(previewRow.value)")
        }

        @MainActor
        private func rebuildColumns(in tableView: NSTableView) {
            for column in tableView.tableColumns {
                tableView.removeTableColumn(column)
            }

            let pathColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(Self.pathIdentifier))
            pathColumn.width = 300
            pathColumn.minWidth = 180
            pathColumn.maxWidth = 560
            tableView.addTableColumn(pathColumn)

            let kindColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(Self.kindIdentifier))
            kindColumn.width = 78
            kindColumn.minWidth = 64
            kindColumn.maxWidth = 120
            tableView.addTableColumn(kindColumn)

            let valueColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(Self.valueIdentifier))
            valueColumn.width = 420
            valueColumn.minWidth = 180
            valueColumn.maxWidth = 760
            tableView.addTableColumn(valueColumn)
        }

        private func copyText(_ text: String) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }

        private static func previewText(_ value: String) -> String {
            guard value.count > 260 else { return value }
            return String(value.prefix(260)) + " ..."
        }

        private static let pathIdentifier = "path"
        private static let kindIdentifier = "kind"
        private static let valueIdentifier = "value"
    }

    private static let rowHeight: CGFloat = 28
}

private struct FileManagerKeyValuePreview: View {
    let document: FilePreviewKeyValueDocument
    let truncated: Bool
    let theme: TerminalTheme
    let fontFamily: AppearanceFontFamily
    let fontScale: AppearanceFontScale

    var body: some View {
        VStack(spacing: 0) {
            infoBar
            if usesAppKitPreview {
                FileManagerKeyValuePreviewHost(
                    document: document,
                    valueFont: .conductorMonospacedSystemFont(ofSize: 11.5, scale: fontScale),
                    keyFont: .conductorMonospacedSystemFont(ofSize: 11.5, weight: .semibold, scale: fontScale),
                    lineNumberFont: .conductorMonospacedSystemFont(ofSize: 10.5, weight: .medium, scale: fontScale),
                    backgroundColor: NSColor(theme.terminalBackground),
                    valueTextColor: NSColor(theme.shellChromeText.opacity(0.72)),
                    keyTextColor: NSColor(theme.shellChromeText.opacity(0.82)),
                    lineNumberTextColor: NSColor(theme.shellChromeText.opacity(0.34)),
                    lineNumberBackgroundColor: NSColor(theme.terminalChrome.opacity(theme.usesDarkChrome ? 0.30 : 0.18)),
                    keyBackgroundColor: NSColor(theme.floatingSelectedFill.opacity(theme.usesDarkChrome ? 0.18 : 0.12)),
                    evenValueBackgroundColor: NSColor(theme.floatingControlFill.opacity(theme.usesDarkChrome ? 0.06 : 0.09)),
                    oddValueBackgroundColor: NSColor.clear,
                    gridColor: NSColor(theme.terminalOuterStroke.opacity(theme.usesDarkChrome ? 0.22 : 0.16))
                )
                .background(theme.terminalBackground)
            } else {
                ScrollView([.vertical, .horizontal]) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(document.rows) { row in
                            HStack(spacing: 0) {
                                Text("\(row.index)")
                                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                                    .foregroundStyle(theme.shellChromeText.opacity(0.34))
                                    .frame(width: 38, height: 27, alignment: .trailing)
                                    .padding(.trailing, 8)
                                    .background(theme.terminalChrome.opacity(theme.usesDarkChrome ? 0.30 : 0.18))

                                Text(row.key)
                                    .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(theme.shellChromeText.opacity(0.82))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .padding(.horizontal, 8)
                                    .frame(width: 210, height: 27, alignment: .leading)
                                    .background(theme.floatingSelectedFill.opacity(theme.usesDarkChrome ? 0.18 : 0.12))

                                Text(row.value)
                                    .font(.system(size: 11.5, weight: .regular, design: .monospaced))
                                    .foregroundStyle(theme.shellChromeText.opacity(0.72))
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    .padding(.horizontal, 8)
                                    .frame(width: 360, height: 27, alignment: .leading)
                            }
                            .contextMenu {
                                Button(L("复制 Key", "Copy Key")) {
                                    copyText(row.key)
                                }
                                Button(L("复制 Value", "Copy Value")) {
                                    copyText(row.value)
                                }
                                Button(L("复制整行", "Copy Line")) {
                                    copyText(row.raw)
                                }
                            }
                            .overlay(alignment: .bottom) {
                                Rectangle()
                                    .fill(theme.terminalOuterStroke.opacity(theme.usesDarkChrome ? 0.20 : 0.14))
                                    .frame(height: 1)
                            }
                        }
                    }
                    .padding(.top, 10)
                    .padding(.bottom, 18)
                    .padding(.trailing, 18)
                }
                .background(theme.terminalBackground)
            }
        }
    }

    private var usesAppKitPreview: Bool {
        document.rows.count > Self.swiftUIRowLimit || truncated
    }

    private var infoBar: some View {
        HStack(spacing: 7) {
            infoPill(document.formatLabel)
            infoPill(L("\(document.rows.count) 个键值", "\(document.rows.count) pairs"))
            infoPill(L("\(document.sourceLineCount) 行", "\(document.sourceLineCount) lines"))
            if truncated {
                infoPill(L("仅读取前 256 KB", "First 256 KB only"))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(height: 28)
        .background(theme.terminalChrome.opacity(theme.usesDarkChrome ? 0.72 : 0.64))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(theme.terminalOuterStroke.opacity(theme.usesDarkChrome ? 0.48 : 0.35))
                .frame(height: 1)
        }
    }

    private func infoPill(_ title: String) -> some View {
        Text(title)
            .font(.conductorSystem(size: 10, weight: .semibold, family: fontFamily, scale: fontScale))
            .foregroundStyle(theme.shellChromeText.opacity(0.52))
            .lineLimit(1)
            .padding(.horizontal, 7)
            .frame(height: 19)
            .background(theme.floatingControlFill.opacity(0.56))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private func copyText(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private static let swiftUIRowLimit = 160
}

private struct FileManagerStructuredPreview: View {
    let document: FilePreviewStructuredDocument
    let truncated: Bool
    let theme: TerminalTheme
    let fontFamily: AppearanceFontFamily
    let fontScale: AppearanceFontScale

    var body: some View {
        VStack(spacing: 0) {
            infoBar
            if usesAppKitPreview {
                FileManagerStructuredPreviewHost(
                    document: document,
                    pathFont: .conductorMonospacedSystemFont(ofSize: 11, weight: .medium, scale: fontScale),
                    kindFont: .conductorSystemFont(ofSize: 10.5, weight: .bold, scale: fontScale),
                    valueFont: .conductorMonospacedSystemFont(ofSize: 11.2, scale: fontScale),
                    backgroundColor: NSColor(theme.terminalBackground),
                    pathTextColor: NSColor(theme.shellChromeText.opacity(0.72)),
                    kindTextColor: NSColor(theme.shellChromeText.opacity(0.52)),
                    valueTextColor: NSColor(theme.shellChromeText.opacity(0.78)),
                    pathBackgroundColor: NSColor(theme.terminalChrome.opacity(theme.usesDarkChrome ? 0.26 : 0.16)),
                    evenValueBackgroundColor: NSColor(theme.floatingControlFill.opacity(theme.usesDarkChrome ? 0.06 : 0.09)),
                    oddValueBackgroundColor: NSColor.clear,
                    gridColor: NSColor(theme.terminalOuterStroke.opacity(theme.usesDarkChrome ? 0.22 : 0.16))
                )
                .background(theme.terminalBackground)
            } else {
                ScrollView([.vertical, .horizontal]) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(document.rows) { row in
                            HStack(spacing: 0) {
                                Text(row.path)
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .foregroundStyle(theme.shellChromeText.opacity(0.72))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .padding(.leading, 10 + CGFloat(min(row.depth, 8)) * 16)
                                    .padding(.trailing, 8)
                                    .frame(width: 300, height: 28, alignment: .leading)
                                    .background(theme.terminalChrome.opacity(theme.usesDarkChrome ? 0.26 : 0.16))

                                Text(row.kind)
                                    .font(.conductorSystem(size: 10.5, weight: .bold, family: fontFamily, scale: fontScale))
                                    .foregroundStyle(theme.shellChromeText.opacity(0.52))
                                    .lineLimit(1)
                                    .frame(width: 78, height: 28, alignment: .leading)

                                Text(row.value.isEmpty ? " " : row.value)
                                    .font(.system(size: 11.2, weight: .regular, design: .monospaced))
                                    .foregroundStyle(theme.shellChromeText.opacity(0.78))
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    .padding(.horizontal, 8)
                                    .frame(width: 420, height: 28, alignment: .leading)
                            }
                            .contextMenu {
                                Button(L("复制路径", "Copy Path")) {
                                    copyText(row.path)
                                }
                                Button(L("复制键", "Copy Key")) {
                                    copyText(row.key)
                                }
                                Button(L("复制值", "Copy Value")) {
                                    copyText(row.value)
                                }
                                Button(L("复制路径和值", "Copy Path and Value")) {
                                    copyText("\(row.path) = \(row.value)")
                                }
                            }
                            .overlay(alignment: .bottom) {
                                Rectangle()
                                    .fill(theme.terminalOuterStroke.opacity(theme.usesDarkChrome ? 0.20 : 0.14))
                                    .frame(height: 1)
                            }
                        }
                    }
                    .padding(.top, 10)
                    .padding(.bottom, 18)
                    .padding(.trailing, 18)
                }
                .background(theme.terminalBackground)
            }
        }
    }

    private var usesAppKitPreview: Bool {
        document.rows.count > Self.swiftUIRowLimit || truncated
    }

    private var infoBar: some View {
        HStack(spacing: 7) {
            infoPill(document.formatLabel)
            infoPill(L("\(document.rows.count) 个节点", "\(document.rows.count) nodes"))
            infoPill(L("\(document.sourceLineCount) 行", "\(document.sourceLineCount) lines"))
            if truncated {
                infoPill(L("仅读取前 256 KB", "First 256 KB only"))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(height: 28)
        .background(theme.terminalChrome.opacity(theme.usesDarkChrome ? 0.72 : 0.64))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(theme.terminalOuterStroke.opacity(theme.usesDarkChrome ? 0.48 : 0.35))
                .frame(height: 1)
        }
    }

    private func infoPill(_ title: String) -> some View {
        Text(title)
            .font(.conductorSystem(size: 10, weight: .semibold, family: fontFamily, scale: fontScale))
            .foregroundStyle(theme.shellChromeText.opacity(0.52))
            .lineLimit(1)
            .padding(.horizontal, 7)
            .frame(height: 19)
            .background(theme.floatingControlFill.opacity(0.56))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private func copyText(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private static let swiftUIRowLimit = 160
}

private struct SourcePreviewLine: View {
    let number: Int
    let text: String
    let isHighlighted: Bool
    let theme: TerminalTheme

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(number)")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(theme.shellChromeText.opacity(0.28))
                .frame(width: 42, alignment: .trailing)
                .textSelection(.disabled)

            Text(text.isEmpty ? " " : text)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundStyle(theme.shellChromeText.opacity(0.82))
                .lineLimit(1)
                .textSelection(.enabled)
        }
        .padding(.leading, 4)
        .padding(.trailing, 10)
        .frame(minWidth: 420, maxWidth: .infinity, minHeight: 22, alignment: .leading)
        .background {
            Rectangle()
                .fill(isHighlighted ? theme.floatingSelectedFill.opacity(0.30) : Color.clear)
        }
    }

}

private struct SourcePreviewMinimap: View {
    let lines: [String]
    let theme: TerminalTheme

    private var sampledLines: [String] {
        let maxLines = 220
        guard lines.count > maxLines else { return lines }
        let stride = max(1, lines.count / maxLines)
        return lines.enumerated().compactMap { index, line in
            index.isMultiple(of: stride) ? line : nil
        }
    }

    var body: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                let rows = sampledLines
                guard !rows.isEmpty else { return }
                let rowHeight = max(1.2, min(3.0, size.height / CGFloat(rows.count)))
                for (index, line) in rows.enumerated() {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    let opacity = trimmed.isEmpty ? 0.18 : 0.42
                    let maxWidth = size.width - 4
                    let widthRatio = min(1, max(0.12, CGFloat(trimmed.count) / 72.0))
                    let rect = CGRect(
                        x: 2,
                        y: CGFloat(index) * rowHeight,
                        width: maxWidth * widthRatio,
                        height: max(1, rowHeight * 0.48)
                    )
                    context.fill(Path(roundedRect: rect, cornerRadius: 0.8), with: .color(theme.shellChromeText.opacity(opacity)))
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .background(theme.floatingControlFill.opacity(theme.usesDarkChrome ? 0.20 : 0.28))
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(theme.terminalOuterStroke.opacity(0.35))
                    .frame(width: 1)
            }
        }
    }
}

private final class FileDropURLCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var urls: [URL] = []

    func append(_ url: URL) {
        lock.lock()
        urls.append(url)
        lock.unlock()
    }

    func snapshot() -> [URL] {
        lock.lock()
        let currentURLs = urls
        lock.unlock()
        return currentURLs
    }
}

private func collectDroppedFileURLs(from providers: [NSItemProvider], completion: @escaping ([URL]) -> Void) {
    let collector = FileDropURLCollector()
    let group = DispatchGroup()
    for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
        group.enter()
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            defer { group.leave() }
            let resolvedURL: URL?
            if let url = item as? URL {
                resolvedURL = url.standardizedFileURL
            } else if let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) {
                resolvedURL = url.standardizedFileURL
            } else if let string = item as? String,
                      let url = URL(string: string), url.isFileURL {
                resolvedURL = url.standardizedFileURL
            } else {
                resolvedURL = nil
            }
            if let resolvedURL {
                collector.append(resolvedURL)
            }
        }
    }
    group.notify(queue: .main) {
        completion(collector.snapshot())
    }
}

private struct FileManagerRowView: View {
    let item: FileManagerItem
    let depth: Int
    let isExpanded: Bool
    let isLoading: Bool
    let isSelected: Bool
    let selectedCount: Int
    let isRenaming: Bool
    let isPendingDelete: Bool
    @Binding var renamingName: String
    let renamingFocusToken: Int
    let open: () -> Void
    let openInWorkspace: () -> Void
    let openInSystemApp: () -> Void
    let copyPath: () -> Void
    let copyName: () -> Void
    let copyDirectoryPath: () -> Void
    let copyRelativePath: () -> Void
    let copyShellPath: () -> Void
    let copyFile: () -> Void
    let cutFile: () -> Void
    let paste: () -> Void
    let duplicate: () -> Void
    let showInfo: () -> Void
    let rename: () -> Void
    let commitRename: () -> Void
    let cancelRename: () -> Void
    let delete: () -> Void
    let canPaste: Bool
    let insertPath: () -> Void
    let insertCDCommand: () -> Void
    let insertListCommand: () -> Void
    let reveal: () -> Void
    let dropFiles: ([URL], Bool) -> Void
    @Environment(\.conductorTheme) private var theme
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorFontFamily) private var fontFamily
    @State private var isDropTargeted = false

    var body: some View {
        rowContent
            .contentShape(Rectangle())
            .onTapGesture {
                if !isRenaming {
                    open()
                }
            }
            .contextMenu {
                if item.isDirectory {
                    Button(isExpanded ? L("收起文件夹", "Collapse Folder") : L("展开文件夹", "Expand Folder"), action: open)
                } else {
                    Button(L("打开", "Open"), action: open)
                }
                Menu(L("打开方式", "Open With")) {
                    Button(L("工作区标签", "Workspace Tab"), action: openInWorkspace)
                        .disabled(item.isDirectory)
                    Button(L("系统应用", "System App"), action: openInSystemApp)
                    Button(L("在 Finder 中显示", "Reveal in Finder"), action: reveal)
                }
                Menu(L("终端", "Terminal")) {
                    Button(L("插入路径", "Insert Path"), action: insertPath)
                    Button(L("插入 cd 命令", "Insert cd Command"), action: insertCDCommand)
                    Button(L("插入 ls 命令", "Insert ls Command"), action: insertListCommand)
                }
                Menu(L("复制为", "Copy As")) {
                    Button(L("文件名", "Name"), action: copyName)
                    Button(L("相对路径", "Relative Path"), action: copyRelativePath)
                    Button(L("绝对路径", "Absolute Path"), action: copyPath)
                    Button(L("所在目录", "Parent Directory"), action: copyDirectoryPath)
                    Button(L("Shell 转义路径", "Shell Escaped Path"), action: copyShellPath)
                    Button(L("终端可粘贴路径", "Terminal-ready Path"), action: copyShellPath)
                }
                Divider()
                Button(selectedCount > 1 ? L("复制 \(selectedCount) 项", "Copy \(selectedCount) Items") : L("复制", "Copy"), action: copyFile)
                Button(selectedCount > 1 ? L("剪切 \(selectedCount) 项", "Cut \(selectedCount) Items") : L("剪切", "Cut"), action: cutFile)
                Button(L("粘贴", "Paste"), action: paste)
                    .disabled(!canPaste)
                Button(L("复制副本", "Duplicate"), action: duplicate)
                Button(L("显示信息", "Get Info"), action: showInfo)
                Button(L("重命名...", "Rename..."), action: rename)
                Button(L("在 Finder 中显示", "Reveal in Finder"), action: reveal)
                Divider()
                Button(role: .destructive, action: delete) {
                    Text(selectedCount > 1 ? L("移到废纸篓 \(selectedCount) 项", "Move \(selectedCount) Items to Trash") : L("移到废纸篓", "Move to Trash"))
                }
            }
            .onDrag {
                NSItemProvider(object: item.url.standardizedFileURL as NSURL)
            }
            .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isDropTargeted) { providers in
                guard item.isDirectory else { return false }
                let move = NSApp.currentEvent?.modifierFlags.contains(.option) != true
                collectDroppedFileURLs(from: providers) { urls in
                    guard !urls.isEmpty else { return }
                    dropFiles(urls, move)
                }
                return true
            }
    }

    private var rowContent: some View {
        HStack(spacing: 8) {
            if item.isDirectory {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.conductorSystem(size: 8.5, weight: .bold, family: fontFamily, scale: fontScale))
                    .foregroundStyle(rowIconSecondaryColor)
                    .frame(width: 12)
            } else {
                Spacer()
                    .frame(width: 12)
            }

            Image(systemName: item.isDirectory ? (isExpanded ? "folder.fill" : "folder") : iconName)
                .font(.conductorSystem(size: 12.5, weight: .semibold, family: fontFamily, scale: fontScale))
                .foregroundStyle(rowIconColor)
                .frame(width: 18)

            nameView

            Spacer(minLength: 8)

            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.58)
                    .frame(width: 16, height: 16)
            }

            if !isRenaming {
                Text(item.rowDetail)
                    .font(.conductorSystem(size: 10.2, weight: .semibold, family: fontFamily, scale: fontScale))
                    .foregroundStyle(theme.shellChromeText.opacity(isSelected ? 0.56 : 0.34))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 150, alignment: .trailing)
            }

            if item.isSymbolicLink {
                statusBadge(
                    systemImage: "arrowshape.turn.up.right",
                    help: L("符号链接", "Symbolic Link")
                )
            }

            if item.isReadable == false {
                statusBadge(
                    systemImage: "lock.slash",
                    help: L("没有读取权限", "No Read Permission")
                )
            } else if item.isWritable == false {
                statusBadge(
                    systemImage: "lock",
                    help: L("只读", "Read-only")
                )
            }

            if item.isLargeEditableFile {
                statusBadge(
                    systemImage: "exclamationmark.triangle",
                    help: L("超过 20 MB，将以保护模式打开", "Over 20 MB; opens in protected mode")
                )
            } else if item.isUnsupportedBinaryLikeFile {
                statusBadge(
                    systemImage: "nosign",
                    help: L("二进制或暂不支持内联预览", "Binary or unsupported inline preview")
                )
            }
        }
        .opacity(isPendingDelete ? 0.50 : 1)
        .padding(.leading, 10 + CGFloat(min(depth, 8)) * 18)
        .padding(.trailing, 10)
        .frame(height: 31)
        .background {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(backgroundColor)
        }
    }

    @ViewBuilder
    private var nameView: some View {
        if isRenaming {
            RenameTextField(
                text: $renamingName,
                placeholder: item.name,
                font: .systemFont(ofSize: 12, weight: .semibold),
                textColor: .labelColor
            ) {
                commitRename()
            } onCancel: {
                cancelRename()
            }
            .id(renamingFocusToken)
            .frame(minWidth: 90, maxWidth: .infinity, alignment: .leading)
        } else {
            Text(item.name)
                .font(.conductorSystem(size: 12.2, weight: item.isDirectory ? .semibold : .medium, family: fontFamily, scale: fontScale))
                .foregroundStyle(rowTextColor)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private var iconName: String {
        switch item.url.pathExtension.lowercased() {
        case "swift", "js", "jsx", "ts", "tsx", "rb", "py", "sh", "zsh", "bash":
            "curlybraces"
        case "json", "jsonl", "toml", "yaml", "yml", "xml":
            "doc.text"
        case "md", "txt", "log":
            "doc.plaintext"
        case "png", "jpg", "jpeg", "gif", "webp", "heic", "tiff":
            "photo"
        default:
            "doc"
        }
    }

    private func statusBadge(systemImage: String, help: String) -> some View {
        Image(systemName: systemImage)
            .font(.conductorSystem(size: 9.5, weight: .semibold, family: fontFamily, scale: fontScale))
            .foregroundStyle(theme.shellChromeText.opacity(0.42))
            .frame(width: 14, height: 16)
            .macNativeTooltip(help)
    }

    private var rowIconColor: Color {
        if item.isDirectory {
            return theme.floatingEmphasis.opacity(isSelected ? 1.0 : 0.88)
        }
        return theme.shellChromeText.opacity(isSelected ? 0.78 : 0.50)
    }

    private var rowIconSecondaryColor: Color {
        theme.shellChromeText.opacity(isSelected ? 0.70 : 0.34)
    }

    private var rowTextColor: Color {
        theme.shellChromeText.opacity(isSelected ? 0.94 : 0.78)
    }

    private var backgroundColor: Color {
        if isPendingDelete {
            return Color.red.opacity(isSelected ? 0.22 : 0.12)
        }
        if isDropTargeted {
            return theme.floatingSelectedFill.opacity(theme.usesDarkChrome ? 0.62 : 0.68)
        }
        if isSelected {
            return theme.floatingSelectedFill.opacity(theme.usesDarkChrome ? 0.48 : 0.54)
        }
        return Color.clear
    }

}

private struct FileManagerPanelIconButton: View {
    let systemImage: String
    let help: String
    let size: CGFloat
    let symbolSize: CGFloat
    let opacity: CGFloat
    let disabled: Bool
    let action: () -> Void

    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorFontFamily) private var fontFamily
    @Environment(\.conductorTheme) private var theme

    var body: some View {
        Button {
            guard !disabled else { return }
            action()
        } label: {
            Image(systemName: systemImage)
                .font(.conductorSystem(size: symbolSize, weight: .semibold, family: fontFamily, scale: fontScale))
                .foregroundStyle(theme.shellChromeText.opacity(disabled ? 0.26 : opacity))
                .frame(width: size, height: size)
                .contentShape(Rectangle())
                .accessibilityLabel(Text(help))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .macNativeTooltip(help)
    }
}
