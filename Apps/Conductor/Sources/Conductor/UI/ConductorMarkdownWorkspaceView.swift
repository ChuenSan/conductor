import AppKit
import SwiftUI

private func L(_ zh: String, _ en: String) -> String {
    ConductorLocalization.text(zh: zh, en: en)
}

private enum ConductorMarkdownMode: String, CaseIterable, Identifiable {
    case source
    case preview
    case split

    var id: String { rawValue }

    var title: String {
        switch self {
        case .source:
            L("源码", "Source")
        case .preview:
            L("预览", "Preview")
        case .split:
            L("分屏", "Split")
        }
    }

    var icon: String {
        switch self {
        case .source:
            "curlybraces"
        case .preview:
            "doc.richtext"
        case .split:
            "rectangle.split.2x1"
        }
    }
}

struct ConductorMarkdownWorkspaceView: View {
    @Binding var text: String
    let fileURL: URL
    let rootURL: URL
    let fontSize: CGFloat
    let focusToken: Int
    var snapshotToken = 0
    var isEditable = true
    var searchFocusToken = 0
    var searchNextToken = 0
    var searchPreviousToken = 0
    var onTextSnapshot: (String) -> Void = { _ in }
    var openFile: (URL) -> Void = { _ in }

    @State private var selectedMode: ConductorMarkdownMode?
    @State private var outlineVisible = true
    @State private var searchQuery = ""
    @State private var selectedSearchIndex = 0
    @State private var selectedPreviewBlockID: String?
    @State private var sourceJumpLine: Int?
    @State private var sourceJumpToken = 0
    @State private var sourceSelectionRange: NSRange?
    @State private var sourceSelectionToken = 0
    @State private var searchVisible = false
    @State private var searchHistory: [String]
    @State private var document: ConductorMarkdownDocument
    @State private var cachedSearchMatches: [ConductorMarkdownSearchMatch] = []
    @State private var parseTask: Task<Void, Never>?
    @State private var searchTask: Task<Void, Never>?
    @State private var parseGeneration = 0
    @State private var searchGeneration = 0
    @State private var parsePending = false
    @State private var searchPending = false

    private var searchMatches: [ConductorMarkdownSearchMatch] { cachedSearchMatches }

    @Environment(\.conductorTheme) private var theme
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorFontFamily) private var fontFamily

    init(
        text: Binding<String>,
        fileURL: URL,
        rootURL: URL,
        fontSize: CGFloat,
        focusToken: Int,
        snapshotToken: Int = 0,
        isEditable: Bool = true,
        searchFocusToken: Int = 0,
        searchNextToken: Int = 0,
        searchPreviousToken: Int = 0,
        onTextSnapshot: @escaping (String) -> Void = { _ in },
        openFile: @escaping (URL) -> Void = { _ in }
    ) {
        _text = text
        self.fileURL = fileURL
        self.rootURL = rootURL
        self.fontSize = fontSize
        self.focusToken = focusToken
        self.snapshotToken = snapshotToken
        self.isEditable = isEditable
        self.searchFocusToken = searchFocusToken
        self.searchNextToken = searchNextToken
        self.searchPreviousToken = searchPreviousToken
        self.onTextSnapshot = onTextSnapshot
        self.openFile = openFile
        _document = State(initialValue: .empty)
        _searchHistory = State(initialValue: ConductorSearchHistory.load(scope: "markdown"))
    }

    var body: some View {
        GeometryReader { proxy in
            let mode = effectiveMode(for: proxy.size.width)
            VStack(spacing: 0) {
                markdownToolbar(mode: mode, width: proxy.size.width)
                markdownBody(mode: mode, width: proxy.size.width)
            }
            .background(theme.terminalBackground)
            .onAppear {
                scheduleMarkdownParse(delay: .zero)
                refreshSearchMatches(resetSelection: true, delay: .zero)
            }
            .onChange(of: text) {
                scheduleMarkdownParse(delay: .milliseconds(180))
                refreshSearchMatches(resetSelection: false, delay: .milliseconds(160))
            }
            .onChange(of: searchQuery) {
                refreshSearchMatches(resetSelection: true, delay: .milliseconds(80))
            }
            .onChange(of: searchFocusToken) { _, newValue in
                guard newValue > 0 else { return }
                showSearch()
            }
            .onChange(of: searchNextToken) { _, newValue in
                guard newValue > 0 else { return }
                moveSearchSelection(1)
            }
            .onChange(of: searchPreviousToken) { _, newValue in
                guard newValue > 0 else { return }
                moveSearchSelection(-1)
            }
            .onDisappear {
                parseTask?.cancel()
                searchTask?.cancel()
            }
        }
    }

    private func effectiveMode(for width: CGFloat) -> ConductorMarkdownMode {
        if let selectedMode {
            if selectedMode == .split && width < 760 {
                return .source
            }
            return selectedMode
        }
        return width >= 760 ? .split : .preview
    }

    private var sourceEditor: some View {
        ConductorCodeEditSourceEditor(
            text: $text,
            fileURL: fileURL,
            theme: theme,
            fontSize: fontSize,
            focusToken: focusToken,
            jumpLine: sourceJumpLine,
            jumpLineToken: sourceJumpToken,
            selectionRange: sourceSelectionRange,
            selectionToken: sourceSelectionToken,
            snapshotToken: snapshotToken,
            isEditable: isEditable,
            onTextSnapshot: onTextSnapshot
        )
    }

    @ViewBuilder
    private func markdownBody(mode: ConductorMarkdownMode, width: CGFloat) -> some View {
        HStack(spacing: 0) {
            if mode == .source || mode == .split {
                sourceEditor
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if mode == .split {
                Rectangle()
                    .fill(theme.terminalOuterStroke.opacity(theme.usesDarkChrome ? 0.34 : 0.24))
                    .frame(width: 1)
            }

            if mode == .preview || mode == .split {
                markdownPreview(width: width)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if outlineVisible && mode != .source && !document.headings.isEmpty && width >= 900 {
                Rectangle()
                    .fill(theme.terminalOuterStroke.opacity(theme.usesDarkChrome ? 0.22 : 0.14))
                    .frame(width: 1)
                markdownOutline
                    .frame(width: min(220, max(184, width * 0.18)))
            }
        }
    }

    private func markdownToolbar(mode: ConductorMarkdownMode, width: CGFloat) -> some View {
        HStack(spacing: 10) {
            HStack(spacing: 4) {
                ForEach(ConductorMarkdownMode.allCases) { candidate in
                    Button {
                        selectedMode = candidate
                        if candidate != .preview {
                            sourceJumpToken &+= 1
                        }
                    } label: {
                        Image(systemName: candidate.icon)
                            .font(.conductorSystem(size: 11.5, weight: .semibold, family: fontFamily, scale: fontScale))
                            .frame(width: 29, height: 26)
                            .foregroundStyle(mode == candidate ? theme.shellChromeText.opacity(0.92) : theme.shellChromeTextMuted.opacity(0.72))
                            .background(mode == candidate ? theme.floatingSelectedFill.opacity(0.70) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .macNativeTooltip(candidate.title)
                }
            }
            .padding(3)
            .background(theme.shellControlFill.opacity(theme.usesDarkChrome ? 0.40 : 0.20))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            if searchVisible || !searchQuery.isEmpty {
                markdownSearchField
            }

            Spacer(minLength: 8)

            toolbarIcon(outlineVisible ? "sidebar.right" : "sidebar.right", active: outlineVisible && mode != .source, help: L("大纲", "Outline")) {
                outlineVisible.toggle()
            }
            .disabled(document.headings.isEmpty || width < 900 || mode == .source)
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(theme.terminalChrome.opacity(theme.usesDarkChrome ? 0.32 : 0.14))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(theme.terminalOuterStroke.opacity(theme.usesDarkChrome ? 0.20 : 0.12))
                .frame(height: 1)
        }
    }

    private var markdownSearchField: some View {
        ConductorContextSearchSurface {
            Image(systemName: "magnifyingglass")
                .font(.conductorSystem(size: 11, weight: .semibold, family: fontFamily, scale: fontScale))
                .foregroundStyle(theme.shellChromeText.opacity(0.58))

            ConductorContextSearchScopeChip(systemImage: "doc.richtext", title: "Markdown")

            if !searchHistory.isEmpty {
                Menu {
                    ForEach(searchHistory, id: \.self) { query in
                        Button(query) {
                            searchQuery = query
                            recordSearchQuery()
                            jumpToCurrentSearchMatch()
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
                placeholder: L("搜索 Markdown", "Search Markdown"),
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
        if searchPending { return L("搜索中", "Searching") }
        guard !searchMatches.isEmpty else { return "0/0" }
        return "\(selectedSearchIndex + 1)/\(searchMatches.count)"
    }

    private var markdownOutline: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: "list.bullet.indent")
                    .font(.conductorSystem(size: 11, weight: .semibold, family: fontFamily, scale: fontScale))
                Text(L("大纲", "Outline"))
                    .font(.conductorSystem(size: 11.5, weight: .bold, family: fontFamily, scale: fontScale))
                Spacer()
            }
            .foregroundStyle(theme.shellChromeText.opacity(0.74))
            .padding(.horizontal, 12)
            .frame(height: 38)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(document.headings) { heading in
                        Button {
                            jumpToHeading(heading)
                        } label: {
                            HStack(spacing: 6) {
                                Text("H\(heading.level)")
                                    .font(.conductorSystem(size: 9.5, weight: .bold, family: fontFamily, scale: fontScale))
                                    .foregroundStyle(theme.shellChromeTextMuted.opacity(0.58))
                                    .frame(width: 18, alignment: .leading)
                                Text(heading.title)
                                    .font(.conductorSystem(size: 11.2, weight: .medium, family: fontFamily, scale: fontScale))
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                            .foregroundStyle(selectedPreviewBlockID == heading.blockID ? theme.shellChromeText.opacity(0.92) : theme.shellChromeText.opacity(0.70))
                            .padding(.leading, CGFloat(max(0, heading.level - 1)) * 9)
                            .padding(.horizontal, 9)
                            .frame(height: 28, alignment: .leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(selectedPreviewBlockID == heading.blockID ? theme.floatingSelectedFill.opacity(0.48) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 7)
                .padding(.bottom, 10)
            }
        }
        .background(theme.terminalChrome.opacity(theme.usesDarkChrome ? 0.28 : 0.18))
    }

    private func markdownPreview(width: CGFloat) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(document.blocks) { block in
                        ConductorMarkdownBlockView(
                            block: block,
                            rootURL: rootURL,
                            fileURL: fileURL,
                            currentMatchRange: currentSearchRange,
                            openURL: openMarkdownURL
                        )
                        .id(block.id)
                    }
                }
                .padding(.horizontal, width >= 980 ? 42 : 24)
                .padding(.vertical, 34)
                .frame(maxWidth: 860, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .background(theme.terminalBackground)
            .onChange(of: selectedPreviewBlockID) { _, value in
                guard let value else { return }
                withAnimation(.easeOut(duration: 0.16)) {
                    proxy.scrollTo(value, anchor: .top)
                }
            }
        }
    }

    private var currentSearchRange: NSRange? {
        guard searchMatches.indices.contains(selectedSearchIndex) else { return nil }
        return searchMatches[selectedSearchIndex].range
    }

    private func toolbarIcon(_ systemImage: String, active: Bool = false, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.conductorSystem(size: 11.5, weight: .semibold, family: fontFamily, scale: fontScale))
                .foregroundStyle(active ? theme.floatingEmphasis : theme.shellChromeText.opacity(0.66))
                .frame(width: 25, height: 24)
                .background(active ? theme.floatingSelectedFill.opacity(0.56) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .macNativeTooltip(help)
    }

    private func jumpToHeading(_ heading: ConductorMarkdownHeading) {
        selectedPreviewBlockID = heading.blockID
        sourceJumpLine = heading.line
        sourceJumpToken &+= 1
    }

    private func moveSearchSelection(_ delta: Int) {
        searchVisible = true
        guard !searchMatches.isEmpty else { return }
        selectedSearchIndex = (selectedSearchIndex + delta + searchMatches.count) % searchMatches.count
        jumpToCurrentSearchMatch()
    }

    private func showSearch() {
        searchVisible = true
        jumpToCurrentSearchMatch()
    }

    private func closeSearch() {
        recordSearchQuery()
        searchVisible = false
        searchQuery = ""
        selectedPreviewBlockID = nil
    }

    private func clampSearchSelectionAndScroll() {
        if selectedSearchIndex >= searchMatches.count {
            selectedSearchIndex = max(0, searchMatches.count - 1)
        }
        jumpToCurrentSearchMatch()
    }

    private func jumpToCurrentSearchMatch() {
        guard let match = currentSearchRange else {
            selectedPreviewBlockID = nil
            return
        }
        sourceSelectionRange = match
        sourceSelectionToken &+= 1
        if let block = document.block(containing: match.location) {
            selectedPreviewBlockID = block.id
        }
    }

    private func recordSearchQuery() {
        ConductorSearchHistory.record(searchQuery, scope: "markdown")
        searchHistory = ConductorSearchHistory.load(scope: "markdown")
    }

    private func scheduleMarkdownParse(delay: Duration) {
        parseTask?.cancel()
        parseGeneration += 1
        let generation = parseGeneration
        let snapshot = text
        parsePending = true
        parseTask = Task { @MainActor in
            if delay != .zero {
                try? await Task.sleep(for: delay)
            }
            guard !Task.isCancelled else { return }
            let parsed = await Task.detached(priority: .userInitiated) {
                ConductorMarkdownParser.parse(snapshot)
            }.value
            guard !Task.isCancelled, generation == parseGeneration else { return }
            parsePending = false
            document = parsed
            clampSearchSelectionAndScroll()
        }
    }

    private func refreshSearchMatches(resetSelection: Bool, delay: Duration) {
        let needle = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else {
            searchTask?.cancel()
            searchPending = false
            cachedSearchMatches = []
            selectedSearchIndex = 0
            selectedPreviewBlockID = nil
            sourceSelectionRange = nil
            return
        }

        searchTask?.cancel()
        searchGeneration += 1
        let generation = searchGeneration
        let snapshot = text
        searchPending = true
        searchTask = Task { @MainActor in
            if delay != .zero {
                try? await Task.sleep(for: delay)
            }
            guard !Task.isCancelled else { return }
            let matches = await Task.detached(priority: .userInitiated) {
                ConductorMarkdownSearch.matches(in: snapshot, query: needle, maxMatches: 20_000)
            }.value
            guard generation == searchGeneration else { return }
            searchPending = false
            cachedSearchMatches = matches
            if resetSelection {
                selectedSearchIndex = 0
            } else if selectedSearchIndex >= cachedSearchMatches.count {
                selectedSearchIndex = max(0, cachedSearchMatches.count - 1)
            }
            jumpToCurrentSearchMatch()
        }
    }

    private func openMarkdownURL(_ target: String) {
        if target.hasPrefix("#") {
            let anchor = ConductorMarkdownParser.slug(String(target.dropFirst()))
            if let heading = document.headings.first(where: { $0.anchor == anchor }) {
                jumpToHeading(heading)
            }
            return
        }

        if let url = URL(string: target), let scheme = url.scheme, scheme == "http" || scheme == "https" {
            NSWorkspace.shared.open(url)
            return
        }

        guard let resolved = ConductorMarkdownPathResolver.resolve(
            target,
            fileURL: fileURL,
            rootURL: rootURL
        ) else { return }
        openFile(resolved)
    }
}

private struct ConductorMarkdownBlockView: View {
    let block: ConductorMarkdownBlock
    let rootURL: URL
    let fileURL: URL
    let currentMatchRange: NSRange?
    let openURL: (String) -> Void
    @Environment(\.conductorTheme) private var theme
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorFontFamily) private var fontFamily

    private var containsCurrentMatch: Bool {
        guard let currentMatchRange else { return false }
        return block.range.intersection(currentMatchRange) != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            blockContent
            let links = ConductorMarkdownParser.links(in: block.plainText)
            if !links.isEmpty {
                HStack(spacing: 6) {
                    ForEach(links) { link in
                        Button {
                            openURL(link.target)
                        } label: {
                            Label(link.label, systemImage: link.target.hasPrefix("#") ? "number" : "link")
                                .font(.conductorSystem(size: 10.5, weight: .semibold, family: fontFamily, scale: fontScale))
                                .lineLimit(1)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(theme.floatingEmphasis.opacity(0.86))
                        .padding(.horizontal, 7)
                        .frame(height: 21)
                        .background(theme.floatingSelectedFill.opacity(0.34))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                }
            }
        }
        .padding(.vertical, verticalPadding)
        .padding(.horizontal, containsCurrentMatch ? 10 : 0)
        .background(containsCurrentMatch ? theme.floatingSelectedFill.opacity(0.28) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    @ViewBuilder
    private var blockContent: some View {
        switch block.kind {
        case .heading(let level, let title):
            Text(title)
                .font(.system(size: headingSize(level), weight: headingWeight(level)))
                .foregroundStyle(theme.shellChromeText.opacity(0.94))
                .padding(.top, level <= 2 ? 8 : 4)
        case .paragraph(let text):
            markdownText(text)
                .font(.system(size: 14, weight: .regular))
                .lineSpacing(4)
                .foregroundStyle(theme.shellChromeText.opacity(0.84))
                .textSelection(.enabled)
        case .quote(let text):
            HStack(alignment: .top, spacing: 10) {
                Rectangle()
                    .fill(theme.floatingEmphasis.opacity(0.48))
                    .frame(width: 3)
                markdownText(text)
                    .font(.system(size: 13.5, weight: .regular))
                    .foregroundStyle(theme.shellChromeText.opacity(0.70))
                    .lineSpacing(4)
            }
        case .unorderedList(let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    listRow(marker: "•", text: item)
                }
            }
        case .orderedList(let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    listRow(marker: "\(index + 1).", text: item)
                }
            }
        case .taskList(let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: item.checked ? "checkmark.square.fill" : "square")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(item.checked ? theme.floatingEmphasis : theme.shellChromeTextMuted.opacity(0.70))
                            .frame(width: 16)
                        markdownText(item.text)
                            .font(.system(size: 13.5))
                            .foregroundStyle(theme.shellChromeText.opacity(0.82))
                    }
                }
            }
        case .code(let language, let code):
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    if let language, !language.isEmpty {
                        Text(language)
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(theme.shellChromeTextMuted.opacity(0.66))
                    }
                    Spacer(minLength: 0)
                    Button {
                        copyText(code)
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(theme.shellChromeText.opacity(0.58))
                            .frame(width: 22, height: 20)
                    }
                    .buttonStyle(.plain)
                    .macNativeTooltip(L("复制代码", "Copy Code"))
                }
                Text(code)
                    .font(.system(size: 12.5, weight: .regular, design: .monospaced))
                    .foregroundStyle(theme.shellChromeText.opacity(0.88))
                    .lineSpacing(3)
                    .textSelection(.enabled)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.shellControlFill.opacity(theme.usesDarkChrome ? 0.42 : 0.30))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        case .image(let alt, let target):
            markdownImage(alt: alt, target: target)
        case .horizontalRule:
            Rectangle()
                .fill(theme.terminalOuterStroke.opacity(theme.usesDarkChrome ? 0.42 : 0.28))
                .frame(height: 1)
                .padding(.vertical, 8)
        case .table(let rows):
            markdownTable(rows)
        }
    }

    private var verticalPadding: CGFloat {
        switch block.kind {
        case .heading:
            4
        case .horizontalRule:
            2
        default:
            7
        }
    }

    private func listRow(marker: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(marker)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(theme.shellChromeTextMuted.opacity(0.70))
                .frame(width: 24, alignment: .trailing)
            markdownText(text)
                .font(.system(size: 13.5))
                .foregroundStyle(theme.shellChromeText.opacity(0.82))
                .lineSpacing(3)
        }
    }

    private func markdownText(_ value: String) -> Text {
        if let attributed = try? AttributedString(markdown: value) {
            return Text(attributed)
        }
        return Text(value)
    }

    private func copyText(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func headingSize(_ level: Int) -> CGFloat {
        switch level {
        case 1: 25
        case 2: 21
        case 3: 17
        default: 14.5
        }
    }

    private func headingWeight(_ level: Int) -> Font.Weight {
        level <= 2 ? .bold : .semibold
    }

    @ViewBuilder
    private func markdownImage(alt: String, target: String) -> some View {
        if let imageURL = ConductorMarkdownPathResolver.resolve(target, fileURL: fileURL, rootURL: rootURL) {
            ConductorAsyncImage(url: imageURL) { image in
                VStack(alignment: .leading, spacing: 6) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 620, maxHeight: 420)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    if !alt.isEmpty {
                        Text(alt)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(theme.shellChromeTextMuted.opacity(0.72))
                    }
                }
            } placeholder: { isLoading, _ in
                markdownImageUnavailable(
                    alt: alt,
                    target: target,
                    systemImage: isLoading ? "hourglass" : "photo.badge.exclamationmark",
                    title: isLoading ? L("正在读取图片", "Loading image") : nil
                )
            }
        } else {
            markdownImageUnavailable(alt: alt, target: target)
        }
    }

    private func markdownImageUnavailable(
        alt: String,
        target: String,
        systemImage: String = "photo.badge.exclamationmark",
        title: String? = nil
    ) -> some View {
        HStack(spacing: 9) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
            VStack(alignment: .leading, spacing: 2) {
                Text(title ?? (alt.isEmpty ? L("图片无法显示", "Image unavailable") : alt))
                    .font(.system(size: 12.5, weight: .semibold))
                Text(target)
                    .font(.system(size: 10.5, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .foregroundStyle(theme.shellChromeTextMuted.opacity(0.76))
        .padding(10)
        .background(theme.shellControlFill.opacity(theme.usesDarkChrome ? 0.35 : 0.24))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func markdownTable(_ rows: [[String]]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                HStack(spacing: 0) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                        Text(cell)
                            .font(.system(size: 12.5, weight: rowIndex == 0 ? .semibold : .regular))
                            .foregroundStyle(theme.shellChromeText.opacity(rowIndex == 0 ? 0.90 : 0.78))
                            .lineLimit(3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 7)
                            .overlay(alignment: .trailing) {
                                Rectangle()
                                    .fill(theme.terminalOuterStroke.opacity(0.20))
                                    .frame(width: 1)
                            }
                    }
                }
                .background(rowIndex == 0 ? theme.shellControlFill.opacity(0.34) : Color.clear)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(theme.terminalOuterStroke.opacity(0.22))
                        .frame(height: 1)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(theme.terminalOuterStroke.opacity(0.26), lineWidth: 1)
        }
    }
}

private struct ConductorMarkdownDocument {
    let blocks: [ConductorMarkdownBlock]
    let headings: [ConductorMarkdownHeading]

    static let empty = ConductorMarkdownDocument(blocks: [], headings: [])

    func block(containing utf16Location: Int) -> ConductorMarkdownBlock? {
        blocks.first { block in
            utf16Location >= block.range.location && utf16Location <= block.range.location + block.range.length
        }
    }
}

private struct ConductorMarkdownHeading: Identifiable, Equatable {
    let id: String
    let blockID: String
    let level: Int
    let title: String
    let anchor: String
    let line: Int
}

private struct ConductorMarkdownBlock: Identifiable {
    enum Kind {
        case heading(level: Int, title: String)
        case paragraph(String)
        case quote(String)
        case unorderedList([String])
        case orderedList([String])
        case taskList([(checked: Bool, text: String)])
        case code(language: String?, text: String)
        case image(alt: String, target: String)
        case horizontalRule
        case table([[String]])
    }

    let id: String
    let kind: Kind
    let startLine: Int
    let endLine: Int
    let range: NSRange

    var plainText: String {
        switch kind {
        case .heading(_, let title):
            title
        case .paragraph(let text), .quote(let text):
            text
        case .unorderedList(let items), .orderedList(let items):
            items.joined(separator: "\n")
        case .taskList(let items):
            items.map(\.text).joined(separator: "\n")
        case .code(_, let text):
            text
        case .image(let alt, let target):
            "\(alt) \(target)"
        case .horizontalRule:
            ""
        case .table(let rows):
            rows.map { $0.joined(separator: " ") }.joined(separator: "\n")
        }
    }
}

private struct ConductorMarkdownSearchMatch: Equatable {
    let range: NSRange
}

private enum ConductorMarkdownSearch {
    static func matches(in text: String, query: String, maxMatches: Int = .max) -> [ConductorMarkdownSearchMatch] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let nsText = text as NSString
        var results: [ConductorMarkdownSearchMatch] = []
        var searchRange = NSRange(location: 0, length: nsText.length)
        while searchRange.length > 0 {
            let found = nsText.range(of: trimmed, options: [.caseInsensitive, .diacriticInsensitive], range: searchRange)
            guard found.location != NSNotFound else { break }
            results.append(ConductorMarkdownSearchMatch(range: found))
            if results.count >= maxMatches { break }
            let nextLocation = found.location + max(found.length, 1)
            guard nextLocation < nsText.length else { break }
            searchRange = NSRange(location: nextLocation, length: nsText.length - nextLocation)
        }
        return results
    }
}

private enum ConductorMarkdownPathResolver {
    static func resolve(_ target: String, fileURL: URL, rootURL: URL) -> URL? {
        let cleaned = target
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        guard !cleaned.isEmpty, !cleaned.hasPrefix("#") else { return nil }
        guard URL(string: cleaned)?.scheme == nil else { return nil }

        let decoded = cleaned.removingPercentEncoding ?? cleaned
        let candidate: URL
        if decoded.hasPrefix("/") {
            candidate = URL(fileURLWithPath: decoded)
        } else {
            candidate = fileURL.deletingLastPathComponent().appendingPathComponent(decoded)
        }
        let resolved = candidate.standardizedFileURL
        let rootPath = rootURL.standardizedFileURL.path
        guard resolved.path == rootPath || resolved.path.hasPrefix(rootPath + "/") else {
            return nil
        }
        return resolved
    }
}

private struct ConductorMarkdownLink: Identifiable, Equatable {
    var id: String { "\(label)|\(target)" }
    let label: String
    let target: String
}

private enum ConductorMarkdownParser {
    static func parse(_ text: String) -> ConductorMarkdownDocument {
        let lines = text.components(separatedBy: "\n")
        let offsets = lineOffsets(for: lines)
        var blocks: [ConductorMarkdownBlock] = []
        var headings: [ConductorMarkdownHeading] = []
        var index = 0

        func makeRange(start: Int, end: Int) -> NSRange {
            let startOffset = offsets[min(start, offsets.count - 1)]
            let endIndex = min(end, max(lines.count - 1, 0))
            let endOffset = offsets[min(endIndex, offsets.count - 1)] + (lines[endIndex] as NSString).length
            return NSRange(location: startOffset, length: max(0, endOffset - startOffset))
        }

        func appendBlock(_ kind: ConductorMarkdownBlock.Kind, start: Int, end: Int) {
            let id = blockID(kind: kind, line: start + 1)
            let block = ConductorMarkdownBlock(
                id: id,
                kind: kind,
                startLine: start + 1,
                endLine: end + 1,
                range: makeRange(start: start, end: end)
            )
            blocks.append(block)
            if case .heading(let level, let title) = kind {
                headings.append(
                    ConductorMarkdownHeading(
                        id: "\(id)-outline",
                        blockID: id,
                        level: level,
                        title: title,
                        anchor: slug(title),
                        line: start + 1
                    )
                )
            }
        }

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                index += 1
                continue
            }

            if let fence = fenceStart(trimmed) {
                let start = index
                index += 1
                var codeLines: [String] = []
                while index < lines.count {
                    let candidate = lines[index].trimmingCharacters(in: .whitespaces)
                    if candidate.hasPrefix(fence.marker) {
                        break
                    }
                    codeLines.append(lines[index])
                    index += 1
                }
                let end = min(index, max(lines.count - 1, start))
                appendBlock(.code(language: fence.language, text: codeLines.joined(separator: "\n")), start: start, end: end)
                index = min(index + 1, lines.count)
                continue
            }

            if let heading = heading(in: trimmed) {
                appendBlock(.heading(level: heading.level, title: heading.title), start: index, end: index)
                index += 1
                continue
            }

            if isHorizontalRule(trimmed) {
                appendBlock(.horizontalRule, start: index, end: index)
                index += 1
                continue
            }

            if let image = image(in: trimmed) {
                appendBlock(.image(alt: image.alt, target: image.target), start: index, end: index)
                index += 1
                continue
            }

            if isTableStart(lines, index: index) {
                let start = index
                var rows: [[String]] = []
                while index < lines.count, lines[index].contains("|"), !lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
                    if !isTableSeparator(lines[index]) {
                        rows.append(tableCells(lines[index]))
                    }
                    index += 1
                }
                appendBlock(.table(rows), start: start, end: max(start, index - 1))
                continue
            }

            if let task = taskItem(in: trimmed) {
                let start = index
                var items: [(checked: Bool, text: String)] = []
                while index < lines.count, let item = taskItem(in: lines[index].trimmingCharacters(in: .whitespaces)) {
                    items.append(item)
                    index += 1
                }
                _ = task
                appendBlock(.taskList(items), start: start, end: max(start, index - 1))
                continue
            }

            if let unordered = unorderedListItem(in: trimmed) {
                let start = index
                var items = [unordered]
                index += 1
                while index < lines.count, let item = unorderedListItem(in: lines[index].trimmingCharacters(in: .whitespaces)) {
                    items.append(item)
                    index += 1
                }
                appendBlock(.unorderedList(items), start: start, end: max(start, index - 1))
                continue
            }

            if let ordered = orderedListItem(in: trimmed) {
                let start = index
                var items = [ordered]
                index += 1
                while index < lines.count, let item = orderedListItem(in: lines[index].trimmingCharacters(in: .whitespaces)) {
                    items.append(item)
                    index += 1
                }
                appendBlock(.orderedList(items), start: start, end: max(start, index - 1))
                continue
            }

            if trimmed.hasPrefix(">") {
                let start = index
                var quoteLines: [String] = []
                while index < lines.count {
                    let candidate = lines[index].trimmingCharacters(in: .whitespaces)
                    guard candidate.hasPrefix(">") else { break }
                    quoteLines.append(candidate.dropFirst().trimmingCharacters(in: .whitespaces).description)
                    index += 1
                }
                appendBlock(.quote(quoteLines.joined(separator: "\n")), start: start, end: max(start, index - 1))
                continue
            }

            let start = index
            var paragraphLines = [line]
            index += 1
            while index < lines.count {
                let candidate = lines[index].trimmingCharacters(in: .whitespaces)
                guard !candidate.isEmpty,
                      heading(in: candidate) == nil,
                      fenceStart(candidate) == nil,
                      !isHorizontalRule(candidate),
                      image(in: candidate) == nil,
                      taskItem(in: candidate) == nil,
                      unorderedListItem(in: candidate) == nil,
                      orderedListItem(in: candidate) == nil,
                      !candidate.hasPrefix(">"),
                      !isTableStart(lines, index: index) else {
                    break
                }
                paragraphLines.append(lines[index])
                index += 1
            }
            appendBlock(.paragraph(paragraphLines.joined(separator: "\n")), start: start, end: max(start, index - 1))
        }

        return ConductorMarkdownDocument(blocks: blocks, headings: headings)
    }

    static func slug(_ value: String) -> String {
        let lower = value.lowercased()
        var result = ""
        var lastWasDash = false
        for scalar in lower.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                result.append(Character(scalar))
                lastWasDash = false
            } else if !lastWasDash {
                result.append("-")
                lastWasDash = true
            }
        }
        return result.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    static func links(in text: String) -> [ConductorMarkdownLink] {
        let pattern = #"(?<!!)\[([^\]]+)\]\(([^)]+)\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsText = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)).compactMap { match in
            guard match.numberOfRanges >= 3 else { return nil }
            let label = nsText.substring(with: match.range(at: 1))
            let target = nsText.substring(with: match.range(at: 2))
            return ConductorMarkdownLink(label: label, target: target)
        }
    }

    private static func lineOffsets(for lines: [String]) -> [Int] {
        var offsets: [Int] = []
        var offset = 0
        for line in lines {
            offsets.append(offset)
            offset += (line as NSString).length + 1
        }
        return offsets.isEmpty ? [0] : offsets
    }

    private static func blockID(kind: ConductorMarkdownBlock.Kind, line: Int) -> String {
        if case .heading(_, let title) = kind {
            return "heading-\(slug(title))-\(line)"
        }
        return "block-\(line)"
    }

    private static func fenceStart(_ line: String) -> (marker: String, language: String?)? {
        let marker: String
        if line.hasPrefix("```") {
            marker = "```"
        } else if line.hasPrefix("~~~") {
            marker = "~~~"
        } else {
            return nil
        }
        let language = String(line.dropFirst(marker.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        return (marker, language.isEmpty ? nil : language)
    }

    private static func heading(in line: String) -> (level: Int, title: String)? {
        guard line.hasPrefix("#") else { return nil }
        let count = line.prefix { $0 == "#" }.count
        guard (1...6).contains(count), line.dropFirst(count).first == " " else { return nil }
        let title = line.dropFirst(count).trimmingCharacters(in: .whitespaces)
        return title.isEmpty ? nil : (count, title)
    }

    private static func isHorizontalRule(_ line: String) -> Bool {
        let stripped = line.filter { !$0.isWhitespace }
        guard stripped.count >= 3 else { return false }
        return stripped.allSatisfy { $0 == "-" } || stripped.allSatisfy { $0 == "_" } || stripped.allSatisfy { $0 == "*" }
    }

    private static func image(in line: String) -> (alt: String, target: String)? {
        let pattern = #"^!\[([^\]]*)\]\(([^)]+)\)\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsText = line as NSString
        guard let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: nsText.length)),
              match.numberOfRanges >= 3 else {
            return nil
        }
        return (nsText.substring(with: match.range(at: 1)), nsText.substring(with: match.range(at: 2)))
    }

    private static func unorderedListItem(in line: String) -> String? {
        guard line.count > 2 else { return nil }
        let prefix = line.prefix(2)
        if prefix == "- " || prefix == "* " || prefix == "+ " {
            return String(line.dropFirst(2))
        }
        return nil
    }

    private static func orderedListItem(in line: String) -> String? {
        guard let dot = line.firstIndex(of: ".") else { return nil }
        let prefix = line[..<dot]
        guard !prefix.isEmpty, prefix.allSatisfy(\.isNumber) else { return nil }
        let afterDot = line.index(after: dot)
        guard afterDot < line.endIndex, line[afterDot] == " " else { return nil }
        return String(line[line.index(after: afterDot)...])
    }

    private static func taskItem(in line: String) -> (checked: Bool, text: String)? {
        let lowered = line.lowercased()
        if lowered.hasPrefix("- [ ] ") || lowered.hasPrefix("* [ ] ") {
            return (false, String(line.dropFirst(6)))
        }
        if lowered.hasPrefix("- [x] ") || lowered.hasPrefix("* [x] ") {
            return (true, String(line.dropFirst(6)))
        }
        return nil
    }

    private static func isTableStart(_ lines: [String], index: Int) -> Bool {
        guard index + 1 < lines.count else { return false }
        return lines[index].contains("|") && isTableSeparator(lines[index + 1])
    }

    private static func isTableSeparator(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("|") else { return false }
        let cleaned = trimmed.replacingOccurrences(of: "|", with: "")
            .replacingOccurrences(of: ":", with: "")
            .trimmingCharacters(in: .whitespaces)
        return cleaned.count >= 3 && cleaned.allSatisfy { $0 == "-" || $0.isWhitespace }
    }

    private static func tableCells(_ line: String) -> [String] {
        var trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("|") { trimmed.removeFirst() }
        if trimmed.hasSuffix("|") { trimmed.removeLast() }
        return trimmed.split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }
}
