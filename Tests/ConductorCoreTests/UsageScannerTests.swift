import XCTest
@testable import ConductorCore

final class UsageScannerTests: XCTestCase {
    private func makeTempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("conductor-usage-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testClaudeAggregationAndDedup() throws {
        let claude = try makeTempDir()
        let codex = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: claude); try? FileManager.default.removeItem(at: codex) }

        let proj = claude.appendingPathComponent("-Users-test")
        try FileManager.default.createDirectory(at: proj, withIntermediateDirectories: true)

        // 两行：同一条 assistant 消息（相同 id+requestId）应只计一次；另一条不同 id 正常计。
        let cwdLine = #"{"type":"user","cwd":"/Users/test/proj-a","message":{"role":"user"}}"#
        let line1 = #"{"timestamp":"2026-06-08T10:00:00.000Z","requestId":"req_1","message":{"id":"msg_1","model":"claude-opus-4-7","role":"assistant","usage":{"input_tokens":100,"output_tokens":200,"cache_creation_input_tokens":50,"cache_read_input_tokens":1000}}}"#
        let line1dup = line1   // 重复行
        let line2 = #"{"timestamp":"2026-06-08T11:00:00.000Z","requestId":"req_2","message":{"id":"msg_2","model":"claude-sonnet-4-6","role":"assistant","usage":{"input_tokens":10,"output_tokens":20,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}"#
        let content = [cwdLine, line1, line1dup, line2].joined(separator: "\n") + "\n"
        try content.write(to: proj.appendingPathComponent("s1.jsonl"), atomically: true, encoding: .utf8)

        let scanner = UsageScanner(claudeProjectsDir: claude, codexSessionsDir: codex)
        let report = scanner.scan(daysBack: 3650, now: ISO8601DateFormatter().date(from: "2026-06-09T00:00:00Z")!)

        // 去重后：opus 100/200/50/1000，sonnet 10/20/0/0
        XCTAssertEqual(report.grand.inputTokens, 110)
        XCTAssertEqual(report.grand.outputTokens, 220)
        XCTAssertEqual(report.grand.cacheCreationTokens, 50)
        XCTAssertEqual(report.grand.cacheReadTokens, 1000)

        // 成本：opus($5/$25/$6.25/$0.50) + sonnet($3/$15)
        // opus = (100*5 + 200*25 + 50*6.25 + 1000*0.5)/1e6 = (500+5000+312.5+500)/1e6
        // sonnet = (10*3 + 20*15)/1e6 = (30+300)/1e6
        let expected = (500.0 + 5000 + 312.5 + 500 + 30 + 300) / 1_000_000
        XCTAssertEqual(report.grand.costUSD, expected, accuracy: 1e-9)

        XCTAssertEqual(report.byModel.count, 2)
        XCTAssertEqual(report.byDay.count, 1)
        XCTAssertEqual(report.byDay.first?.day, "2026-06-08")
        XCTAssertEqual(report.bySource[.claude]?.inputTokens, 110)

        // 每日按来源细分 + 项目维度
        XCTAssertEqual(report.byDay.first?.bySource[.claude]?.inputTokens, 110)
        XCTAssertEqual(report.byProject.count, 1)
        XCTAssertEqual(report.byProject.first?.path, "/Users/test/proj-a")
        XCTAssertEqual(report.byProject.first?.totals.inputTokens, 110)
        XCTAssertEqual(report.byProject.first?.bySource[.claude]?.inputTokens, 110)
        XCTAssertEqual(report.sessionsBySource[.claude], 1)
    }

    func testCodexUsesLastCumulativeTotal() throws {
        let claude = try makeTempDir()
        let codex = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: claude); try? FileManager.default.removeItem(at: codex) }

        let dayDir = codex.appendingPathComponent("2026/06/08")
        try FileManager.default.createDirectory(at: dayDir, withIntermediateDirectories: true)

        let meta = #"{"timestamp":"2026-06-08T09:00:00.000Z","type":"session_meta","payload":{"id":"x","cwd":"/Users/test/proj-b","model":"gpt-5.5"}}"#
        // 累计值递增：取最后一个 total_token_usage = 1000 in / 300 cached / 200 out
        let tc1 = #"{"timestamp":"2026-06-08T09:01:00Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":500,"cached_input_tokens":100,"output_tokens":50,"reasoning_output_tokens":10,"total_tokens":560}}}}"#
        let tc2 = #"{"timestamp":"2026-06-08T09:02:00Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1000,"cached_input_tokens":300,"output_tokens":200,"reasoning_output_tokens":40,"total_tokens":1200}}}}"#
        let content = [meta, tc1, tc2].joined(separator: "\n") + "\n"
        try content.write(to: dayDir.appendingPathComponent("rollout-x.jsonl"), atomically: true, encoding: .utf8)

        let scanner = UsageScanner(claudeProjectsDir: claude, codexSessionsDir: codex)
        let report = scanner.scan(daysBack: 3650, now: ISO8601DateFormatter().date(from: "2026-06-09T00:00:00Z")!)

        // uncached input = 1000-300=700, cacheRead=300, output=200+40=240
        XCTAssertEqual(report.grand.inputTokens, 700)
        XCTAssertEqual(report.grand.cacheReadTokens, 300)
        XCTAssertEqual(report.grand.outputTokens, 240)
        XCTAssertEqual(report.bySource[.codex]?.outputTokens, 240)
        XCTAssertEqual(report.byDay.first?.day, "2026-06-08")
        XCTAssertEqual(report.byDay.first?.bySource[.codex]?.outputTokens, 240)
        XCTAssertEqual(report.byProject.first?.path, "/Users/test/proj-b")
        XCTAssertEqual(report.sessionsScanned, 1)
    }

    func testPricingLookup() {
        XCTAssertEqual(ModelPricing.forModel("claude-opus-4-7").inputPerM, 5)
        XCTAssertEqual(ModelPricing.forModel("claude-opus-4-1-20250101").inputPerM, 15)
        XCTAssertEqual(ModelPricing.forModel("claude-sonnet-4-6").outputPerM, 15)
        XCTAssertEqual(ModelPricing.forModel("gpt-5.5").outputPerM, 10)
        XCTAssertEqual(ModelPricing.forModel("gpt-5-mini").inputPerM, 0.25)
    }
}
