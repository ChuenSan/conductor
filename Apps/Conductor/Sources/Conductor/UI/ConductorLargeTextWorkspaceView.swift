import AppKit
import SwiftUI

private func L(_ zh: String, _ en: String) -> String {
    ConductorLocalization.text(zh: zh, en: en)
}

struct WorkspaceLargeTextDocument: Equatable {
    let fileURL: URL
    let byteCount: Int64
    let formatTitle: String
    let formatSystemImage: String
    let reason: String
    let extractsOutline: Bool
}

struct WorkspaceLargeTextHeading: Equatable, Identifiable {
    var id: String { "\(line)-\(level)-\(title)" }
    let line: Int
    let level: Int
    let title: String
}

struct ConductorLargeTextWorkspaceView: View {
    let document: WorkspaceLargeTextDocument
    let theme: TerminalTheme
    let fontSize: CGFloat
    let searchQuery: String
    let searchNextToken: Int
    let searchPreviousToken: Int
    let onSearchStatus: (String) -> Void
    var isActive = true

    @StateObject private var model = ConductorLargeTextViewModel()
    @State private var outlineVisible = true
    @State private var jumpLine: Int?
    @State private var jumpLineToken = 0
    @State private var jumpLineText = ""
    @State private var jumpLinePopoverVisible = false
    @State private var operationMessage: String?
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorFontFamily) private var fontFamily

    var body: some View {
        VStack(spacing: 0) {
            statusBar
            HStack(spacing: 0) {
                ConductorLargeTextViewport(
                    document: document,
                    theme: theme,
                    fontSize: fontSize,
                    searchQuery: searchQuery,
                    searchNextToken: searchNextToken,
                    searchPreviousToken: searchPreviousToken,
                    jumpLine: jumpLine,
                    jumpLineToken: jumpLineToken,
                    onMetrics: model.applyMetrics,
                    onHeadings: model.applyHeadings,
                    onSearchStatus: model.applySearchStatus
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if outlineVisible && !model.headings.isEmpty {
                    Rectangle()
                        .fill(theme.terminalOuterStroke.opacity(theme.usesDarkChrome ? 0.26 : 0.16))
                        .frame(width: 1)
                    outline
                        .frame(width: 228)
                }
            }
        }
        .onAppear {
            onSearchStatus(model.searchStatus)
        }
        .onChange(of: model.searchStatus) { _, value in
            onSearchStatus(value)
        }
        .background {
            ConductorKeyboardShortcutBridge(autofocus: isActive) { event in
                handleKeyboardShortcut(event)
            }
            .frame(width: 0, height: 0)
        }
    }

    private var statusBar: some View {
        HStack(spacing: 7) {
            statusPill(systemImage: document.formatSystemImage, title: document.formatTitle)
            statusPill(systemImage: "speedometer", title: L("大文件模式", "Large File Mode"))
            statusPill(systemImage: "doc.text", title: ByteCountFormatter.string(fromByteCount: document.byteCount, countStyle: .file))
            statusPill(systemImage: "number", title: model.lineStatus)
            Text(document.reason)
                .font(.conductorSystem(size: 10.5, weight: .semibold, family: fontFamily, scale: fontScale))
                .foregroundStyle(theme.shellChromeText.opacity(0.48))
                .lineLimit(1)
                .truncationMode(.tail)
            if let operationMessage {
                Text(operationMessage)
                    .font(.conductorSystem(size: 10.5, weight: .semibold, family: fontFamily, scale: fontScale))
                    .foregroundStyle(theme.shellChromeText.opacity(0.48))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            iconButton("number", help: L("跳转到行 Cmd-L", "Go to Line Cmd-L")) {
                jumpLineText = ""
                jumpLinePopoverVisible = true
            }
            .popover(isPresented: $jumpLinePopoverVisible, arrowEdge: .bottom) {
                jumpLinePopover
            }
            .keyboardShortcut("l", modifiers: .command)

            iconButton("doc.on.doc", help: L("复制路径 Cmd-Opt-C", "Copy Path Cmd-Opt-C")) {
                copy(document.fileURL.path, message: L("已复制路径", "Path copied"))
            }
            .keyboardShortcut("c", modifiers: [.command, .option])

            iconButton("arrow.up.right.square", help: L("系统应用打开 Cmd-O", "Open in System App Cmd-O")) {
                NSWorkspace.shared.open(document.fileURL)
            }
            .keyboardShortcut("o", modifiers: .command)

            iconButton("folder", help: L("在 Finder 中显示 Cmd-Opt-R", "Reveal in Finder Cmd-Opt-R")) {
                NSWorkspace.shared.activateFileViewerSelecting([document.fileURL])
            }
            .keyboardShortcut("r", modifiers: [.command, .option])

            if !model.headings.isEmpty {
                Button {
                    outlineVisible.toggle()
                } label: {
                    Image(systemName: "list.bullet.indent")
                        .font(.conductorSystem(size: 11.5, weight: .semibold, family: fontFamily, scale: fontScale))
                        .frame(width: 28, height: 24)
                        .foregroundStyle(theme.shellChromeText.opacity(outlineVisible ? 0.82 : 0.50))
                        .background(outlineVisible ? theme.floatingSelectedFill.opacity(0.58) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)
                .macNativeTooltip(L("大纲 Cmd-B", "Outline Cmd-B"))
                .keyboardShortcut("b", modifiers: .command)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(theme.terminalChrome.opacity(theme.usesDarkChrome ? 0.50 : 0.22))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(theme.terminalOuterStroke.opacity(theme.usesDarkChrome ? 0.30 : 0.16))
                .frame(height: 1)
        }
    }

    private var jumpLinePopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("跳转到行", "Go to Line"))
                .font(.conductorSystem(size: 12.5, weight: .semibold, family: fontFamily, scale: fontScale))
            TextField(L("行号", "Line"), text: $jumpLineText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 160)
                .onSubmit {
                    commitJumpLine()
                }
            HStack(spacing: 8) {
                Button(L("取消", "Cancel")) {
                    jumpLinePopoverVisible = false
                }
                Button(L("跳转", "Go")) {
                    commitJumpLine()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(14)
    }

    private var outline: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: "list.bullet.indent")
                    .font(.conductorSystem(size: 11, weight: .semibold, family: fontFamily, scale: fontScale))
                Text(L("大纲", "Outline"))
                    .font(.conductorSystem(size: 11.5, weight: .bold, family: fontFamily, scale: fontScale))
                Spacer(minLength: 0)
            }
            .foregroundStyle(theme.shellChromeText.opacity(0.74))
            .padding(.horizontal, 12)
            .frame(height: 38)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(model.headings) { heading in
                        Button {
                            jumpLine = heading.line
                            jumpLineToken &+= 1
                        } label: {
                            HStack(spacing: 6) {
                                Text("H\(heading.level)")
                                    .font(.conductorSystem(size: 9.5, weight: .bold, family: fontFamily, scale: fontScale))
                                    .foregroundStyle(theme.shellChromeText.opacity(0.42))
                                    .frame(width: 18, alignment: .leading)
                                Text(heading.title)
                                    .font(.conductorSystem(size: 11.2, weight: .medium, family: fontFamily, scale: fontScale))
                                    .foregroundStyle(theme.shellChromeText.opacity(0.70))
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                            .padding(.leading, CGFloat(max(0, heading.level - 1)) * 9)
                            .padding(.horizontal, 9)
                            .frame(height: 28, alignment: .leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 7)
                .padding(.bottom, 10)
            }
        }
        .background(theme.terminalChrome.opacity(theme.usesDarkChrome ? 0.28 : 0.14))
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
        .background(theme.shellControlFill.opacity(theme.usesDarkChrome ? 0.34 : 0.18))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private func iconButton(_ systemImage: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.conductorSystem(size: 11.5, weight: .semibold, family: fontFamily, scale: fontScale))
                .foregroundStyle(theme.shellChromeText.opacity(0.66))
                .frame(width: 28, height: 24)
                .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .macNativeTooltip(help)
    }

    private func commitJumpLine() {
        let trimmed = jumpLineText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let line = Int(trimmed), line > 0 else {
            operationMessage = L("请输入有效行号", "Enter a valid line number")
            NSSound.beep()
            return
        }
        jumpLine = line
        jumpLineToken &+= 1
        jumpLinePopoverVisible = false
        operationMessage = L("已跳转到第 \(line) 行", "Jumped to line \(line)")
    }

    private func copy(_ text: String, message: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        operationMessage = message
    }

    private func handleKeyboardShortcut(_ event: NSEvent) -> Bool {
        guard isActive else { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command),
              let characters = event.charactersIgnoringModifiers?.lowercased() else {
            return false
        }

        switch characters {
        case "l":
            jumpLineText = ""
            jumpLinePopoverVisible = true
            return true
        case "b":
            if !model.headings.isEmpty {
                outlineVisible.toggle()
                operationMessage = outlineVisible ? L("已显示大纲", "Outline shown") : L("已隐藏大纲", "Outline hidden")
                return true
            }
            return false
        case "c" where flags.contains(.option):
            copy(document.fileURL.path, message: L("已复制路径", "Path copied"))
            return true
        case "o":
            NSWorkspace.shared.open(document.fileURL)
            return true
        case "r" where flags.contains(.option):
            NSWorkspace.shared.activateFileViewerSelecting([document.fileURL])
            return true
        default:
            return false
        }
    }
}

@MainActor
private final class ConductorLargeTextViewModel: ObservableObject {
    @Published var lineStatus = L("索引中", "Indexing")
    @Published var headings: [WorkspaceLargeTextHeading] = []
    @Published var searchStatus = "0/0"

    func applyMetrics(_ metrics: ConductorLargeTextMetrics) {
        if metrics.isIndexing {
            let indexed = ByteCountFormatter.string(fromByteCount: Int64(metrics.indexedBytes), countStyle: .file)
            lineStatus = L("索引 \(indexed)", "Indexing \(indexed)")
        } else {
            lineStatus = L("\(metrics.lineCount) 行", "\(metrics.lineCount) lines")
        }
    }

    func applyHeadings(_ headings: [WorkspaceLargeTextHeading]) {
        self.headings = headings
    }

    func applySearchStatus(_ status: String) {
        searchStatus = status
    }
}

private struct ConductorLargeTextMetrics: Equatable {
    let lineCount: Int
    let indexedBytes: UInt64
    let isIndexing: Bool
}

private struct ConductorLargeTextViewport: NSViewRepresentable {
    let document: WorkspaceLargeTextDocument
    let theme: TerminalTheme
    let fontSize: CGFloat
    let searchQuery: String
    let searchNextToken: Int
    let searchPreviousToken: Int
    let jumpLine: Int?
    let jumpLineToken: Int
    let onMetrics: (ConductorLargeTextMetrics) -> Void
    let onHeadings: ([WorkspaceLargeTextHeading]) -> Void
    let onSearchStatus: (String) -> Void

    func makeNSView(context: Context) -> ConductorLargeTextHostView {
        ConductorLargeTextHostView()
    }

    func updateNSView(_ view: ConductorLargeTextHostView, context: Context) {
        view.configure(
            document: document,
            theme: ConductorLargeTextTheme(theme),
            fontSize: fontSize,
            searchQuery: searchQuery,
            searchNextToken: searchNextToken,
            searchPreviousToken: searchPreviousToken,
            jumpLine: jumpLine,
            jumpLineToken: jumpLineToken,
            onMetrics: onMetrics,
            onHeadings: onHeadings,
            onSearchStatus: onSearchStatus
        )
    }
}

private struct ConductorLargeTextTheme {
    let background: NSColor
    let text: NSColor
    let mutedText: NSColor
    let selection: NSColor
    let lineHighlight: NSColor
    let separator: NSColor

    init(_ theme: TerminalTheme) {
        background = NSColor(theme.terminalBackground)
        text = NSColor(theme.shellChromeText).withAlphaComponent(0.88)
        mutedText = NSColor(theme.shellChromeText).withAlphaComponent(0.36)
        selection = NSColor(theme.floatingSelectedFill).withAlphaComponent(0.46)
        lineHighlight = NSColor(theme.floatingSelectedFill).withAlphaComponent(0.20)
        separator = NSColor(theme.terminalOuterStroke).withAlphaComponent(theme.usesDarkChrome ? 0.32 : 0.18)
    }
}

private final class ConductorLargeTextHostView: NSView {
    private let scrollView = NSScrollView()
    private let canvas = ConductorLargeTextCanvasView()
    private let workerQueue = DispatchQueue(label: "conductor.large-text.index", qos: .userInitiated)
    private var document: WorkspaceLargeTextDocument?
    private var generation = 0
    private var searchGeneration = 0
    private var lastSearchQuery = ""
    private var lastSearchNextToken = 0
    private var lastSearchPreviousToken = 0
    private var lastJumpLineToken = 0
    private var searchLines: [Int] = []
    private var selectedSearchIndex = 0
    private var onMetrics: ((ConductorLargeTextMetrics) -> Void)?
    private var onHeadings: (([WorkspaceLargeTextHeading]) -> Void)?
    private var onSearchStatus: ((String) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = false
        scrollView.borderType = .noBorder
        scrollView.contentView.postsBoundsChangedNotifications = true
        scrollView.documentView = canvas
        addSubview(scrollView)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(boundsDidChange),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
    }

    required init?(coder: NSCoder) {
        nil
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func layout() {
        super.layout()
        scrollView.frame = bounds
        canvas.ensureContentWidth(atLeast: max(bounds.width, 900))
    }

    func configure(
        document: WorkspaceLargeTextDocument,
        theme: ConductorLargeTextTheme,
        fontSize: CGFloat,
        searchQuery: String,
        searchNextToken: Int,
        searchPreviousToken: Int,
        jumpLine: Int?,
        jumpLineToken: Int,
        onMetrics: @escaping (ConductorLargeTextMetrics) -> Void,
        onHeadings: @escaping ([WorkspaceLargeTextHeading]) -> Void,
        onSearchStatus: @escaping (String) -> Void
    ) {
        self.onMetrics = onMetrics
        self.onHeadings = onHeadings
        self.onSearchStatus = onSearchStatus
        canvas.apply(theme: theme, fontSize: fontSize)
        layer?.backgroundColor = theme.background.cgColor

        if self.document?.fileURL != document.fileURL || self.document?.byteCount != document.byteCount {
            self.document = document
            startIndexing(document: document)
        }

        updateSearch(query: searchQuery, nextToken: searchNextToken, previousToken: searchPreviousToken)

        if jumpLineToken != lastJumpLineToken {
            lastJumpLineToken = jumpLineToken
            if let jumpLine {
                scrollToLine(jumpLine)
            }
        }
    }

    @objc private func boundsDidChange() {
        canvas.setNeedsDisplay(canvas.visibleRect)
    }

    private func startIndexing(document: WorkspaceLargeTextDocument) {
        generation &+= 1
        searchGeneration &+= 1
        let currentGeneration = generation
        canvas.setIndex(nil)
        searchLines = []
        selectedSearchIndex = 0
        onSearchStatus?("0/0")
        onMetrics?(ConductorLargeTextMetrics(lineCount: 0, indexedBytes: 0, isIndexing: true))

        workerQueue.async { [weak self] in
            let result = ConductorLargeTextIndexer.index(
                url: document.fileURL,
                byteCount: UInt64(max(0, document.byteCount)),
                extractsOutline: document.extractsOutline,
                progress: { indexedBytes, lineCount in
                    DispatchQueue.main.async { [weak self] in
                        guard let self, self.generation == currentGeneration else { return }
                        self.onMetrics?(ConductorLargeTextMetrics(lineCount: lineCount, indexedBytes: indexedBytes, isIndexing: true))
                    }
                }
            )

            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == currentGeneration else { return }
                switch result {
                case .success(let index):
                    self.canvas.setIndex(index)
                    self.canvas.ensureContentWidth(atLeast: max(self.bounds.width, 900))
                    self.onMetrics?(ConductorLargeTextMetrics(lineCount: index.lineCount, indexedBytes: index.byteCount, isIndexing: false))
                    self.onHeadings?(index.headings)
                    if !self.lastSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        self.startSearch(query: self.lastSearchQuery)
                    }
                case .failure:
                    self.canvas.setMessage(L("文件无法读取", "File could not be read"))
                    self.onMetrics?(ConductorLargeTextMetrics(lineCount: 0, indexedBytes: 0, isIndexing: false))
                }
            }
        }
    }

    private func updateSearch(query: String, nextToken: Int, previousToken: Int) {
        if query != lastSearchQuery {
            lastSearchQuery = query
            startSearch(query: query)
        }

        if nextToken != lastSearchNextToken {
            lastSearchNextToken = nextToken
            moveSearchSelection(1)
        }

        if previousToken != lastSearchPreviousToken {
            lastSearchPreviousToken = previousToken
            moveSearchSelection(-1)
        }
    }

    private func startSearch(query: String) {
        searchGeneration &+= 1
        let currentSearchGeneration = searchGeneration
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty, let index = canvas.index else {
            searchLines = []
            selectedSearchIndex = 0
            canvas.highlightedLine = nil
            onSearchStatus?("0/0")
            return
        }

        onSearchStatus?(L("搜索中", "Searching"))
        workerQueue.async { [weak self] in
            let matches = index.searchLines(containing: needle, maxMatches: 20_000) { scannedLines in
                if scannedLines % 20_000 == 0 {
                    DispatchQueue.main.async { [weak self] in
                        guard let self, self.searchGeneration == currentSearchGeneration else { return }
                        self.onSearchStatus?(L("搜索 \(scannedLines) 行", "Searching \(scannedLines) lines"))
                    }
                }
            }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.searchGeneration == currentSearchGeneration else { return }
                self.searchLines = matches
                self.selectedSearchIndex = 0
                self.canvas.searchQuery = needle
                self.applyCurrentSearchMatch()
            }
        }
    }

    private func moveSearchSelection(_ delta: Int) {
        guard !searchLines.isEmpty else {
            onSearchStatus?("0/0")
            return
        }
        selectedSearchIndex = (selectedSearchIndex + delta + searchLines.count) % searchLines.count
        applyCurrentSearchMatch()
    }

    private func applyCurrentSearchMatch() {
        guard !searchLines.isEmpty else {
            canvas.highlightedLine = nil
            onSearchStatus?("0/0")
            return
        }
        let line = searchLines[selectedSearchIndex]
        canvas.highlightedLine = line
        onSearchStatus?("\(selectedSearchIndex + 1)/\(searchLines.count)")
        scrollToLine(line)
    }

    private func scrollToLine(_ line: Int) {
        guard let index = canvas.index else { return }
        let clamped = max(1, min(index.lineCount, line))
        let y = CGFloat(clamped - 1) * canvas.lineHeight
        scrollView.contentView.scroll(to: NSPoint(x: scrollView.contentView.bounds.origin.x, y: max(0, y - canvas.lineHeight * 3)))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        canvas.setNeedsDisplay(canvas.visibleRect)
    }
}

private final class ConductorLargeTextCanvasView: NSView {
    private(set) var index: ConductorLargeTextIndex?
    private var theme = ConductorLargeTextTheme(TerminalTheme.graphite)
    private var font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
    private var lineNumberFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
    private var lineCache: [Int: String] = [:]
    private var loadingRanges: Set<String> = []
    private var message: String?
    var highlightedLine: Int? {
        didSet { setNeedsDisplay(bounds) }
    }
    var searchQuery = "" {
        didSet { setNeedsDisplay(bounds) }
    }
    private let gutterWidth: CGFloat = 64
    private let textLeftInset: CGFloat = 14
    private let maxDrawnCharacters = 1_000
    private var selectionAnchorLine: Int?
    private var selectedLineRange: ClosedRange<Int>?

    var lineHeight: CGFloat {
        max(18, ceil(font.pointSize * 1.46))
    }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        nil
    }

    func apply(theme: ConductorLargeTextTheme, fontSize: CGFloat) {
        self.theme = theme
        let size = CGFloat(max(10, min(28, fontSize)))
        font = NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        lineNumberFont = NSFont.monospacedDigitSystemFont(ofSize: max(9, size - 2), weight: .medium)
        layer?.backgroundColor = theme.background.cgColor
        setNeedsDisplay(bounds)
    }

    func setIndex(_ index: ConductorLargeTextIndex?) {
        self.index = index
        message = nil
        lineCache.removeAll(keepingCapacity: false)
        loadingRanges.removeAll(keepingCapacity: false)
        selectionAnchorLine = nil
        selectedLineRange = nil
        let lineCount = max(index?.lineCount ?? 1, 1)
        frame = NSRect(x: 0, y: 0, width: max(frame.width, 900), height: CGFloat(lineCount) * lineHeight + 24)
        setNeedsDisplay(bounds)
    }

    func setMessage(_ message: String) {
        self.message = message
        setIndex(nil)
        self.message = message
        setNeedsDisplay(bounds)
    }

    func ensureContentWidth(atLeast width: CGFloat) {
        if abs(frame.width - width) > 1 {
            frame.size.width = width
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        theme.background.setFill()
        dirtyRect.fill()

        if let message {
            drawMessage(message, in: dirtyRect)
            return
        }

        guard let index else {
            drawMessage(L("正在建立行索引…", "Building line index..."), in: dirtyRect)
            return
        }

        theme.separator.setFill()
        NSRect(x: gutterWidth, y: dirtyRect.minY, width: 1, height: dirtyRect.height).fill()

        let startLine = max(1, Int(floor(dirtyRect.minY / lineHeight)) + 1)
        let endLine = min(index.lineCount, Int(ceil(dirtyRect.maxY / lineHeight)) + 2)
        if startLine <= endLine {
            ensureLinesLoaded(startLine: startLine, endLine: endLine)
        }

        for line in startLine...max(startLine, endLine) where line <= index.lineCount {
            drawLine(line, text: lineCache[line], in: dirtyRect)
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        guard let line = lineNumber(at: event.locationInWindow) else { return }
        selectionAnchorLine = line
        selectedLineRange = line...line
        setNeedsDisplay(bounds)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let anchor = selectionAnchorLine,
              let line = lineNumber(at: event.locationInWindow) else { return }
        selectedLineRange = min(anchor, line)...max(anchor, line)
        setNeedsDisplay(bounds)
    }

    override func mouseUp(with event: NSEvent) {
        guard let anchor = selectionAnchorLine,
              let line = lineNumber(at: event.locationInWindow) else { return }
        selectedLineRange = min(anchor, line)...max(anchor, line)
        setNeedsDisplay(bounds)
    }

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers?.lowercased() == "c" {
            copySelectedLines()
            return
        }
        switch event.keyCode {
        case 123:
            scrollBy(deltaX: -48, deltaY: 0)
            return
        case 124:
            scrollBy(deltaX: 48, deltaY: 0)
            return
        case 125:
            scrollBy(deltaX: 0, deltaY: lineHeight * 3)
            return
        case 126:
            scrollBy(deltaX: 0, deltaY: -lineHeight * 3)
            return
        case 115:
            scrollTo(y: 0)
            return
        case 119:
            scrollTo(y: max(0, bounds.height))
            return
        case 116:
            scrollBy(deltaX: 0, deltaY: max(120, visibleRect.height * 0.88))
            return
        case 121:
            scrollBy(deltaX: 0, deltaY: -max(120, visibleRect.height * 0.88))
            return
        default:
            break
        }
        super.keyDown(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        let copySelection = NSMenuItem(title: L("复制选中行", "Copy Selected Lines"), action: #selector(copySelectedLinesMenuAction), keyEquivalent: "")
        copySelection.target = self
        copySelection.isEnabled = selectedLineRange != nil
        menu.addItem(copySelection)

        let copyPath = NSMenuItem(title: L("复制路径", "Copy Path"), action: #selector(copyPathMenuAction), keyEquivalent: "")
        copyPath.target = self
        copyPath.isEnabled = index != nil
        menu.addItem(copyPath)
        return menu
    }

    @objc private func copySelectedLinesMenuAction() {
        copySelectedLines()
    }

    @objc private func copyPathMenuAction() {
        guard let path = index?.url.path else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(path, forType: .string)
    }

    private func drawMessage(_ message: String, in rect: NSRect) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: theme.mutedText
        ]
        let size = message.size(withAttributes: attributes)
        message.draw(
            at: NSPoint(x: max(18, rect.midX - size.width / 2), y: max(18, rect.midY - size.height / 2)),
            withAttributes: attributes
        )
    }

    private func drawLine(_ line: Int, text: String?, in dirtyRect: NSRect) {
        let y = CGFloat(line - 1) * lineHeight
        let lineRect = NSRect(x: 0, y: y, width: bounds.width, height: lineHeight)
        if selectedLineRange?.contains(line) == true {
            theme.selection.withAlphaComponent(0.56).setFill()
            lineRect.fill()
        } else if highlightedLine == line {
            theme.selection.setFill()
            lineRect.fill()
        } else if line % 2 == 0 {
            theme.lineHighlight.withAlphaComponent(0.10).setFill()
            lineRect.fill()
        }

        let number = "\(line)" as NSString
        number.draw(
            in: NSRect(x: 6, y: y + 3, width: gutterWidth - 14, height: lineHeight),
            withAttributes: [
                .font: lineNumberFont,
                .foregroundColor: theme.mutedText,
                .paragraphStyle: rightAlignedParagraphStyle
            ]
        )

        let displayText = displayLine(text)
        let textColor = displayText == nil ? theme.mutedText.withAlphaComponent(0.55) : theme.text
        (displayText ?? "·").draw(
            at: NSPoint(x: gutterWidth + textLeftInset, y: y + 2),
            withAttributes: [
                .font: font,
                .foregroundColor: textColor
            ]
        )
    }

    private var rightAlignedParagraphStyle: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.alignment = .right
        return style
    }

    private func displayLine(_ text: String?) -> String? {
        guard var text else { return nil }
        if text.count > maxDrawnCharacters {
            text = String(text.prefix(maxDrawnCharacters)) + " ..."
        }
        return text.isEmpty ? " " : text
    }

    private func ensureLinesLoaded(startLine: Int, endLine: Int) {
        guard let index else { return }
        let paddedStart = max(1, startLine - 80)
        let paddedEnd = min(index.lineCount, endLine + 120)
        let key = "\(paddedStart)-\(paddedEnd)"
        guard !loadingRanges.contains(key) else { return }
        let missing = (paddedStart...paddedEnd).contains { lineCache[$0] == nil }
        guard missing else { return }
        loadingRanges.insert(key)

        DispatchQueue.global(qos: .userInitiated).async { [weak self, weak index] in
            guard let index else { return }
            let lines = index.readLines(startLine: paddedStart, endLine: paddedEnd)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                for (line, text) in lines {
                    self.lineCache[line] = text
                }
                self.loadingRanges.remove(key)
                self.setNeedsDisplay(self.visibleRect)
            }
        }
    }

    private func lineNumber(at windowPoint: NSPoint) -> Int? {
        guard let index else { return nil }
        let point = convert(windowPoint, from: nil)
        let line = Int(floor(point.y / lineHeight)) + 1
        return max(1, min(index.lineCount, line))
    }

    private func copySelectedLines() {
        guard let index,
              let selectedLineRange else {
            NSSound.beep()
            return
        }
        let cappedEnd = min(selectedLineRange.upperBound, selectedLineRange.lowerBound + 1_999)
        let lines = index.readLines(startLine: selectedLineRange.lowerBound, endLine: cappedEnd)
        let text = (selectedLineRange.lowerBound...cappedEnd)
            .compactMap { lines[$0] }
            .joined(separator: "\n")
        guard !text.isEmpty else {
            NSSound.beep()
            return
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private func scrollBy(deltaX: CGFloat, deltaY: CGFloat) {
        guard let clipView = enclosingScrollView?.contentView else { return }
        let current = clipView.bounds.origin
        scrollTo(x: current.x + deltaX, y: current.y + deltaY)
    }

    private func scrollTo(x: CGFloat? = nil, y: CGFloat) {
        guard let scrollView = enclosingScrollView else { return }
        let clipView = scrollView.contentView
        let maxX = max(0, bounds.width - clipView.bounds.width)
        let maxY = max(0, bounds.height - clipView.bounds.height)
        let next = NSPoint(
            x: min(max(x ?? clipView.bounds.origin.x, 0), maxX),
            y: min(max(y, 0), maxY)
        )
        clipView.scroll(to: next)
        scrollView.reflectScrolledClipView(clipView)
        setNeedsDisplay(visibleRect)
    }
}

private final class ConductorLargeTextIndex: @unchecked Sendable {
    let url: URL
    let byteCount: UInt64
    let lineStarts: [UInt64]
    let headings: [WorkspaceLargeTextHeading]

    var lineCount: Int {
        max(1, lineStarts.count)
    }

    init(url: URL, byteCount: UInt64, lineStarts: [UInt64], headings: [WorkspaceLargeTextHeading]) {
        self.url = url
        self.byteCount = byteCount
        self.lineStarts = lineStarts.isEmpty ? [0] : lineStarts
        self.headings = headings
    }

    func readLines(startLine: Int, endLine: Int, maxBytesPerLine: UInt64 = 24 * 1024) -> [Int: String] {
        guard startLine <= endLine,
              let handle = try? FileHandle(forReadingFrom: url) else { return [:] }
        defer { try? handle.close() }
        var result: [Int: String] = [:]
        for line in startLine...endLine {
            guard let range = byteRange(forLine: line) else { continue }
            let byteLength = min(range.upperBound - range.lowerBound, maxBytesPerLine)
            do {
                try handle.seek(toOffset: range.lowerBound)
                let data = handle.readData(ofLength: Int(byteLength))
                var text = Self.decode(data)
                text = text.trimmingCharacters(in: CharacterSet(charactersIn: "\r\n"))
                if range.upperBound - range.lowerBound > maxBytesPerLine {
                    text += " ..."
                }
                result[line] = text
            } catch {
                result[line] = ""
            }
        }
        return result
    }

    func searchLines(containing query: String, maxMatches: Int, progress: (Int) -> Void) -> [Int] {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }
        let needle = query.lowercased()
        var matches: [Int] = []
        var currentLine = 1
        var lineData = Data()
        let chunkSize = 256 * 1024
        let maxSearchLineBytes = 256 * 1024

        while true {
            let chunk = handle.readData(ofLength: chunkSize)
            if chunk.isEmpty { break }
            for byte in chunk {
                if byte == 10 {
                    if Self.decode(lineData).lowercased().contains(needle) {
                        matches.append(currentLine)
                        if matches.count >= maxMatches { return matches }
                    }
                    currentLine += 1
                    lineData.removeAll(keepingCapacity: true)
                    progress(currentLine)
                } else if lineData.count < maxSearchLineBytes {
                    lineData.append(byte)
                }
            }
        }

        if !lineData.isEmpty, Self.decode(lineData).lowercased().contains(needle), matches.count < maxMatches {
            matches.append(currentLine)
        }
        return matches
    }

    private func byteRange(forLine line: Int) -> Range<UInt64>? {
        guard line >= 1, line <= lineCount else { return nil }
        let index = line - 1
        let start = lineStarts[index]
        let end: UInt64
        if index + 1 < lineStarts.count {
            end = lineStarts[index + 1]
        } else {
            end = byteCount
        }
        return start..<max(start, end)
    }

    private static func decode(_ data: Data) -> String {
        String(data: data, encoding: .utf8) ??
            String(data: data, encoding: .utf16) ??
            String(decoding: data, as: UTF8.self)
    }
}

private enum ConductorLargeTextIndexer {
    static func index(
        url: URL,
        byteCount: UInt64,
        extractsOutline: Bool,
        progress: (UInt64, Int) -> Void
    ) -> Result<ConductorLargeTextIndex, Error> {
        Result {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            var starts: [UInt64] = [0]
            starts.reserveCapacity(Int(min(byteCount / 42, 400_000)))
            var headings: [WorkspaceLargeTextHeading] = []
            var lineBytes = Data()
            var lineNumber = 1
            var offset: UInt64 = 0
            var lastProgressOffset: UInt64 = 0
            let chunkSize = 512 * 1024
            let maxHeadingBytes = 8 * 1024
            let maxHeadings = 800

            while true {
                let chunk = handle.readData(ofLength: chunkSize)
                if chunk.isEmpty { break }
                for byte in chunk {
                    if byte == 0 {
                        throw NSError(domain: "ConductorLargeText", code: 415, userInfo: [
                            NSLocalizedDescriptionKey: L("二进制文件不能在这里预览", "Binary files cannot be previewed here")
                        ])
                    }

                    if byte == 10 {
                        starts.append(offset + 1)
                        if extractsOutline, headings.count < maxHeadings {
                            appendHeading(from: lineBytes, lineNumber: lineNumber, into: &headings)
                        }
                        lineBytes.removeAll(keepingCapacity: true)
                        lineNumber += 1
                    } else if extractsOutline, lineBytes.count < maxHeadingBytes {
                        lineBytes.append(byte)
                    }
                    offset += 1
                }

                if offset - lastProgressOffset >= 4 * 1024 * 1024 {
                    lastProgressOffset = offset
                    progress(offset, starts.count)
                }
            }

            if extractsOutline, !lineBytes.isEmpty, headings.count < maxHeadings {
                appendHeading(from: lineBytes, lineNumber: lineNumber, into: &headings)
            }

            return ConductorLargeTextIndex(
                url: url,
                byteCount: byteCount,
                lineStarts: starts,
                headings: headings
            )
        }
    }

    private static func appendHeading(from data: Data, lineNumber: Int, into headings: inout [WorkspaceLargeTextHeading]) {
        guard let line = String(data: data, encoding: .utf8) else { return }
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("#") else { return }
        let level = trimmed.prefix { $0 == "#" }.count
        guard (1...6).contains(level),
              trimmed.dropFirst(level).first == " " else { return }
        let title = trimmed.dropFirst(level).trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        headings.append(WorkspaceLargeTextHeading(line: lineNumber, level: level, title: title))
    }
}
