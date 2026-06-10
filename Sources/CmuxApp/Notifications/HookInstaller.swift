import CmuxCore
import Foundation

/// 安装 / 检测「agent 完成 → cmux 通知」所需的 CLI hook：
/// - 写 `~/.cmux/bin/cmux-notify` 脚本：把通知请求写进 cmux 收件箱（HooksInbox 监听）；
/// - Claude：`~/.claude/settings.json` 的 `hooks.Stop` 加一条命令；
/// - Codex：`~/.codex/hooks.json` 的 `hooks.Stop` 加一条命令。
///
/// 命令带 `$CMUX_PANE_ID` 网关（只对 cmux 启动的 agent 触发）和 `#cmux:notify` 哨兵
/// （便于 Hook 管理面板识别与移除）。合并写入，保留配置里其它键（含敏感信息）。
enum HookInstaller {
    static let recipeID = "notify"

    struct Status {
        var scriptInstalled: Bool
        var codexConfigured: Bool
        var claudeConfigured: Bool
        var allDone: Bool { scriptInstalled && codexConfigured && claudeConfigured }
    }

    enum InstallError: LocalizedError {
        case write(String)
        var errorDescription: String? { switch self { case .write(let m): return m } }
    }

    private static var home: URL { FileManager.default.homeDirectoryForCurrentUser }
    static var scriptURL: URL { home.appendingPathComponent(".cmux/bin/cmux-notify") }

    /// 写入 Stop hook 的命令（网关 + 哨兵）。
    static var stopCommand: String {
        "[ -n \"$CMUX_PANE_ID\" ] && '\(scriptURL.path)' >/dev/null 2>&1 || true #cmux:\(recipeID)"
    }

    // MARK: - 状态

    static func status() -> Status {
        Status(
            scriptInstalled: FileManager.default.isExecutableFile(atPath: scriptURL.path),
            codexConfigured: configHasNotify(.codex),
            claudeConfigured: configHasNotify(.claude))
    }

    private static func configHasNotify(_ source: HookSource) -> Bool {
        HookConfigDocument(source: source).entries()
            .contains { $0.command.contains("#cmux:\(recipeID)") }
    }

    // MARK: - 安装

    @discardableResult
    static func installAll() throws -> Status {
        try installScript()
        do {
            try HookConfigDocument(source: .claude).addCommand(event: HookEventName.stop, command: stopCommand)
            try HookConfigDocument(source: .codex).addCommand(event: HookEventName.stop, command: stopCommand)
        } catch {
            throw InstallError.write(L("写 hook 配置失败：%@", error.localizedDescription))
        }
        return status()
    }

    static func installScript() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: scriptURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        do {
            try scriptBody.write(to: scriptURL, atomically: true, encoding: .utf8)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        } catch {
            throw InstallError.write(L("写 cmux-notify 脚本失败：%@", error.localizedDescription))
        }
    }

    // MARK: - cmux-notify 脚本内容

    static var scriptBody: String {
        """
        #!/bin/sh
        # cmux-notify —— 由 cmux 自动生成。把一条通知请求写入 cmux 收件箱，
        # cmux.app 监听该目录并发系统通知。点击通知可跳回对应 pane（需 CMUX_PANE_ID）。
        #
        #   Codex hooks.json Stop：事件 JSON 从 stdin 传入。
        #   Claude Stop hook：事件 JSON 从 stdin 传入。
        INBOX="$HOME/Library/Application Support/cmux/hooks-inbox"
        mkdir -p "$INBOX"
        PANE="${CMUX_PANE_ID:-}"
        TITLE="AI 已完成"
        MSG="可以查看结果了"

        esc() { printf '%s' "$1" | tr '\\n\\r\\t' '   ' | sed 's/\\\\/\\\\\\\\/g; s/"/\\\\"/g'; }
        F="$INBOX/$(date +%s)-$$.json"
        printf '{"paneId":"%s","title":"%s","message":"%s"}\\n' "$(esc "$PANE")" "$(esc "$TITLE")" "$(esc "$MSG")" > "$F"
        exit 0
        """
    }
}
