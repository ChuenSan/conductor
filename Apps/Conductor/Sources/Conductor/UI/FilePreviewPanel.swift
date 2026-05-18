import AppKit
import ConductorCore
import MarkdownUI
import SwiftUI
import UniformTypeIdentifiers

struct FilePreviewPanel: View {
    @ObservedObject var model: ConductorWindowModel
    @State private var entries: [FilePreviewEntry] = []
    @State private var directoryLoading = false
    @State private var document = FilePreviewDocument.empty
    @Environment(\.conductorTheme) private var theme
    @Environment(\.conductorFontScale) private var fontScale

    private var rootURL: URL? {
        model.filePreview.rootURL
    }

    private var selectedURL: URL? {
        model.filePreview.selectedURL
    }

    var body: some View {
        ConductorGlassSurface(style: .panel, clarity: model.appearance.chromeClarity, interactive: true) {
            VStack(spacing: 0) {
                header
                panelDivider
                content
            }
            .padding(10)
        }
        .frame(maxHeight: .infinity)
        .onAppear {
            reloadDirectory()
            reloadDocument()
        }
        .onChange(of: model.filePreview.rootURL) {
            reloadDirectory()
        }
        .onChange(of: model.filePreview.selectedURL) {
            reloadDocument()
        }
    }

    private var header: some View {
        HStack(spacing: 9) {
            Image(systemName: "doc.richtext")
                .font(.conductorSystem(size: 12, weight: .semibold, scale: fontScale))
                .foregroundStyle(theme.floatingEmphasis.opacity(0.92))
                .frame(width: 24, height: 24)
                .background(theme.floatingControlFill)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text(selectedURL?.lastPathComponent ?? rootURL?.lastPathComponent ?? "文件预览")
                    .font(.conductorSystem(size: 13.5, weight: .bold, scale: fontScale))
                    .foregroundStyle(ConductorDesign.primaryText)
                    .lineLimit(1)
                Text(rootURL?.path(percentEncoded: false) ?? "当前终端路径")
                    .font(.conductorSystem(size: 10.5, weight: .medium, scale: fontScale))
                    .foregroundStyle(ConductorDesign.tertiaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            Button {
                revealInFinder()
            } label: {
                Image(systemName: "arrow.up.forward.app")
                    .font(.conductorSystem(size: 10.5, weight: .semibold, scale: fontScale))
                    .foregroundStyle(ConductorDesign.secondaryText)
                    .frame(width: 24, height: 24)
                    .background(theme.floatingControlFill)
                    .clipShape(Circle())
            }
            .buttonStyle(ConductorPressButtonStyle())
            .disabled(rootURL == nil && selectedURL == nil)
            .help("在 Finder 中显示")

            Button {
                ConductorMotion.perform {
                    model.closeFilePreview()
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.conductorSystem(size: 10, weight: .semibold, scale: fontScale))
                    .foregroundStyle(ConductorDesign.secondaryText)
                    .frame(width: 24, height: 24)
                    .background(theme.floatingControlFill)
                    .clipShape(Circle())
            }
            .buttonStyle(ConductorPressButtonStyle())
            .help("关闭预览")
        }
        .padding(.bottom, 9)
    }

    private var panelDivider: some View {
        Rectangle()
            .fill(theme.floatingSeparator)
            .frame(height: 1)
            .padding(.bottom, 9)
    }

    private var content: some View {
        VStack(spacing: 9) {
            pathBar
            HStack(spacing: 9) {
                directoryList
                    .frame(width: 138)
                previewSurface
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var pathBar: some View {
        HStack(spacing: 6) {
            Button {
                guard let rootURL else { return }
                let parent = rootURL.deletingLastPathComponent()
                guard parent.path != rootURL.path else { return }
                model.openFilePreview(parent, sourceTerminalID: model.filePreview.sourceTerminalID)
            } label: {
                Image(systemName: "chevron.up")
                    .font(.conductorSystem(size: 10, weight: .bold, scale: fontScale))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(ConductorPressButtonStyle())
            .disabled(rootURL == nil || rootURL?.path == "/")
            .help("上一级")

            Text(rootURL?.abbreviatedPath ?? "未选择路径")
                .font(.conductorSystem(size: 11, weight: .medium, scale: fontScale))
                .foregroundStyle(ConductorDesign.secondaryText)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 4)

            Button {
                reloadDirectory()
                reloadDocument()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.conductorSystem(size: 10, weight: .semibold, scale: fontScale))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(ConductorPressButtonStyle())
            .disabled(rootURL == nil)
            .help("刷新")
        }
        .foregroundStyle(ConductorDesign.secondaryText)
        .padding(.horizontal, 7)
        .frame(height: 30)
        .background(theme.floatingControlFill.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: ConductorTokens.Radius.row, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ConductorTokens.Radius.row, style: .continuous)
                .stroke(theme.floatingStroke, lineWidth: 1)
        }
    }

    private var directoryList: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("文件")
                    .font(.conductorSystem(size: 10.5, weight: .semibold, scale: fontScale))
                    .foregroundStyle(ConductorDesign.tertiaryText)
                Spacer()
                if directoryLoading {
                    ProgressView()
                        .controlSize(.mini)
                        .scaleEffect(0.58)
                }
            }

            if let error = model.filePreview.lastError {
                FilePreviewEmptyState(systemImage: "exclamationmark.triangle", title: error)
            } else if entries.isEmpty && !directoryLoading {
                FilePreviewEmptyState(systemImage: "folder", title: "这个目录为空")
            } else {
                ScrollView {
                    LazyVStack(spacing: 3) {
                        ForEach(entries) { entry in
                            FilePreviewEntryRow(
                                entry: entry,
                                selected: entry.url == selectedURL,
                                onSelect: {
                                    model.selectFilePreviewURL(entry.url)
                                }
                            )
                        }
                    }
                    .padding(.vertical, 1)
                }
                .scrollIndicators(.visible)
                .mask(ConductorVerticalFadeMask())
            }
        }
        .padding(8)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(theme.floatingControlFill.opacity(0.56))
        .clipShape(RoundedRectangle(cornerRadius: ConductorTokens.Radius.row, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ConductorTokens.Radius.row, style: .continuous)
                .stroke(theme.floatingStroke.opacity(0.76), lineWidth: 1)
        }
    }

    private var previewSurface: some View {
        ZStack {
            RoundedRectangle(cornerRadius: ConductorTokens.Radius.row, style: .continuous)
                .fill(theme.floatingControlStrongFill.opacity(0.62))
            RoundedRectangle(cornerRadius: ConductorTokens.Radius.row, style: .continuous)
                .stroke(theme.floatingStroke.opacity(0.76), lineWidth: 1)

            FilePreviewDocumentView(document: document)
                .padding(1)
        }
    }

    private func reloadDirectory() {
        guard let rootURL else {
            entries = []
            directoryLoading = false
            return
        }
        directoryLoading = true
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                FilePreviewEntry.load(from: rootURL)
            }.value
            guard rootURL == model.filePreview.rootURL else { return }
            switch result {
            case let .success(nextEntries):
                entries = nextEntries
            case .failure:
                entries = []
            }
            directoryLoading = false
        }
    }

    private func reloadDocument() {
        guard let selectedURL else {
            document = .empty
            return
        }
        document = .loading
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                FilePreviewDocument.load(from: selectedURL)
            }.value
            guard selectedURL == model.filePreview.selectedURL else { return }
            document = result
        }
    }

    private func revealInFinder() {
        if let targetURL = selectedURL ?? rootURL {
            NSWorkspace.shared.activateFileViewerSelecting([targetURL.standardizedFileURL])
        }
    }
}

private struct FilePreviewEntry: Identifiable, Equatable, Sendable {
    let id: String
    let url: URL
    let name: String
    let kind: FilePreviewContentKind
    let byteCount: Int64?

    var isDirectory: Bool {
        kind == .directory
    }

    var systemImage: String {
        switch kind {
        case .directory:
            "folder"
        case .markdown:
            "doc.richtext"
        case .image:
            "photo"
        case .text:
            "doc.plaintext"
        case .unsupported:
            "doc"
        }
    }

    var detail: String {
        if isDirectory {
            return "目录"
        }
        guard let byteCount else { return "文件" }
        return ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
    }

    static func load(from rootURL: URL) -> Result<[FilePreviewEntry], Error> {
        do {
            let resourceKeys: Set<URLResourceKey> = [
                .isDirectoryKey,
                .isHiddenKey,
                .fileSizeKey,
                .contentTypeKey
            ]
            let urls = try FileManager.default.contentsOfDirectory(
                at: rootURL,
                includingPropertiesForKeys: Array(resourceKeys),
                options: [.skipsPackageDescendants]
            )
            let entries = try urls.compactMap { url -> FilePreviewEntry? in
                let values = try url.resourceValues(forKeys: resourceKeys)
                if values.isHidden == true {
                    return nil
                }
                let isDirectory = values.isDirectory == true
                let kind = FilePreviewContentKind(url: url, isDirectory: isDirectory)
                return FilePreviewEntry(
                    id: url.path,
                    url: url.standardizedFileURL,
                    name: url.lastPathComponent,
                    kind: kind,
                    byteCount: values.fileSize.map(Int64.init)
                )
            }
            .sorted { lhs, rhs in
                if lhs.isDirectory != rhs.isDirectory {
                    return lhs.isDirectory && !rhs.isDirectory
                }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
            return .success(entries)
        } catch {
            return .failure(error)
        }
    }
}

private enum FilePreviewDocument: Equatable, Sendable {
    case empty
    case loading
    case markdown(String, baseURL: URL)
    case image(Data)
    case text(String)
    case unsupported(String)
    case error(String)

    static func load(from url: URL) -> FilePreviewDocument {
        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            return .empty
        }

        let kind = FilePreviewContentKind(url: url, isDirectory: false)
        do {
            switch kind {
            case .markdown:
                let markdown = try String(contentsOf: url, encoding: .utf8)
                return .markdown(markdown, baseURL: url.deletingLastPathComponent())
            case .image:
                return .image(try Data(contentsOf: url))
            case .text:
                let text = try String(contentsOf: url, encoding: .utf8)
                return .text(text)
            case .directory:
                return .empty
            case .unsupported:
                return .unsupported(url.lastPathComponent)
            }
        } catch {
            return .error(error.localizedDescription)
        }
    }
}

private struct FilePreviewDocumentView: View {
    let document: FilePreviewDocument
    @Environment(\.conductorTheme) private var theme

    var body: some View {
        switch document {
        case .empty:
            FilePreviewEmptyState(systemImage: "cursorarrow.click", title: "选择 Markdown 或图片")
        case .loading:
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .markdown(markdown, baseURL):
            ScrollView {
                Markdown(markdown, baseURL: baseURL, imageBaseURL: baseURL)
                    .markdownTheme(.gitHub)
                    .textSelection(.enabled)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.visible)
        case let .image(data):
            ScrollView([.horizontal, .vertical]) {
                if let image = NSImage(data: data) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding(12)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    FilePreviewEmptyState(systemImage: "photo", title: "图片无法读取")
                }
            }
            .scrollIndicators(.visible)
        case let .text(text):
            ScrollView {
                Text(text)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(ConductorDesign.primaryText)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
            }
            .scrollIndicators(.visible)
        case let .unsupported(name):
            FilePreviewEmptyState(systemImage: "doc", title: "暂不预览 \(name)")
        case let .error(message):
            FilePreviewEmptyState(systemImage: "exclamationmark.triangle", title: message)
        }
    }
}

private struct FilePreviewEntryRow: View {
    let entry: FilePreviewEntry
    let selected: Bool
    let onSelect: () -> Void
    @State private var hovering = false
    @Environment(\.conductorTheme) private var theme
    @Environment(\.conductorFontScale) private var fontScale

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 6) {
                Image(systemName: entry.systemImage)
                    .font(.conductorSystem(size: 10.5, weight: .semibold, scale: fontScale))
                    .foregroundStyle(iconColor)
                    .frame(width: 17)

                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.name)
                        .font(.conductorSystem(size: 11, weight: selected ? .semibold : .medium, scale: fontScale))
                        .foregroundStyle(ConductorDesign.primaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(entry.detail)
                        .font(.conductorSystem(size: 9.5, weight: .medium, scale: fontScale))
                        .foregroundStyle(ConductorDesign.tertiaryText)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 7)
            .frame(height: 36)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(rowFill)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { value in
            withAnimation(ConductorMotion.micro) {
                hovering = value
            }
        }
    }

    private var rowFill: Color {
        if selected {
            return theme.floatingSelectedFill
        }
        if hovering {
            return theme.floatingHoverFill
        }
        return Color.clear
    }

    private var iconColor: Color {
        if selected {
            return theme.floatingEmphasis
        }
        return entry.isDirectory ? ConductorDesign.secondaryText : ConductorDesign.tertiaryText
    }
}

private struct FilePreviewEmptyState: View {
    let systemImage: String
    let title: String
    @Environment(\.conductorFontScale) private var fontScale

    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.conductorSystem(size: 18, weight: .semibold, scale: fontScale))
                .foregroundStyle(ConductorDesign.tertiaryText)
            Text(title)
                .font(.conductorSystem(size: 11.5, weight: .semibold, scale: fontScale))
                .foregroundStyle(ConductorDesign.secondaryText)
                .multilineTextAlignment(.center)
                .lineLimit(3)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private extension URL {
    var abbreviatedPath: String {
        let path = path(percentEncoded: false)
        let home = FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false)
        if path == home {
            return "~"
        }
        if path.hasPrefix(home + "/") {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}
