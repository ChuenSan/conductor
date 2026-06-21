import Combine
import ConductorCore
import Foundation

/// 一次用量采样：从 `UsageSnapshot` 抽出可画趋势的关键信号（各窗已用% + 额度/消费）。
public struct UsageSample: Codable, Equatable, Sendable {
    public var at: Date
    public var primaryPercent: Double?
    public var secondaryPercent: Double?
    public var tertiaryPercent: Double?
    /// providerCost.used（消费/余额金额）。
    public var costUsed: Double?
    /// providerCost.limit（<=0 表示无上限，存 0）。
    public var costLimit: Double?
    public var currency: String?
}

/// 账号用量历史：每次成功拉到 `UsageSnapshot` 就采一笔（按 15 分钟时间桶去重），落盘到
/// `Application Support/conductor/usage-history.json`，供 provider 行里的趋势图展示。
///
/// CodexBar 的历史图靠各 provider 的服务端时间序列接口；conductor 改用「自采样」——把我们每次
/// 已经拉到的快照累积起来画趋势，对全部 49 个 provider 通用，且不额外发请求。
@MainActor
public final class UsageHistoryStore: ObservableObject {
    public static let shared = UsageHistoryStore()

    @Published public private(set) var series: [String: [UsageSample]] = [:]
    @Published public private(set) var codexHistoricalDataset: CodexHistoricalDataset?
    @Published public private(set) var codexHistoricalAccountKey: String?

    /// 同一 provider 15 分钟内的采样合并为一笔（覆盖最后一笔），避免反复开面板灌爆历史。
    private let bucketSeconds: TimeInterval = 15 * 60
    private let maxPoints = 800
    private let maxAgeDays: TimeInterval = 45
    private let codexHistoricalStore = HistoricalUsageHistoryStore()
    private var dirty = false

    private init() { series = Self.load() }

    /// 记一笔采样到内存（不立刻写盘；批量结束后调 `persist()`）。
    public func record(id: String, snapshot: UsageSnapshot, now: Date = Date()) {
        record(id: id, snapshot: snapshot, accountKey: nil, now: now)
    }

    public func record(providerID: String, snapshot: UsageSnapshot, config: AppConfig, now: Date = Date()) {
        let accountKey = Self.accountKey(providerID: providerID, snapshot: snapshot, config: config)
        record(
            id: providerID,
            snapshot: snapshot,
            accountKey: accountKey,
            now: now)
        if providerID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "codex" {
            recordCodexHistoricalSampleIfNeeded(snapshot: snapshot, accountKey: accountKey, sampledAt: now)
        }
    }

    public func record(id: String, snapshot: UsageSnapshot, accountKey: String?, now: Date = Date()) {
        let sample = UsageSample(
            at: now,
            primaryPercent: snapshot.primary?.usedPercent,
            secondaryPercent: snapshot.secondary?.usedPercent,
            tertiaryPercent: snapshot.tertiary?.usedPercent,
            costUsed: snapshot.providerCost?.used,
            costLimit: snapshot.providerCost.map { $0.limit > 0 ? $0.limit : 0 },
            currency: snapshot.providerCost?.currencyCode)
        // 全空快照不记。
        guard sample.primaryPercent != nil || sample.secondaryPercent != nil
            || sample.tertiaryPercent != nil || sample.costUsed != nil else { return }

        let storageID = UsageAccountCacheKey.storageID(providerID: id, accountKey: accountKey)
        var arr = self.series[storageID] ?? []
        if let last = arr.last, now.timeIntervalSince(last.at) < self.bucketSeconds {
            arr[arr.count - 1] = sample
        } else {
            arr.append(sample)
        }
        let cutoff = now.addingTimeInterval(-self.maxAgeDays * 86400)
        arr.removeAll { $0.at < cutoff }
        if arr.count > self.maxPoints { arr.removeFirst(arr.count - self.maxPoints) }
        self.series[storageID] = arr
        self.dirty = true
        UsageSnapshotHydrationStore.save(
            providerID: id,
            accountKey: accountKey,
            snapshot: snapshot,
            recordedAt: now,
            source: "app")
    }

    public func samples(for id: String, accountKey: String? = nil) -> [UsageSample] {
        let storageID = UsageAccountCacheKey.storageID(providerID: id, accountKey: accountKey)
        if let scoped = self.series[storageID], !scoped.isEmpty {
            return scoped
        }
        guard accountKey != nil,
              !self.hasScopedSamples(for: id)
        else {
            return self.series[storageID] ?? []
        }
        return self.series[id] ?? []
    }

    public func samples(for providerID: String, snapshot: UsageSnapshot?, config: AppConfig) -> [UsageSample] {
        samples(
            for: providerID,
            accountKey: Self.accountKey(providerID: providerID, snapshot: snapshot, config: config))
    }

    public func sampleCount(for providerID: String, snapshot: UsageSnapshot?, config: AppConfig) -> Int {
        samples(for: providerID, snapshot: snapshot, config: config).count
    }

    public func paceSummary(
        providerID: String,
        window: RateWindow,
        snapshot: UsageSnapshot?,
        config: AppConfig,
        now: Date = Date())
        -> UsagePaceSummary?
    {
        let accountKey = Self.accountKey(providerID: providerID, snapshot: snapshot, config: config)
        if providerID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "codex",
           self.codexHistoricalAccountKey == accountKey,
           let historical = CodexHistoricalPaceEvaluator.evaluate(
               window: window,
               now: now,
               dataset: self.codexHistoricalDataset),
           historical.expectedUsedPercent >= 3
        {
            return historical.summary(now: now)
        }
        return UsagePace.summary(
            window: window,
            now: now,
            weeklyProgressWorkDays: config.usage.weeklyProgressWorkDays)
    }

    public static func accountKey(
        providerID: String,
        snapshot: UsageSnapshot?,
        config: AppConfig)
        -> String?
    {
        if let account = selectedTokenAccount(providerID: providerID, config: config) {
            return UsageAccountCacheKey.tokenAccountKey(
                providerID: providerID,
                account: account,
                usageAccountLabel: snapshot?.accountLabel)
        }
        return UsageAccountCacheKey.snapshotDerivedKey(
            providerID: providerID,
            usageAccountLabel: snapshot?.accountLabel)
    }

    /// 把内存历史落盘（批量采样后调一次）。
    public func persist() {
        guard self.dirty else { return }
        self.dirty = false
        Self.save(self.series)
    }

    private func hasScopedSamples(for providerID: String) -> Bool {
        self.series.contains { storageID, samples in
            !samples.isEmpty && UsageAccountCacheKey.isScopedStorageID(storageID, providerID: providerID)
        }
    }

    private func recordCodexHistoricalSampleIfNeeded(
        snapshot: UsageSnapshot,
        accountKey: String?,
        sampledAt: Date)
    {
        guard let weekly = snapshot.secondary,
              weekly.resetsAt != nil,
              weekly.windowMinutes != nil
        else {
            return
        }
        let usageAccountLabel = snapshot.accountLabel
        let snapshotUpdatedAt = snapshot.updatedAt
        Task.detached(priority: .utility) { [codexHistoricalStore] in
            var dataset = await codexHistoricalStore.recordCodexWeekly(
                window: weekly,
                sampledAt: sampledAt,
                accountKey: accountKey)
            if let backfilled = await Self.backfillCodexHistoricalFromReusableDashboard(
                store: codexHistoricalStore,
                snapshotWeekly: weekly,
                snapshotUpdatedAt: snapshotUpdatedAt,
                accountKey: accountKey,
                usageAccountLabel: usageAccountLabel)
            {
                dataset = backfilled
            }
            let finalDataset = dataset
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.codexHistoricalDataset = finalDataset
                self.codexHistoricalAccountKey = accountKey
            }
        }
    }

    nonisolated private static func backfillCodexHistoricalFromReusableDashboard(
        store: HistoricalUsageHistoryStore,
        snapshotWeekly: RateWindow,
        snapshotUpdatedAt: Date,
        accountKey: String?,
        usageAccountLabel: String?)
        async -> CodexHistoricalDataset?
    {
        guard let dashboard = OpenAIDashboardCacheStore.reusableSnapshotForCLI(
            reportAccount: nil,
            usageAccountLabel: usageAccountLabel,
            sourceLabel: "app-history")
        else {
            return nil
        }
        return await backfillCodexHistoricalFromDashboard(
            dashboard,
            store: store,
            fallbackWeekly: snapshotWeekly,
            fallbackUpdatedAt: snapshotUpdatedAt,
            accountKey: accountKey)
    }

    nonisolated static func backfillCodexHistoricalFromDashboard(
        _ dashboard: OpenAIDashboardSnapshot,
        store: HistoricalUsageHistoryStore,
        fallbackWeekly: RateWindow,
        fallbackUpdatedAt: Date,
        accountKey: String?)
        async -> CodexHistoricalDataset?
    {
        guard !dashboard.usageBreakdown.isEmpty else { return nil }
        if let dashboardWeekly = dashboard.secondaryLimit,
           dashboardWeekly.resetsAt != nil,
           dashboardWeekly.windowMinutes != nil
        {
            return await store.backfillCodexWeeklyFromUsageBreakdown(
                dashboard.usageBreakdown,
                referenceWindow: dashboardWeekly,
                now: dashboard.updatedAt,
                accountKey: accountKey)
        }

        let fallbackTolerance: TimeInterval = 5 * 60
        guard abs(fallbackUpdatedAt.timeIntervalSince(dashboard.updatedAt)) <= fallbackTolerance else {
            return nil
        }
        return await store.backfillCodexWeeklyFromUsageBreakdown(
            dashboard.usageBreakdown,
            referenceWindow: fallbackWeekly,
            now: fallbackUpdatedAt,
            accountKey: accountKey)
    }

    private static func selectedTokenAccount(providerID: String, config: AppConfig) -> UsageProviderTokenAccount? {
        guard let data = config.usage.providers[providerID]?.tokenAccounts,
              !data.accounts.isEmpty
        else {
            if providerID == "codex" {
                return CodexActiveAccountResolver.resolveDefaultAccount(
                    configured: nil,
                    discoveredAccounts: CodexManagedAccountDiscovery.tokenAccounts(
                        env: UsageCredentials.providerDiscoveryEnvironment()))
                    .resolvedAccount
            }
            return nil
        }

        if providerID == "codex" {
            return CodexActiveAccountResolver.resolveDefaultAccount(
                configured: data,
                discoveredAccounts: CodexManagedAccountDiscovery.tokenAccounts(
                    env: UsageCredentials.providerDiscoveryEnvironment()))
                .resolvedAccount
        }
        return data.accounts[data.clampedActiveIndex()]
    }

    // MARK: - 磁盘

    private static var fileURL: URL {
        let dir = ConductorPaths.appSupportDirectory()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("usage-history.json")
    }

    private static func load() -> [String: [UsageSample]] {
        guard let data = try? Data(contentsOf: self.fileURL) else { return [:] }
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return (try? d.decode([String: [UsageSample]].self, from: data)) ?? [:]
    }

    private static func save(_ series: [String: [UsageSample]]) {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        guard let data = try? e.encode(series) else { return }
        try? data.write(to: self.fileURL, options: .atomic)
    }
}
