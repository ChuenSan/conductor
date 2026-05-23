import AppKit
import Foundation
import UniformTypeIdentifiers

func fileManagerL(_ zh: String, _ en: String) -> String {
    ConductorLocalization.text(zh: zh, en: en)
}

struct FileManagerItem: Equatable, Identifiable, Sendable {
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

struct FileManagerVisibleRow: Equatable, Identifiable {
    var id: String { item.id }
    let item: FileManagerItem
    let depth: Int
    let index: Int

    init(item: FileManagerItem, depth: Int, index: Int = 0) {
        self.item = item
        self.depth = depth
        self.index = index
    }
}

struct FileManagerRenameResult: Equatable, Sendable {
    let oldPath: String
    let newURL: URL
    let isDirectory: Bool
}

struct FileManagerTrashRecord: Equatable, Sendable {
    let originalURL: URL
    let trashURL: URL?
    let isDirectory: Bool
}

enum FileManagerSelectionMode {
    case primary
    case toggle
    case range
}

struct FilePreviewTextDocument: Equatable, Sendable {
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

struct FilePreviewTableDocument: Equatable, Sendable {
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

struct FilePreviewKeyValueDocument: Equatable, Sendable {
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

struct FilePreviewStructuredDocument: Equatable, Sendable {
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

enum FilePreviewState: Equatable, Sendable {
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

enum FileManagerOpenMode {
    case workspaceEditor
    case systemApplication
}

enum FileManagerSortMode: String, CaseIterable, Identifiable {
    case name
    case modified
    case size
    case type

    var id: String { rawValue }

    var title: String {
        switch self {
        case .name:
            fileManagerL("名称", "Name")
        case .modified:
            fileManagerL("修改时间", "Modified")
        case .size:
            fileManagerL("大小", "Size")
        case .type:
            fileManagerL("类型", "Type")
        }
    }
}

enum FileManagerKindFilter: String, CaseIterable, Identifiable {
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
            fileManagerL("全部", "All")
        case .folders:
            fileManagerL("文件夹", "Folders")
        case .documents:
            fileManagerL("文档", "Docs")
        case .code:
            fileManagerL("代码", "Code")
        case .data:
            fileManagerL("数据", "Data")
        case .images:
            fileManagerL("图片", "Images")
        case .other:
            fileManagerL("其他", "Other")
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

enum FileManagerPasteboard {
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

struct FileManagerService {
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
        if isDirectory { return fileManagerL("文件夹", "Folder") }
        guard let byteCount else { return fileManagerL("文件", "File") }
        return ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
    }

    private static func typeLabel(for url: URL, isDirectory: Bool) -> String {
        if isDirectory { return fileManagerL("文件夹", "Folder") }
        let ext = url.pathExtension.lowercased()
        return ext.isEmpty ? fileManagerL("文件", "File") : ext.uppercased()
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
            parts.append(fileManagerL("文件夹", "Folder"))
        } else if let byteCount {
            parts.append(ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file))
        } else {
            let ext = url.pathExtension.lowercased()
            parts.append(ext.isEmpty ? fileManagerL("文件", "File") : ext.uppercased())
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
                NSLocalizedDescriptionKey: fileManagerL("无法创建文件", "Could not create file")
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
            return .failed(fileManagerL("无法读取这个项目", "Could not read this item"))
        }

        if values.isDirectory == true {
            return .directory(fileManagerL("双击进入文件夹，或使用上方按钮返回上级。", "Double-click to enter this folder, or use the button above to go up."))
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
            return .message(fileManagerL("这个文件类型暂不支持内联预览", "This file type cannot be previewed inline yet"))
        }

        let size = values.fileSize ?? 0
        let readLimit = min(max(size, 0), Self.maxInlineTextBytes)
        do {
            let handle = try FileHandle(forReadingFrom: fileURL)
            defer { try? handle.close() }
            let data = try handle.read(upToCount: readLimit) ?? Data()
            if data.contains(0) {
                return .message(fileManagerL("二进制文件暂不支持内联预览", "Binary files cannot be previewed inline"))
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
                NSLocalizedDescriptionKey: fileManagerL("请输入有效文件名", "Enter a valid file name")
            ])
        }
        let source = sourceURL.standardizedFileURL
        let destination = source.deletingLastPathComponent().appendingPathComponent(trimmed)
        guard source.path != destination.standardizedFileURL.path else { return source }
        guard !fileManager.fileExists(atPath: destination.path) else {
            throw NSError(domain: "ConductorFileManager", code: 409, userInfo: [
                NSLocalizedDescriptionKey: fileManagerL("同名项目已存在", "An item with that name already exists")
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
                NSLocalizedDescriptionKey: fileManagerL("目标不是文件夹", "The target is not a folder")
            ])
        }

        var destinations: [URL] = []
        for sourceURL in sourceURLs.map(\.standardizedFileURL) {
            guard fileManager.fileExists(atPath: sourceURL.path) else { continue }
            if move, sourceURL.path == directory.path { continue }
            if move, isDirectory(sourceURL), directory.path.hasPrefix(sourceURL.path + "/") {
                throw NSError(domain: "ConductorFileManager", code: 409, userInfo: [
                    NSLocalizedDescriptionKey: fileManagerL("不能把文件夹移动到它自己里面", "A folder cannot be moved into itself")
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
                NSLocalizedDescriptionKey: fileManagerL("废纸篓中的项目已经不存在，无法撤销", "The trashed item no longer exists, so undo is unavailable")
            ])
        }
        guard !fileManager.fileExists(atPath: record.originalURL.path) else {
            throw NSError(domain: "ConductorFileManager", code: 409, userInfo: [
                NSLocalizedDescriptionKey: fileManagerL("原位置已经有同名项目，无法撤销", "The original location already contains an item with the same name")
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
                return FilePreviewTextDocument(text: text, formatLabel: fileManagerL("JSON", "JSON"))
            }
            return FilePreviewTextDocument(text: prettyText, formatLabel: fileManagerL("JSON 格式化", "Formatted JSON"))
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
                        key: fileManagerL("解析错误", "Parse Error"),
                        kind: fileManagerL("错误", "Error"),
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
                        kind: fileManagerL("错误", "Error"),
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
                kind = fileManagerL("对象", "Object")
                displayValue = fileManagerL("\(dictionary.count) 个键", "\(dictionary.count) keys")
                rows.append(.init(id: path, path: path, key: key, kind: kind, value: displayValue, depth: depth))
                for childKey in dictionary.keys.sorted() {
                    guard let child = dictionary[childKey] else { continue }
                    append(child, key: childKey, path: "\(path).\(childKey)", depth: depth + 1)
                }
            } else if let array = value as? [Any] {
                kind = fileManagerL("数组", "Array")
                displayValue = fileManagerL("\(array.count) 项", "\(array.count) items")
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
            key: fileManagerL("已截断", "Truncated"),
            kind: fileManagerL("提示", "Notice"),
            value: fileManagerL("结构节点较多，只显示前 \(limit) 项", "Large structure; showing the first \(limit) nodes"),
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
            let kind = value.isEmpty ? fileManagerL("节点", "Node") : fileManagerL("值", "Value")
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
                rows.append(.init(id: "toml-section-\(lineIndex)", path: section.joined(separator: "."), key: name, kind: fileManagerL("节", "Section"), value: "", depth: max(0, section.count - 1)))
                continue
            }
            guard let separator = trimmed.firstIndex(of: "=") else { continue }
            let key = String(trimmed[..<separator]).trimmingCharacters(in: .whitespaces)
            let value = String(trimmed[trimmed.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
            let path = (section + [key]).joined(separator: ".")
            rows.append(.init(id: "toml-\(lineIndex)", path: path, key: key, kind: fileManagerL("值", "Value"), value: value, depth: section.count))
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
