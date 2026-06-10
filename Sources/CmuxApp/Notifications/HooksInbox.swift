import Foundation

/// 一条来自 CLI hook 的通知请求。
struct HookEvent {
    let paneID: String?
    let title: String
    let message: String
}

/// 监听 hook 收件箱目录：CLI 的 hook 脚本（cmux-notify）往这里写 JSON 文件，
/// cmux 读到后发系统通知，然后删除该文件。文件名随意，内容形如：
/// `{"paneId":"p-...","title":"AI 已完成","message":"..."}`。
@MainActor
final class HooksInbox {
    /// 收件箱目录（与 cmux-notify 脚本约定一致）。
    static var directory: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("cmux", isDirectory: true)
            .appendingPathComponent("hooks-inbox", isDirectory: true)
    }

    var onEvent: ((HookEvent) -> Void)?
    private var watcher: ConfigWatcher?

    func start() {
        let dir = Self.directory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let watcher = ConfigWatcher { [weak self] in self?.drain() }
        watcher.start(directory: dir)
        self.watcher = watcher
        drain()   // 处理启动前堆积的事件
    }

    func stop() { watcher?.stop(); watcher = nil }

    private func drain() {
        let dir = Self.directory
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.creationDateKey], options: [.skipsHiddenFiles])
        else { return }
        let jsons = files.filter { $0.pathExtension == "json" }
            .sorted { ($0.path) < ($1.path) }
        for url in jsons {
            defer { try? FileManager.default.removeItem(at: url) }
            guard let data = try? Data(contentsOf: url),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }
            let paneRaw = (obj["paneId"] as? String) ?? (obj["paneID"] as? String)
            let pane = (paneRaw?.isEmpty == false) ? paneRaw : nil
            let title = (obj["title"] as? String)?.isEmpty == false
                ? (obj["title"] as! String) : "AI 已完成"
            let message = (obj["message"] as? String) ?? ""
            onEvent?(HookEvent(paneID: pane, title: title, message: message))
        }
    }
}
