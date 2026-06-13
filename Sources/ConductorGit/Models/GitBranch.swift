import Foundation

/// 一个本地或远程分支。移植自 SourceGit `Models.Branch`。
public struct GitBranch: Sendable, Equatable, Identifiable {
    public var name: String = ""
    /// 完整 ref 名，如 `refs/heads/main`、`refs/remotes/origin/main`。
    public var fullName: String = ""
    public var committerDate: Int = 0
    /// 指向的提交 SHA。
    public var head: String = ""
    public var isLocal: Bool = true
    public var isCurrent: Bool = false
    public var isDetachedHead: Bool = false
    /// 上游 ref 全名（仅本地分支有）。
    public var upstream: String = ""
    public var remote: String = ""
    public var isUpstreamGone: Bool = false
    public var worktreePath: String = ""
    /// 领先/落后上游的提交数（按需由 QueryTrackStatus 填充）。
    public var ahead: Int = 0
    public var behind: Int = 0

    public var id: String { self.fullName.isEmpty ? self.name : self.fullName }

    public var friendlyName: String { self.isLocal ? self.name : "\(self.remote)/\(self.name)" }
    public var isTrackStatusVisible: Bool { self.ahead > 0 || self.behind > 0 }

    /// 形如 `2↑ 1↓` 的领先/落后描述。
    public var trackStatusDescription: String {
        if self.ahead > 0 {
            return self.behind > 0 ? "\(self.ahead)↑ \(self.behind)↓" : "\(self.ahead)↑"
        }
        return self.behind > 0 ? "\(self.behind)↓" : ""
    }

    public init() {}
}
