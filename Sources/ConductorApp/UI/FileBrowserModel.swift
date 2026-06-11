import Foundation

/// 文件视图里的一条目录项（纯数据，可单测）。
struct FileBrowserEntry: Identifiable, Equatable {
    let name: String
    let path: String
    let isDirectory: Bool
    let isHidden: Bool
    let size: Int?            // 文件字节数；目录为 nil
    let modifiedAt: Date?
    /// 目录下有 .git → 树里标记 git 仓库。
    var isGitRepo: Bool = false

    var id: String { path }
}

/// 把路径包进单引号给 shell（内部单引号按 POSIX 规则转义）。
enum ShellQuoting {
    static func quote(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

/// 目录列举与排序：纯逻辑，便于单测。
enum FileBrowserLister {
    /// 列举目录内容。目录优先，组内按名称本地化排序；`showHidden` 为 false 时过滤隐藏项。
    static func list(directory: String, showHidden: Bool, fileManager: FileManager = .default) -> [FileBrowserEntry] {
        let url = URL(fileURLWithPath: directory, isDirectory: true)
        let keys: [URLResourceKey] = [.isDirectoryKey, .isHiddenKey, .fileSizeKey, .contentModificationDateKey]
        guard let children = try? fileManager.contentsOfDirectory(
            at: url, includingPropertiesForKeys: keys, options: [])
        else { return [] }

        let entries = children.compactMap { child -> FileBrowserEntry? in
            let values = try? child.resourceValues(forKeys: Set(keys))
            let isDirectory = values?.isDirectory ?? false
            let entry = FileBrowserEntry(
                name: child.lastPathComponent,
                path: child.path,
                isDirectory: isDirectory,
                isHidden: values?.isHidden ?? child.lastPathComponent.hasPrefix("."),
                size: values?.fileSize,
                modifiedAt: values?.contentModificationDate,
                isGitRepo: isDirectory && fileManager.fileExists(
                    atPath: child.appendingPathComponent(".git").path))
            if !showHidden, entry.isHidden { return nil }
            return entry
        }
        return sorted(entries)
    }

    /// 目录在前，组内按名称排序（大小写不敏感、数字感知）。
    static func sorted(_ entries: [FileBrowserEntry]) -> [FileBrowserEntry] {
        entries.sorted { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }

    /// 仅子目录（侧栏文件夹树用）。
    static func subdirectories(of path: String, showHidden: Bool = false,
                               fileManager: FileManager = .default) -> [FileBrowserEntry] {
        list(directory: path, showHidden: showHidden, fileManager: fileManager)
            .filter(\.isDirectory)
    }

    /// 把绝对路径拆成面包屑段：`[("/", "/"), ("Users", "/Users"), …]`。
    static func breadcrumb(for path: String) -> [(name: String, path: String)] {
        let components = (path as NSString).pathComponents
        var crumbs: [(String, String)] = []
        var current = ""
        for component in components {
            if component == "/" {
                current = "/"
                crumbs.append(("/", "/"))
            } else {
                current = (current as NSString).appendingPathComponent(component)
                crumbs.append((component, current))
            }
        }
        return crumbs
    }
}
