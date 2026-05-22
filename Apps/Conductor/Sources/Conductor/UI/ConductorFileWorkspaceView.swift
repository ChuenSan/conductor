import AppKit
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
    case message(String)
    case editableText(String)
}

private enum WorkspaceMarkdownMode: String, CaseIterable, Identifiable {
    case source
    case preview
    case split

    var id: String { rawValue }

    var title: String {
        switch self {
        case .source: L("源码", "Source")
        case .preview: L("预览", "Preview")
        case .split: L("分屏", "Split")
        }
    }

    var systemImage: String {
        switch self {
        case .source: "chevron.left.forwardslash.chevron.right"
        case .preview: "doc.richtext"
        case .split: "rectangle.split.2x1"
        }
    }
}

private struct WorkspaceFileDocument: Equatable {
    let title: String
    let subtitle: String
    let isReadOnly: Bool
    let state: WorkspaceFileDocumentState
}

private struct WorkspaceFileLoadResult: Equatable {
    let document: WorkspaceFileDocument
    let diskSignature: WorkspaceFileDiskSignature?
}

private struct WorkspaceFileDiskSignature: Equatable {
    let modificationDate: Date?
    let byteCount: Int64
}

private struct WorkspaceFileService {
    private let maxEditableBytes = 20 * 1024 * 1024

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

        let byteCount = Int64(values.fileSize ?? 0)
        guard byteCount <= maxEditableBytes else {
            return WorkspaceFileDocument(
                title: tab.title,
                subtitle: subtitle,
                isReadOnly: true,
                state: .message(L("文件较大，已停止加载到编辑器以保护性能", "Large file was not loaded into the editor to protect performance"))
            )
        }

        if let data = try? Data(contentsOf: fileURL),
           !data.contains(0) {
            let loadedText = String(data: data, encoding: .utf8) ??
                String(data: data, encoding: .utf16) ??
                String(decoding: data, as: UTF8.self)
            return WorkspaceFileDocument(
                title: tab.title,
                subtitle: subtitle,
                isReadOnly: values.isWritable == false,
                state: .editableText(loadedText)
            )
        }

        return WorkspaceFileDocument(
            title: tab.title,
            subtitle: subtitle,
            isReadOnly: true,
            state: .message(L("由统一文档查看器打开", "Opened by the unified document viewer"))
        )
    }

    func loadResult(for tab: ConductorWorkspaceFileTab) -> WorkspaceFileLoadResult {
        WorkspaceFileLoadResult(
            document: document(for: tab),
            diskSignature: diskSignature(for: tab)
        )
    }

    func loadingDocument(for tab: ConductorWorkspaceFileTab) -> WorkspaceFileDocument {
        WorkspaceFileDocument(
            title: tab.title,
            subtitle: relativePath(for: tab.fileURL.standardizedFileURL, rootURL: tab.rootURL),
            isReadOnly: true,
            state: .message(L("正在读取文件", "Loading file"))
        )
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
                ConductorWorkspaceFileEditorView(model: model, tab: selected, isSelected: true)
                    .environment(\.workspaceFileSearchFocusToken, model.workspaceFileSearchFocusGeneration)
                    .environment(\.workspaceFileSearchNextToken, model.workspaceFileSearchNextGeneration)
                    .environment(\.workspaceFileSearchPreviousToken, model.workspaceFileSearchPreviousGeneration)
                    .id(selected.id)
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
    let model: ConductorWindowModel
    let tab: ConductorWorkspaceFileTab
    let isSelected: Bool
    @State private var document: WorkspaceFileDocument
    @State private var text: String
    @State private var savedText: String
    @State private var textMetrics: WorkspaceTextMetrics
    @State private var statusMessage: String?
    @State private var editorFocusToken = 1
    @State private var editorSnapshotToken = 0
    @State private var autosaveTask: Task<Void, Never>?
    @State private var externalWatchTask: Task<Void, Never>?
    @State private var searchTask: Task<Void, Never>?
    @State private var saveGeneration = 0
    @State private var loadGeneration = 0
    @State private var diffGeneration = 0
    @State private var pendingSaveRequest: WorkspaceFileSaveRequest?
    @State private var lastKnownDiskSignature: WorkspaceFileDiskSignature?
    @State private var externalChangeDetected = false
    @State private var externalDiffVisible = false
    @State private var externalDiffState: WorkspaceFileDiffState = .idle
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
    @State private var searchGeneration = 0
    @State private var searchPending = false
    @State private var sourceSelectionRange: NSRange?
    @State private var sourceSelectionToken = 0
    @State private var documentSearchStatus = "0/0"
    @State private var documentSearchRevision = 0
    @State private var documentSearchNextToken = 0
    @State private var documentSearchPreviousToken = 0
    @State private var markdownMode: WorkspaceMarkdownMode = .split
    @State private var markdownPreviewText = ""
    @State private var markdownPreviewUpdateTask: Task<Void, Never>?

    init(model: ConductorWindowModel, tab: ConductorWorkspaceFileTab, isSelected: Bool) {
        self.model = model
        self.tab = tab
        self.isSelected = isSelected
        let loaded = WorkspaceFileService().loadingDocument(for: tab)
        _document = State(initialValue: loaded)
        _text = State(initialValue: "")
        _savedText = State(initialValue: "")
        _textMetrics = State(initialValue: .empty)
        _lastKnownDiskSignature = State(initialValue: nil)
        _searchHistory = State(initialValue: [])
    }

    private var isDirty: Bool {
        text != savedText
    }

    private var canEditText: Bool {
        if case .editableText = document.state { return true }
        return false
    }

    private var canSaveText: Bool {
        canEditText && !document.isReadOnly
    }

    private var canEditSourceText: Bool {
        canSaveText && !usesProtectedTextReader
    }

    private var isMarkdown: Bool {
        let ext = tab.fileURL.pathExtension.lowercased()
        return ext == "md" || ext == "markdown"
    }

    private var isLogLikeFile: Bool {
        let ext = tab.fileURL.pathExtension.lowercased()
        return ["log", "out", "stdout", "stderr", "trace"].contains(ext)
    }

    private var isLargeText: Bool {
        guard canEditText else { return false }
        return textMetrics.byteCount > Self.protectedTextReaderByteThreshold ||
            textMetrics.lineCount > Self.protectedTextReaderLineThreshold
    }

    private var usesProtectedTextReader: Bool {
        canEditText && (isLogLikeFile || isLargeText)
    }

    private var usesDocumentSearch: Bool {
        isMarkdown && canEditText && markdownMode != .source
    }

    private var isSourceEditorMounted: Bool {
        canEditText && (!isMarkdown || markdownMode != .preview)
    }

    private var supportsFileSearch: Bool {
        canEditText
    }

    private var isImageFile: Bool {
        let ext = tab.fileURL.pathExtension.lowercased()
        if Self.imageFileExtensions.contains(ext) { return true }
        guard let type = UTType(filenameExtension: ext) else { return false }
        return type.conforms(to: .image)
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
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(theme.terminalBackground)
        .task(id: tab.id) {
            await loadDocument(resetDirty: true)
        }
        .onAppear {
            model.setWorkspaceFileTabDirty(tab.id, isDirty: isDirty)
            model.setWorkspaceFileTabExternallyChanged(tab.id, changed: externalChangeDetected)
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
            textMetrics = Self.metrics(for: text)
            scheduleAutosave()
            refreshSearchMatches(resetSelection: false)
            scheduleMarkdownPreviewRefresh()
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
            documentSearchRevision &+= 1
            refreshSearchMatches(resetSelection: true)
        }
        .onDisappear {
            autosaveTask?.cancel()
            externalWatchTask?.cancel()
            searchTask?.cancel()
            markdownPreviewUpdateTask?.cancel()
            if isDirty, canEditSourceText, !externalChangeDetected {
                saveGeneration += 1
                requestSaveSnapshot(generation: saveGeneration, showStatus: false, closeAfterSave: false)
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

            statusPill(systemImage: isImageFile ? "photo" : "doc.text.magnifyingglass", title: fileKindTitle)
            if externalChangeDetected {
                statusPill(systemImage: "arrow.triangle.2.circlepath", title: L("外部已修改", "Changed externally"))
            }

            if supportsFileSearch && (searchVisible || !searchQuery.isEmpty) {
                fileSearchField
            }

            editorButton("arrow.clockwise", help: L("重新载入", "Reload")) {
                reload()
            }

            if canEditText {
                if isMarkdown {
                    Picker("", selection: $markdownMode) {
                        ForEach(WorkspaceMarkdownMode.allCases) { mode in
                            Label(mode.title, systemImage: mode.systemImage)
                                .tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 190)
                    .onChange(of: markdownMode) { _, newValue in
                        if newValue == .source || newValue == .split {
                            editorFocusToken &+= 1
                        }
                    }
                }
                if canEditSourceText {
                    editorButton("square.and.arrow.down", help: L("保存", "Save")) {
                        save()
                    }
                }
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
                    toggleExternalDiff()
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
                    Text(externalDiffText)
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

    private var externalDiffText: String {
        switch externalDiffState {
        case .idle:
            L("准备比较磁盘版本", "Preparing disk comparison")
        case .loading:
            L("正在比较磁盘版本", "Comparing disk version")
        case .ready(let text):
            text
        }
    }

    private func toggleExternalDiff() {
        externalDiffVisible.toggle()
        guard externalDiffVisible else { return }
        loadExternalDiff()
    }

    @ViewBuilder
    private var content: some View {
        if isImageFile {
            imageView(tab.fileURL)
        } else if isMarkdown, canEditText {
            markdownContent
        } else if canEditText {
            sourceEditor
        } else {
            messageView(
                systemImage: "doc.text.magnifyingglass",
                title: fileKindTitle,
                message: documentMessage
            )
        }
    }

    private var sourceEditor: some View {
        ConductorWorkspaceSourceTextView(
            text: $text,
            isEditable: canEditSourceText,
            focusToken: editorFocusToken,
            allowsFocusRequests: !searchVisible,
            selectionRange: sourceSelectionRange,
            selectionToken: sourceSelectionToken,
            snapshotToken: editorSnapshotToken,
            fontSize: model.appearance.terminalFontSize,
            backgroundColor: NSColor(theme.terminalBackground),
            textColor: NSColor(theme.shellChromeText),
            mutedTextColor: NSColor(theme.shellChromeTextMuted),
            onSnapshot: handleEditorSnapshot
        )
        .background(theme.terminalBackground)
    }

    @ViewBuilder
    private var markdownContent: some View {
        switch markdownMode {
        case .source:
            sourceEditor
        case .preview:
            documentPreview(textOverride: markdownPreviewText)
        case .split:
            HSplitView {
                sourceEditor
                    .frame(minWidth: 280, maxWidth: .infinity, maxHeight: .infinity)
                documentPreview(textOverride: markdownPreviewText)
                    .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func documentPreview(textOverride: String?) -> some View {
        ConductorDocumentWorkspaceView(
            fileURL: tab.fileURL,
            rootURL: tab.rootURL,
            title: tab.title,
            theme: theme,
            fontSize: model.appearance.terminalFontSize,
            isActive: isSelected,
            textOverride: textOverride,
            chromeStyle: .plain,
            layoutRevision: model.workspaceFileLayoutRevision,
            searchQuery: searchVisible ? searchQuery : "",
            searchRevision: documentSearchRevision,
            searchNextToken: documentSearchNextToken,
            searchPreviousToken: documentSearchPreviousToken,
            onSearchStatusChange: { status in
                documentSearchStatus = status
            }
        )
    }

    private var fileSearchField: some View {
        EmptyView()
    }

    private var searchStatus: String {
        if usesDocumentSearch { return documentSearchStatus }
        if searchPending { return L("搜索中", "Searching") }
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

    private var fileKindTitle: String {
        switch tab.fileURL.pathExtension.lowercased() {
        case let ext where Self.imageFileExtensions.contains(ext):
            L("图片预览", "Image Preview")
        case "md", "markdown", "mdown", "mkd":
            L("Markdown 阅读", "Markdown Reader")
        case "log", "out", "stdout", "stderr", "trace":
            L("日志阅读", "Log Reader")
        case "tex", "latex", "sty", "cls", "bib":
            L("TeX 阅读", "TeX Reader")
        case "json", "jsonl":
            "JSON"
        case "csv", "tsv", "tab":
            L("表格", "Table")
        default:
            L("文档阅读", "Document Reader")
        }
    }

    private var documentMessage: String {
        if case .message(let message) = document.state {
            return message
        }
        return L("这个文件不能作为文本编辑", "This file cannot be edited as text")
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

    private static let imageFileExtensions: Set<String> = [
        "apng", "avif", "bmp", "gif", "heic", "heif", "ico", "jpeg", "jpg", "png",
        "psd", "svg", "tif", "tiff", "webp"
    ]

    private func showSearch() {
        searchVisible = true
        documentSearchRevision &+= 1
    }

    private func closeSearch() {
        recordSearchQuery()
        searchVisible = false
        searchQuery = ""
        documentSearchStatus = "0/0"
        documentSearchRevision &+= 1
        sourceSelectionRange = nil
    }

    private func moveSearchSelection(_ delta: Int) {
        searchVisible = true
        if usesDocumentSearch {
            if delta < 0 {
                documentSearchPreviousToken &+= 1
            } else {
                documentSearchNextToken &+= 1
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
        guard !matches.isEmpty, matches.indices.contains(selectedSearchIndex) else {
            sourceSelectionRange = nil
            return
        }
        sourceSelectionRange = matches[selectedSearchIndex]
        sourceSelectionToken &+= 1
    }

    private func refreshSearchMatches(resetSelection: Bool) {
        guard !usesDocumentSearch else {
            searchTask?.cancel()
            searchPending = false
            cachedSearchMatches = []
            selectedSearchIndex = 0
            sourceSelectionRange = nil
            return
        }
        guard canEditText else {
            searchTask?.cancel()
            searchPending = false
            cachedSearchMatches = []
            selectedSearchIndex = 0
            sourceSelectionRange = nil
            return
        }

        let needle = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else {
            searchTask?.cancel()
            searchPending = false
            cachedSearchMatches = []
            selectedSearchIndex = 0
            sourceSelectionRange = nil
            return
        }

        searchTask?.cancel()
        searchGeneration += 1
        let generation = searchGeneration
        let snapshot = text
        searchPending = true
        searchTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(resetSelection ? 80 : 160))
            guard !Task.isCancelled else { return }
            let matches = await Task.detached(priority: .userInitiated) {
                Self.searchMatches(in: snapshot, query: needle, maxMatches: 20_000)
            }.value
            guard generation == searchGeneration else { return }
            searchPending = false
            cachedSearchMatches = matches
            if resetSelection {
                selectedSearchIndex = 0
            } else if selectedSearchIndex >= cachedSearchMatches.count {
                selectedSearchIndex = max(0, cachedSearchMatches.count - 1)
            }
            selectCurrentSearchMatch()
        }
    }

    nonisolated private static func searchMatches(in text: String, query: String, maxMatches: Int = .max) -> [NSRange] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return [] }
        let haystack = text as NSString
        var matches: [NSRange] = []
        var range = NSRange(location: 0, length: haystack.length)
        while range.location < haystack.length {
            let match = haystack.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive], range: range)
            guard match.location != NSNotFound else { break }
            matches.append(match)
            if matches.count >= maxMatches { break }
            let nextLocation = match.location + max(match.length, 1)
            range = NSRange(location: nextLocation, length: haystack.length - nextLocation)
        }
        return matches
    }

    private func recordSearchQuery() {
        searchHistory = []
    }

    private func save(showStatus: Bool = true, closeAfterSave: Bool = false) {
        guard canEditSourceText else {
            statusMessage = usesProtectedTextReader
                ? L("大文本已使用轻量阅读，未进入编辑器", "Large text is using the lightweight reader, not the editor")
                : L("当前文件不能保存", "Current file cannot be saved")
            return
        }
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
        requestSaveSnapshot(generation: saveGeneration, showStatus: showStatus, closeAfterSave: closeAfterSave)
    }

    private func scheduleAutosave() {
        autosaveTask?.cancel()
        guard isDirty, canEditSourceText, !externalChangeDetected else { return }

        let generation = saveGeneration + 1
        saveGeneration = generation
        autosaveTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            saveSnapshot(text, generation: generation, showStatus: false, closeAfterSave: false)
        }
    }

    private func requestSaveSnapshot(generation: Int, showStatus: Bool, closeAfterSave: Bool) {
        guard isSourceEditorMounted else {
            saveSnapshot(text, generation: generation, showStatus: showStatus, closeAfterSave: closeAfterSave)
            return
        }
        pendingSaveRequest = WorkspaceFileSaveRequest(
            generation: generation,
            showStatus: showStatus,
            closeAfterSave: closeAfterSave
        )
        editorSnapshotToken &+= 1
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
                Result {
                    try WorkspaceFileService().save(snapshot, to: tab)
                    return WorkspaceFileService().diskSignature(for: tab)
                }
            }.value
            guard generation == saveGeneration else { return }
            switch result {
            case .success(let signature):
                text = snapshot
                savedText = snapshot
                lastKnownDiskSignature = signature
                externalChangeDetected = false
                externalDiffState = .idle
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
        Task {
            await loadDocument(resetDirty: true)
        }
    }

    private func loadDocument(resetDirty: Bool) async {
        autosaveTask?.cancel()
        searchTask?.cancel()
        loadGeneration += 1
        let generation = loadGeneration
        let tab = tab
        statusMessage = L("正在读取文件", "Loading file")
        let result = await Task.detached(priority: .userInitiated) {
            WorkspaceFileService().loadResult(for: tab)
        }.value
        guard generation == loadGeneration else { return }
        applyLoadedDocument(result, resetDirty: resetDirty)
    }

    private func applyLoadedDocument(_ result: WorkspaceFileLoadResult, resetDirty: Bool) {
        document = result.document
        lastKnownDiskSignature = result.diskSignature
        externalChangeDetected = false
        externalDiffVisible = false
        externalDiffState = .idle
        switch result.document.state {
        case .editableText(let loadedText):
            text = loadedText
            textMetrics = Self.metrics(for: loadedText)
            markdownPreviewText = loadedText
            if resetDirty {
                savedText = loadedText
            }
        case .message:
            text = ""
            textMetrics = .empty
            markdownPreviewText = ""
            if resetDirty {
                savedText = ""
            }
        }
        markdownMode = isMarkdown && canEditText ? .split : markdownMode
        refreshSearchMatches(resetSelection: true)
        model.setWorkspaceFileTabDirty(tab.id, isDirty: false)
        model.setWorkspaceFileTabExternallyChanged(tab.id, changed: false)
        statusMessage = nil
        startExternalChangeWatch()
    }

    private func keepCurrentVersionAfterExternalChange() {
        let tab = tab
        Task {
            lastKnownDiskSignature = await Task.detached(priority: .utility) {
                WorkspaceFileService().diskSignature(for: tab)
            }.value
        }
        externalChangeDetected = false
        externalDiffVisible = false
        externalDiffState = .idle
        model.setWorkspaceFileTabExternallyChanged(tab.id, changed: false)
        statusMessage = L("已保留当前编辑内容，可再次保存覆盖磁盘版本", "Keeping current edits; save again to overwrite the disk version")
    }

    private func loadExternalDiff() {
        diffGeneration += 1
        let generation = diffGeneration
        let tab = tab
        let snapshot = text
        externalDiffState = .loading
        Task {
            let summary = await Task.detached(priority: .utility) {
                Self.externalDiffSummary(tab: tab, currentText: snapshot)
            }.value
            guard generation == diffGeneration else { return }
            externalDiffState = .ready(summary)
        }
    }

    nonisolated private static func externalDiffSummary(tab: ConductorWorkspaceFileTab, currentText text: String) -> String {
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
                await checkExternalChange()
            }
        }
    }

    private func checkExternalChange() async {
        let tab = tab
        guard let signature = await Task.detached(priority: .utility, operation: {
            WorkspaceFileService().diskSignature(for: tab)
        }).value else { return }
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

    private func scheduleMarkdownPreviewRefresh() {
        guard isMarkdown else { return }
        markdownPreviewUpdateTask?.cancel()
        let snapshot = text
        markdownPreviewUpdateTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            markdownPreviewText = snapshot
        }
    }

    nonisolated private static let protectedTextReaderByteThreshold = 1_500_000
    nonisolated private static let protectedTextReaderLineThreshold = 20_000

    nonisolated private static func metrics(for text: String) -> WorkspaceTextMetrics {
        var count = 1
        for scalar in text.unicodeScalars where CharacterSet.newlines.contains(scalar) {
            count += 1
            if count > protectedTextReaderLineThreshold {
                return WorkspaceTextMetrics(byteCount: text.utf8.count, lineCount: count)
            }
        }
        return WorkspaceTextMetrics(byteCount: text.utf8.count, lineCount: count)
    }
}

private struct WorkspaceTextMetrics: Equatable {
    let byteCount: Int
    let lineCount: Int

    static let empty = WorkspaceTextMetrics(byteCount: 0, lineCount: 0)
}

private struct WorkspaceFileSaveRequest: Equatable {
    let generation: Int
    let showStatus: Bool
    let closeAfterSave: Bool
}

private enum WorkspaceFileDiffState: Equatable {
    case idle
    case loading
    case ready(String)
}

private struct ConductorWorkspaceSourceTextView: NSViewRepresentable {
    @Binding var text: String
    let isEditable: Bool
    let focusToken: Int
    let allowsFocusRequests: Bool
    let selectionRange: NSRange?
    let selectionToken: Int
    let snapshotToken: Int
    let fontSize: CGFloat
    let backgroundColor: NSColor
    let textColor: NSColor
    let mutedTextColor: NSColor
    let onSnapshot: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSnapshot: onSnapshot)
    }

    func makeNSView(context: Context) -> SourceTextScrollView {
        let scrollView = SourceTextScrollView()
        scrollView.drawsBackground = true
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.scrollerStyle = .overlay

        let textView = SourceTextView(frame: scrollView.bounds)
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.importsGraphics = false
        textView.usesFontPanel = false
        textView.allowsUndo = true
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
        textView.textContainerInset = NSSize(width: 18, height: 14)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        scrollView.documentView = textView
        context.coordinator.textView = textView
        context.coordinator.applyText(text, to: textView)
        context.coordinator.applyConfiguration(
            to: textView,
            scrollView: scrollView,
            isEditable: isEditable,
            fontSize: fontSize,
            backgroundColor: backgroundColor,
            textColor: textColor,
            insertionPointColor: mutedTextColor
        )
        return scrollView
    }

    func updateNSView(_ scrollView: SourceTextScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.onSnapshot = onSnapshot
        context.coordinator.applyConfiguration(
            to: textView,
            scrollView: scrollView,
            isEditable: isEditable,
            fontSize: fontSize,
            backgroundColor: backgroundColor,
            textColor: textColor,
            insertionPointColor: mutedTextColor
        )
        let isSnapshotRequest = context.coordinator.lastSnapshotToken != snapshotToken
        if isSnapshotRequest {
            context.coordinator.lastSnapshotToken = snapshotToken
            context.coordinator.flushAndReportSnapshot(from: textView)
        } else if textView.string != text {
            context.coordinator.applyText(text, to: textView)
        }
        if allowsFocusRequests, context.coordinator.lastFocusToken != focusToken {
            context.coordinator.lastFocusToken = focusToken
            textView.window?.makeFirstResponder(textView)
        }
        if context.coordinator.lastSelectionToken != selectionToken {
            context.coordinator.lastSelectionToken = selectionToken
            if let selectionRange, NSMaxRange(selectionRange) <= (textView.string as NSString).length {
                textView.setSelectedRange(selectionRange)
                textView.scrollRangeToVisible(selectionRange)
            }
        }
    }

    static func dismantleNSView(_ scrollView: SourceTextScrollView, coordinator: Coordinator) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        coordinator.flushAndReportSnapshot(from: textView)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        private let text: Binding<String>
        var onSnapshot: (String) -> Void
        weak var textView: NSTextView?
        var lastFocusToken = 0
        var lastSelectionToken = 0
        var lastSnapshotToken = 0
        private var isApplyingProgrammaticChange = false
        private var lastConfiguration: Configuration?
        private var pendingTextUpdateTask: Task<Void, Never>?
        private var pendingText: String?

        init(text: Binding<String>, onSnapshot: @escaping (String) -> Void) {
            self.text = text
            self.onSnapshot = onSnapshot
        }

        @MainActor
        func textDidChange(_ notification: Notification) {
            guard !isApplyingProgrammaticChange,
                  let textView = notification.object as? NSTextView else {
                return
            }
            scheduleTextUpdate(textView.string)
        }

        @MainActor
        func applyText(_ newText: String, to textView: NSTextView) {
            pendingTextUpdateTask?.cancel()
            pendingText = nil
            isApplyingProgrammaticChange = true
            let selectedRange = textView.selectedRange()
            textView.string = newText
            let maxLength = (newText as NSString).length
            if selectedRange.location <= maxLength {
                textView.setSelectedRange(NSRange(location: selectedRange.location, length: min(selectedRange.length, maxLength - selectedRange.location)))
            }
            isApplyingProgrammaticChange = false
        }

        @MainActor
        func flushAndReportSnapshot(from textView: NSTextView) {
            let snapshot = textView.string
            commitTextUpdate(snapshot)
            onSnapshot(snapshot)
        }

        @MainActor
        func applyConfiguration(
            to textView: NSTextView,
            scrollView: NSScrollView,
            isEditable: Bool,
            fontSize: CGFloat,
            backgroundColor: NSColor,
            textColor: NSColor,
            insertionPointColor: NSColor
        ) {
            let configuration = Configuration(
                isEditable: isEditable,
                fontSize: fontSize,
                backgroundColor: backgroundColor,
                textColor: textColor,
                insertionPointColor: insertionPointColor
            )
            guard configuration != lastConfiguration else { return }
            lastConfiguration = configuration
            scrollView.backgroundColor = backgroundColor
            textView.backgroundColor = backgroundColor
            textView.textColor = textColor
            textView.insertionPointColor = insertionPointColor
            textView.isEditable = isEditable
            textView.isSelectable = true
            (textView as? SourceTextView)?.usesInputCursor = isEditable
            textView.window?.invalidateCursorRects(for: textView)
            textView.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        }

        private struct Configuration: Equatable {
            let isEditable: Bool
            let fontSize: CGFloat
            let backgroundColor: NSColor
            let textColor: NSColor
            let insertionPointColor: NSColor
        }

        @MainActor
        private func scheduleTextUpdate(_ snapshot: String) {
            pendingText = snapshot
            pendingTextUpdateTask?.cancel()
            pendingTextUpdateTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(90))
                guard !Task.isCancelled else { return }
                guard let pendingText else { return }
                commitTextUpdate(pendingText)
            }
        }

        @MainActor
        private func commitTextUpdate(_ snapshot: String) {
            pendingTextUpdateTask?.cancel()
            pendingTextUpdateTask = nil
            pendingText = nil
            guard text.wrappedValue != snapshot else { return }
            text.wrappedValue = snapshot
        }
    }
}

private final class SourceTextView: NSTextView {
    var usesInputCursor = true {
        didSet {
            guard usesInputCursor != oldValue else { return }
            window?.invalidateCursorRects(for: self)
            (usesInputCursor ? NSCursor.iBeam : NSCursor.arrow).set()
        }
    }

    override func resetCursorRects() {
        addCursorRect(visibleRect, cursor: usesInputCursor ? .iBeam : .arrow)
    }

    override func cursorUpdate(with event: NSEvent) {
        (usesInputCursor ? NSCursor.iBeam : NSCursor.arrow).set()
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        NSCursor.arrow.set()
    }
}

private final class SourceTextScrollView: NSScrollView {
    override func viewWillStartLiveResize() {
        super.viewWillStartLiveResize()
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        documentView?.layerContentsRedrawPolicy = .onSetNeedsDisplay
    }

    override func viewDidEndLiveResize() {
        super.viewDidEndLiveResize()
        layerContentsRedrawPolicy = .duringViewResize
        documentView?.layerContentsRedrawPolicy = .duringViewResize
        documentView?.needsDisplay = true
    }
}
