import Foundation

/// blame 的一行：哪个提交、谁、何时、内容。
public struct GitBlameLine: Sendable, Equatable, Identifiable {
    public var lineNumber: Int
    public var sha: String
    public var author: String
    public var time: Int
    public var content: String

    public var id: Int { self.lineNumber }
    public var shortSHA: String { String(self.sha.prefix(8)) }

    public init(lineNumber: Int, sha: String, author: String, time: Int, content: String) {
        self.lineNumber = lineNumber
        self.sha = sha
        self.author = author
        self.time = time
        self.content = content
    }
}

public struct GitBlame: Sendable, Equatable {
    public var lines: [GitBlameLine] = []
    public var isBinary: Bool = false

    public init() {}
}
