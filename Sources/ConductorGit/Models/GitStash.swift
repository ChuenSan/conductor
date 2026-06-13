import Foundation

/// 一条 stash。移植自 SourceGit `Models.Stash`（简化版）。
public struct GitStash: Sendable, Equatable, Identifiable {
    /// stash 的 ref，如 `stash@{0}`。
    public var name: String
    public var sha: String
    public var time: Int
    public var message: String

    public var id: String { self.name }
    public var date: Date { Date(timeIntervalSince1970: TimeInterval(self.time)) }

    public init(name: String, sha: String, time: Int, message: String) {
        self.name = name
        self.sha = sha
        self.time = time
        self.message = message
    }
}
