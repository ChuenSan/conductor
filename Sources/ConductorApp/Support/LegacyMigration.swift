import Foundation

/// cmux → Conductor 改名后的一次性旧数据迁移（新路径不存在且旧路径存在时才拷贝）：
/// - `~/Library/Application Support/cmux` → `.../conductor`（工作区布局、会话缓存、回放快照）
/// - `~/.config/cmux/config.yaml` → `~/.config/conductor/config.yaml`
/// 旧的 `~/.cmux/bin/cmux-notify` hook 脚本不迁移——脚本内容与哨兵都换了名，
/// 在「Hooks 管理」面板重新安装即可。
enum LegacyMigration {
    static func migrateIfNeeded(fileManager fm: FileManager = .default) {
        let home = fm.homeDirectoryForCurrentUser
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]

        copyIfMissing(
            from: appSupport.appendingPathComponent("cmux", isDirectory: true),
            to: appSupport.appendingPathComponent("conductor", isDirectory: true),
            fm: fm)
        copyIfMissing(
            from: home.appendingPathComponent(".config/cmux/config.yaml"),
            to: home.appendingPathComponent(".config/conductor/config.yaml"),
            fm: fm)
    }

    private static func copyIfMissing(from old: URL, to new: URL, fm: FileManager) {
        guard fm.fileExists(atPath: old.path), !fm.fileExists(atPath: new.path) else { return }
        do {
            try fm.createDirectory(
                at: new.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.copyItem(at: old, to: new)
            NSLog("[conductor] 旧数据已迁移：\(old.path) → \(new.path)")
        } catch {
            NSLog("[conductor] 旧数据迁移失败（忽略，按全新启动继续）：\(error)")
        }
    }
}
