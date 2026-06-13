import Foundation

/// 一个 tag。移植自 SourceGit `Models.Tag`（简化）。
public struct GitTag: Sendable, Equatable, Identifiable {
    public var name: String
    /// 指向的提交 SHA（annotated tag 已解引用到提交）。
    public var sha: String
    public var time: Int
    public var message: String

    public var id: String { self.name }

    public init(name: String, sha: String, time: Int, message: String = "") {
        self.name = name
        self.sha = sha
        self.time = time
        self.message = message
    }
}
