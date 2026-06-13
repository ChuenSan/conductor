import Foundation

/// 一个远程仓库。移植自 SourceGit `Models.Remote`（简化版：名字 + fetch URL）。
public struct GitRemote: Sendable, Equatable, Identifiable {
    public var name: String
    public var url: String

    public var id: String { self.name }

    public init(name: String, url: String) {
        self.name = name
        self.url = url
    }
}
