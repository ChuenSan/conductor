import Foundation

/// 一个 git 工作区。`path` 是仓库顶层目录（`git rev-parse --show-toplevel`）。
///
/// 作为各命令的入口：所有 `Query*` / 写操作都挂在这里，工作目录统一用 `path`。
/// 对应 SourceGit 把 `repo` 路径透传给每个 `Command` 的做法。
public struct GitRepository: Sendable, Equatable {
    /// 仓库顶层目录的绝对路径。
    public let path: String

    public init(path: String) {
        self.path = path
    }

    /// 从任意目录（或其子目录）发现所属仓库的顶层目录。
    /// 不是 git 仓库则返回 nil。
    public static func discover(at directory: String) async -> GitRepository? {
        let result = try? await GitProcess(repository: directory, ["rev-parse", "--show-toplevel"])
            .run(allowFailure: true)
        guard let result, result.isSuccess else { return nil }
        let top = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !top.isEmpty else { return nil }
        return GitRepository(path: top)
    }

    /// 该目录是否位于某个 git 工作区内。
    public static func isInsideWorkTree(_ directory: String) async -> Bool {
        let result = try? await GitProcess(repository: directory, ["rev-parse", "--is-inside-work-tree"])
            .run(allowFailure: true)
        return result?.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "true"
    }

    /// 在该仓库上发起一次 git 调用。
    public func git(_ args: [String]) -> GitProcess {
        GitProcess(repository: self.path, args: args)
    }
}
