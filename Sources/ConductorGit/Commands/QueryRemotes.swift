import Foundation

/// `git remote -v` → `[GitRemote]`（取每个远程的 fetch URL，去重）。
public enum QueryRemotes {
    public static func run(_ repo: GitRepository) async throws -> [GitRemote] {
        let result = try await repo.git(["remote", "-v"]).run(allowFailure: true)
        guard result.isSuccess else { return [] }
        return self.parse(result.stdout)
    }

    /// 解析 `name<TAB>url (fetch|push)`，每个 remote 只保留 fetch URL，保序去重。纯函数。
    public static func parse(_ stdout: String) -> [GitRemote] {
        var order: [String] = []
        var urls: [String: String] = [:]
        for rawLine in stdout.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = String(rawLine)
            // 形如：origin\thttps://... (fetch)
            let tabSplit = line.components(separatedBy: "\t")
            guard tabSplit.count == 2 else { continue }
            let name = tabSplit[0]
            let rest = tabSplit[1]
            guard rest.hasSuffix("(fetch)") else { continue }
            let url = String(rest.dropLast("(fetch)".count)).trimmingCharacters(in: .whitespaces)
            if urls[name] == nil {
                order.append(name)
                urls[name] = url
            }
        }
        return order.map { GitRemote(name: $0, url: urls[$0] ?? "") }
    }
}
