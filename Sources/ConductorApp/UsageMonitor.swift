import ConductorCore
import Foundation

struct StatusProviderUsageSignal: Identifiable, Equatable {
    struct Metric: Equatable {
        let title: String
        let remainingPercent: Double
        let usedPercent: Double
    }

    let providerID: String
    let providerName: String
    let logoName: String
    let fallbackSystemImage: String
    let windowTitle: String
    let remainingPercent: Double
    let usedPercent: Double
    let updatedAt: Date
    let secondaryMetric: Metric?

    var id: String { providerID }
}

struct StatusProviderUsageOverview: Equatable {
    var configuredCount: Int = 0
    var loadedCount: Int = 0
    var loadingCount: Int = 0
    var errorCount: Int = 0
    var headline: StatusProviderUsageSignal?
    var lastUpdatedAt: Date?

    var hasContent: Bool {
        configuredCount > 0 || loadedCount > 0 || loadingCount > 0 || errorCount > 0 || headline != nil
    }
}

struct StatusProviderSwitcherItem: Identifiable, Equatable {
    let providerID: String
    let providerName: String
    let logoName: String
    let fallbackSystemImage: String
    let isConfigured: Bool
    let isLoading: Bool
    let errorMessage: String?
    let signal: StatusProviderUsageSignal?
    let storageFootprint: ProviderStorageFootprint?
    let updatedAt: Date?

    var id: String { providerID }
}

/// 手动拉取 Codex 用量，供状态栏常驻显示。启动应用不会主动请求账号数据。
@MainActor
final class UsageMonitor: ObservableObject {
    @Published private(set) var codex: CodexUsageSnapshot?
    @Published private(set) var codexError: String?
    @Published private(set) var isRefreshing = false
    @Published private(set) var visibleProviders: [UsageProviderEntry] = []
    @Published private(set) var configuredProviderIDs: Set<String> = []
    @Published private(set) var providerSnapshots: [String: UsageSnapshot] = [:]
    @Published private(set) var providerErrors: [String: String] = [:]
    @Published private(set) var providerLoadingIDs: Set<String> = []
    @Published private(set) var providerStorageFootprints: [String: ProviderStorageFootprint] = [:]
    @Published private(set) var isScanningProviderStorage = false
    @Published private(set) var providerOverviewPrepared = false
    @Published private(set) var isPreparingProviderOverview = false
    @Published private(set) var providerRefreshCompletedAt: Date?

    private var providerSmartRefreshTask: Task<Void, Never>?
    private var providerStorageScanTask: Task<Void, Never>?
    private var providerLastBackgroundRefreshAttemptAt: Date?

    private static let providerSmartRefreshInitialDelay: TimeInterval = 20
    private static let providerSmartRefreshManualSleepInterval: TimeInterval = 60
    private static let providerSmartRefreshMaxProviders = 6

    deinit {
        providerSmartRefreshTask?.cancel()
        providerStorageScanTask?.cancel()
    }

    var providerOverview: StatusProviderUsageOverview {
        let config = ConfigStore.shared.config
        let overviewProviders = statusBarOverviewProviders(config: config)
        let overviewIDs = Set(overviewProviders.map(\.id))
        let configuredCount = overviewProviders.filter { configuredProviderIDs.contains($0.id) }.count
        let loadedSignals = overviewProviders.compactMap { provider -> (provider: UsageProviderEntry, snapshot: UsageSnapshot, signal: StatusProviderUsageSignal)? in
            guard let snapshot = providerSnapshots[provider.id],
                  let signal = Self.signal(provider: provider, snapshot: snapshot, config: config)
            else {
                return nil
            }
            return (provider, snapshot, signal)
        }
        let headline = loadedSignals
            .filter { item in
                !Self.excludeFromProviderHeadline(
                    providerID: item.provider.id,
                    snapshot: item.snapshot,
                    signal: item.signal)
            }
            .map(\.signal)
            .min {
                let leftRemaining = min($0.remainingPercent, $0.secondaryMetric?.remainingPercent ?? 100)
                let rightRemaining = min($1.remainingPercent, $1.secondaryMetric?.remainingPercent ?? 100)
                if leftRemaining != rightRemaining {
                    return leftRemaining < rightRemaining
                }
                return $0.providerName < $1.providerName
            }
        return StatusProviderUsageOverview(
            configuredCount: configuredCount,
            loadedCount: loadedSignals.count,
            loadingCount: providerLoadingIDs.filter { overviewIDs.contains($0) }.count,
            errorCount: providerErrors.keys.filter { overviewIDs.contains($0) }.count,
            headline: headline,
            lastUpdatedAt: providerRefreshCompletedAt)
    }

    var providerSwitcherItems: [StatusProviderSwitcherItem] {
        let config = ConfigStore.shared.config
        return statusBarOverviewProviders(config: config)
            .map { provider in
                let snapshot = providerSnapshots[provider.id]
                return StatusProviderSwitcherItem(
                    providerID: provider.id,
                    providerName: provider.name,
                    logoName: provider.logoName,
                    fallbackSystemImage: provider.fallbackSystemImage,
                    isConfigured: configuredProviderIDs.contains(provider.id),
                    isLoading: providerLoadingIDs.contains(provider.id),
                    errorMessage: providerErrors[provider.id],
                    signal: snapshot.flatMap { Self.signal(provider: provider, snapshot: $0, config: config) },
                    storageFootprint: config.usage.providerStorageFootprintsEnabled ? providerStorageFootprints[provider.id] : nil,
                    updatedAt: snapshot?.updatedAt)
            }
    }

    private func statusBarOverviewProviders(config: AppConfig) -> [UsageProviderEntry] {
        let active = visibleProviders.filter { $0.id != "codex" }
        let selectedIDs = config.usage.effectiveStatusBarOverviewProviderIDs(
            activeProviderIDs: active.map(\.id))
        let selectedSet = Set(selectedIDs)
        return active.filter { selectedSet.contains($0.id) }
    }

    private static func hydratedProviderSnapshots(
        providers: [UsageProviderEntry],
        configuredIDs: Set<String>,
        config: AppConfig)
        -> [String: UsageSnapshot]
    {
        providers.reduce(into: [:]) { result, provider in
            guard configuredIDs.contains(provider.id) else { return }
            let accountKey = UsageHistoryStore.accountKey(
                providerID: provider.id,
                snapshot: nil,
                config: config)
            guard let snapshot = UsageSnapshotHydrationStore.loadSnapshot(
                providerID: provider.id,
                accountKey: accountKey)
            else {
                return
            }
            result[provider.id] = snapshot
        }
    }

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        Task {
            do {
                let snap = try await CodexUsageFetcher.fetch()
                self.codex = snap
                self.codexError = nil
                let snapshot = UsageSnapshot(codexSnapshot: snap)
                self.providerSnapshots["codex"] = snapshot
                self.providerErrors.removeValue(forKey: "codex")
                UsageHistoryStore.shared.record(
                    providerID: "codex",
                    snapshot: snapshot,
                    config: ConfigStore.shared.config)
                UsageHistoryStore.shared.persist()
                if let provider = UsageProviderCatalog.all.first(where: { $0.id == "codex" }) {
                    UsageQuotaWarningCenter.shared.handle(
                        provider: provider,
                        snapshot: snapshot,
                        config: ConfigStore.shared.config)
                }
            } catch {
                self.codexError = error.localizedDescription
                self.providerErrors["codex"] = error.localizedDescription
            }
            self.isRefreshing = false
            MemoryPressureReliefScheduler.shared.schedule()
        }
    }

    func prepareProviderOverview(force: Bool = false) {
        guard force || (!providerOverviewPrepared && !isPreparingProviderOverview) else { return }
        isPreparingProviderOverview = true
        let config = ConfigStore.shared.config
        Task {
            let resolved = await Task.detached(priority: .utility) { () -> [(UsageProviderEntry, Bool)] in
                UsageCredentials.apply(config)
                return UsageProviderCatalog.orderedEntries(config: config)
                    .filter { UsageCredentials.isVisible($0, config: config) }
                    .map { ($0, UsageCredentials.isConfiguredWithoutBrowserPrompt($0, config: config)) }
            }.value
            let providers = resolved.map(\.0)
            let configured = Set(resolved.filter(\.1).map { $0.0.id })
            await MainActor.run {
                let visibleIDs = Set(providers.map(\.id))
                let hydratedSnapshots = Self.hydratedProviderSnapshots(
                    providers: providers,
                    configuredIDs: configured,
                    config: config)
                var nextSnapshots = self.providerSnapshots.filter { visibleIDs.contains($0.key) }
                for (providerID, snapshot) in hydratedSnapshots where nextSnapshots[providerID] == nil {
                    nextSnapshots[providerID] = snapshot
                }
                self.visibleProviders = providers
                self.configuredProviderIDs = configured
                self.providerSnapshots = nextSnapshots
                self.providerErrors = self.providerErrors.filter { visibleIDs.contains($0.key) }
                self.providerLoadingIDs = self.providerLoadingIDs.filter { visibleIDs.contains($0) }
                self.providerOverviewPrepared = true
                self.isPreparingProviderOverview = false
                if config.usage.providerStorageFootprintsEnabled {
                    self.refreshProviderStorageFootprints(force: force)
                } else {
                    self.clearProviderStorageFootprints()
                }
            }
        }
    }

    func refreshProviderStorageFootprints(force: Bool = false) {
        let config = ConfigStore.shared.config
        guard config.usage.providerStorageFootprintsEnabled else {
            clearProviderStorageFootprints()
            return
        }
        let providers = visibleProviders
        guard !providers.isEmpty else { return }
        if force {
            providerStorageScanTask?.cancel()
            providerStorageScanTask = nil
            isScanningProviderStorage = false
        } else if isScanningProviderStorage {
            return
        }

        isScanningProviderStorage = true
        providerStorageScanTask = Task { [weak self] in
            let footprints = await Task.detached(priority: .utility) {
                ProviderStorageFootprintLoader.scanProviders(providers, config: config)
            }.value
            await MainActor.run { [weak self] in
                guard let self, !Task.isCancelled else { return }
                let updated = ProviderStorageFootprint.applyingScanResults(
                    footprints,
                    to: self.providerStorageFootprints,
                    providerIDs: providers.map(\.id))
                if updated != self.providerStorageFootprints {
                    self.providerStorageFootprints = updated
                }
                self.isScanningProviderStorage = false
                self.providerStorageScanTask = nil
            }
        }
    }

    func clearProviderStorageFootprints() {
        providerStorageScanTask?.cancel()
        providerStorageScanTask = nil
        isScanningProviderStorage = false
        if !providerStorageFootprints.isEmpty {
            providerStorageFootprints = [:]
        }
    }

    func startProviderSmartRefresh() {
        guard providerSmartRefreshTask == nil else { return }
        guard providerSmartRefreshInterval() != nil else { return }
        providerSmartRefreshTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.providerSmartRefreshInitialDelay))
            while !Task.isCancelled {
                self?.refreshConfiguredProvidersIfStale()
                let interval = self?.providerSmartRefreshInterval()
                    ?? Self.providerSmartRefreshManualSleepInterval
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    func restartProviderSmartRefresh() {
        providerSmartRefreshTask?.cancel()
        providerSmartRefreshTask = nil
        startProviderSmartRefresh()
    }

    func refreshConfiguredProviders(maxProviders: Int = 6, force: Bool = true) {
        guard providerLoadingIDs.isEmpty else { return }
        if !force, !providerBackgroundRefreshDue() { return }
        if force {
            providerLastBackgroundRefreshAttemptAt = nil
        } else {
            providerLastBackgroundRefreshAttemptAt = Date()
        }
        let config = ConfigStore.shared.config
        Task {
            let resolved = await Task.detached(priority: .utility) { () -> [(UsageProviderEntry, Bool)] in
                UsageCredentials.apply(config)
                return UsageProviderCatalog.orderedEntries(config: config)
                    .filter { UsageCredentials.isVisible($0, config: config) }
                    .map { ($0, UsageCredentials.isConfiguredWithoutBrowserPrompt($0, config: config)) }
            }.value
            let providers = Array(resolved.filter(\.1).map(\.0).prefix(max(1, maxProviders)))
            await MainActor.run {
                self.visibleProviders = resolved.map(\.0)
                self.configuredProviderIDs = Set(resolved.filter(\.1).map { $0.0.id })
                self.providerOverviewPrepared = true
                self.isPreparingProviderOverview = false
                self.providerLoadingIDs = Set(providers.map(\.id))
                for provider in providers {
                    self.providerErrors.removeValue(forKey: provider.id)
                }
                if providers.isEmpty {
                    self.providerRefreshCompletedAt = Date()
                }
            }

            for provider in providers {
                do {
                    let snapshot = try await UsageProviderAppFetchBridge.fetch(provider, config: config) {
                        try await UsageProviderRuntimeContext.withInteraction(force ? .foreground : .background) {
                            try await provider.fetch()
                        }
                    }
                    await MainActor.run {
                        self.providerSnapshots[provider.id] = snapshot
                        self.providerErrors.removeValue(forKey: provider.id)
                        self.providerLoadingIDs.remove(provider.id)
                        UsageHistoryStore.shared.record(
                            providerID: provider.id,
                            snapshot: snapshot,
                            config: config)
                        UsageHistoryStore.shared.persist()
                        UsageQuotaWarningCenter.shared.handle(provider: provider, snapshot: snapshot, config: config)
                    }
                } catch {
                    await MainActor.run {
                        self.providerErrors[provider.id] = error.localizedDescription
                        self.providerLoadingIDs.remove(provider.id)
                    }
                }
            }

            await MainActor.run {
                self.providerRefreshCompletedAt = Date()
                MemoryPressureReliefScheduler.shared.schedule()
            }
        }
    }

    private func refreshConfiguredProvidersIfStale() {
        if !providerOverviewPrepared {
            prepareProviderOverview()
        }
        refreshConfiguredProviders(maxProviders: Self.providerSmartRefreshMaxProviders, force: false)
    }

    private func providerBackgroundRefreshDue(now: Date = Date()) -> Bool {
        guard providerOverviewPrepared, !isPreparingProviderOverview, providerLoadingIDs.isEmpty else {
            return false
        }
        guard !configuredProviderIDs.subtracting(["codex"]).isEmpty else {
            return false
        }
        let lastAttempt = providerLastBackgroundRefreshAttemptAt ?? .distantPast
        let lastCompleted = providerRefreshCompletedAt ?? .distantPast
        let last = max(lastAttempt, lastCompleted)
        guard let interval = providerSmartRefreshInterval() else { return false }
        return now.timeIntervalSince(last) >= interval
    }

    private func providerSmartRefreshInterval() -> TimeInterval? {
        let seconds = ConfigStore.shared.config.usage.providerRefreshIntervalSeconds
        guard seconds > UsageConfig.manualProviderRefreshIntervalSeconds else { return nil }
        return TimeInterval(UsageConfig.normalizedProviderRefreshIntervalSeconds(seconds))
    }

    static func signal(
        provider: UsageProviderEntry,
        snapshot: UsageSnapshot,
        config: AppConfig) -> StatusProviderUsageSignal?
    {
        if provider.id == "antigravity" {
            return antigravitySignal(provider: provider, snapshot: snapshot)
        }

        let showOptional = config.usage.showOptionalCreditsAndExtraUsage
        let metadata = provider.displayMetadata
        var windows: [(title: String, window: RateWindow)] = []
        if let primary = snapshot.primary { windows.append((primary.title ?? metadata.sessionLabel, primary)) }
        if let secondary = snapshot.secondary { windows.append((secondary.title ?? metadata.weeklyLabel, secondary)) }
        if let tertiary = snapshot.tertiary { windows.append((tertiary.title ?? metadata.opusLabel ?? L("其它"), tertiary)) }
        if showOptional {
            windows.append(contentsOf: snapshot.extraRateWindows.map { ($0.title, $0.window) })
        }
        var candidates = windows.map { item in
            (title: item.title, remaining: item.window.remainingPercent, used: item.window.usedPercent)
        }
        if showOptional, let cost = snapshot.providerCost, cost.hasLimit {
            candidates.append((
                title: cost.period?.isEmpty == false ? cost.period! : L("成本"),
                remaining: max(0, 100 - cost.usedPercent),
                used: cost.usedPercent))
        }
        guard let tightest = candidates.min(by: {
            if $0.remaining != $1.remaining { return $0.remaining < $1.remaining }
            return $0.title < $1.title
        }) else {
            return nil
        }
        let secondaryMetric = copilotSecondaryMetric(providerID: provider.id, snapshot: snapshot, config: config)
        return StatusProviderUsageSignal(
            providerID: provider.id,
            providerName: provider.name,
            logoName: provider.logoName,
            fallbackSystemImage: provider.fallbackSystemImage,
            windowTitle: tightest.title,
            remainingPercent: tightest.remaining,
            usedPercent: tightest.used,
            updatedAt: snapshot.updatedAt,
            secondaryMetric: secondaryMetric)
    }

    static func excludeFromProviderHeadline(
        providerID: String,
        snapshot: UsageSnapshot,
        signal: StatusProviderUsageSignal) -> Bool
    {
        guard providerID == "antigravity", signal.usedPercent >= 100 else { return false }
        let windows = antigravityCompactWindows(snapshot: snapshot)
        let percents = [windows.primary?.window.usedPercent, windows.secondary?.window.usedPercent]
            .compactMap(\.self)
        guard !percents.isEmpty else { return true }
        return percents.allSatisfy { $0 >= 100 }
    }

    private static let antigravityQuotaSummaryWindowIDPrefix = "antigravity-quota-summary-"
    private static let antigravityGeminiQuotaBucketIDPrefix = "gemini-"
    private static let antigravitySessionWindowMinutes = 5 * 60
    private static let antigravityWeeklyWindowMinutes = 7 * 24 * 60

    private static func antigravitySignal(
        provider: UsageProviderEntry,
        snapshot: UsageSnapshot) -> StatusProviderUsageSignal?
    {
        let windows = antigravityCompactWindows(snapshot: snapshot)
        let compactWindows = [windows.primary, windows.secondary].compactMap(\.self)
        guard let tightest = tightestWindow(in: compactWindows) else { return nil }
        let secondaryMetric = compactWindows
            .filter { $0.title != tightest.title || $0.window != tightest.window }
            .first
            .map { item in
                StatusProviderUsageSignal.Metric(
                    title: item.title,
                    remainingPercent: item.window.remainingPercent,
                    usedPercent: item.window.usedPercent)
            }
        return StatusProviderUsageSignal(
            providerID: provider.id,
            providerName: provider.name,
            logoName: provider.logoName,
            fallbackSystemImage: provider.fallbackSystemImage,
            windowTitle: tightest.title,
            remainingPercent: tightest.window.remainingPercent,
            usedPercent: tightest.window.usedPercent,
            updatedAt: snapshot.updatedAt,
            secondaryMetric: secondaryMetric)
    }

    private static func antigravityCompactWindows(snapshot: UsageSnapshot)
        -> (primary: (title: String, window: RateWindow)?, secondary: (title: String, window: RateWindow)?)
    {
        let quotaSummaryWindows = snapshot.extraRateWindows.filter {
            $0.id.hasPrefix(antigravityQuotaSummaryWindowIDPrefix)
        }
        guard !quotaSummaryWindows.isEmpty else { return (nil, nil) }

        let geminiWindows = quotaSummaryWindows.filter(isAntigravityGeminiQuotaSummaryWindow)
        let candidates = geminiWindows.isEmpty ? quotaSummaryWindows : geminiWindows
        return (
            primary: antigravityMostConstrainedWindow(
                in: candidates,
                windowMinutes: antigravitySessionWindowMinutes),
            secondary: antigravityMostConstrainedWindow(
                in: candidates,
                windowMinutes: antigravityWeeklyWindowMinutes))
    }

    private static func isAntigravityGeminiQuotaSummaryWindow(_ window: NamedRateWindow) -> Bool {
        antigravityQuotaSummaryBucketID(for: window)?
            .hasPrefix(antigravityGeminiQuotaBucketIDPrefix) == true
    }

    private static func antigravityQuotaSummaryBucketID(for window: NamedRateWindow) -> String? {
        guard window.id.hasPrefix(antigravityQuotaSummaryWindowIDPrefix) else { return nil }
        return String(window.id.dropFirst(antigravityQuotaSummaryWindowIDPrefix.count))
    }

    private static func antigravityMostConstrainedWindow(
        in windows: [NamedRateWindow],
        windowMinutes: Int) -> (title: String, window: RateWindow)?
    {
        windows
            .filter { $0.window.windowMinutes == windowMinutes }
            .max { lhs, rhs in
                if lhs.window.usedPercent != rhs.window.usedPercent {
                    return lhs.window.usedPercent < rhs.window.usedPercent
                }
                return lhs.id > rhs.id
            }
            .map { ($0.title, $0.window) }
    }

    private static func tightestWindow(in windows: [(title: String, window: RateWindow)])
        -> (title: String, window: RateWindow)?
    {
        windows
            .min {
                if $0.window.remainingPercent != $1.window.remainingPercent {
                    return $0.window.remainingPercent < $1.window.remainingPercent
                }
                return $0.title < $1.title
            }
    }

    private static func copilotSecondaryMetric(
        providerID: String,
        snapshot: UsageSnapshot,
        config: AppConfig) -> StatusProviderUsageSignal.Metric?
    {
        guard providerID == "copilot" else { return nil }
        let showOptional = config.usage.showOptionalCreditsAndExtraUsage
        let selected = config.usage.providers["copilot"]?.extra["iconSecondaryWindowID"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedID = selected?.isEmpty == false ? selected! : "chat"
        let window: (title: String, window: RateWindow)?
        if resolvedID == "chat" {
            window = snapshot.secondary.map { ($0.title ?? L("聊天"), $0) }
        } else if showOptional, let extra = snapshot.extraRateWindows.first(where: { $0.id == resolvedID }) {
            window = (extra.title, extra.window)
        } else {
            window = snapshot.secondary.map { ($0.title ?? L("聊天"), $0) }
        }
        guard let window else { return nil }
        return StatusProviderUsageSignal.Metric(
            title: window.title,
            remainingPercent: window.window.remainingPercent,
            usedPercent: window.window.usedPercent)
    }

}
