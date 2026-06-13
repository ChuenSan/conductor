import Foundation

/// 提交作者/提交者。移植自 SourceGit `Models.User`。
public struct GitUser: Sendable, Equatable {
    public var name: String
    public var email: String

    public static let invalid = GitUser(name: "", email: "")

    public init(name: String, email: String) {
        self.name = name
        self.email = email
    }

    /// 解析 `name±email` 形式（SourceGit 用 `±` 作分隔符，避免和邮箱里的字符冲突）。
    public static func parse(_ raw: String) -> GitUser {
        guard let sep = raw.range(of: "±") else {
            return GitUser(name: raw, email: "")
        }
        return GitUser(
            name: String(raw[raw.startIndex..<sep.lowerBound]),
            email: String(raw[sep.upperBound...]))
    }
}

/// 提交上的引用装饰（分支头/远程头/tag/HEAD）。移植自 SourceGit `Models.Decorator`。
public struct GitDecorator: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case currentBranchHead
        case currentCommitHead
        case localBranchHead
        case remoteBranchHead
        case tag
    }

    public var kind: Kind
    public var name: String

    public init(kind: Kind, name: String) {
        self.kind = kind
        self.name = name
    }
}

/// 一条提交记录。移植自 SourceGit `Models.Commit`。
public struct GitCommit: Sendable, Equatable, Identifiable {
    public var sha: String = ""
    public var parents: [String] = []
    public var author: GitUser = .invalid
    public var authorTime: Int = 0
    public var committer: GitUser = .invalid
    public var committerTime: Int = 0
    public var subject: String = ""
    public var decorators: [GitDecorator] = []
    /// 是否在当前分支历史里（log 解析时按 HEAD 装饰标记）。
    public var isMerged: Bool = false

    public var id: String { self.sha }

    public var shortSHA: String { String(self.sha.prefix(10)) }
    public var authorDate: Date { Date(timeIntervalSince1970: TimeInterval(self.authorTime)) }
    public var committerDate: Date { Date(timeIntervalSince1970: TimeInterval(self.committerTime)) }
    public var hasDecorators: Bool { !self.decorators.isEmpty }
    public var isCurrentHead: Bool {
        self.decorators.contains { $0.kind == .currentBranchHead || $0.kind == .currentCommitHead }
    }

    public init() {}

    /// 解析 `%P`（空格分隔的父提交）。
    mutating func parseParents(_ data: String) {
        self.parents = data
            .split(separator: " ", omittingEmptySubsequences: true)
            .map(String.init)
    }

    /// 解析 `%D`（decorate=full 的引用列表）。移植自 SourceGit `Commit.ParseDecorators`。
    mutating func parseDecorators(_ data: String) {
        guard data.count >= 3 else { return }
        for sub in data.split(separator: ",", omittingEmptySubsequences: true) {
            let d = sub.trimmingCharacters(in: .whitespaces)
            if d.hasSuffix("/HEAD") { continue }

            if d.hasPrefix("tag: refs/tags/") {
                self.decorators.append(.init(kind: .tag, name: String(d.dropFirst("tag: refs/tags/".count))))
            } else if d.hasPrefix("HEAD -> refs/heads/") {
                self.isMerged = true
                self.decorators.append(.init(
                    kind: .currentBranchHead, name: String(d.dropFirst("HEAD -> refs/heads/".count))))
            } else if d == "HEAD" {
                self.isMerged = true
                self.decorators.append(.init(kind: .currentCommitHead, name: d))
            } else if d.hasPrefix("refs/heads/") {
                self.decorators.append(.init(kind: .localBranchHead, name: String(d.dropFirst("refs/heads/".count))))
            } else if d.hasPrefix("refs/remotes/") {
                self.decorators.append(.init(
                    kind: .remoteBranchHead, name: String(d.dropFirst("refs/remotes/".count))))
            }
        }
    }
}
