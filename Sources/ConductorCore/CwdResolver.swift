import Foundation

/// 恢复布局时，为一个 pane 选择实际可用的启动目录：cwd → 工作区 path → home。
/// `exists` 注入以便单测；生产用 FileManager.default.fileExists。
public enum CwdResolver {
    public static func resolve(cwd: String, workspacePath: String, home: String,
                               exists: (String) -> Bool) -> String {
        if exists(cwd) { return cwd }
        if exists(workspacePath) { return workspacePath }
        return home
    }

    /// 生产便捷入口：用真实文件系统判断。
    public static func resolve(cwd: String, workspacePath: String,
                               home: String = NSHomeDirectory()) -> String {
        resolve(cwd: cwd, workspacePath: workspacePath, home: home,
                exists: { FileManager.default.fileExists(atPath: $0) })
    }
}
