import AppKit
import SwiftUI

@ViewBuilder
func filePreviewBody(
    state: FilePreviewState,
    theme: TerminalTheme,
    fontFamily: AppearanceFontFamily,
    fontScale: AppearanceFontScale
) -> some View {
    switch state {
    case .empty:
        EmptyView()
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
    default:
        EmptyView()
    }
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
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(document.formatLabel ?? fileManagerL("文本预览", "Text Preview"))
                    .font(.conductorSystem(size: 12, weight: .bold, family: fontFamily, scale: fontScale))
                    .foregroundStyle(theme.shellChromeText.opacity(0.82))
                Text(sourceSubtitle)
                    .font(.conductorSystem(size: 10, weight: .semibold, family: fontFamily, scale: fontScale))
                    .foregroundStyle(theme.shellChromeText.opacity(0.45))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            infoPill(fileManagerL("\(document.lineCount) 行", "\(document.lineCount) lines"))
            if document.isLineLimited { infoPill(fileManagerL("前 \(document.displayedLineCount) 行", "First \(document.displayedLineCount) lines")) }
            if truncated { infoPill(fileManagerL("前 256 KB", "First 256 KB")) }
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
            return fileManagerL("轻量预览已限制读取和渲染范围，完整编辑请在工作区打开。", "Light preview is bounded; open in workspace for the full file.")
        }
        return fileManagerL("轻量文本阅读器", "Lightweight text reader")
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
            infoPill(fileManagerL("\(document.sourceLineCount) 行", "\(document.sourceLineCount) lines"))
            infoPill(fileManagerL("\(document.columnCount) 列", "\(document.columnCount) columns"))
            infoPill(fileManagerL("预览前 \(document.rows.count) 行", "Previewing \(document.rows.count) rows"))
            if truncated {
                infoPill(fileManagerL("仅读取前 256 KB", "First 256 KB only"))
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
            infoPill(fileManagerL("\(document.rows.count) 个键值", "\(document.rows.count) pairs"))
            infoPill(fileManagerL("\(document.sourceLineCount) 行", "\(document.sourceLineCount) lines"))
            if truncated {
                infoPill(fileManagerL("仅读取前 256 KB", "First 256 KB only"))
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
            infoPill(fileManagerL("\(document.rows.count) 个节点", "\(document.rows.count) nodes"))
            infoPill(fileManagerL("\(document.sourceLineCount) 行", "\(document.sourceLineCount) lines"))
            if truncated {
                infoPill(fileManagerL("仅读取前 256 KB", "First 256 KB only"))
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
        .background {
            Rectangle()
                .fill(isHighlighted ? theme.floatingSelectedFill.opacity(0.30) : Color.clear)
        }
    }

}

struct SourcePreviewMinimap: View {
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
