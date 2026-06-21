import AppKit
import ConductorCore

/// ② 命令结果：一条命令跑完后的事实记录（退出码/时长/时刻/cwd）。
/// 命令原文、输出区域 ghostty 没暴露给嵌入方，这里只记能拿到的硬事实，足够做
/// 失败标红、重跑、耗时排查、"把失败甩给 agent"。
struct PaneCommandRecord: Identifiable, Equatable, Sendable {
    let id: Int                 // per-pane 递增序号（重跑/定位用）
    let exitCode: Int?          // nil = shell 没上报退出码
    let durationNanos: UInt64
    let finishedAt: Date
    let cwd: String?

    var failed: Bool { (exitCode ?? 0) != 0 }
    var durationMillis: Int { Int(durationNanos / 1_000_000) }

    /// "1.2s" / "308ms" / "—"
    var durationText: String {
        if durationNanos == 0 { return "—" }
        let ms = durationMillis
        if ms < 1000 { return "\(ms)ms" }
        let s = Double(ms) / 1000
        return s < 10 ? String(format: "%.1fs", s) : "\(Int(s.rounded()))s"
    }
}

@MainActor
extension AppCoordinator {
    /// shell 集成（OSC 133）上报"一条命令跑完"——退出码 + 时长。
    /// ② 命令结果（记录 + 失败红闪）与 ③ 联动（命令完成→规则）的共用入口。
    func handleCommandFinished(_ pane: PaneID, exitCode: Int?, durationNanos: UInt64) {
        let record = recordPaneCommand(pane, exitCode: exitCode, durationNanos: durationNanos)
        runChoreography(for: pane, record: record)
    }
}
