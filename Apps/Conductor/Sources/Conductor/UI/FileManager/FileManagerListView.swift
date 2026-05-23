import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct FileManagerListView: View {
    @ObservedObject var store: FileManagerPanelStore
    let model: ConductorWindowModel
    let rootURL: URL
    @Binding var infoItem: FileManagerItem?
    let focusKeyboard: () -> Void

    @Environment(\.conductorTheme) private var theme
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorFontFamily) private var fontFamily

    var body: some View {
        VStack(spacing: 0) {
            if store.isLoading && store.items.isEmpty {
                panelMessage(systemImage: "folder", text: fileManagerL("读取中", "Loading"))
            } else if let error = store.errorMessage, store.items.isEmpty {
                panelMessage(systemImage: "exclamationmark.triangle", text: error)
            } else if store.items.isEmpty {
                panelMessage(systemImage: "folder", text: fileManagerL("没有文件", "No files"))
            } else if store.displaySnapshot.totalRowCount == 0 {
                panelMessage(systemImage: "line.3.horizontal.decrease", text: fileManagerL("没有匹配的文件", "No matching files"))
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        if store.displaySnapshot.visibleRange.lowerBound > 0 {
                            windowButton(
                                systemImage: "chevron.up",
                                title: fileManagerL("显示上一组", "Show previous")
                            ) {
                                store.showPreviousVisibleWindow()
                            }
                        }

                        ForEach(store.displaySnapshot.rows) { row in
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
                                toggleExpansion: { Task { await store.toggleDirectory(row.item) } },
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

                        if store.displaySnapshot.visibleRange.upperBound < store.displaySnapshot.totalRowCount {
                            windowButton(
                                systemImage: "chevron.down",
                                title: fileManagerL("显示下一组", "Show next")
                            ) {
                                store.showNextVisibleWindow()
                            }
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

    private func windowButton(systemImage: String, title: String, action: @escaping () -> Void) -> some View {
        let directionID = systemImage == "chevron.up" ? "previous" : "next"
        let visibleRange = store.displaySnapshot.visibleRange
        let rangeText = "\(visibleRange.lowerBound + 1)-\(visibleRange.upperBound)/\(store.displaySnapshot.totalRowCount)"

        return ConductorCommandButton(
            state: ConductorControlState(
                id: "file-manager.visible-window.\(directionID)",
                title: title,
                systemImage: systemImage,
                tooltip: title,
                accessibilityLabel: title
            ),
            fillsWidth: true,
            trailingText: rangeText,
            action: action
        )
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
            Task { await store.openDirectory(item) }
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
        model.openFileInWorkspace(item.url, rootURL: store.currentURL ?? rootURL)
        model.closeFileManagerPanel()
    }

    private var canPaste: Bool {
        FileManagerService().fileURLsFromPasteboard().isEmpty == false
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

    private func copyFiles(_ urls: [URL]) {
        FileManagerPasteboard.writeFiles(urls, cut: false)
    }

    private func cutFiles(_ urls: [URL]) {
        FileManagerPasteboard.writeFiles(urls, cut: true)
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

    private func itemsForBatch(default item: FileManagerItem) -> [FileManagerItem] {
        let selected = store.selectedItems
        guard store.selectedPaths.contains(item.url.path), !selected.isEmpty else {
            return [item]
        }
        return selected
    }

    private func relativePath(for url: URL) -> String {
        let root = rootURL.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path == root || path.hasPrefix(root + "/") else { return url.lastPathComponent }
        let suffix = path.dropFirst(root.count).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return suffix.isEmpty ? url.lastPathComponent : String(suffix)
    }

    private func shellEscapedPath(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url.standardizedFileURL])
    }
}

final class FileDropURLCollector: @unchecked Sendable {
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

func collectDroppedFileURLs(from providers: [NSItemProvider], completion: @escaping ([URL]) -> Void) {
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

struct FileManagerRowView: View {
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
    let toggleExpansion: () -> Void
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
                    Button(isExpanded ? fileManagerL("收起文件夹", "Collapse Folder") : fileManagerL("展开文件夹", "Expand Folder"), action: toggleExpansion)
                } else {
                    Button(fileManagerL("打开", "Open"), action: open)
                }
                Menu(fileManagerL("打开方式", "Open With")) {
                    Button(fileManagerL("工作区标签", "Workspace Tab"), action: openInWorkspace)
                        .disabled(item.isDirectory)
                    Button(fileManagerL("系统应用", "System App"), action: openInSystemApp)
                    Button(fileManagerL("在 Finder 中显示", "Reveal in Finder"), action: reveal)
                }
                Menu(fileManagerL("终端", "Terminal")) {
                    Button(fileManagerL("插入路径", "Insert Path"), action: insertPath)
                    Button(fileManagerL("插入 cd 命令", "Insert cd Command"), action: insertCDCommand)
                    Button(fileManagerL("插入 ls 命令", "Insert ls Command"), action: insertListCommand)
                }
                Menu(fileManagerL("复制为", "Copy As")) {
                    Button(fileManagerL("文件名", "Name"), action: copyName)
                    Button(fileManagerL("相对路径", "Relative Path"), action: copyRelativePath)
                    Button(fileManagerL("绝对路径", "Absolute Path"), action: copyPath)
                    Button(fileManagerL("所在目录", "Parent Directory"), action: copyDirectoryPath)
                    Button(fileManagerL("Shell 转义路径", "Shell Escaped Path"), action: copyShellPath)
                    Button(fileManagerL("终端可粘贴路径", "Terminal-ready Path"), action: copyShellPath)
                }
                Divider()
                Button(selectedCount > 1 ? fileManagerL("复制 \(selectedCount) 项", "Copy \(selectedCount) Items") : fileManagerL("复制", "Copy"), action: copyFile)
                Button(selectedCount > 1 ? fileManagerL("剪切 \(selectedCount) 项", "Cut \(selectedCount) Items") : fileManagerL("剪切", "Cut"), action: cutFile)
                Button(fileManagerL("粘贴", "Paste"), action: paste)
                    .disabled(!canPaste)
                Button(fileManagerL("复制副本", "Duplicate"), action: duplicate)
                Button(fileManagerL("显示信息", "Get Info"), action: showInfo)
                Button(fileManagerL("重命名...", "Rename..."), action: rename)
                Button(fileManagerL("在 Finder 中显示", "Reveal in Finder"), action: reveal)
                Divider()
                Button(role: .destructive, action: delete) {
                    Text(selectedCount > 1 ? fileManagerL("移到废纸篓 \(selectedCount) 项", "Move \(selectedCount) Items to Trash") : fileManagerL("移到废纸篓", "Move to Trash"))
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
                Button(action: toggleExpansion) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.conductorSystem(size: 8.5, weight: .bold, family: fontFamily, scale: fontScale))
                        .foregroundStyle(rowIconSecondaryColor)
                        .frame(width: 12, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isExpanded ? fileManagerL("收起文件夹", "Collapse Folder") : fileManagerL("展开文件夹", "Expand Folder"))
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
                    help: fileManagerL("符号链接", "Symbolic Link")
                )
            }

            if item.isReadable == false {
                statusBadge(
                    systemImage: "lock.slash",
                    help: fileManagerL("没有读取权限", "No Read Permission")
                )
            } else if item.isWritable == false {
                statusBadge(
                    systemImage: "lock",
                    help: fileManagerL("只读", "Read-only")
                )
            }

            if item.isLargeEditableFile {
                statusBadge(
                    systemImage: "exclamationmark.triangle",
                    help: fileManagerL("超过 20 MB，将以保护模式打开", "Over 20 MB; opens in protected mode")
                )
            } else if item.isUnsupportedBinaryLikeFile {
                statusBadge(
                    systemImage: "nosign",
                    help: fileManagerL("二进制或暂不支持内联预览", "Binary or unsupported inline preview")
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
