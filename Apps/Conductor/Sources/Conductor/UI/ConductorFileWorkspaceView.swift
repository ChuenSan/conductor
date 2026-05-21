import AppKit
import CodeEditLanguages
import CodeEditSourceEditor
import SwiftUI
import UniformTypeIdentifiers

private func L(_ zh: String, _ en: String) -> String {
    ConductorLocalization.text(zh: zh, en: en)
}

private struct WorkspaceFileSearchFocusTokenKey: EnvironmentKey {
    static let defaultValue = 0
}

private struct WorkspaceFileSearchNextTokenKey: EnvironmentKey {
    static let defaultValue = 0
}

private struct WorkspaceFileSearchPreviousTokenKey: EnvironmentKey {
    static let defaultValue = 0
}

private extension EnvironmentValues {
    var workspaceFileSearchFocusToken: Int {
        get { self[WorkspaceFileSearchFocusTokenKey.self] }
        set { self[WorkspaceFileSearchFocusTokenKey.self] = newValue }
    }

    var workspaceFileSearchNextToken: Int {
        get { self[WorkspaceFileSearchNextTokenKey.self] }
        set { self[WorkspaceFileSearchNextTokenKey.self] = newValue }
    }

    var workspaceFileSearchPreviousToken: Int {
        get { self[WorkspaceFileSearchPreviousTokenKey.self] }
        set { self[WorkspaceFileSearchPreviousTokenKey.self] = newValue }
    }
}

private enum WorkspaceFileDocumentState: Equatable {
    case text(String)
    case image(URL)
    case largeText(WorkspaceLargeTextDocument)
    case largeFile(Int64)
    case message(String)
}

private struct WorkspaceFileDocument: Equatable {
    let title: String
    let subtitle: String
    let isReadOnly: Bool
    let state: WorkspaceFileDocumentState
}

private struct WorkspaceFilePerformanceProfile {
    let interactiveByteLimit: Int
    let interactiveLineLimit: Int
    let formatTitle: String
    let formatSystemImage: String
    let protectedReason: String
    let extractsOutline: Bool
}

private struct WorkspaceFileDiskSignature: Equatable {
    let modificationDate: Date?
    let byteCount: Int64
}

private struct WorkspaceFileService {
    private let maxEditableBytes = 20 * 1024 * 1024
    private let maxInteractiveMarkdownBytes = 192 * 1024
    private let maxInteractiveStructuredBytes = 256 * 1024
    private let maxInteractiveTableBytes = 256 * 1024
    private let maxInteractiveLogBytes = 256 * 1024
    private let maxInteractiveSourceBytes = 768 * 1024
    private let maxInteractivePlainTextBytes = 768 * 1024
    private let maxInteractiveMarkdownLines = 2_500
    private let maxInteractiveStructuredLines = 2_500
    private let maxInteractiveTableLines = 1_500
    private let maxInteractiveLogLines = 4_000
    private let maxInteractiveSourceLines = 6_000
    private let maxInteractivePlainTextLines = 6_000

    func document(for tab: ConductorWorkspaceFileTab) -> WorkspaceFileDocument {
        let fileURL = tab.fileURL.standardizedFileURL
        let subtitle = relativePath(for: fileURL, rootURL: tab.rootURL)
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .fileSizeKey, .contentTypeKey, .isReadableKey, .isWritableKey]

        guard let values = try? fileURL.resourceValues(forKeys: keys),
              values.isDirectory != true else {
            return WorkspaceFileDocument(
                title: tab.title,
                subtitle: subtitle,
                isReadOnly: true,
                state: .message(L("文件无法读取", "File could not be read"))
            )
        }

        guard values.isReadable != false else {
            return WorkspaceFileDocument(
                title: tab.title,
                subtitle: subtitle,
                isReadOnly: true,
                state: .message(L("没有读取权限", "No read permission"))
            )
        }

        let isReadOnly = values.isWritable == false
        let byteCount = Int64(values.fileSize ?? 0)
        let type = values.contentType ?? UTType(filenameExtension: fileURL.pathExtension)
        if type?.conforms(to: .image) == true {
            return WorkspaceFileDocument(title: tab.title, subtitle: subtitle, isReadOnly: isReadOnly, state: .image(fileURL))
        }

        let pathExtension = fileURL.pathExtension.lowercased()
        let profile = performanceProfile(for: type, extension: pathExtension)
        if let profile, byteCount > profile.interactiveByteLimit {
            return largeTextDocument(title: tab.title, subtitle: subtitle, fileURL: fileURL, byteCount: byteCount, profile: profile)
        }

        guard byteCount <= maxEditableBytes else {
            return WorkspaceFileDocument(
                title: tab.title,
                subtitle: subtitle,
                isReadOnly: true,
                state: .largeFile(byteCount)
            )
        }

        do {
            let data = try Data(contentsOf: fileURL)
            if data.contains(0) {
                return WorkspaceFileDocument(
                    title: tab.title,
                    subtitle: subtitle,
                    isReadOnly: true,
                    state: .message(L("二进制文件不能在这里编辑", "Binary files cannot be edited here"))
                )
            }
            let text = String(data: data, encoding: .utf8) ??
                String(data: data, encoding: .utf16) ??
                String(decoding: data, as: UTF8.self)
            if let profile, Self.exceedsLineLimit(text, limit: profile.interactiveLineLimit) {
                return largeTextDocument(title: tab.title, subtitle: subtitle, fileURL: fileURL, byteCount: byteCount, profile: profile)
            }
            return WorkspaceFileDocument(title: tab.title, subtitle: subtitle, isReadOnly: isReadOnly, state: .text(text))
        } catch {
            return WorkspaceFileDocument(title: tab.title, subtitle: subtitle, isReadOnly: true, state: .message(error.localizedDescription))
        }
    }

    func save(_ text: String, to tab: ConductorWorkspaceFileTab) throws {
        let fileURL = tab.fileURL.standardizedFileURL
        guard isWithinRoot(fileURL, rootURL: tab.rootURL) else {
            throw NSError(domain: "ConductorFileWorkspace", code: 403, userInfo: [
                NSLocalizedDescriptionKey: L("文件不在当前工作区内", "This file is outside the current workspace")
            ])
        }
        let values = try fileURL.resourceValues(forKeys: [.isDirectoryKey, .isWritableKey])
        guard values.isDirectory != true else {
            throw NSError(domain: "ConductorFileWorkspace", code: 400, userInfo: [
                NSLocalizedDescriptionKey: L("文件夹不能作为文本保存", "Folders cannot be saved as text")
            ])
        }
        guard values.isWritable != false else {
            throw NSError(domain: "ConductorFileWorkspace", code: 403, userInfo: [
                NSLocalizedDescriptionKey: L("文件是只读的，无法保存", "File is read-only and cannot be saved")
            ])
        }
        let data = Data(text.utf8)
        guard data.count <= maxEditableBytes else {
            throw NSError(domain: "ConductorFileWorkspace", code: 413, userInfo: [
                NSLocalizedDescriptionKey: L("内容超过 20 MB，已停止保存以保护编辑器", "Content exceeds 20 MB; save was stopped to protect the editor")
            ])
        }
        try data.write(to: fileURL, options: .atomic)
    }

    func diskSignature(for tab: ConductorWorkspaceFileTab) -> WorkspaceFileDiskSignature? {
        let fileURL = tab.fileURL.standardizedFileURL
        guard let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]) else {
            return nil
        }
        return WorkspaceFileDiskSignature(
            modificationDate: values.contentModificationDate,
            byteCount: Int64(values.fileSize ?? 0)
        )
    }

    private static func decodeText(_ data: Data) -> String {
        String(data: data, encoding: .utf8) ??
            String(data: data, encoding: .utf16) ??
            String(decoding: data, as: UTF8.self)
    }

    private func performanceProfile(for type: UTType?, extension pathExtension: String) -> WorkspaceFilePerformanceProfile? {
        let ext = pathExtension.lowercased()

        if Self.markdownExtensions.contains(ext) {
            return WorkspaceFilePerformanceProfile(
                interactiveByteLimit: maxInteractiveMarkdownBytes,
                interactiveLineLimit: maxInteractiveMarkdownLines,
                formatTitle: "Markdown",
                formatSystemImage: "doc.richtext",
                protectedReason: L("Markdown 文件较大，已跳过实时预览解析和源码编辑器", "Large Markdown file; live preview parsing and the source editor were skipped"),
                extractsOutline: true
            )
        }

        if Self.structuredExtensions.contains(ext) {
            return WorkspaceFilePerformanceProfile(
                interactiveByteLimit: maxInteractiveStructuredBytes,
                interactiveLineLimit: maxInteractiveStructuredLines,
                formatTitle: L("结构化", "Structured"),
                formatSystemImage: "curlybraces",
                protectedReason: L("结构化文件较大，已避免格式化/语法高亮造成卡顿", "Large structured file; formatting and syntax highlighting were avoided"),
                extractsOutline: false
            )
        }

        if Self.tableExtensions.contains(ext) {
            return WorkspaceFilePerformanceProfile(
                interactiveByteLimit: maxInteractiveTableBytes,
                interactiveLineLimit: maxInteractiveTableLines,
                formatTitle: L("表格文本", "Table Text"),
                formatSystemImage: "tablecells",
                protectedReason: L("表格文件较大，已避免一次性解析整表", "Large table file; full-table parsing was avoided"),
                extractsOutline: false
            )
        }

        if Self.logExtensions.contains(ext) {
            return WorkspaceFilePerformanceProfile(
                interactiveByteLimit: maxInteractiveLogBytes,
                interactiveLineLimit: maxInteractiveLogLines,
                formatTitle: L("日志", "Log"),
                formatSystemImage: "list.bullet.rectangle",
                protectedReason: L("日志文件较大，已进入只读保护预览", "Large log file opened in read-only protected preview"),
                extractsOutline: false
            )
        }

        if Self.sourceExtensions.contains(ext) || type?.conforms(to: .sourceCode) == true {
            return WorkspaceFilePerformanceProfile(
                interactiveByteLimit: maxInteractiveSourceBytes,
                interactiveLineLimit: maxInteractiveSourceLines,
                formatTitle: L("源码", "Source"),
                formatSystemImage: "chevron.left.forwardslash.chevron.right",
                protectedReason: L("源码文件较大，已跳过编辑器语法高亮", "Large source file; editor syntax highlighting was skipped"),
                extractsOutline: false
            )
        }

        if type?.conforms(to: .text) == true || Self.plainTextExtensions.contains(ext) {
            return WorkspaceFilePerformanceProfile(
                interactiveByteLimit: maxInteractivePlainTextBytes,
                interactiveLineLimit: maxInteractivePlainTextLines,
                formatTitle: L("文本", "Text"),
                formatSystemImage: "doc.text",
                protectedReason: L("文本文件较大，已进入只读保护预览", "Large text file opened in read-only protected preview"),
                extractsOutline: false
            )
        }

        return nil
    }

    private func largeTextDocument(
        title: String,
        subtitle: String,
        fileURL: URL,
        byteCount: Int64,
        profile: WorkspaceFilePerformanceProfile
    ) -> WorkspaceFileDocument {
        WorkspaceFileDocument(
            title: title,
            subtitle: subtitle,
            isReadOnly: true,
            state: .largeText(WorkspaceLargeTextDocument(
                fileURL: fileURL,
                byteCount: byteCount,
                formatTitle: profile.formatTitle,
                formatSystemImage: profile.formatSystemImage,
                reason: profile.protectedReason,
                extractsOutline: profile.extractsOutline
            ))
        )
    }

    private static func exceedsLineLimit(_ text: String, limit: Int) -> Bool {
        guard limit > 0 else { return false }
        var count = 1
        for character in text where character == "\n" {
            count += 1
            if count > limit {
                return true
            }
        }
        return false
    }

    private static let markdownExtensions: Set<String> = ["md", "markdown", "mdown", "mkd"]
    private static let structuredExtensions: Set<String> = [
        "cfg", "conf", "env", "ini", "json", "json5", "jsonl", "plist", "properties", "toml", "xml", "yaml", "yml"
    ]
    private static let tableExtensions: Set<String> = ["csv", "tsv", "tab", "psv"]
    private static let logExtensions: Set<String> = ["err", "log", "out", "stderr", "stdout", "trace"]
    private static let sourceExtensions: Set<String> = [
        "bash", "c", "cc", "cpp", "css", "diff", "go", "h", "hpp", "htm", "html", "java", "js", "jsx", "kt", "m",
        "mm", "patch", "php", "py", "rb", "rs", "scss", "sh", "sql", "swift", "ts", "tsx", "zsh"
    ]
    private static let plainTextExtensions: Set<String> = ["adoc", "env", "ini", "properties", "rst", "text", "txt"]

    private func relativePath(for url: URL, rootURL: URL) -> String {
        let rootPath = rootURL.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path == rootPath || path.hasPrefix(rootPath + "/") else {
            return url.lastPathComponent
        }
        let suffix = path.dropFirst(rootPath.count).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return suffix.isEmpty ? url.lastPathComponent : String(suffix)
    }

    private func isWithinRoot(_ url: URL, rootURL: URL) -> Bool {
        let rootPath = rootURL.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        return path == rootPath || path.hasPrefix(rootPath + "/")
    }
}

struct ConductorFileWorkspaceView: View {
    @ObservedObject var model: ConductorWindowModel
    @Environment(\.conductorTheme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            if let selected = model.selectedWorkspaceFileTab {
                ZStack {
                    ForEach(model.workspaceFileTabs) { tab in
                        let isSelected = tab.id == selected.id
                        ConductorWorkspaceFileEditorView(model: model, tab: tab, isSelected: isSelected)
                            .environment(\.workspaceFileSearchFocusToken, model.workspaceFileSearchFocusGeneration)
                            .environment(\.workspaceFileSearchNextToken, model.workspaceFileSearchNextGeneration)
                            .environment(\.workspaceFileSearchPreviousToken, model.workspaceFileSearchPreviousGeneration)
                            .id(tab.id)
                            .opacity(isSelected ? 1 : 0)
                            .allowsHitTesting(isSelected)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
            } else {
                emptyState
            }
        }
        .background(theme.terminalBackground)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(theme.shellChromeText.opacity(0.28))
            Text(L("没有打开的文件", "No File Open"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.shellChromeText.opacity(0.58))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

}

struct ConductorWorkspaceContentTabBar: View {
    @ObservedObject var model: ConductorWindowModel
    @Environment(\.conductorTheme) private var theme

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(model.workspaceTerminalContentTabs) { tab in
                    ConductorWorkspaceContentTabPill(
                        systemImage: "terminal",
                        title: tab.title,
                        dirty: false,
                        isSelected: model.selectedWorkspaceTerminalTabID == tab.id && model.selectedWorkspaceFileTab == nil,
                        close: nil,
                        action: { model.selectWorkspaceTerminalTab(tab.id) }
                    )
                }

                if !model.workspaceFileTabs.isEmpty && !model.workspaceTerminalContentTabs.isEmpty {
                    Rectangle()
                        .fill(theme.terminalOuterStroke.opacity(theme.usesDarkChrome ? 0.48 : 0.32))
                        .frame(width: 1, height: 18)
                        .padding(.horizontal, 2)
                }

                ForEach(model.workspaceFileTabs) { tab in
                    ConductorWorkspaceContentTabPill(
                        systemImage: "doc.text",
                        title: tab.title,
                        dirty: model.isWorkspaceFileTabDirty(tab.id),
                        externallyChanged: model.isWorkspaceFileTabExternallyChanged(tab.id),
                        isSelected: model.selectedWorkspaceFileTab?.id == tab.id,
                        close: { model.closeWorkspaceFileTab(tab) },
                        action: { model.selectWorkspaceFileTab(tab.id) }
                    )
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .frame(height: 39)
        .background(theme.terminalChrome.opacity(theme.usesDarkChrome ? 0.38 : 0.24))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(theme.terminalOuterStroke.opacity(theme.usesDarkChrome ? 0.42 : 0.30))
                .frame(height: 1)
        }
    }
}

private struct ConductorWorkspaceContentTabPill: View {
    let systemImage: String
    let title: String
    let dirty: Bool
    var externallyChanged = false
    let isSelected: Bool
    let close: (() -> Void)?
    let action: () -> Void
    @Environment(\.conductorTheme) private var theme
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Circle()
                    .fill(externallyChanged ? Color.orange.opacity(0.94) : theme.floatingEmphasis.opacity(0.92))
                    .frame(width: 5, height: 5)
                    .opacity((dirty || externallyChanged) ? 1 : 0)
                    .macNativeTooltip(externallyChanged ? L("文件已被外部修改", "File changed outside Conductor") : L("未保存更改", "Unsaved changes"))
                if let close {
                    Button(action: close) {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                            .frame(width: 14, height: 14)
                    }
                    .buttonStyle(.plain)
                    .opacity(isHovered || isSelected ? 1 : 0.36)
                }
            }
            .foregroundStyle(theme.shellChromeText.opacity(isSelected ? 0.94 : 0.62))
            .padding(.horizontal, 9)
            .frame(minWidth: 84, maxWidth: 210, minHeight: 27)
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private var backgroundColor: Color {
        if isSelected {
            return theme.floatingSelectedFill.opacity(theme.usesDarkChrome ? 0.68 : 0.78)
        }
        if isHovered {
            return theme.floatingHoverFill.opacity(theme.usesDarkChrome ? 0.55 : 0.70)
        }
        return Color.clear
    }
}

private struct ConductorWorkspaceFileEditorView: View {
    @ObservedObject var model: ConductorWindowModel
    let tab: ConductorWorkspaceFileTab
    let isSelected: Bool
    @State private var document: WorkspaceFileDocument
    @State private var text: String
    @State private var savedText: String
    @State private var statusMessage: String?
    @State private var editorFocusToken = 1
    @State private var editorSnapshotToken = 0
    @State private var autosaveTask: Task<Void, Never>?
    @State private var externalWatchTask: Task<Void, Never>?
    @State private var saveGeneration = 0
    @State private var pendingSaveRequest: WorkspaceFileSaveRequest?
    @State private var lastKnownDiskSignature: WorkspaceFileDiskSignature?
    @State private var externalChangeDetected = false
    @State private var externalDiffVisible = false
    @Environment(\.conductorTheme) private var theme
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorFontFamily) private var fontFamily
    @Environment(\.workspaceFileSearchFocusToken) private var searchFocusToken
    @Environment(\.workspaceFileSearchNextToken) private var searchNextToken
    @Environment(\.workspaceFileSearchPreviousToken) private var searchPreviousToken
    @State private var searchVisible = false
    @State private var searchQuery = ""
    @State private var searchHistory: [String]
    @State private var selectedSearchIndex = 0
    @State private var cachedSearchMatches: [NSRange] = []
    @State private var sourceSelectionRange: NSRange?
    @State private var sourceSelectionToken = 0
    @State private var largeSearchStatus = "0/0"
    @State private var largeSearchNextToken = 0
    @State private var largeSearchPreviousToken = 0

    init(model: ConductorWindowModel, tab: ConductorWorkspaceFileTab, isSelected: Bool) {
        self.model = model
        self.tab = tab
        self.isSelected = isSelected
        let loaded = WorkspaceFileService().document(for: tab)
        _document = State(initialValue: loaded)
        if case .text(let loadedText) = loaded.state {
            _text = State(initialValue: loadedText)
            _savedText = State(initialValue: loadedText)
        } else {
            _text = State(initialValue: "")
            _savedText = State(initialValue: "")
        }
        _lastKnownDiskSignature = State(initialValue: WorkspaceFileService().diskSignature(for: tab))
        _searchHistory = State(initialValue: ConductorSearchHistory.load(scope: "workspace-file"))
    }

    private var isDirty: Bool {
        text != savedText
    }

    private var isMarkdown: Bool {
        let ext = tab.fileURL.pathExtension.lowercased()
        return ext == "md" || ext == "markdown"
    }

    private var isLargeText: Bool {
        if case .largeText = document.state { return true }
        return false
    }

    private var supportsToolbarSearch: Bool {
        if isLargeText { return true }
        if case .text = document.state { return !isMarkdown }
        return false
    }

    private var searchMatches: [NSRange] {
        cachedSearchMatches
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            if externalChangeDetected {
                externalChangeBar
            }
            content
        }
        .background(theme.terminalBackground)
        .onAppear {
            model.setWorkspaceFileTabDirty(tab.id, isDirty: isDirty)
            model.setWorkspaceFileTabExternallyChanged(tab.id, changed: externalChangeDetected)
            startExternalChangeWatch()
            if isSelected {
                editorFocusToken &+= 1
            }
        }
        .onChange(of: isSelected) { _, newValue in
            if newValue {
                editorFocusToken &+= 1
            }
        }
        .onChange(of: text) {
            scheduleAutosave()
            refreshSearchMatches(resetSelection: false)
        }
        .onChange(of: isDirty) { _, newValue in
            model.setWorkspaceFileTabDirty(tab.id, isDirty: newValue)
        }
        .onChange(of: model.workspaceFileEditorSaveRequestToken(for: tab.id)) { _, newValue in
            guard newValue > 0 else { return }
            save()
        }
        .onChange(of: model.workspaceFileEditorSaveAndCloseRequestToken(for: tab.id)) { _, newValue in
            guard newValue > 0 else { return }
            save(closeAfterSave: true)
        }
        .onChange(of: searchFocusToken) { _, newValue in
            guard newValue > 0, isSelected else { return }
            showSearch()
        }
        .onChange(of: searchNextToken) { _, newValue in
            guard newValue > 0, isSelected else { return }
            moveSearchSelection(1)
        }
        .onChange(of: searchPreviousToken) { _, newValue in
            guard newValue > 0, isSelected else { return }
            moveSearchSelection(-1)
        }
        .onChange(of: searchQuery) {
            refreshSearchMatches(resetSelection: true)
            selectCurrentSearchMatch()
        }
        .onDisappear {
            autosaveTask?.cancel()
            externalWatchTask?.cancel()
            if isDirty, !externalChangeDetected {
                saveGeneration += 1
                saveSnapshot(text, generation: saveGeneration, showStatus: false, closeAfterSave: false)
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(document.title)
                    .font(.conductorSystem(size: 13.4, weight: .semibold, family: fontFamily, scale: fontScale))
                    .foregroundStyle(theme.shellChromeText.opacity(0.90))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(document.subtitle.isEmpty ? tab.fileURL.path : document.subtitle)
                    .font(.conductorSystem(size: 10, weight: .medium, family: fontFamily, scale: fontScale))
                    .foregroundStyle(theme.shellChromeText.opacity(0.48))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            if let statusMessage {
                Text(statusMessage)
                    .font(.conductorSystem(size: 11, weight: .medium, family: fontFamily, scale: fontScale))
                    .foregroundStyle(theme.shellChromeText.opacity(0.50))
                    .lineLimit(1)
            }

            if document.isReadOnly {
                statusPill(systemImage: "lock", title: L("只读", "Read-only"))
            }
            if externalChangeDetected {
                statusPill(systemImage: "arrow.triangle.2.circlepath", title: L("外部已修改", "Changed externally"))
            }

            if supportsToolbarSearch && (searchVisible || !searchQuery.isEmpty) {
                fileSearchField
            }

            editorButton("checkmark.circle", active: isDirty, help: L("保存", "Save")) {
                save()
            }
            .disabled(!isDirty || document.isReadOnly)
            .keyboardShortcut("s", modifiers: .command)

            editorButton("arrow.clockwise", help: L("重新载入", "Reload")) {
                reload()
            }

            editorButton("arrow.up.right.square", help: L("系统应用打开", "Open in System App")) {
                NSWorkspace.shared.open(tab.fileURL)
            }

            editorButton("folder", help: L("在 Finder 中显示", "Reveal in Finder")) {
                NSWorkspace.shared.activateFileViewerSelecting([tab.fileURL])
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(theme.terminalChrome.opacity(theme.usesDarkChrome ? 0.36 : 0.16))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(theme.terminalOuterStroke.opacity(theme.usesDarkChrome ? 0.22 : 0.14))
                .frame(height: 1)
        }
    }

    private var externalChangeBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.conductorSystem(size: 12, weight: .bold, family: fontFamily, scale: fontScale))
                Text(L("磁盘上的文件已变化，保存已暂停。选择重新载入、保留当前内容，或先查看差异。", "The file changed on disk; saving is paused. Reload, keep current content, or inspect the diff first."))
                    .font(.conductorSystem(size: 11.4, weight: .semibold, family: fontFamily, scale: fontScale))
                    .lineLimit(2)
                Spacer(minLength: 8)
                Button(externalDiffVisible ? L("隐藏差异", "Hide Diff") : L("查看差异", "View Diff")) {
                    externalDiffVisible.toggle()
                }
                Button(L("重新载入", "Reload")) {
                    reload()
                }
                Button(L("保留当前", "Keep Current")) {
                    keepCurrentVersionAfterExternalChange()
                }
            }
            .buttonStyle(.borderless)
            .foregroundStyle(theme.shellChromeText.opacity(0.84))
            .padding(.horizontal, 14)
            .frame(minHeight: 36)
            .background(theme.floatingControlStrongFill.opacity(theme.usesDarkChrome ? 0.34 : 0.40))

            if externalDiffVisible {
                ScrollView {
                    Text(externalDiffSummary())
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundStyle(theme.shellChromeText.opacity(0.76))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(12)
                }
                .frame(maxHeight: 150)
                .background(theme.terminalBackground.opacity(0.98))
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(theme.terminalOuterStroke.opacity(theme.usesDarkChrome ? 0.26 : 0.16))
                        .frame(height: 1)
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch document.state {
        case .text:
            Group {
                if isMarkdown {
                    ConductorMarkdownWorkspaceView(
                        model: model,
                        text: $text,
                        fileURL: tab.fileURL,
                        rootURL: tab.rootURL,
                        fontSize: model.appearance.terminalFontSize,
                        focusToken: editorFocusToken,
                        snapshotToken: editorSnapshotToken,
                        isEditable: !document.isReadOnly,
                        searchFocusToken: searchFocusToken,
                        searchNextToken: searchNextToken,
                        searchPreviousToken: searchPreviousToken,
                        onTextSnapshot: handleEditorSnapshot
                    )
                } else {
                    ConductorCodeEditSourceEditor(
                        text: $text,
                        fileURL: tab.fileURL,
                        theme: theme,
                        fontSize: model.appearance.terminalFontSize,
                        focusToken: editorFocusToken,
                        selectionRange: sourceSelectionRange,
                        selectionToken: sourceSelectionToken,
                        snapshotToken: editorSnapshotToken,
                        isEditable: !document.isReadOnly,
                        onTextSnapshot: handleEditorSnapshot
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        case .largeText(let largeDocument):
            ConductorLargeTextWorkspaceView(
                document: largeDocument,
                theme: theme,
                fontSize: model.appearance.terminalFontSize,
                searchQuery: searchQuery,
                searchNextToken: largeSearchNextToken,
                searchPreviousToken: largeSearchPreviousToken,
                onSearchStatus: { largeSearchStatus = $0 },
                isActive: isSelected
            )
        case .largeFile(let byteCount):
            largeFileView(byteCount)
        case .image(let url):
            imageView(url)
        case .message(let message):
            messageView(systemImage: "doc.badge.ellipsis", title: L("无法编辑", "Cannot Edit"), message: message)
        }
    }

    private var fileSearchField: some View {
        ConductorContextSearchSurface {
            Image(systemName: "magnifyingglass")
                .font(.conductorSystem(size: 11, weight: .semibold, family: fontFamily, scale: fontScale))
                .foregroundStyle(theme.shellChromeText.opacity(0.58))

            ConductorContextSearchScopeChip(systemImage: "doc.text", title: L("当前文件", "Current file"))

            if !searchHistory.isEmpty {
                Menu {
                    ForEach(searchHistory, id: \.self) { query in
                        Button(query) {
                            searchQuery = query
                            refreshSearchMatches(resetSelection: true)
                            recordSearchQuery()
                            selectCurrentSearchMatch()
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
                text: $searchQuery,
                placeholder: L("搜索当前文件", "Search current file"),
                focusToken: searchFocusToken,
                theme: theme,
                fontFamily: fontFamily,
                fontScale: fontScale,
                onNavigate: { previous in
                    recordSearchQuery()
                    moveSearchSelection(previous ? -1 : 1)
                },
                onClose: closeSearch
            )
            .frame(width: 168, height: 22)

            Text(searchStatus)
                .font(.conductorSystem(size: 10, weight: .semibold, family: fontFamily, scale: fontScale))
                .foregroundStyle(theme.shellChromeText.opacity(0.52))
                .monospacedDigit()
                .frame(minWidth: 48, alignment: .trailing)

            ConductorContextSearchIconButton(
                systemImage: "chevron.up",
                help: L("上一个匹配", "Previous Match"),
                disabled: searchQuery.isEmpty
            ) {
                moveSearchSelection(-1)
            }

            ConductorContextSearchIconButton(
                systemImage: "chevron.down",
                help: L("下一个匹配", "Next Match"),
                disabled: searchQuery.isEmpty
            ) {
                moveSearchSelection(1)
            }

            ConductorContextSearchIconButton(systemImage: "xmark", help: L("关闭搜索", "Close Search")) {
                closeSearch()
            }
        }
    }

    private var searchStatus: String {
        if isLargeText { return largeSearchStatus }
        guard !searchMatches.isEmpty else { return "0/0" }
        return "\(selectedSearchIndex + 1)/\(searchMatches.count)"
    }

    private func editorButton(_ systemImage: String, active: Bool = false, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.conductorSystem(size: 12, weight: .semibold, family: fontFamily, scale: fontScale))
                .foregroundStyle(active ? theme.floatingEmphasis : theme.shellChromeText.opacity(0.62))
                .frame(width: 30, height: 30)
                .background(active ? theme.floatingSelectedFill.opacity(0.72) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .macNativeTooltip(help)
    }

    private func statusPill(systemImage: String, title: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.conductorSystem(size: 10.5, weight: .bold, family: fontFamily, scale: fontScale))
            Text(title)
                .font(.conductorSystem(size: 10.5, weight: .semibold, family: fontFamily, scale: fontScale))
        }
        .foregroundStyle(theme.shellChromeText.opacity(0.64))
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background(theme.shellControlFill.opacity(theme.usesDarkChrome ? 0.38 : 0.22))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private func largeFileView(_ byteCount: Int64) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.conductorSystem(size: 30, weight: .semibold, family: fontFamily, scale: fontScale))
                .foregroundStyle(theme.shellChromeText.opacity(0.30))
            Text(L("文件太大", "File Too Large"))
                .font(.conductorSystem(size: 14, weight: .semibold, family: fontFamily, scale: fontScale))
                .foregroundStyle(theme.shellChromeText.opacity(0.66))
            Text(L(
                "大小 \(ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file))，已阻止加载到编辑器。可以用系统应用打开，或在 Finder 中显示。",
                "Size \(ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)); loading into the editor was blocked. Open with the system app or reveal it in Finder."
            ))
            .font(.conductorSystem(size: 12, weight: .medium, family: fontFamily, scale: fontScale))
            .foregroundStyle(theme.shellChromeText.opacity(0.50))
            .multilineTextAlignment(.center)
            .frame(maxWidth: 420)

            HStack(spacing: 8) {
                Button(L("系统应用打开", "Open in System App")) {
                    NSWorkspace.shared.open(tab.fileURL)
                }
                Button(L("Finder 中显示", "Reveal in Finder")) {
                    NSWorkspace.shared.activateFileViewerSelecting([tab.fileURL])
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private func messageView(systemImage: String, title: String, message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.conductorSystem(size: 28, weight: .semibold, family: fontFamily, scale: fontScale))
                .foregroundStyle(theme.shellChromeText.opacity(0.28))
            Text(title)
                .font(.conductorSystem(size: 13, weight: .semibold, family: fontFamily, scale: fontScale))
                .foregroundStyle(theme.shellChromeText.opacity(0.62))
            Text(message)
                .font(.conductorSystem(size: 12, weight: .medium, family: fontFamily, scale: fontScale))
                .foregroundStyle(theme.shellChromeText.opacity(0.46))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private func imageView(_ url: URL) -> some View {
        ConductorImageWorkspaceView(url: url, theme: theme, isActive: isSelected)
    }

    private func showSearch() {
        searchVisible = true
        selectCurrentSearchMatch()
    }

    private func closeSearch() {
        recordSearchQuery()
        searchVisible = false
        searchQuery = ""
        sourceSelectionRange = nil
    }

    private func moveSearchSelection(_ delta: Int) {
        if isMarkdown && !isLargeText { return }
        searchVisible = true
        if isLargeText {
            if delta < 0 {
                largeSearchPreviousToken &+= 1
            } else {
                largeSearchNextToken &+= 1
            }
            return
        }
        let matches = searchMatches
        guard !matches.isEmpty else { return }
        selectedSearchIndex = (selectedSearchIndex + delta + matches.count) % matches.count
        selectCurrentSearchMatch()
    }

    private func selectCurrentSearchMatch() {
        let matches = searchMatches
        if isLargeText {
            sourceSelectionRange = nil
            return
        }
        guard !matches.isEmpty, matches.indices.contains(selectedSearchIndex) else {
            sourceSelectionRange = nil
            return
        }
        sourceSelectionRange = matches[selectedSearchIndex]
        sourceSelectionToken &+= 1
    }

    private func refreshSearchMatches(resetSelection: Bool) {
        guard !isLargeText, !isMarkdown else {
            cachedSearchMatches = []
            selectedSearchIndex = 0
            sourceSelectionRange = nil
            return
        }
        cachedSearchMatches = Self.searchMatches(in: text, query: searchQuery)
        if resetSelection {
            selectedSearchIndex = 0
        } else if selectedSearchIndex >= cachedSearchMatches.count {
            selectedSearchIndex = max(0, cachedSearchMatches.count - 1)
        }
    }

    private static func searchMatches(in text: String, query: String) -> [NSRange] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return [] }
        let haystack = text as NSString
        var matches: [NSRange] = []
        var range = NSRange(location: 0, length: haystack.length)
        while range.location < haystack.length {
            let match = haystack.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive], range: range)
            guard match.location != NSNotFound else { break }
            matches.append(match)
            let nextLocation = match.location + max(match.length, 1)
            range = NSRange(location: nextLocation, length: haystack.length - nextLocation)
        }
        return matches
    }

    private func recordSearchQuery() {
        ConductorSearchHistory.record(searchQuery, scope: "workspace-file")
        searchHistory = ConductorSearchHistory.load(scope: "workspace-file")
    }

    private func save(showStatus: Bool = true, closeAfterSave: Bool = false) {
        guard !document.isReadOnly else {
            statusMessage = L("只读文件无法保存", "Read-only file cannot be saved")
            return
        }
        guard !externalChangeDetected else {
            statusMessage = L("文件已被外部修改，请先重新载入或另存处理", "File changed outside Conductor; reload before saving")
            model.setWorkspaceFileTabExternallyChanged(tab.id, changed: true)
            NSSound.beep()
            return
        }
        autosaveTask?.cancel()
        saveGeneration += 1
        pendingSaveRequest = WorkspaceFileSaveRequest(
            generation: saveGeneration,
            showStatus: showStatus,
            closeAfterSave: closeAfterSave
        )
        editorSnapshotToken &+= 1
    }

    private func scheduleAutosave() {
        autosaveTask?.cancel()
        guard isDirty, !document.isReadOnly, !externalChangeDetected else { return }

        let generation = saveGeneration + 1
        saveGeneration = generation
        autosaveTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            pendingSaveRequest = WorkspaceFileSaveRequest(generation: generation, showStatus: false, closeAfterSave: false)
            editorSnapshotToken &+= 1
        }
    }

    private func handleEditorSnapshot(_ snapshot: String) {
        guard let request = pendingSaveRequest else { return }
        pendingSaveRequest = nil
        saveSnapshot(
            snapshot,
            generation: request.generation,
            showStatus: request.showStatus,
            closeAfterSave: request.closeAfterSave
        )
    }

    private func saveSnapshot(_ snapshot: String, generation: Int, showStatus: Bool, closeAfterSave: Bool) {
        let tab = tab
        Task {
            let result = await Task.detached(priority: .utility) {
                Result { try WorkspaceFileService().save(snapshot, to: tab) }
            }.value
            guard generation == saveGeneration else { return }
            switch result {
            case .success:
                text = snapshot
                savedText = snapshot
                lastKnownDiskSignature = WorkspaceFileService().diskSignature(for: tab)
                externalChangeDetected = false
                statusMessage = showStatus ? L("已保存", "Saved") : L("已自动保存", "Autosaved")
                model.setWorkspaceFileTabDirty(tab.id, isDirty: false)
                model.setWorkspaceFileTabExternallyChanged(tab.id, changed: false)
                if closeAfterSave {
                    _ = model.closeWorkspaceFileTabAfterSaving(tabID: tab.id)
                }
            case .failure(let error):
                statusMessage = error.localizedDescription
            }
        }
    }

    private func reload() {
        autosaveTask?.cancel()
        saveGeneration += 1
        let loaded = WorkspaceFileService().document(for: tab)
        document = loaded
        lastKnownDiskSignature = WorkspaceFileService().diskSignature(for: tab)
        externalChangeDetected = false
        if case .text(let loadedText) = loaded.state {
            text = loadedText
            savedText = loadedText
        } else {
            text = ""
            savedText = ""
        }
        refreshSearchMatches(resetSelection: true)
        model.setWorkspaceFileTabDirty(tab.id, isDirty: false)
        model.setWorkspaceFileTabExternallyChanged(tab.id, changed: false)
        statusMessage = nil
        externalDiffVisible = false
    }

    private func keepCurrentVersionAfterExternalChange() {
        lastKnownDiskSignature = WorkspaceFileService().diskSignature(for: tab)
        externalChangeDetected = false
        externalDiffVisible = false
        model.setWorkspaceFileTabExternallyChanged(tab.id, changed: false)
        statusMessage = L("已保留当前编辑内容，可再次保存覆盖磁盘版本", "Keeping current edits; save again to overwrite the disk version")
    }

    private func externalDiffSummary() -> String {
        if let values = try? tab.fileURL.resourceValues(forKeys: [.fileSizeKey]),
           (values.fileSize ?? 0) > 2 * 1024 * 1024 {
            return L("磁盘版本超过 2 MB，差异摘要已跳过。请重新载入或在系统工具中比较。", "The disk version is over 2 MB, so the inline diff summary was skipped. Reload or compare with an external tool.")
        }
        guard let diskText = try? String(contentsOf: tab.fileURL, encoding: .utf8) else {
            return L("无法读取磁盘版本进行差异比较。", "Could not read the disk version for diff.")
        }
        let currentLines = text.components(separatedBy: .newlines)
        let diskLines = diskText.components(separatedBy: .newlines)
        let maxCount = max(currentLines.count, diskLines.count)
        var output: [String] = [
            L("当前编辑内容：\(currentLines.count) 行", "Current edits: \(currentLines.count) lines"),
            L("磁盘版本：\(diskLines.count) 行", "Disk version: \(diskLines.count) lines"),
            ""
        ]
        var emitted = 0
        for index in 0..<maxCount {
            let current = index < currentLines.count ? currentLines[index] : ""
            let disk = index < diskLines.count ? diskLines[index] : ""
            guard current != disk else { continue }
            output.append("@@ \(index + 1) @@")
            output.append("- \(disk)")
            output.append("+ \(current)")
            emitted += 1
            if emitted >= 20 {
                output.append(L("...只显示前 20 处差异", "...showing first 20 changed lines"))
                break
            }
        }
        if emitted == 0 {
            output.append(L("文本内容一致，可能只有时间戳或权限发生变化。", "Text content matches; only metadata may have changed."))
        }
        return output.joined(separator: "\n")
    }

    private func startExternalChangeWatch() {
        externalWatchTask?.cancel()
        externalWatchTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                checkExternalChange()
            }
        }
    }

    private func checkExternalChange() {
        guard let signature = WorkspaceFileService().diskSignature(for: tab) else { return }
        guard let lastKnownDiskSignature else {
            self.lastKnownDiskSignature = signature
            return
        }
        guard signature != lastKnownDiskSignature else { return }
        externalChangeDetected = true
        model.setWorkspaceFileTabExternallyChanged(tab.id, changed: true)
        statusMessage = isDirty
            ? L("文件已被外部修改，保存已暂停", "File changed outside Conductor; saving paused")
            : L("文件已被外部修改，可重新载入", "File changed outside Conductor; reload available")
        autosaveTask?.cancel()
    }
}

private struct WorkspaceFileSaveRequest: Equatable {
    let generation: Int
    let showStatus: Bool
    let closeAfterSave: Bool
}

struct ConductorCodeEditSourceEditor: View {
    @Binding var text: String
    let fileURL: URL
    let theme: TerminalTheme
    let fontSize: CGFloat
    let focusToken: Int
    var jumpLine: Int?
    var jumpLineToken = 0
    var selectionRange: NSRange?
    var selectionToken = 0
    var snapshotToken = 0
    var isEditable = true
    var onTextSnapshot: (String) -> Void = { _ in }
    @State private var editorState = SourceEditorState()
    @State private var coordinator = ConductorCodeEditSourceEditorCoordinator()

    private var language: CodeLanguage {
        CodeLanguage.detectLanguageFrom(
            url: fileURL,
            prefixBuffer: String(text.prefix(4096)),
            suffixBuffer: String(text.suffix(4096))
        )
    }

    private var configuration: SourceEditorConfiguration {
        SourceEditorConfiguration(
            appearance: .init(
                theme: editorTheme,
                font: NSFont.monospacedSystemFont(ofSize: CGFloat(max(10, min(28, fontSize))), weight: .regular),
                lineHeightMultiple: 1.36,
                wrapLines: true,
                tabWidth: 4
            ),
            behavior: .init(
                isEditable: isEditable,
                isSelectable: true,
                indentOption: .spaces(count: 4)
            ),
            layout: .init(
                editorOverscroll: 0.18,
                contentInsets: NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0),
                additionalTextInsets: NSEdgeInsets(top: 8, left: 0, bottom: 12, right: 0)
            ),
            peripherals: .init(
                showGutter: true,
                showMinimap: true,
                showReformattingGuide: false,
                showFoldingRibbon: true
            )
        )
    }

    private var editorTheme: EditorTheme {
        let foreground = NSColor(theme.shellChromeText)
        let background = NSColor(theme.terminalBackground)
        let muted = NSColor(theme.shellChromeTextMuted)
        let accent = NSColor(theme.floatingEmphasis)
        let selection = NSColor(theme.floatingSelectedFill.opacity(0.95))
        let comment = muted.withAlphaComponent(0.82)
        return EditorTheme(
            text: .init(color: foreground),
            insertionPoint: accent,
            invisibles: .init(color: muted.withAlphaComponent(0.45)),
            background: background,
            lineHighlight: selection.withAlphaComponent(0.20),
            selection: selection,
            keywords: .init(color: accent),
            commands: .init(color: accent),
            types: .init(color: NSColor.systemTeal),
            attributes: .init(color: NSColor.systemPurple),
            variables: .init(color: foreground),
            values: .init(color: NSColor.systemOrange),
            numbers: .init(color: NSColor.systemOrange),
            strings: .init(color: NSColor.systemGreen),
            characters: .init(color: NSColor.systemGreen),
            comments: .init(color: comment, italic: true)
        )
    }

    var body: some View {
        SourceEditor(
            $text,
            language: language,
            configuration: configuration,
            state: $editorState,
            coordinators: [coordinator]
        )
        .background(Color(nsColor: editorTheme.background))
        .clipped()
        .onAppear {
            editorState.findPanelVisible = false
            if focusToken > 0 {
                coordinator.focus()
            }
        }
        .onChange(of: focusToken) {
            coordinator.focus()
        }
        .onChange(of: jumpLineToken) {
            if let jumpLine {
                coordinator.selectLine(jumpLine)
            }
        }
        .onChange(of: selectionToken) {
            if let selectionRange {
                coordinator.selectRange(selectionRange)
            }
        }
        .onChange(of: snapshotToken) {
            onTextSnapshot(coordinator.currentText(fallback: text))
        }
    }
}

@MainActor
private final class ConductorCodeEditSourceEditorCoordinator: NSObject, @preconcurrency TextViewCoordinator {
    private weak var controller: TextViewController?
    private var pendingFocus = false

    func prepareCoordinator(controller: TextViewController) {
        self.controller = controller
        constrainLoadedEditorToBounds(controller)
        if pendingFocus {
            pendingFocus = false
            focus()
        }
    }

    func controllerDidAppear(controller: TextViewController) {
        self.controller = controller
        constrainLoadedEditorToBounds(controller)
    }

    func textViewDidChangeSelection(controller: TextViewController, newPositions: [CursorPosition]) {
        self.controller = controller
    }

    func textViewDidChangeText(controller: TextViewController) {
        self.controller = controller
    }

    func destroy() {
        controller = nil
    }

    func focus() {
        guard let controller else {
            pendingFocus = true
            return
        }
        controller.view.window?.makeFirstResponder(controller.textView)
    }

    func selectLine(_ line: Int) {
        guard let controller else { return }
        controller.setCursorPositions([CursorPosition(line: max(1, line), column: 1)], scrollToVisible: true)
        controller.view.window?.makeFirstResponder(controller.textView)
    }

    func selectRange(_ range: NSRange) {
        guard let controller else { return }
        controller.setCursorPositions([CursorPosition(range: range)], scrollToVisible: true)
        controller.view.window?.makeFirstResponder(controller.textView)
    }

    func currentText(fallback: String) -> String {
        controller?.text ?? fallback
    }

    private func constrainLoadedEditorToBounds(_ controller: TextViewController) {
        guard controller.isViewLoaded else { return }
        let views: [NSView] = [
            controller.view,
            controller.scrollView,
            controller.scrollView.contentView,
            controller.scrollView.documentView
        ].compactMap { $0 }

        for view in views {
            view.clipsToBounds = true
            view.wantsLayer = true
            view.layer?.masksToBounds = true
        }
    }
}
