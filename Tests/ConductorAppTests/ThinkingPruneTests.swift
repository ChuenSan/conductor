@testable import ConductorApp
import ConductorCore
import XCTest

/// 思考状态兜底回收：只在「agent 进程没了」或「超过硬上限」时熄灭，
/// 绝不因「输出静止/安静」熄灭（那是曾经误杀仍在运行转圈的 bug）。
final class ThinkingPruneTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000)
    private let timeout: TimeInterval = 600

    private func at(_ secondsAgo: TimeInterval) -> Date { now.addingTimeInterval(-secondsAgo) }

    func testKeepsAliveAndRecent() {
        let p = PaneID("p1")
        let out = AppCoordinator.prunedThinking([p: at(5)], agents: [p: "claude"], now: now, timeout: timeout)
        XCTAssertEqual(Set(out.keys), [p])
    }

    func testDropsWhenAgentProcessGone() {
        let p = PaneID("p1")
        // 思考点亮中，但 agent 进程已不在（崩溃/被 kill）→ 熄灭
        let out = AppCoordinator.prunedThinking([p: at(5)], agents: [:], now: now, timeout: timeout)
        XCTAssertTrue(out.isEmpty)
    }

    func testDropsWhenPastHardTimeout() {
        let p = PaneID("p1")
        let out = AppCoordinator.prunedThinking([p: at(timeout + 10)], agents: [p: "claude"], now: now, timeout: timeout)
        XCTAssertTrue(out.isEmpty)
    }

    /// 回归核心：agent 跑了 2 分钟、期间一直没刷屏（跑长工具/等模型），
    /// 但进程还在、未超硬上限 → **必须保留转圈**（旧的 6s 输出空闲启发会在这里误杀）。
    func testKeepsLongQuietButRunningAgent() {
        let p = PaneID("p1")
        let out = AppCoordinator.prunedThinking([p: at(120)], agents: [p: "claude"], now: now, timeout: timeout)
        XCTAssertEqual(Set(out.keys), [p], "安静但仍在运行的 agent 不应被熄灭")
    }

    func testMixedFleet() {
        let alive = PaneID("alive"), gone = PaneID("gone"), stale = PaneID("stale")
        let out = AppCoordinator.prunedThinking(
            [alive: at(30), gone: at(30), stale: at(timeout + 1)],
            agents: [alive: "claude", stale: "codex"],   // gone 不在 agents 里
            now: now, timeout: timeout)
        XCTAssertEqual(Set(out.keys), [alive])
    }
}
