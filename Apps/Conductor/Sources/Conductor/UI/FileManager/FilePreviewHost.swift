import AppKit
import SwiftUI

@ViewBuilder
@MainActor
func filePreviewBody(
    state: FilePreviewState,
    rootURL: URL,
    currentURL: URL?,
    theme: TerminalTheme,
    terminalFontSize: CGFloat,
    fontFamily: AppearanceFontFamily,
    fontScale: AppearanceFontScale
) -> some View {
    switch state {
    case .empty:
        filePreviewMessage(
            systemImage: "doc.text.magnifyingglass",
            text: fileManagerL("选择文件开始预览", "Select a file to preview"),
            theme: theme,
            fontFamily: fontFamily,
            fontScale: fontScale
        )
    case .loading:
        filePreviewMessage(
            systemImage: "hourglass",
            text: fileManagerL("读取中", "Loading"),
            theme: theme,
            fontFamily: fontFamily,
            fontScale: fontScale
        )
    case .directory(let message):
        filePreviewMessage(
            systemImage: "folder",
            text: message,
            theme: theme,
            fontFamily: fontFamily,
            fontScale: fontScale
        )
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
            filePreviewMessage(
                systemImage: isLoading ? "hourglass" : "photo",
                text: isLoading ? fileManagerL("正在读取图片", "Loading image") : fileManagerL("图片无法读取", "Image could not be loaded"),
                theme: theme,
                fontFamily: fontFamily,
                fontScale: fontScale
            )
        }
    case .document(let url):
        ConductorDocumentWorkspaceView(
            fileURL: url,
            rootURL: currentURL ?? rootURL,
            title: url.lastPathComponent,
            theme: theme,
            fontSize: terminalFontSize,
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
            filePreviewInfoBar(height: 28, theme: theme) {
                HStack(spacing: 7) {
                    Label {
                        filePreviewInfoLabel(
                            descriptor.title,
                            theme: theme,
                            fontFamily: fontFamily,
                            fontScale: fontScale
                        )
                    } icon: {
                        Image(systemName: "eye")
                            .font(.conductorSystem(size: 9.5, weight: .semibold, family: fontFamily, scale: fontScale))
                    }
                    .labelStyle(.titleAndIcon)
                    Text(descriptor.reason)
                        .font(.conductorSystem(size: 10, weight: .semibold, family: fontFamily, scale: fontScale))
                        .foregroundStyle(theme.shellChromeText.opacity(0.48))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 0)
                }
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
        filePreviewMessage(
            systemImage: "doc",
            text: message,
            theme: theme,
            fontFamily: fontFamily,
            fontScale: fontScale
        )
    case .failed(let message):
        filePreviewMessage(
            systemImage: "exclamationmark.triangle",
            text: message,
            theme: theme,
            fontFamily: fontFamily,
            fontScale: fontScale
        )
    }
}

@MainActor
private func filePreviewInfoBar<Content: View>(
    height: CGFloat,
    theme: TerminalTheme,
    horizontalPadding: CGFloat = 12,
    @ViewBuilder content: () -> Content
) -> some View {
    VStack(spacing: 0) {
        content()
            .padding(.horizontal, horizontalPadding)
            .frame(height: height)
        filePreviewSeparator(theme: theme)
    }
    .background(ConductorTokens.Settings.panelChromeWash(dark: theme.usesDarkChrome))
}

@MainActor
private func filePreviewSeparator(theme: TerminalTheme) -> some View {
    Rectangle()
        .fill(ConductorTokens.Settings.subtleSeparator(dark: theme.usesDarkChrome))
        .frame(height: 1)
}

@MainActor
private func filePreviewInfoLabel(
    _ title: String,
    theme: TerminalTheme,
    fontFamily: AppearanceFontFamily,
    fontScale: AppearanceFontScale
) -> some View {
    Text(title)
        .font(.conductorSystem(size: 10, weight: .semibold, family: fontFamily, scale: fontScale))
        .foregroundStyle(theme.shellChromeText.opacity(0.52))
        .lineLimit(1)
        .frame(height: 19)
}

@MainActor
private func filePreviewMessage(
    systemImage: String,
    text: String,
    theme: TerminalTheme,
    fontFamily: AppearanceFontFamily,
    fontScale: AppearanceFontScale
) -> some View {
    ContentUnavailableView {
        Label(text, systemImage: systemImage)
    }
    .overlay(alignment: .topTrailing) {
        if systemImage == "hourglass" {
            ProgressView()
                .controlSize(.small)
                .padding(14)
        }
    }
    .font(.conductorSystem(size: 12, weight: .semibold, family: fontFamily, scale: fontScale))
    .foregroundStyle(theme.shellChromeText.opacity(0.58))
    .frame(maxWidth: .infinity, maxHeight: .infinity)
}

struct FileManagerSourcePreview: View {
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
        filePreviewInfoBar(height: 44, theme: theme, horizontalPadding: 14) {
            HStack(spacing: 10) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(document.formatLabel ?? fileManagerL("文本预览", "Text Preview"))
                            .font(.conductorSystem(size: 12, weight: .bold, family: fontFamily, scale: fontScale))
                            .foregroundStyle(theme.shellChromeText.opacity(0.82))
                        Text(sourceSubtitle)
                            .font(.conductorSystem(size: 10, weight: .semibold, family: fontFamily, scale: fontScale))
                            .foregroundStyle(theme.shellChromeText.opacity(0.45))
                            .lineLimit(1)
                    }
                } icon: {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.conductorSystem(size: 11, weight: .semibold, family: fontFamily, scale: fontScale))
                        .foregroundStyle(theme.shellChromeText.opacity(0.58))
                }
                .labelStyle(.titleAndIcon)
                Spacer(minLength: 0)
                filePreviewInfoLabel(
                    fileManagerL("\(document.lineCount) 行", "\(document.lineCount) lines"),
                    theme: theme,
                    fontFamily: fontFamily,
                    fontScale: fontScale
                )
                if document.isLineLimited { infoLabel(fileManagerL("前 \(document.displayedLineCount) 行", "First \(document.displayedLineCount) lines")) }
                if truncated { infoLabel(fileManagerL("前 256 KB", "First 256 KB")) }
            }
        }
    }

    private var sourceSubtitle: String {
        if truncated || document.isLineLimited {
            return fileManagerL("轻量预览已限制读取和渲染范围，完整编辑请在工作区打开。", "Light preview is bounded; open in workspace for the full file.")
        }
        return fileManagerL("轻量文本阅读器", "Lightweight text reader")
    }

    private func infoLabel(_ title: String) -> some View {
        filePreviewInfoLabel(title, theme: theme, fontFamily: fontFamily, fontScale: fontScale)
    }

    private static let swiftUIRenderedLineLimit = 180
}

struct FileManagerTablePreview: View {
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
                    lineNumberTextColor: NSColor(theme.shellChromeText.opacity(0.34))
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

                                ForEach(0..<document.columnCount, id: \.self) { columnIndex in
                                    Text(cell(row: row.values, columnIndex: columnIndex))
                                        .font(.system(size: 11.5, weight: row.index == 0 ? .semibold : .regular, design: .monospaced))
                                        .foregroundStyle(theme.shellChromeText.opacity(row.index == 0 ? 0.82 : 0.74))
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                        .padding(.horizontal, 8)
                                        .frame(width: Self.cellWidth, height: Self.rowHeight, alignment: .leading)
                                        .contextMenu {
                                            Button(fileManagerL("复制单元格", "Copy Cell")) {
                                                copyText(cell(row: row.values, columnIndex: columnIndex))
                                            }
                                            Button(fileManagerL("复制行", "Copy Row")) {
                                                copyText(row.values.joined(separator: document.delimiterName == "TSV" ? "\t" : ","))
                                            }
                                        }
                                }
                            }
                            .overlay(alignment: .bottom) {
                                filePreviewSeparator(theme: theme)
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
        filePreviewInfoBar(height: 28, theme: theme) {
            HStack(spacing: 7) {
                infoLabel(document.delimiterName)
                infoLabel(fileManagerL("\(document.sourceLineCount) 行", "\(document.sourceLineCount) lines"))
                infoLabel(fileManagerL("\(document.columnCount) 列", "\(document.columnCount) columns"))
                infoLabel(fileManagerL("预览前 \(document.rows.count) 行", "Previewing \(document.rows.count) rows"))
                if truncated {
                    infoLabel(fileManagerL("仅读取前 256 KB", "First 256 KB only"))
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func cell(row: [String], columnIndex: Int) -> String {
        guard row.indices.contains(columnIndex) else { return "" }
        let value = row[columnIndex]
        guard value.count > 160 else { return value }
        return String(value.prefix(160)) + " ..."
    }

    private func copyText(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func infoLabel(_ title: String) -> some View {
        filePreviewInfoLabel(title, theme: theme, fontFamily: fontFamily, fontScale: fontScale)
    }

    private static let swiftUICellLimit = 600
    private static let rowHeight: CGFloat = 26
    private static let cellWidth: CGFloat = 156
}

struct FileManagerKeyValuePreview: View {
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
                    lineNumberTextColor: NSColor(theme.shellChromeText.opacity(0.34))
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

                                Text(row.key)
                                    .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(theme.shellChromeText.opacity(0.82))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .padding(.horizontal, 8)
                                    .frame(width: 210, height: 27, alignment: .leading)

                                Text(row.value)
                                    .font(.system(size: 11.5, weight: .regular, design: .monospaced))
                                    .foregroundStyle(theme.shellChromeText.opacity(0.72))
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    .padding(.horizontal, 8)
                                    .frame(width: 360, height: 27, alignment: .leading)
                            }
                            .contextMenu {
                                Button(fileManagerL("复制 Key", "Copy Key")) {
                                    copyText(row.key)
                                }
                                Button(fileManagerL("复制 Value", "Copy Value")) {
                                    copyText(row.value)
                                }
                                Button(fileManagerL("复制整行", "Copy Line")) {
                                    copyText(row.raw)
                                }
                            }
                            .overlay(alignment: .bottom) {
                                filePreviewSeparator(theme: theme)
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
        filePreviewInfoBar(height: 28, theme: theme) {
            HStack(spacing: 7) {
                infoLabel(document.formatLabel)
                infoLabel(fileManagerL("\(document.rows.count) 个键值", "\(document.rows.count) pairs"))
                infoLabel(fileManagerL("\(document.sourceLineCount) 行", "\(document.sourceLineCount) lines"))
                if truncated {
                    infoLabel(fileManagerL("仅读取前 256 KB", "First 256 KB only"))
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func infoLabel(_ title: String) -> some View {
        filePreviewInfoLabel(title, theme: theme, fontFamily: fontFamily, fontScale: fontScale)
    }

    private func copyText(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private static let swiftUIRowLimit = 160
}

struct FileManagerStructuredPreview: View {
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
                    valueTextColor: NSColor(theme.shellChromeText.opacity(0.78))
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
                                Button(fileManagerL("复制路径", "Copy Path")) {
                                    copyText(row.path)
                                }
                                Button(fileManagerL("复制键", "Copy Key")) {
                                    copyText(row.key)
                                }
                                Button(fileManagerL("复制值", "Copy Value")) {
                                    copyText(row.value)
                                }
                                Button(fileManagerL("复制路径和值", "Copy Path and Value")) {
                                    copyText("\(row.path) = \(row.value)")
                                }
                            }
                            .overlay(alignment: .bottom) {
                                filePreviewSeparator(theme: theme)
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
        filePreviewInfoBar(height: 28, theme: theme) {
            HStack(spacing: 7) {
                infoLabel(document.formatLabel)
                infoLabel(fileManagerL("\(document.rows.count) 个节点", "\(document.rows.count) nodes"))
                infoLabel(fileManagerL("\(document.sourceLineCount) 行", "\(document.sourceLineCount) lines"))
                if truncated {
                    infoLabel(fileManagerL("仅读取前 256 KB", "First 256 KB only"))
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func infoLabel(_ title: String) -> some View {
        filePreviewInfoLabel(title, theme: theme, fontFamily: fontFamily, fontScale: fontScale)
    }

    private func copyText(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private static let swiftUIRowLimit = 160
}

struct SourcePreviewLine: View {
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
        .background(isHighlighted ? theme.floatingSelectedFill : Color.clear)
    }

}
