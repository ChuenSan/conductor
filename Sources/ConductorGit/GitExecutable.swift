import ConductorCore
import Foundation

/// 解析 git 可执行文件路径并构建运行环境。
///
/// 复用 ConductorCore 的 `PathBuilder.effectivePATH`，与 app 其它进程调用拿到同一份 PATH，
/// 这样无论 git 装在 /usr/bin、Homebrew 还是别处都能找到。结果缓存一次。
public enum GitExecutable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cached: String?

    /// 常见安装位置，作为扫 PATH 之后的兜底。
    private static let wellKnownPaths = [
        "/usr/bin/git",
        "/opt/homebrew/bin/git",
        "/usr/local/bin/git",
    ]

    /// 解析 git 绝对路径。优先级：`GIT_EXECUTABLE` 覆盖 → effectivePATH → 常见位置。
    public static func resolve(fileManager: FileManager = .default) -> String? {
        self.lock.lock()
        if let cached {
            self.lock.unlock()
            return cached
        }
        self.lock.unlock()

        let resolved = self.locate(fileManager: fileManager)

        self.lock.lock()
        self.cached = resolved
        self.lock.unlock()
        return resolved
    }

    private static func locate(fileManager: FileManager) -> String? {
        let env = ProcessInfo.processInfo.environment

        // 1) 显式覆盖
        if let override = env["GIT_EXECUTABLE"], fileManager.isExecutableFile(atPath: override) {
            return override
        }

        // 2) effectivePATH（与 conductor 其它进程一致）
        let path = PathBuilder.effectivePATH(purposes: [.tty], env: env)
        for dir in path.split(separator: ":").map(String.init) where !dir.isEmpty {
            let candidate = "\(dir.hasSuffix("/") ? String(dir.dropLast()) : dir)/git"
            if fileManager.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }

        // 3) 常见位置兜底
        for candidate in self.wellKnownPaths where fileManager.isExecutableFile(atPath: candidate) {
            return candidate
        }

        return nil
    }

    /// 子进程环境：继承当前环境，覆盖 PATH，并禁止任何交互提示，保证 git 永不挂起。
    public static func environment(base: [String: String] = ProcessInfo.processInfo.environment)
        -> [String: String]
    {
        var env = base
        env["PATH"] = PathBuilder.effectivePATH(purposes: [.tty], env: base)
        // 凭据/口令提示一律失败而非挂起（远程操作的鉴权 P4 再单独处理）。
        env["GIT_TERMINAL_PROMPT"] = "0"
        env["GIT_OPTIONAL_LOCKS"] = "0"
        if env["LANG"]?.isEmpty ?? true {
            env["LANG"] = "en_US.UTF-8"
        }
        return env
    }

    /// 仅供测试：清掉缓存，便于重复解析。
    static func _test_resetCache() {
        self.lock.lock()
        self.cached = nil
        self.lock.unlock()
    }
}
