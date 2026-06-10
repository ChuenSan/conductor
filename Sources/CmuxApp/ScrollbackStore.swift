import CmuxCore
import Foundation

/// 终端内容快照的存取：退出 / 误关时把 pane 的屏幕+回滚文本写盘，
/// 恢复时由 wrapper 脚本 `cat` 回放到新终端（随后删除，消费一次性）。
/// 目录：~/Library/Application Support/cmux/scrollback/<paneID>.txt
@MainActor
enum ScrollbackStore {
    private static var directory: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("cmux/scrollback", isDirectory: true)
    }

    private static func fileURL(for pane: PaneID) -> URL {
        directory.appendingPathComponent("\(pane.value).txt")
    }

    /// 截尾 + 结尾加一条暗色分隔线（回放后、新提示符之前），原子写盘。
    static func save(_ text: String, for pane: PaneID) {
        let trimmed = ScrollbackTrimmer.trim(text)
        guard !trimmed.isEmpty else { return }
        let separator = "\n\u{001B}[2m\(L("── 以上为上次会话回放（进程未恢复）──"))\u{001B}[0m\n"
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? Data((trimmed + separator).utf8).write(to: fileURL(for: pane), options: .atomic)
    }

    /// 该 pane 是否有待回放的快照；有则返回路径。
    static func pendingFile(for pane: PaneID) -> String? {
        let path = fileURL(for: pane).path
        return FileManager.default.fileExists(atPath: path) ? path : nil
    }

    /// 清理孤儿快照：不在 keep 集合里的 pane 文件全部删除（防目录无限膨胀）。
    static func cleanup(keeping keep: Set<PaneID>) {
        let keepNames = Set(keep.map { "\($0.value).txt" })
        let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        for name in files where !keepNames.contains(name) {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
    }

    /// 确保回放 wrapper 脚本存在（cat 快照 → 删除 → exec 真 shell），返回其路径。
    /// 用 env 传参避免任何引号/转义问题；exec 前 unset，不污染 shell 环境。
    ///
    /// 必须放在**无空格路径**（~/.cmux）：ghostty 的 command 按空格切词，
    /// 放 "Application Support" 会被切碎 → exec 失败 → 子进程秒退 → pane 被连锁关闭。
    static func ensureWrapperScript() -> String? {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cmux/restore-shell.sh")
        // 防御：路径仍含空格（如用户名带空格）→ 放弃回放，退回普通 shell 启动。
        guard !url.path.contains(" ") else { return nil }
        let script = """
        #!/bin/sh
        # cmux 内容恢复：回放上次会话文本，再进入真正的 shell。由 cmux 自动生成/覆盖。
        f="$CMUX_RESTORE_FILE"; s="$CMUX_RESTORE_SHELL"
        unset CMUX_RESTORE_FILE CMUX_RESTORE_SHELL
        if [ -n "$f" ] && [ -f "$f" ]; then
          cat -- "$f"
          rm -f -- "$f"
        fi
        [ -n "$s" ] || s=/bin/zsh
        exec $s
        """
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(script.utf8).write(to: url, options: .atomic)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755], ofItemAtPath: url.path)
            // 清掉旧版本误放在 Application Support（带空格路径）的脚本。
            try? FileManager.default.removeItem(
                at: directory.deletingLastPathComponent().appendingPathComponent("restore-shell.sh"))
            return url.path
        } catch {
            NSLog("[cmux] restore-shell.sh write failed: \(error)")
            return nil
        }
    }
}
