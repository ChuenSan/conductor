import Foundation

/// 一个文件相对 index / 工作区的变更状态。移植自 SourceGit `Models.ChangeState`。
public enum GitChangeState: Sendable, Equatable {
    case none
    case modified
    case typeChanged
    case added
    case deleted
    case renamed
    case copied
    case untracked
    case conflicted
}

/// 冲突原因（porcelain 的 DD/AU/UU 等）。移植自 SourceGit `Models.ConflictReason`。
public enum GitConflictReason: Sendable, Equatable {
    case none
    case bothDeleted
    case addedByUs
    case deletedByThem
    case addedByThem
    case deletedByUs
    case bothAdded
    case bothModified
}

/// 一个工作区/暂存区变更条目。移植自 SourceGit `Models.Change`。
///
/// `index` 是相对 HEAD 已暂存的状态（porcelain 第 1 列 X），
/// `workTree` 是工作区相对 index 的状态（第 2 列 Y）。
public struct GitChange: Sendable, Equatable, Identifiable {
    public var index: GitChangeState = .none
    public var workTree: GitChangeState = .none
    public var path: String = ""
    /// 重命名/复制时的原路径。
    public var originalPath: String = ""
    public var conflictReason: GitConflictReason = .none

    public var id: String { self.path }

    public var isConflicted: Bool { self.workTree == .conflicted }
    /// 是否有已暂存的改动（index 列非 none，且不是未跟踪/冲突的占位）。
    public var isStaged: Bool { self.index != .none && self.index != .untracked }
    /// 是否有未暂存的工作区改动。
    public var hasWorkTreeChange: Bool { self.workTree != .none }

    public init() {}

    public init(
        index: GitChangeState,
        workTree: GitChangeState,
        path: String,
        originalPath: String = "",
        conflictReason: GitConflictReason = .none)
    {
        self.index = index
        self.workTree = workTree
        self.path = path
        self.originalPath = originalPath
        self.conflictReason = conflictReason
    }

    /// 设置 index/workTree，并按需从 `path` 中拆出 "orig -> new" 重命名对、去掉外层引号。
    /// 移植自 SourceGit `Change.Set`。
    mutating func apply(index: GitChangeState, workTree: GitChangeState = .none) {
        self.index = index
        self.workTree = workTree

        if index == .renamed || index == .copied || workTree == .renamed {
            var parts = self.path.components(separatedBy: "\t")
            if parts.count < 2 {
                parts = self.path.components(separatedBy: " -> ")
            }
            if parts.count == 2 {
                self.originalPath = parts[0]
                self.path = parts[1]
            }
        }

        self.path = Self.unquote(self.path)
        if !self.originalPath.isEmpty {
            self.originalPath = Self.unquote(self.originalPath)
        }
    }

    private static func unquote(_ s: String) -> String {
        guard s.count >= 2, s.hasPrefix("\""), s.hasSuffix("\"") else { return s }
        return String(s.dropFirst().dropLast())
    }
}
