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

    var subtitle: String {
        if isDirectory { return L("文件夹", "Folder") }
        guard let byteCount else { return L("文件", "File") }
        return ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
    }

    var typeLabel: String {
        if isDirectory { return L("文件夹", "Folder") }
        let ext = url.pathExtension.lowercased()
        return ext.isEmpty ? L("文件", "File") : ext.uppercased()
    }
}

private struct FileManagerVisibleRow: Equatable, Identifiable {
    var id: String { item.id }
    let item: FileManagerItem
    let depth: Int
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
    let lines: [String]
    let lineCount: Int
    let displayedLineCount: Int
    let formatLabel: String?

    init(text: String, formatLabel: String? = nil) {
        let splitLines = text.components(separatedBy: .newlines)
        self.lines = Array(splitLines.prefix(Self.maxRenderedLines))
        self.lineCount = max(1, splitLines.count)
        self.displayedLineCount = self.lines.count
        self.formatLabel = formatLabel
    }

    var isLineLimited: Bool {
        displayedLineCount < lineCount
    }

    private static let maxRenderedLines = 800
}

private struct FilePreviewTableDocument: Equatable, Sendable {
    let rows: [[String]]
    let delimiterName: String
    let sourceLineCount: Int

    var columnCount: Int {
        rows.map(\.count).max() ?? 0
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

        return urls.compactMap { childURL in
            guard let values = try? childURL.resourceValues(forKeys: keys) else { return nil }
            let isDirectory = values.isDirectory == true && values.isPackage != true
            return FileManagerItem(
                url: childURL.standardizedFileURL,
                name: values.name ?? childURL.lastPathComponent,
                isDirectory: isDirectory,
                isSymbolicLink: values.isSymbolicLink == true,
                byteCount: values.fileSize.map(Int64.init),
                modificationDate: values.contentModificationDate,
                creationDate: values.creationDate,
                isReadable: values.isReadable ?? true,
                isWritable: values.isWritable ?? true,
                contentTypeIdentifier: values.contentType?.identifier
            )
        }
        .filter { includeHidden || !$0.name.hasPrefix(".") }
        .filter { $0.name != ".DS_Store" }
        .sorted { Self.sort($0, before: $1, mode: sortMode) }
    }

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
        if let descriptor = Self.nativePreviewDescriptor(for: fileURL, type: type) {
            return .nativePreview(fileURL, descriptor)
        }
        if type?.conforms(to: .image) == true {
            return .image(fileURL)
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
        "adoc", "bash", "c", "cc", "cfg", "conf", "cpp", "css", "csv", "diff", "env", "err", "go", "h", "hpp", "htm",
        "html", "java", "js", "json", "jsonl", "jsx", "log", "m", "md", "mm", "out", "patch", "php",
        "plist", "properties", "py", "rb", "rs", "rst", "scss", "sh", "stderr", "stdout", "swift", "tab", "toml",
        "trace", "ts", "tsv", "tsx", "txt", "xml", "yaml", "yml", "zsh"
    ]

    private static let systemApplicationExtensions: Set<String> = [
        "apng", "avif", "bmp", "gif", "heic", "heif", "ico", "jpeg", "jpg", "png", "psd", "svg", "tif", "tiff", "webp",
        "3g2", "3gp", "avi", "m4v", "mkv", "mov", "mp4", "mpeg", "mpg", "webm", "wmv",
        "aac", "aiff", "flac", "m4a", "mp3", "ogg", "wav",
        "doc", "docx", "key", "numbers", "pages", "pdf", "ppt", "pptx", "xls", "xlsx"
    ]
}

@MainActor
private final class FileManagerPanelStore: ObservableObject {
    @Published private(set) var currentURL: URL?
    @Published private(set) var items: [FileManagerItem] = []
    @Published private(set) var expandedDirectoryPaths: Set<String> = []
    @Published private(set) var childItemsByDirectoryPath: [String: [FileManagerItem]] = [:]
    @Published private(set) var loadingDirectoryPaths: Set<String> = []
    @Published private(set) var directoryErrorsByPath: [String: String] = [:]
    @Published private(set) var selectedItem: FileManagerItem?
    @Published private(set) var selectedPaths: Set<String> = []
    @Published private(set) var previewState = FilePreviewState.empty
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var operationMessage: String?
    @Published private(set) var pendingDeletePaths: Set<String> = []
    @Published var renamingPath: String?
    @Published var renamingName = ""
    @Published var searchQuery = ""
    @Published private(set) var searchHistory: [String] = []
    @Published var includeHiddenFiles = false
    @Published var sortMode: FileManagerSortMode = .name
    @Published private(set) var recentFileURLs: [URL] = []
    @Published private(set) var favoriteDirectoryURLs: [URL] = []
    @Published private(set) var renamingFocusToken = 0
    @Published private(set) var lastTrashRecords: [FileManagerTrashRecord] = []

    private let service = FileManagerService()
    private var requestID: UUID?
    private var loadGeneration = 0
    private var previewGeneration = 0
    private var selectionAnchorPath: String?

    var visibleRows: [FileManagerVisibleRow] {
        visibleRows(for: items, depth: 0)
    }

    var displayedRows: [FileManagerVisibleRow] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return visibleRows }
        return knownRows(for: items, depth: 0).filter { row in
            row.item.name.localizedCaseInsensitiveContains(query) ||
                row.item.url.path.localizedCaseInsensitiveContains(query)
        }
    }

    func load(_ request: FileManagerPanelRequest) async {
        guard requestID != request.id else { return }
        requestID = request.id
        loadLocalLists()
        searchHistory = ConductorSearchHistory.load(scope: Self.searchHistoryScope)
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
        displayedRows.map(\.item).filter { selectedPaths.contains($0.url.path) }
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
        ConductorSearchHistory.record(searchQuery, scope: Self.searchHistoryScope)
        searchHistory = ConductorSearchHistory.load(scope: Self.searchHistoryScope)
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

    private func visibleRows(for items: [FileManagerItem], depth: Int) -> [FileManagerVisibleRow] {
        items.flatMap { item -> [FileManagerVisibleRow] in
            var rows = [FileManagerVisibleRow(item: item, depth: depth)]
            if item.isDirectory,
               expandedDirectoryPaths.contains(item.url.path),
               let children = childItemsByDirectoryPath[item.url.path] {
                rows.append(contentsOf: visibleRows(for: children, depth: depth + 1))
            }
            return rows
        }
    }

    private func knownRows(for items: [FileManagerItem], depth: Int) -> [FileManagerVisibleRow] {
        items.flatMap { item -> [FileManagerVisibleRow] in
            var rows = [FileManagerVisibleRow(item: item, depth: depth)]
            if item.isDirectory, let children = childItemsByDirectoryPath[item.url.path] {
                rows.append(contentsOf: knownRows(for: children, depth: depth + 1))
            }
            return rows
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
    @ObservedObject var model: ConductorWindowModel
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
        VStack(spacing: 0) {
            header
            divider
            if searchVisible || !store.searchQuery.isEmpty {
                fileTreeSearchBar
                divider
            }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            if newValue != nil {
                keyboardFocused = false
            }
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

                panelIconButton("arrow.up", help: L("上级目录", "Parent Directory")) {
                    Task { await store.goUp() }
                }
                .disabled(store.currentURL == nil)

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
    private var content: some View {
        browser
    }

    private var fileTreeSearchBar: some View {
        HStack {
            ConductorContextSearchSurface {
            Image(systemName: "magnifyingglass")
                .font(.conductorSystem(size: 11, weight: .semibold, family: fontFamily, scale: fontScale))
                .foregroundStyle(theme.shellChromeText.opacity(0.58))

                ConductorContextSearchScopeChip(systemImage: "folder", title: L("文件树", "Files"))

                if !store.searchHistory.isEmpty {
                    Menu {
                        ForEach(store.searchHistory, id: \.self) { query in
                            Button(query) {
                                store.reuseSearchQuery(query)
                            }
                        }
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.conductorSystem(size: 10.5, weight: .semibold, family: fontFamily, scale: fontScale))
                            .foregroundStyle(theme.shellChromeText.opacity(0.56))
                            .frame(width: 22, height: 22)
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    .macNativeTooltip(L("搜索历史", "Search History"))
                }

                ConductorContextSearchTextField(
                    text: $store.searchQuery,
                    placeholder: L("过滤文件", "Filter files"),
                    focusToken: searchFocusToken,
                    theme: theme,
                    fontFamily: fontFamily,
                    fontScale: fontScale,
                    onNavigate: { previous in
                        store.recordSearchQuery()
                        store.selectAdjacentRow(by: previous ? -1 : 1)
                    },
                    onClose: closeSearch
                )
                .frame(width: 168, height: 22)

                Text("\(store.displayedRows.count)")
                    .font(.conductorSystem(size: 10, weight: .semibold, family: fontFamily, scale: fontScale))
                    .foregroundStyle(theme.shellChromeText.opacity(0.52))
                    .monospacedDigit()
                    .frame(minWidth: 48, alignment: .trailing)

                ConductorContextSearchIconButton(
                    systemImage: "chevron.up",
                    help: L("上一个文件", "Previous File"),
                    disabled: store.displayedRows.isEmpty
                ) {
                    store.selectAdjacentRow(by: -1)
                }

                ConductorContextSearchIconButton(
                    systemImage: "chevron.down",
                    help: L("下一个文件", "Next File"),
                    disabled: store.displayedRows.isEmpty
                ) {
                    store.selectAdjacentRow(by: 1)
                }

                ConductorContextSearchIconButton(systemImage: "xmark", help: L("关闭搜索", "Close Search")) {
                    closeSearch()
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(theme.terminalChrome.opacity(theme.usesDarkChrome ? 0.18 : 0.06))
    }

    private var browser: some View {
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
                        ForEach(store.displayedRows) { row in
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
                .macNativeTooltip(L("恢复刚移到废纸篓的项目", "Restore the items just moved to Trash"))
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
        switch FileManagerService().openMode(for: item.url) {
        case .workspaceEditor:
            store.recordOpenedFile(item.url)
            model.openFileInWorkspace(item.url, rootURL: store.currentURL ?? request.rootURL)
            keyboardFocused = false
        case .systemApplication:
            NSWorkspace.shared.open(item.url)
        }
    }

    private func openURL(_ url: URL) {
        let standardized = url.standardizedFileURL
        guard FileManager.default.fileExists(atPath: standardized.path) else {
            return
        }
        store.recordOpenedFile(standardized)
        model.openFileInWorkspace(standardized, rootURL: standardized.deletingLastPathComponent())
        keyboardFocused = false
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

            panelIconButton("terminal", help: L("插入路径到终端", "Insert Path into Terminal")) {
                _ = model.insertPathIntoFocusedTerminal(item.url)
            }
            .disabled(model.focusedTerminalID == nil)

            panelIconButton("doc.on.doc", help: L("复制路径", "Copy Path")) {
                copyPath(item.url)
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
            if let image = NSImage(contentsOf: url) {
                GeometryReader { proxy in
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .background(theme.terminalBackground)
                }
            } else {
                panelMessage(systemImage: "photo", text: L("图片无法读取", "Image could not be loaded"))
            }
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

                ConductorNativePreviewSurface(url: url)
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

    private func panelIconButton(_ systemImage: String, help: String, action: @escaping () -> Void) -> some View {
        ConductorNativeIconButton(
            systemImage: systemImage,
            help: help,
            size: 28,
            symbolSize: 11,
            opacity: 0.62,
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
        case "md", "txt", "log":
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
            ZStack(alignment: .trailing) {
                ScrollView([.vertical, .horizontal]) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(document.lines.enumerated()), id: \.offset) { index, line in
                            SourcePreviewLine(
                                number: index + 1,
                                text: line,
                                isHighlighted: false,
                                theme: theme
                            )
                        }
                    }
                    .padding(.top, 10)
                    .padding(.bottom, 18)
                    .padding(.trailing, 56)
                }
                .scrollIndicators(.visible)

                SourcePreviewMinimap(lines: document.lines, theme: theme)
                    .frame(width: 42)
                    .padding(.trailing, 6)
                    .padding(.vertical, 8)
                    .allowsHitTesting(false)
            }
            .background(theme.terminalBackground)
        }
    }

    private var sourceInfoBar: some View {
        HStack(spacing: 7) {
            if let formatLabel = document.formatLabel {
                infoPill(formatLabel)
            }
            infoPill(L("\(document.lineCount) 行", "\(document.lineCount) lines"))
            if document.isLineLimited {
                infoPill(L("预览前 \(document.displayedLineCount) 行", "Previewing \(document.displayedLineCount) lines"))
            }
            if truncated {
                infoPill(L("仅预览前 256 KB", "First 256 KB only"))
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
            ScrollView([.vertical, .horizontal]) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(document.rows.enumerated()), id: \.offset) { rowIndex, row in
                        HStack(spacing: 0) {
                            Text("\(rowIndex + 1)")
                                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                                .foregroundStyle(theme.shellChromeText.opacity(0.34))
                                .frame(width: 38, height: 26, alignment: .trailing)
                                .padding(.trailing, 8)
                                .background(theme.terminalChrome.opacity(theme.usesDarkChrome ? 0.30 : 0.18))

                            ForEach(0..<document.columnCount, id: \.self) { columnIndex in
                                Text(cell(row: row, columnIndex: columnIndex))
                                    .font(.system(size: 11.5, weight: rowIndex == 0 ? .semibold : .regular, design: .monospaced))
                                    .foregroundStyle(theme.shellChromeText.opacity(rowIndex == 0 ? 0.82 : 0.74))
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    .padding(.horizontal, 8)
                                    .frame(width: 156, height: 26, alignment: .leading)
                                    .background(cellBackground(rowIndex: rowIndex, columnIndex: columnIndex))
                                    .overlay(alignment: .trailing) {
                                        Rectangle()
                                            .fill(theme.terminalOuterStroke.opacity(theme.usesDarkChrome ? 0.22 : 0.16))
                                            .frame(width: 1)
                                    }
                                    .contextMenu {
                                        Button(L("复制单元格", "Copy Cell")) {
                                            copyText(cell(row: row, columnIndex: columnIndex))
                                        }
                                        Button(L("复制行", "Copy Row")) {
                                            copyText(row.joined(separator: document.delimiterName == "TSV" ? "\t" : ","))
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
                .foregroundStyle(theme.shellChromeText.opacity(0.34))
                .frame(width: 34, alignment: .trailing)
                .textSelection(.disabled)

            Text(text.isEmpty ? " " : text)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundStyle(theme.shellChromeText.opacity(0.86))
                .lineLimit(1)
                .textSelection(.enabled)
        }
        .padding(.leading, 8)
        .padding(.trailing, 10)
        .frame(minWidth: 360, maxWidth: .infinity, minHeight: 23, alignment: .leading)
        .background {
            Rectangle()
                .fill(isHighlighted ? theme.floatingSelectedFill.opacity(0.35) : Color.clear)
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
    @State private var isHovered = false
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
                loadDroppedFileURLs(from: providers) { urls in
                    guard !urls.isEmpty else { return }
                    dropFiles(urls, move)
                }
                return true
            }
            .onHover { hovering in
                isHovered = hovering
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

            if isMissing {
                statusBadge(
                    systemImage: "questionmark.diamond",
                    help: L("项目已不存在，刷新后会移除", "Item no longer exists; refresh will remove it")
                )
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

            if isLargeEditableFile {
                statusBadge(
                    systemImage: "exclamationmark.triangle",
                    help: L("超过 20 MB，将以保护模式打开", "Over 20 MB; opens in protected mode")
                )
            } else if isUnsupportedBinaryLikeFile {
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

    private var isLargeEditableFile: Bool {
        guard !item.isDirectory, let byteCount = item.byteCount else { return false }
        return byteCount > 20 * 1024 * 1024
    }

    private var isMissing: Bool {
        !FileManager.default.fileExists(atPath: item.url.path)
    }

    private var isUnsupportedBinaryLikeFile: Bool {
        guard !item.isDirectory else { return false }
        let textishExtensions: Set<String> = [
            "md", "markdown", "txt", "log", "json", "jsonl", "yaml", "yml", "toml", "plist",
            "csv", "tsv", "xml", "env", "ini", "conf", "cfg", "properties", "swift", "js",
            "jsx", "ts", "tsx", "py", "rb", "sh", "zsh", "bash", "go", "rs", "java", "kt",
            "kts", "c", "cc", "cpp", "h", "hpp", "m", "mm", "html", "css", "scss", "sql"
        ]
        if textishExtensions.contains(item.url.pathExtension.lowercased()) {
            return false
        }
        if let typeIdentifier = item.contentTypeIdentifier,
           let type = UTType(typeIdentifier),
           type.conforms(to: .image) || type.conforms(to: .text) || type.conforms(to: .sourceCode) {
            return false
        }
        return true
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
        if isHovered {
            return theme.floatingHoverFill.opacity(theme.usesDarkChrome ? 0.24 : 0.32)
        }
        return Color.clear
    }

    private func loadDroppedFileURLs(from providers: [NSItemProvider], completion: @escaping ([URL]) -> Void) {
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
}
