import AppKit
import ConductorCore
import Darwin
import Foundation

/// 工作区侧栏元数据中枢：
/// - 自动化写入的状态指示 / 进度条 / 日志流（socket `set-status` / `set-progress` / `log`）
/// - 周期扫描的监听端口（lsof + 进程 cwd 归属）
/// - git 分支对应的 GitHub PR 状态（gh CLI，装了才启用）
/// 全部按 WorkspaceID 组织，侧栏行直接订阅渲染。
@MainActor
final class WorkspaceMetadataCenter: ObservableObject {
    // MARK: - 自动化状态 / 进度 / 日志

    struct StatusChip: Equatable, Identifiable {
        var key: String
        var text: String
        var color: String?      // 十六进制 "#34c759"，nil 用主题色
        var icon: String?       // SF Symbol 名
        var updatedAt: Date
        var id: String { key }
    }

    struct ProgressInfo: Equatable {
        var value: Double       // 0–1
        var label: String?
        var updatedAt: Date
    }

    struct LogEntry: Equatable, Identifiable {
        let id = UUID()
        var time: Date
        var level: String       // info | warn | error | debug
        var source: String?
        var text: String

        static func == (lhs: LogEntry, rhs: LogEntry) -> Bool { lhs.id == rhs.id }
    }

    @Published private(set) var statusChips: [WorkspaceID: [StatusChip]] = [:]
    @Published private(set) var progress: [WorkspaceID: ProgressInfo] = [:]
    @Published private(set) var logs: [WorkspaceID: [LogEntry]] = [:]
    /// 每个工作区的日志上限（环形截断）。
    private static let maxLogEntries = 500

    func setStatus(workspace: WorkspaceID, key: String, text: String,
                   color: String?, icon: String?) {
        var chips = statusChips[workspace] ?? []
        let chip = StatusChip(key: key, text: text, color: color, icon: icon, updatedAt: Date())
        if let index = chips.firstIndex(where: { $0.key == key }) {
            chips[index] = chip
        } else {
            chips.append(chip)
        }
        statusChips[workspace] = chips
    }

    func clearStatus(workspace: WorkspaceID, key: String?) {
        if let key {
            statusChips[workspace]?.removeAll { $0.key == key }
            if statusChips[workspace]?.isEmpty == true { statusChips.removeValue(forKey: workspace) }
        } else {
            statusChips.removeValue(forKey: workspace)
        }
    }

    func statuses(for workspace: WorkspaceID) -> [StatusChip] {
        statusChips[workspace] ?? []
    }

    func setProgress(workspace: WorkspaceID, value: Double, label: String?) {
        progress[workspace] = ProgressInfo(value: min(max(value, 0), 1),
                                           label: label, updatedAt: Date())
    }

    func clearProgress(workspace: WorkspaceID) {
        progress.removeValue(forKey: workspace)
    }

    func appendLog(workspace: WorkspaceID, text: String, level: String, source: String?) {
        var entries = logs[workspace] ?? []
        entries.append(LogEntry(time: Date(), level: level, source: source, text: text))
        if entries.count > Self.maxLogEntries {
            entries.removeFirst(entries.count - Self.maxLogEntries)
        }
        logs[workspace] = entries
    }

    func logs(for workspace: WorkspaceID, limit: Int) -> [LogEntry] {
        let all = logs[workspace] ?? []
        return Array(all.suffix(max(0, limit)))
    }

    func clearLog(workspace: WorkspaceID) {
        logs.removeValue(forKey: workspace)
    }

    /// 工作区被删除时清掉它名下所有元数据。
    func forget(workspace: WorkspaceID) {
        statusChips.removeValue(forKey: workspace)
        progress.removeValue(forKey: workspace)
        logs.removeValue(forKey: workspace)
        ports.removeValue(forKey: workspace)
        pullRequests.removeValue(forKey: workspace)
    }

    // MARK: - 监听端口（lsof 周期扫描，按进程 cwd 归属工作区）

    struct ListeningPort: Equatable, Identifiable {
        var port: Int
        var processName: String
        var pid: Int32
        var id: Int { port }
    }

    @Published private(set) var ports: [WorkspaceID: [ListeningPort]] = [:]
    private var portTimer: Timer?
    private var portScanInFlight = false

    /// PR 状态（gh CLI）。
    struct PullRequestInfo: Equatable {
        var number: Int
        var title: String
        var state: String          // OPEN / MERGED / CLOSED
        var checks: String?        // pass / fail / pending
        var url: String
        var branch: String
        var fetchedAt: Date
    }

    @Published private(set) var pullRequests: [WorkspaceID: PullRequestInfo] = [:]
    private var prTimer: Timer?
    private var prScanInFlight = false
    /// gh 不存在时整个 PR 探测停摆（启动探测一次）。
    private var ghPath: String?

    /// 工作区列表与分支的提供者（AppCoordinator 注入）。
    var workspacesProvider: (() -> [(id: WorkspaceID, path: String)])?
    var branchProvider: ((_ workspacePath: String) -> String?)?

    func start() {
        detectGH()
        scanPorts()
        scanPullRequests()
        let portTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.scanPorts() }
        }
        portTimer.tolerance = 5
        self.portTimer = portTimer
        let prTimer = Timer.scheduledTimer(withTimeInterval: 180, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.scanPullRequests() }
        }
        prTimer.tolerance = 30
        self.prTimer = prTimer
    }

    func stop() {
        portTimer?.invalidate()
        portTimer = nil
        prTimer?.invalidate()
        prTimer = nil
    }

    private func detectGH() {
        let candidates = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", "/usr/bin/gh"]
        ghPath = candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// 立即刷新 PR（分支变化等时机由 coordinator 触发）。
    func refreshPullRequests() {
        scanPullRequests()
    }

    private func scanPorts() {
        guard !portScanInFlight, let provider = workspacesProvider else { return }
        let workspaces = provider()
        guard !workspaces.isEmpty else {
            if !ports.isEmpty { ports = [:] }
            return
        }
        portScanInFlight = true
        Task.detached(priority: .utility) { [weak self] in
            let result = Self.collectPorts(workspaces: workspaces)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.portScanInFlight = false
                if self.ports != result { self.ports = result }
            }
        }
    }

    /// lsof 列出本机 LISTEN 的 TCP 端口；用 libproc 拿各进程 cwd，按最长前缀匹配归属工作区。
    nonisolated private static func collectPorts(
        workspaces: [(id: WorkspaceID, path: String)]
    ) -> [WorkspaceID: [ListeningPort]] {
        guard let output = runProcess("/usr/sbin/lsof",
                                      ["-nP", "-iTCP", "-sTCP:LISTEN", "-Fpcn"],
                                      timeout: 8) else { return [:] }
        // -F 输出按记录分组：p<pid> / c<command> / n<addr>（一进程多行 n）
        var result: [WorkspaceID: [ListeningPort]] = [:]
        var seen = Set<String>()   // "ws|port" 去重（IPv4/IPv6 双监听）
        var pid: Int32 = 0
        var command = ""
        var cwdCache: [Int32: String?] = [:]
        for line in output.split(separator: "\n") {
            guard let kind = line.first else { continue }
            let value = String(line.dropFirst())
            switch kind {
            case "p": pid = Int32(value) ?? 0
            case "c": command = value
            case "n":
                guard pid > 0,
                      let portText = value.split(separator: ":").last,
                      let port = Int(portText) else { continue }
                let cwd: String?
                if let cached = cwdCache[pid] {
                    cwd = cached
                } else {
                    cwd = processWorkingDirectory(pid)
                    cwdCache[pid] = cwd
                }
                guard let cwd else { continue }
                // 最长路径前缀匹配：嵌套工作区时归更深那个
                let owner = workspaces
                    .filter { cwd == $0.path || cwd.hasPrefix($0.path + "/") }
                    .max { $0.path.count < $1.path.count }
                guard let owner else { continue }
                let dedupeKey = "\(owner.id.value)|\(port)"
                guard !seen.contains(dedupeKey) else { continue }
                seen.insert(dedupeKey)
                result[owner.id, default: []].append(
                    ListeningPort(port: port, processName: command, pid: pid))
            default:
                break
            }
        }
        for key in result.keys {
            result[key]?.sort { $0.port < $1.port }
        }
        return result
    }

    /// libproc 取进程 cwd（免 spawn，扫描便宜）。
    nonisolated private static func processWorkingDirectory(_ pid: Int32) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        let result = proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size)
        guard result == size else { return nil }
        return withUnsafeBytes(of: &info.pvi_cdir.vip_path) { raw in
            String(cString: raw.bindMemory(to: CChar.self).baseAddress!)
        }
    }

    private func scanPullRequests() {
        guard !prScanInFlight, let ghPath, let provider = workspacesProvider else { return }
        let workspaces = provider()
        guard !workspaces.isEmpty else { return }
        // 分支在主线程取（paneBranches 是 UI 状态），扫描丢后台
        let targets: [(id: WorkspaceID, path: String, branch: String?)] = workspaces.map {
            ($0.id, $0.path, branchProvider?($0.path))
        }
        prScanInFlight = true
        Task.detached(priority: .utility) { [weak self] in
            var result: [WorkspaceID: PullRequestInfo] = [:]
            for target in targets {
                guard FileManager.default.fileExists(atPath: target.path + "/.git") else { continue }
                guard let json = runProcess(
                    ghPath,
                    ["pr", "view", "--json", "number,title,state,url,headRefName,statusCheckRollup"],
                    cwd: target.path, timeout: 15
                ), let data = json.data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let number = object["number"] as? Int else { continue }
                let rollup = (object["statusCheckRollup"] as? [[String: Any]]) ?? []
                let checks = Self.summarizeChecks(rollup)
                result[target.id] = PullRequestInfo(
                    number: number,
                    title: object["title"] as? String ?? "",
                    state: object["state"] as? String ?? "OPEN",
                    checks: checks,
                    url: object["url"] as? String ?? "",
                    branch: object["headRefName"] as? String ?? (target.branch ?? ""),
                    fetchedAt: Date())
            }
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.prScanInFlight = false
                if self.pullRequests != result { self.pullRequests = result }
            }
        }
    }

    /// statusCheckRollup 汇总成 pass / fail / pending。
    nonisolated private static func summarizeChecks(_ rollup: [[String: Any]]) -> String? {
        guard !rollup.isEmpty else { return nil }
        var pending = false
        for check in rollup {
            let conclusion = (check["conclusion"] as? String ?? "").uppercased()
            let status = (check["status"] as? String ?? "").uppercased()
            if conclusion == "FAILURE" || conclusion == "TIMED_OUT" || conclusion == "CANCELLED" {
                return "fail"
            }
            if conclusion.isEmpty, status != "COMPLETED" { pending = true }
        }
        return pending ? "pending" : "pass"
    }
}

/// 跑一个外部进程，返回 stdout 文本；超时杀掉返回 nil。仅用于后台扫描（utility QoS）。
/// 边读边等（readDataToEndOfFile）避免大输出塞满管道造成的互等；看门狗负责超时击杀。
private func runProcess(_ launchPath: String, _ arguments: [String],
                        cwd: String? = nil, timeout: TimeInterval) -> String? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: launchPath)
    process.arguments = arguments
    if let cwd { process.currentDirectoryURL = URL(fileURLWithPath: cwd) }
    let stdout = Pipe()
    process.standardOutput = stdout
    process.standardError = FileHandle.nullDevice
    do {
        try process.run()
    } catch {
        return nil
    }
    let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: watchdog)
    let data = stdout.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    let timedOut = watchdog.isCancelled == false && process.terminationReason == .uncaughtSignal
    watchdog.cancel()
    guard !timedOut, process.terminationStatus == 0 else { return nil }
    return String(data: data, encoding: .utf8)
}
