import XCTest
@testable import ConductorCore

final class CostUsageFetcherTests: XCTestCase {
    func testLoadReportOrFallbackUnlessCancelledPropagatesCancellation() async throws {
        let root = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let fetcher = CostUsageFetcher(options: CostUsageFetcher.Options(cacheRoot: root))

        let task = Task<UsageReport, Error> {
            await Task.yield()
            return try await fetcher.loadReportOrFallbackUnlessCancelled(daysBack: 30)
        }
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected CancellationError")
        } catch is CancellationError {
            // Expected: the cancellable path must not fall through to a fallback scan.
        }
    }

    func testFetcherCachesReportAndForceRefreshInvalidatesIt() async throws {
        let root = try Self.makeTempDir()
        let claude = root.appendingPathComponent("claude", isDirectory: true)
        let codex = root.appendingPathComponent("codex", isDirectory: true)
        let pi = root.appendingPathComponent("pi", isDirectory: true)
        let cache = root.appendingPathComponent("cache", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try [claude, codex, pi, cache].forEach {
            try FileManager.default.createDirectory(at: $0, withIntermediateDirectories: true)
        }
        ModelsDevCache.save(catalog: ModelsDevCatalog(providers: [:]), fetchedAt: Date(), cacheRoot: cache)

        let project = claude.appendingPathComponent("project", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try Self.writeClaudeUsage(
            to: project.appendingPathComponent("session.jsonl"),
            input: 100,
            output: 50)

        let scanner = UsageScanner(
            claudeProjectsDir: claude,
            codexSessionsDir: codex,
            modelsDevCacheRoot: cache,
            piSessionsDir: pi)
        let fetcher = CostUsageFetcher(
            scanner: scanner,
            options: CostUsageFetcher.Options(cacheRoot: cache, refreshMinIntervalSeconds: 3600))
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-06-09T00:00:00Z"))

        let first = try await fetcher.loadReport(daysBack: 30, now: now)
        XCTAssertEqual(first.grand.inputTokens, 100)
        XCTAssertEqual(first.grand.outputTokens, 50)
        XCTAssertEqual(first.sourceInfo?.source, .fileCacheScan)

        try FileManager.default.removeItem(at: project.appendingPathComponent("session.jsonl"))
        let cached = try await fetcher.loadReport(daysBack: 30, now: now.addingTimeInterval(10))
        XCTAssertEqual(cached.grand.inputTokens, 100)
        XCTAssertEqual(cached.sourceInfo?.source, .reportCache)
        XCTAssertEqual(cached.sourceInfo?.reason, "refresh interval")

        let refreshed = try await fetcher.loadReport(
            daysBack: 30,
            now: now.addingTimeInterval(20),
            forceRefresh: true)
        XCTAssertEqual(refreshed.grand.inputTokens, 0)
        XCTAssertEqual(refreshed.sourceInfo?.source, .fileCacheScan)
    }

    func testCostUsageDailyReportAndSnapshotMirrorUsageReport() {
        var totals = UsageTotals()
        totals.inputTokens = 10
        totals.outputTokens = 20
        totals.cacheReadTokens = 30
        totals.costUSD = 0.5
        totals.requestCount = 3
        let breakdown = UsageModelBreakdown(model: "gpt-5.5", source: .codex, totals: totals)
        let day = DailyUsage(day: "2026-06-08", totals: totals, bySource: [.codex: totals], modelBreakdowns: [breakdown])
        var report = UsageReport()
        report.daysBack = 7
        report.generatedAt = Date(timeIntervalSince1970: 100)
        report.grand = totals
        report.byDay = [day]
        report.bySession = [
            SessionUsage(
                session: "session-1",
                source: .codex,
                project: "/tmp/project",
                totals: totals,
                lastActivity: "2026-06-08",
                models: ["gpt-5.5"]),
        ]

        let daily = report.costUsageDailyReport
        XCTAssertEqual(daily.summary?.totalTokens, 60)
        XCTAssertEqual(daily.data.first?.requestCount, 3)
        XCTAssertEqual(daily.data.first?.modelBreakdowns?.first?.modelName, "gpt-5.5")
        XCTAssertEqual(daily.data.first?.modelBreakdowns?.first?.requestCount, 3)

        let snapshot = daily.tokenSnapshot(now: report.generatedAt, historyDays: report.daysBack)
        XCTAssertEqual(snapshot.sessionTokens, 60)
        XCTAssertEqual(snapshot.sessionRequests, 3)
        XCTAssertEqual(snapshot.last30DaysCostUSD, 0.5)
        XCTAssertEqual(snapshot.last30DaysRequests, 3)
        XCTAssertEqual(snapshot.historyDays, 7)

        let monthly = report.costUsageMonthlyReport
        XCTAssertEqual(monthly.data.first?.month, "2026-06")
        XCTAssertEqual(monthly.data.first?.totalTokens, 60)
        XCTAssertEqual(monthly.data.first?.costUSD, 0.5)
        XCTAssertEqual(monthly.summary?.totalTokens, 60)
        XCTAssertEqual(monthly.summary?.totalCostUSD, 0.5)

        let sessions = report.costUsageSessionReport
        XCTAssertEqual(sessions.data.first?.session, "session-1")
        XCTAssertEqual(sessions.data.first?.inputTokens, 10)
        XCTAssertEqual(sessions.data.first?.outputTokens, 20)
        XCTAssertEqual(sessions.data.first?.totalTokens, 60)
        XCTAssertEqual(sessions.data.first?.costUSD, 0.5)
        XCTAssertEqual(sessions.data.first?.lastActivity, "2026-06-08")
        XCTAssertEqual(sessions.summary?.totalCostUSD, 0.5)
    }

    func testCostUsageDailyReportDecodesCodexBarShape() throws {
        let data = Data("""
        {
          "daily": [
            {
              "date": "2026-06-08",
              "inputTokens": 100,
              "cacheReadInputTokens": 25,
              "cacheCreationInputTokens": 5,
              "outputTokens": 40,
              "totalTokens": 170,
              "requests": 3,
              "totalCost": 0.123,
              "models": {
                "gpt-5.5": { "cost": 0.1 },
                "claude-sonnet-4-6": { "cost": 0.023 }
              },
              "modelBreakdowns": [
                {
                  "modelName": "gpt-5.5",
                  "cost": 0.1,
                  "totalTokens": 145,
                  "requests": 2
                },
                {
                  "modelName": "claude-sonnet-4-6",
                  "cost": 0.02,
                  "totalTokens": 20,
                  "requests": 1
                },
                {
                  "modelName": "claude-opus-4-5@20251101",
                  "cost": 0.003,
                  "totalTokens": 5,
                  "requests": 1
                }
              ]
            }
          ],
          "totals": {
            "totalInputTokens": 100,
            "totalOutputTokens": 40,
            "totalCacheReadTokens": 25,
            "totalCacheCreationTokens": 5,
            "totalTokens": 170,
            "totalCost": 0.123
          }
        }
        """.utf8)

        let report = try JSONDecoder().decode(CostUsageDailyReport.self, from: data)

        XCTAssertEqual(report.data.first?.cacheReadTokens, 25)
        XCTAssertEqual(report.data.first?.cacheCreationTokens, 5)
        XCTAssertEqual(report.data.first?.requestCount, 3)
        XCTAssertEqual(report.data.first?.costUSD, 0.123)
        XCTAssertEqual(report.data.first?.modelsUsed, ["claude-sonnet-4-6", "gpt-5.5"])
        XCTAssertEqual(report.data.first?.modelBreakdowns?.first?.source, .codex)
        XCTAssertEqual(report.data.first?.modelBreakdowns?.first?.costUSD, 0.1)
        XCTAssertEqual(report.data.first?.modelBreakdowns?.first?.requestCount, 2)
        XCTAssertEqual(report.data.first?.modelBreakdowns?[1].source, .claude)
        XCTAssertEqual(report.data.first?.modelBreakdowns?[2].source, .vertexai)
        XCTAssertEqual(report.summary?.cacheReadTokens, 25)
        XCTAssertEqual(report.summary?.cacheCreationTokens, 5)
        XCTAssertEqual(report.summary?.totalCostUSD, 0.123)
    }

    func testCostUsageDailyReportInfersBedrockSource() throws {
        let data = Data("""
        {
          "data": [
            {
              "date": "2026-06-08",
              "totalCost": 1.25,
              "modelBreakdowns": [
                {
                  "modelName": "Amazon Bedrock",
                  "cost": 1.25
                }
              ]
            }
          ]
        }
        """.utf8)

        let report = try JSONDecoder().decode(CostUsageDailyReport.self, from: data)

        XCTAssertEqual(report.data.first?.modelBreakdowns?.first?.source, .bedrock)
        XCTAssertEqual(report.data.first?.modelBreakdowns?.first?.costUSD, 1.25)
    }

    func testBedrockDailyReportConvertsToUsageReport() {
        let generatedAt = Date(timeIntervalSince1970: 100)
        let daily = CostUsageDailyReport(
            data: [
                CostUsageDailyReport.Entry(
                    date: "2026-06-08",
                    inputTokens: nil,
                    outputTokens: nil,
                    totalTokens: nil,
                    costUSD: 1.25,
                    modelsUsed: ["Amazon Bedrock"],
                    modelBreakdowns: [
                        CostUsageDailyReport.ModelBreakdown(
                            source: .bedrock,
                            modelName: "Amazon Bedrock",
                            costUSD: 1.25),
                    ]),
                CostUsageDailyReport.Entry(
                    date: "2026-06-09",
                    inputTokens: nil,
                    outputTokens: nil,
                    totalTokens: nil,
                    costUSD: 2.50,
                    modelsUsed: ["Amazon Bedrock Runtime"],
                    modelBreakdowns: [
                        CostUsageDailyReport.ModelBreakdown(
                            source: .bedrock,
                            modelName: "Amazon Bedrock Runtime",
                            costUSD: 2.50),
                    ]),
            ],
            summary: nil)

        let report = UsageCostCLIReporter.report(
            fromBedrockDaily: daily,
            daysBack: 90,
            generatedAt: generatedAt,
            sourceInfo: UsageReportSourceInfo(source: .directScan, loadedAt: generatedAt, reason: "test"))
        let cliReport = UsageCostCLIReport(report: report)

        XCTAssertEqual(report.daysBack, 90)
        XCTAssertEqual(report.generatedAt, generatedAt)
        XCTAssertEqual(report.grand.costUSD, 3.75)
        XCTAssertEqual(report.bySource[.bedrock]?.costUSD, 3.75)
        XCTAssertEqual(report.sessionsBySource[.bedrock], 2)
        XCTAssertEqual(report.byDay.count, 2)
        XCTAssertEqual(report.byMonth.first?.month, "2026-06")
        XCTAssertEqual(report.byMonth.first?.totals.costUSD, 3.75)
        XCTAssertEqual(report.bySession.first?.source, .bedrock)
        XCTAssertEqual(report.byModel.first?.source, .bedrock)
        XCTAssertEqual(report.byModel.first?.model, "Amazon Bedrock Runtime")
        XCTAssertEqual(cliReport.bySource.first?.source, "bedrock")
        XCTAssertEqual(cliReport.byModel.first?.name, "AWS Bedrock")
    }

    func testCostUsageDailyReportMergesEntriesAndBreakdowns() {
        let first = CostUsageDailyReport(
            data: [
                CostUsageDailyReport.Entry(
                    date: "2026-06-08",
                    inputTokens: 10,
                    outputTokens: 20,
                    totalTokens: nil,
                    requestCount: 1,
                    costUSD: 0.12,
                    modelsUsed: ["gpt-5.5"],
                    modelBreakdowns: [
                        CostUsageDailyReport.ModelBreakdown(
                            source: .codex,
                            modelName: "gpt-5.5",
                            costUSD: 0.08,
                            totalTokens: 30,
                            requestCount: 1,
                            standardCostUSD: 0.08,
                            standardTokens: 30),
                        CostUsageDailyReport.ModelBreakdown(
                            source: .claude,
                            modelName: "claude-sonnet-4-6",
                            costUSD: 0.04,
                            totalTokens: 10,
                            requestCount: 1),
                    ]),
            ],
            summary: nil)
        let second = CostUsageDailyReport(
            data: [
                CostUsageDailyReport.Entry(
                    date: "2026-06-08",
                    inputTokens: 5,
                    outputTokens: 7,
                    cacheReadTokens: 3,
                    totalTokens: 99,
                    requestCount: 2,
                    costUSD: 0.17,
                    modelsUsed: ["gpt-5.5", "claude-sonnet-4-6"],
                    modelBreakdowns: [
                        CostUsageDailyReport.ModelBreakdown(
                            source: .codex,
                            modelName: "gpt-5.5",
                            costUSD: 0.12,
                            totalTokens: 20,
                            requestCount: 2,
                            priorityCostUSD: 0.12,
                            priorityTokens: 20),
                        CostUsageDailyReport.ModelBreakdown(
                            source: .vertexai,
                            modelName: "claude-sonnet-4-6",
                            costUSD: 0.05,
                            totalTokens: 8,
                            requestCount: 1),
                    ]),
            ],
            summary: nil)

        let merged = CostUsageDailyReport.merged([first, second])

        XCTAssertEqual(merged.data.count, 1)
        let entry = merged.data[0]
        XCTAssertEqual(entry.inputTokens, 15)
        XCTAssertEqual(entry.outputTokens, 27)
        XCTAssertEqual(entry.cacheReadTokens, 3)
        XCTAssertEqual(entry.totalTokens, 129)
        XCTAssertEqual(entry.requestCount, 3)
        XCTAssertEqual(entry.costUSD ?? 0, 0.29, accuracy: 1e-12)
        XCTAssertEqual(entry.modelsUsed, ["claude-sonnet-4-6", "gpt-5.5"])
        XCTAssertEqual(merged.summary?.totalInputTokens, 15)
        XCTAssertEqual(merged.summary?.totalOutputTokens, 27)
        XCTAssertEqual(merged.summary?.cacheReadTokens, 3)
        XCTAssertEqual(merged.summary?.totalTokens, 129)
        XCTAssertEqual(merged.summary?.totalCostUSD ?? 0, 0.29, accuracy: 1e-12)

        let breakdowns = entry.modelBreakdowns ?? []
        XCTAssertEqual(breakdowns.count, 3)
        XCTAssertEqual(breakdowns[0].source, .codex)
        XCTAssertEqual(breakdowns[0].modelName, "gpt-5.5")
        XCTAssertEqual(breakdowns[0].costUSD ?? 0, 0.20, accuracy: 1e-12)
        XCTAssertEqual(breakdowns[0].totalTokens, 50)
        XCTAssertEqual(breakdowns[0].requestCount, 3)
        XCTAssertEqual(breakdowns[0].standardCostUSD ?? 0, 0.08, accuracy: 1e-12)
        XCTAssertEqual(breakdowns[0].priorityCostUSD ?? 0, 0.12, accuracy: 1e-12)
        XCTAssertEqual(breakdowns[1].source, .vertexai)
        XCTAssertEqual(breakdowns[2].source, .claude)
    }

    func testFetcherIncludesCodexArchivedSessionsThroughFileCache() async throws {
        let root = try Self.makeTempDir()
        let claude = root.appendingPathComponent("claude", isDirectory: true)
        let codexRoot = root.appendingPathComponent("codex", isDirectory: true)
        let sessions = codexRoot.appendingPathComponent("sessions", isDirectory: true)
        let archived = codexRoot.appendingPathComponent("archived_sessions/2026/06/08", isDirectory: true)
        let pi = root.appendingPathComponent("pi", isDirectory: true)
        let cache = root.appendingPathComponent("cache", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try [claude, sessions, archived, pi, cache].forEach {
            try FileManager.default.createDirectory(at: $0, withIntermediateDirectories: true)
        }
        ModelsDevCache.save(catalog: ModelsDevCatalog(providers: [:]), fetchedAt: Date(), cacheRoot: cache)

        let meta = #"{"timestamp":"2026-06-08T09:00:00.000Z","type":"session_meta","payload":{"id":"archived-fetcher","cwd":"/Users/test/old","model":"gpt-5.5"}}"#
        let usage = #"{"timestamp":"2026-06-08T09:02:00Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"cached_input_tokens":25,"output_tokens":50,"reasoning_output_tokens":5}}}}"#
        try ([meta, usage].joined(separator: "\n") + "\n")
            .write(to: archived.appendingPathComponent("rollout-archived.jsonl"), atomically: true, encoding: .utf8)

        let scanner = UsageScanner(
            claudeProjectsDir: claude,
            codexSessionsDir: sessions,
            modelsDevCacheRoot: cache,
            piSessionsDir: pi)
        let fetcher = CostUsageFetcher(
            scanner: scanner,
            options: CostUsageFetcher.Options(cacheRoot: cache, refreshMinIntervalSeconds: 3600))
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-06-09T00:00:00Z"))

        let report = try await fetcher.loadReport(daysBack: 30, now: now)

        XCTAssertEqual(report.grand.inputTokens, 75)
        XCTAssertEqual(report.grand.cacheReadTokens, 25)
        XCTAssertEqual(report.grand.outputTokens, 50)
        XCTAssertEqual(report.byProject.first?.path, "/Users/test/old")
        XCTAssertEqual(report.sessionsBySource[.codex], 1)
        XCTAssertEqual(report.sourceInfo?.source, .fileCacheScan)
        XCTAssertTrue(FileManager.default.fileExists(atPath: UsageScanner.fileCacheFileURL(cacheRoot: cache).path))
    }

    func testFetcherIncludesPiSessionsThroughFileCache() async throws {
        let root = try Self.makeTempDir()
        let claude = root.appendingPathComponent("claude", isDirectory: true)
        let codex = root.appendingPathComponent("codex", isDirectory: true)
        let pi = root.appendingPathComponent("pi", isDirectory: true)
        let cache = root.appendingPathComponent("cache", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try [claude, codex, pi, cache].forEach {
            try FileManager.default.createDirectory(at: $0, withIntermediateDirectories: true)
        }
        ModelsDevCache.save(catalog: ModelsDevCatalog(providers: [:]), fetchedAt: Date(), cacheRoot: cache)

        let session = pi.appendingPathComponent("session.jsonl")
        let modelChange = #"{"type":"model_change","timestamp":"2026-06-08T10:00:00Z","provider":"anthropic","model":"claude-sonnet-4-6"}"#
        let message = Self.piAssistantLine(input: 10, output: 20, includeIdentity: false)
        try ([modelChange, message].joined(separator: "\n") + "\n")
            .write(to: session, atomically: true, encoding: .utf8)

        let scanner = UsageScanner(
            claudeProjectsDir: claude,
            codexSessionsDir: codex,
            modelsDevCacheRoot: cache,
            piSessionsDir: pi)
        let fetcher = CostUsageFetcher(
            scanner: scanner,
            options: CostUsageFetcher.Options(cacheRoot: cache, refreshMinIntervalSeconds: 3600))
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-06-09T00:00:00Z"))

        let report = try await fetcher.loadReport(daysBack: 30, now: now)

        XCTAssertEqual(report.grand.inputTokens, 10)
        XCTAssertEqual(report.grand.outputTokens, 20)
        XCTAssertEqual(report.bySource[.claude]?.inputTokens, 10)
        XCTAssertEqual(report.byProject.first?.path, "/Users/test/pi-proj")
        XCTAssertEqual(report.sessionsBySource[.claude], 1)
        XCTAssertEqual(report.sourceInfo?.source, .fileCacheScan)
        XCTAssertTrue(FileManager.default.fileExists(atPath: UsageScanner.fileCacheFileURL(cacheRoot: cache).path))
    }

    func testUsageTotalsDecodesOldCacheWithoutRequestCount() throws {
        let data = Data("""
        {
          "inputTokens": 10,
          "outputTokens": 20,
          "cacheCreationTokens": 0,
          "cacheReadTokens": 5,
          "costUSD": 0.01
        }
        """.utf8)
        let totals = try JSONDecoder().decode(UsageTotals.self, from: data)
        XCTAssertEqual(totals.totalTokens, 35)
        XCTAssertEqual(totals.requestCount, 0)
    }

    func testUsageReportDecodesOldCacheWithoutMonthSummaries() throws {
        let data = Data("""
        {
          "grand": {
            "inputTokens": 10,
            "outputTokens": 20,
            "cacheCreationTokens": 0,
            "cacheReadTokens": 0,
            "costUSD": 0.01
          },
          "byModel": [],
          "byDay": [],
          "byProject": [],
          "bySource": {},
          "sessionsScanned": 0,
          "sessionsBySource": {},
          "daysBack": 30
        }
        """.utf8)
        let report = try JSONDecoder().decode(UsageReport.self, from: data)
        XCTAssertTrue(report.byMonth.isEmpty)
        XCTAssertTrue(report.monthSummaries.isEmpty)
        XCTAssertTrue(report.bySession.isEmpty)
        XCTAssertNil(report.sourceInfo)
        XCTAssertEqual(report.grand.totalTokens, 30)
    }

    func testUsageScannerFileCacheInvalidatesChangedAndRemovedFiles() throws {
        let root = try Self.makeTempDir()
        let claude = root.appendingPathComponent("claude", isDirectory: true)
        let codex = root.appendingPathComponent("codex", isDirectory: true)
        let pi = root.appendingPathComponent("pi", isDirectory: true)
        let cache = root.appendingPathComponent("cache", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try [claude, codex, pi, cache].forEach {
            try FileManager.default.createDirectory(at: $0, withIntermediateDirectories: true)
        }

        let project = claude.appendingPathComponent("project", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let session = project.appendingPathComponent("session.jsonl")
        try Self.writeClaudeUsage(to: session, input: 100, output: 50)

        let scanner = UsageScanner(
            claudeProjectsDir: claude,
            codexSessionsDir: codex,
            modelsDevCacheRoot: cache,
            piSessionsDir: pi)
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-06-09T00:00:00Z"))
        let first = try scanner.scanWithFileCache(daysBack: 30, now: now, cacheRoot: cache)
        XCTAssertEqual(first.grand.inputTokens, 100)
        XCTAssertTrue(FileManager.default.fileExists(atPath: UsageScanner.fileCacheFileURL(cacheRoot: cache).path))

        Thread.sleep(forTimeInterval: 0.02)
        try Self.writeClaudeUsage(to: session, input: 250, output: 75)
        let changed = try scanner.scanWithFileCache(daysBack: 30, now: now.addingTimeInterval(1), cacheRoot: cache)
        XCTAssertEqual(changed.grand.inputTokens, 250)
        XCTAssertEqual(changed.grand.outputTokens, 75)

        try FileManager.default.removeItem(at: session)
        let removed = try scanner.scanWithFileCache(daysBack: 30, now: now.addingTimeInterval(2), cacheRoot: cache)
        XCTAssertEqual(removed.grand.inputTokens, 0)
        XCTAssertEqual(removed.sessionsScanned, 0)
    }

    func testCodexFileCacheAppendsOnlyNewTokenDeltas() throws {
        let root = try Self.makeTempDir()
        let claude = root.appendingPathComponent("claude", isDirectory: true)
        let codex = root.appendingPathComponent("codex", isDirectory: true)
        let pi = root.appendingPathComponent("pi", isDirectory: true)
        let cache = root.appendingPathComponent("cache", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try [claude, codex, pi, cache].forEach {
            try FileManager.default.createDirectory(at: $0, withIntermediateDirectories: true)
        }

        let dayDir = codex.appendingPathComponent("2026/06/08", isDirectory: true)
        try FileManager.default.createDirectory(at: dayDir, withIntermediateDirectories: true)
        let session = dayDir.appendingPathComponent("rollout-x.jsonl")
        let meta = #"{"timestamp":"2026-06-08T09:00:00.000Z","type":"session_meta","payload":{"id":"x","cwd":"/Users/test/proj-b","model":"gpt-5.5"}}"#
        let tc1 = #"{"timestamp":"2026-06-08T09:01:00Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":500,"cached_input_tokens":100,"output_tokens":50,"reasoning_output_tokens":10}}}}"#
        let tc2 = #"{"timestamp":"2026-06-08T09:02:00Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1000,"cached_input_tokens":300,"output_tokens":200,"reasoning_output_tokens":40}}}}"#
        try ([meta, tc1, tc2].joined(separator: "\n") + "\n")
            .write(to: session, atomically: true, encoding: .utf8)

        let scanner = UsageScanner(
            claudeProjectsDir: claude,
            codexSessionsDir: codex,
            modelsDevCacheRoot: cache,
            piSessionsDir: pi)
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-06-09T00:00:00Z"))
        let first = try scanner.scanWithFileCache(daysBack: 30, now: now, cacheRoot: cache)
        XCTAssertEqual(first.grand.inputTokens, 700)
        XCTAssertEqual(first.grand.cacheReadTokens, 300)
        XCTAssertEqual(first.grand.outputTokens, 200)

        let tc3 = #"{"timestamp":"2026-06-08T09:03:00Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1300,"cached_input_tokens":350,"output_tokens":260,"reasoning_output_tokens":50}}}}"#
        try Self.appendLine(tc3, to: session)

        let appended = try scanner.scanWithFileCache(daysBack: 30, now: now.addingTimeInterval(1), cacheRoot: cache)
        XCTAssertEqual(appended.grand.inputTokens, 950)
        XCTAssertEqual(appended.grand.cacheReadTokens, 350)
        XCTAssertEqual(appended.grand.outputTokens, 260)
        XCTAssertEqual(appended.sessionsBySource[.codex], 1)
    }

    func testClaudeFileCacheAppendsOnlyNewAssistantRows() throws {
        let root = try Self.makeTempDir()
        let claude = root.appendingPathComponent("claude", isDirectory: true)
        let codex = root.appendingPathComponent("codex", isDirectory: true)
        let pi = root.appendingPathComponent("pi", isDirectory: true)
        let cache = root.appendingPathComponent("cache", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try [claude, codex, pi, cache].forEach {
            try FileManager.default.createDirectory(at: $0, withIntermediateDirectories: true)
        }

        let project = claude.appendingPathComponent("project", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let session = project.appendingPathComponent("session.jsonl")
        let cwd = #"{"type":"user","cwd":"/Users/test/claude-proj","message":{"role":"user"}}"#
        let firstLine = Self.claudeUsageLine(id: "msg_first", requestID: "req_first", input: 100, output: 50)
        try ([cwd, firstLine].joined(separator: "\n") + "\n").write(to: session, atomically: true, encoding: .utf8)

        let scanner = UsageScanner(
            claudeProjectsDir: claude,
            codexSessionsDir: codex,
            modelsDevCacheRoot: cache,
            piSessionsDir: pi)
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-06-09T00:00:00Z"))
        let first = try scanner.scanWithFileCache(daysBack: 30, now: now, cacheRoot: cache)
        XCTAssertEqual(first.grand.inputTokens, 100)
        XCTAssertEqual(first.byProject.first?.path, "/Users/test/claude-proj")

        try Self.appendLine(Self.claudeUsageLine(id: "msg_second", requestID: "req_second", input: 25, output: 75), to: session)
        let appended = try scanner.scanWithFileCache(daysBack: 30, now: now.addingTimeInterval(1), cacheRoot: cache)
        XCTAssertEqual(appended.grand.inputTokens, 125)
        XCTAssertEqual(appended.grand.outputTokens, 125)
        XCTAssertEqual(appended.sessionsBySource[.claude], 1)
    }

    func testPiFileCacheAppendsUsingCachedModelContext() throws {
        let root = try Self.makeTempDir()
        let claude = root.appendingPathComponent("claude", isDirectory: true)
        let codex = root.appendingPathComponent("codex", isDirectory: true)
        let pi = root.appendingPathComponent("pi", isDirectory: true)
        let cache = root.appendingPathComponent("cache", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try [claude, codex, pi, cache].forEach {
            try FileManager.default.createDirectory(at: $0, withIntermediateDirectories: true)
        }

        let session = pi.appendingPathComponent("session.jsonl")
        let modelChange = #"{"type":"model_change","timestamp":"2026-06-08T10:00:00Z","provider":"anthropic","model":"claude-sonnet-4-6"}"#
        let firstMessage = Self.piAssistantLine(input: 10, output: 20, includeIdentity: false)
        try ([modelChange, firstMessage].joined(separator: "\n") + "\n").write(to: session, atomically: true, encoding: .utf8)

        let scanner = UsageScanner(
            claudeProjectsDir: claude,
            codexSessionsDir: codex,
            modelsDevCacheRoot: cache,
            piSessionsDir: pi)
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-06-09T00:00:00Z"))
        let first = try scanner.scanWithFileCache(daysBack: 30, now: now, cacheRoot: cache)
        XCTAssertEqual(first.grand.inputTokens, 10)
        XCTAssertEqual(first.grand.outputTokens, 20)
        XCTAssertEqual(first.bySource[.claude]?.inputTokens, 10)

        try Self.appendLine(Self.piAssistantLine(input: 30, output: 40, includeIdentity: false), to: session)
        let appended = try scanner.scanWithFileCache(daysBack: 30, now: now.addingTimeInterval(1), cacheRoot: cache)
        XCTAssertEqual(appended.grand.inputTokens, 40)
        XCTAssertEqual(appended.grand.outputTokens, 60)
        XCTAssertEqual(appended.bySource[.claude]?.inputTokens, 40)
    }

    func testClearCostAndPricingCaches() throws {
        let cache = try Self.makeTempDir()
        let appSupport = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: cache) }
        defer { try? FileManager.default.removeItem(at: appSupport) }
        ModelsDevCache.save(catalog: ModelsDevCatalog(providers: [:]), fetchedAt: Date(), cacheRoot: cache)
        let costCacheDir = UsageScanner.fileCacheFileURL(cacheRoot: cache).deletingLastPathComponent()
        try FileManager.default.createDirectory(at: costCacheDir, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: UsageScanner.fileCacheFileURL(cacheRoot: cache))
        let oldFileCache = UsageScanner.fileCacheFileURL(cacheRoot: cache)
            .deletingLastPathComponent()
            .appendingPathComponent("file-cache-v1.json")
        try Data("{}".utf8).write(to: oldFileCache)
        let reportCache = costCacheDir.appendingPathComponent("local-report-v9.json")
        try Data("{}".utf8).write(to: reportCache)
        let uiCache = appSupport.appendingPathComponent("usage-90d.json")
        let preservedHistory = appSupport.appendingPathComponent("usage-history.json")
        try Data("{}".utf8).write(to: uiCache)
        try Data("{}".utf8).write(to: preservedHistory)

        CostUsageFetcher.clearCache(
            cacheRoot: cache,
            includePricing: true,
            applicationSupportRoot: appSupport)

        XCTAssertFalse(FileManager.default.fileExists(atPath: ModelsDevCache.cacheFileURL(cacheRoot: cache).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: UsageScanner.fileCacheFileURL(cacheRoot: cache).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldFileCache.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: reportCache.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: uiCache.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: preservedHistory.path))
    }

    func testClearProviderCachesRemovesDashboardAndWarningStateOnly() throws {
        let cache = try Self.makeTempDir()
        let appSupport = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: cache) }
        defer { try? FileManager.default.removeItem(at: appSupport) }
        let dashboard = OpenAIDashboardCacheStore.cacheURL(cacheRoot: cache)
        try FileManager.default.createDirectory(at: dashboard.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: dashboard)
        let warning = UsageCacheCleaner.quotaWarningStateURL(applicationSupportRoot: appSupport)
        try Data("{}".utf8).write(to: warning)
        let uiCache = appSupport.appendingPathComponent("usage-30d.json")
        try Data("{}".utf8).write(to: uiCache)

        UsageCacheCleaner.clearProviderCaches(
            cacheRoot: cache,
            applicationSupportRoot: appSupport)

        XCTAssertFalse(FileManager.default.fileExists(atPath: dashboard.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: warning.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: uiCache.path))
    }

    func testClearCookieDerivedCachesHonorsProviderScope() throws {
        let cache = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: cache) }
        let dashboard = OpenAIDashboardCacheStore.cacheURL(cacheRoot: cache)
        try FileManager.default.createDirectory(at: dashboard.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: dashboard)

        let claudeRemoved = UsageCacheCleaner.clearCookieDerivedCaches(providerID: "claude", cacheRoot: cache)

        XCTAssertTrue(claudeRemoved.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dashboard.path))

        let codexRemoved = UsageCacheCleaner.clearCookieDerivedCaches(providerID: "codex", cacheRoot: cache)

        XCTAssertEqual(codexRemoved.map(\.lastPathComponent), ["codex-dashboard.json"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: dashboard.path))
    }

    private static func makeTempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("conductor-cost-fetcher-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func writeClaudeUsage(to url: URL, input: Int, output: Int) throws {
        let line = claudeUsageLine(id: "msg_cache", requestID: "req", input: input, output: output)
        try (line + "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    private static func claudeUsageLine(id: String, requestID: String, input: Int, output: Int) -> String {
        """
        {"type":"assistant","timestamp":"2026-06-08T10:00:00.000Z","requestId":"\(requestID)","message":{"id":"\(id)","model":"claude-sonnet-4-6","role":"assistant","usage":{"input_tokens":\(input),"output_tokens":\(output),"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}
        """
    }

    private static func piAssistantLine(input: Int, output: Int, includeIdentity: Bool) -> String {
        let identity = includeIdentity ? #","provider":"anthropic","model":"claude-sonnet-4-6""# : ""
        return """
        {"type":"message","timestamp":"2026-06-08T10:01:00Z"\(identity),"message":{"role":"assistant","cwd":"/Users/test/pi-proj","usage":{"input_tokens":\(input),"output_tokens":\(output)}}}
        """
    }

    private static func appendLine(_ line: String, to url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data((line + "\n").utf8))
    }
}
