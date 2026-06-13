import Foundation

/// 逐 hunk 暂存/取消暂存：把单个 hunk 重建成补丁，`git apply --cached` 到 index。
/// 移植自 SourceGit `Commands.Apply` 的部分暂存路径。
public enum ApplyPatch {
    /// 把补丁应用到 index（暂存这部分改动）。
    public static func stage(_ repo: GitRepository, patch: String) async throws {
        try await self.apply(repo, patch: patch, reverse: false)
    }

    /// 反向应用到 index（取消暂存这部分改动）。
    public static func unstage(_ repo: GitRepository, patch: String) async throws {
        try await self.apply(repo, patch: patch, reverse: true)
    }

    private static func apply(_ repo: GitRepository, patch: String, reverse: Bool) async throws {
        var text = patch
        if !text.hasSuffix("\n") { text += "\n" }
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("conductor-hunk-\(UUID().uuidString).patch")
        try text.write(to: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }

        var args = ["apply", "--cached", "--whitespace=nowarn"]
        if reverse { args.append("--reverse") }
        args.append(tmp.path)
        _ = try await repo.git(args).run()
    }
}
