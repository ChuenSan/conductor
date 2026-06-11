import AppKit
import SwiftUI

// MARK: - 纯逻辑（可单测）

/// 侧栏文件夹树拍平后的一行。
struct FolderTreeRow: Identifiable, Equatable {
    let name: String
    let path: String
    let depth: Int
    let isExpanded: Bool

    var id: String { path }
}

/// 树 → 行数组的拍平逻辑：根路径 + 已展开集合 + 子目录缓存（按需加载）。
enum FolderTreeFlattener {
    static func rows(root: String, rootName: String,
                     expanded: Set<String>,
                     children: [String: [FileBrowserEntry]]) -> [FolderTreeRow] {
        var out: [FolderTreeRow] = []
        func visit(name: String, path: String, depth: Int) {
            let isExpanded = expanded.contains(path)
            out.append(FolderTreeRow(name: name, path: path, depth: depth, isExpanded: isExpanded))
            guard isExpanded else { return }
            for child in children[path] ?? [] {
                visit(name: child.name, path: child.path, depth: depth + 1)
            }
        }
        visit(name: rootName, path: root, depth: 0)
        return out
    }
}

// MARK: - 状态

/// 侧栏文件夹树状态：展开集合（跨启动持久化）+ 子目录懒加载缓存 + 隐藏文件夹开关。
@MainActor
final class FolderTreeModel: ObservableObject {
    private static let expandedKey = "sidebar.folderTree.expanded"
    private static let showHiddenKey = "sidebar.folderTree.showHidden"

    let root = FileManager.default.homeDirectoryForCurrentUser.path
    @Published private(set) var expanded: Set<String>
    @Published private(set) var children: [String: [FileBrowserEntry]] = [:]
    @Published private(set) var showHidden: Bool

    init() {
        let saved = UserDefaults.standard.stringArray(forKey: Self.expandedKey) ?? []
        showHidden = UserDefaults.standard.bool(forKey: Self.showHiddenKey)
        // 只恢复仍然存在的目录（被删/改名的丢弃），根目录始终展开。
        var restored = Set(saved.filter { FileManager.default.fileExists(atPath: $0) })
        restored.insert(root)
        expanded = restored
        for path in restored { loadChildren(of: path) }
    }

    var rows: [FolderTreeRow] {
        FolderTreeFlattener.rows(root: root, rootName: "~", expanded: expanded, children: children)
    }

    func toggle(_ path: String) {
        if expanded.contains(path), path != root {
            expanded.remove(path)
        } else {
            expanded.insert(path)
            // 重新进入时刷新一次，目录内容可能已变
            loadChildren(of: path)
        }
        persistExpanded()
    }

    /// 重新读取某目录（及其已展开后代）的子目录列表。
    func refresh(_ path: String) {
        loadChildren(of: path)
        for sub in expanded where sub.hasPrefix(path + "/") {
            loadChildren(of: sub)
        }
    }

    func setShowHidden(_ show: Bool) {
        guard show != showHidden else { return }
        showHidden = show
        UserDefaults.standard.set(show, forKey: Self.showHiddenKey)
        // 开关影响所有已加载目录，全部重读
        for path in children.keys { loadChildren(of: path) }
    }

    private func persistExpanded() {
        UserDefaults.standard.set(Array(expanded).sorted(), forKey: Self.expandedKey)
    }

    private func loadChildren(of path: String) {
        children[path] = FileBrowserLister.subdirectories(of: path, showHidden: showHidden)
    }
}

// MARK: - 视图

/// 侧栏「文件夹」模式：从家目录开始的目录树，点击展开/收起下级。
/// 行内悬停按钮或右键「在此开终端」→ 新标签在该目录起 shell。
struct SidebarFolderTree: View {
    @ObservedObject var coordinator: AppCoordinator
    @ObservedObject var model: FolderTreeModel

    var body: some View {
        let thinkingCwds = coordinator.thinkingCwds
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(model.rows) { row in
                FolderTreeRowView(
                    row: row,
                    // 已加载且无子目录 → 不画箭头（叶子目录），视觉更干净
                    isKnownLeaf: model.children[row.path]?.isEmpty == true,
                    // 思考中 pane 的 cwd 等于该目录或在其之下 → 整条祖先链都有动效，折叠时也能看见
                    isThinking: thinkingCwds.contains {
                        $0 == row.path || $0.hasPrefix(row.path + "/")
                    },
                    onToggle: {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                            model.toggle(row.path)
                        }
                    },
                    onOpenTerminal: { coordinator.newTab(atDirectory: row.path) }
                )
                .contextMenu {
                    Button { coordinator.newTab(atDirectory: row.path) } label: {
                        Label(L("在此目录打开终端"), systemImage: "terminal")
                    }
                    Divider()
                    Button { coordinator.revealInFinder(row.path) } label: {
                        Label(L("在 Finder 中显示"), systemImage: "folder")
                    }
                    Button { coordinator.copyToClipboard(row.path) } label: {
                        Label(L("复制路径"), systemImage: "doc.on.doc")
                    }
                    Divider()
                    Button { model.refresh(row.path) } label: {
                        Label(L("刷新"), systemImage: "arrow.clockwise")
                    }
                    Button { model.setShowHidden(!model.showHidden) } label: {
                        Label(L("显示隐藏文件夹"),
                              systemImage: model.showHidden ? "checkmark" : "eye.slash")
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

private struct FolderTreeRowView: View {
    let row: FolderTreeRow
    let isKnownLeaf: Bool
    let isThinking: Bool
    let onToggle: () -> Void
    let onOpenTerminal: () -> Void
    @State private var hovering = false

    /// 每级缩进宽度（层级参考线画在每格中央）。
    private static let indentWidth: CGFloat = 14
    private var isRoot: Bool { row.depth == 0 }

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 6) {
                indentGuides
                disclosure
                folderGlyph
                Text(row.name)
                    .font(.system(size: 12.5, weight: isRoot ? .semibold : .regular))
                    .foregroundStyle(isRoot || hovering ? AppStyle.textPrimary : AppStyle.textSecondary)
                    .lineLimit(1)
                if isThinking {
                    ThinkingIndicator(size: 7)
                }
                Spacer(minLength: 0)
                if hovering {
                    Button(action: onOpenTerminal) {
                        Image(systemName: "terminal")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(AppStyle.accent)
                            .frame(width: 20, height: 20)
                            .background(Circle().fill(AppStyle.accent.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                    .help(L("在此目录开终端"))
                }
            }
            .padding(.leading, 8)
            .padding(.trailing, 6)
            .frame(height: 27)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(hovering ? AppStyle.hoverFill : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    /// 层级参考线：每级一条贯穿行高的细竖线，折叠树常见的视觉锚点。
    @ViewBuilder
    private var indentGuides: some View {
        if row.depth > 0 {
            HStack(spacing: 0) {
                ForEach(0..<row.depth, id: \.self) { _ in
                    Rectangle()
                        .fill(AppStyle.separator.opacity(0.6))
                        .frame(width: 1)
                        .frame(width: Self.indentWidth)
                }
            }
            .frame(height: 27)
        }
    }

    /// 展开箭头；已知叶子目录画一个小圆点占位，避免箭头点了没反应的困惑。
    @ViewBuilder
    private var disclosure: some View {
        ZStack {
            if isKnownLeaf {
                Circle()
                    .fill(AppStyle.textTertiary.opacity(0.45))
                    .frame(width: 3, height: 3)
            } else {
                Image(systemName: "chevron.right")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(hovering ? AppStyle.textSecondary : AppStyle.textTertiary)
                    .rotationEffect(.degrees(row.isExpanded ? 90 : 0))
            }
        }
        .frame(width: 12, height: 12)
    }

    /// 文件夹图标：根目录用小房子；展开的目录用主题色渐变填充，未展开用中性灰。
    private var folderGlyph: some View {
        Image(systemName: isRoot ? "house.fill" : (row.isExpanded ? "folder.fill" : "folder"))
            .font(.system(size: isRoot ? 11.5 : 12, weight: .medium))
            .foregroundStyle(
                row.isExpanded || isRoot
                    ? AnyShapeStyle(LinearGradient(
                        colors: [AppStyle.accent, AppStyle.accent.opacity(0.7)],
                        startPoint: .top, endPoint: .bottom))
                    : AnyShapeStyle(AppStyle.textTertiary))
            .frame(width: 17, height: 16)
    }
}
