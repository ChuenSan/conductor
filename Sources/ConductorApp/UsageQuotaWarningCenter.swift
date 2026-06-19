import ConductorCore
import Combine
import Foundation

struct UsageQuotaWarningFlash: Equatable {
    var providerID: String
    var providerName: String
    var windowTitle: String
    var threshold: Int
    var remainingPercent: Double
    var accountLabel: String?
    var postedAt: Date
    var until: Date
}

@MainActor
final class UsageQuotaWarningCenter: ObservableObject {
    static let shared = UsageQuotaWarningCenter()
    static let flashDuration: TimeInterval = 60

    private struct StateKey: Hashable {
        var providerID: String
        var window: QuotaWarningWindow
    }

    private struct PersistentState: Codable {
        var version: Int = 1
        var entries: [Entry] = []

        struct Entry: Codable {
            var providerID: String
            var window: QuotaWarningWindow
            var state: QuotaWarningState
        }
    }

    @Published private(set) var activeFlashes: [String: UsageQuotaWarningFlash] = [:]

    private var states: [StateKey: QuotaWarningState] = [:]
    private var flashTasks: [String: Task<Void, Never>] = [:]

    private init() {
        states = Self.loadStates()
    }

    func handle(provider: UsageProviderEntry, snapshot: UsageSnapshot, config: AppConfig) {
        let globalConfig = config.usage.quotaWarnings
        let providerConfig = config.usage.providers[provider.id]?.quotaWarnings
        var didChangeState = false

        for window in QuotaWarningWindow.allCases {
            let key = StateKey(providerID: provider.id, window: window)
            let policy = QuotaWarningPolicyResolver.resolve(
                global: globalConfig,
                provider: providerConfig,
                window: window)

            let result = UsageQuotaWarningEvaluator.evaluate(
                providerID: provider.id,
                providerName: provider.name,
                snapshot: snapshot,
                window: window,
                policy: policy,
                previous: states[key])

            if states[key] != result.state {
                didChangeState = true
            }
            states[key] = result.state
            if let event = result.event {
                deliver(event, sound: policy.soundEnabled)
            }
        }

        if didChangeState {
            Self.save(states)
        }
    }

    func reset(providerID: String? = nil) {
        guard let providerID else {
            states.removeAll()
            activeFlashes.removeAll()
            flashTasks.values.forEach { $0.cancel() }
            flashTasks.removeAll()
            Self.save(states)
            return
        }
        states = states.filter { $0.key.providerID != providerID }
        activeFlashes.removeValue(forKey: providerID)
        flashTasks[providerID]?.cancel()
        flashTasks.removeValue(forKey: providerID)
        Self.save(states)
    }

    private func deliver(_ event: QuotaWarningEvent, sound: Bool) {
        startFlash(event)

        let remaining = Int(event.currentRemaining.rounded())
        let title = L("用量告警：%@", event.providerName)
        let body: String
        if let account = event.accountLabel {
            body = L(
                "%1$@ · %2$@ · %3$@ 剩余 %4$ld%%，已低于 %5$ld%% 阈值。",
                event.providerName,
                account,
                event.windowTitle,
                remaining,
                event.threshold)
        } else {
            body = L(
                "%1$@ · %2$@ 剩余 %3$ld%%，已低于 %4$ld%% 阈值。",
                event.providerName,
                event.windowTitle,
                remaining,
                event.threshold)
        }

        NotificationManager.shared.notify(
            paneID: nil,
            title: title,
            body: body,
            bodyFallback: L("账号用量接近配额上限"),
            sound: sound)
    }

    private func startFlash(_ event: QuotaWarningEvent, postedAt: Date = Date()) {
        let until = postedAt.addingTimeInterval(Self.flashDuration)
        activeFlashes[event.providerID] = UsageQuotaWarningFlash(
            providerID: event.providerID,
            providerName: event.providerName,
            windowTitle: event.windowTitle,
            threshold: event.threshold,
            remainingPercent: event.currentRemaining,
            accountLabel: event.accountLabel,
            postedAt: postedAt,
            until: until)

        flashTasks[event.providerID]?.cancel()
        flashTasks[event.providerID] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.flashDuration * 1_000_000_000))
            await MainActor.run { [weak self] in
                self?.clearExpiredFlash(providerID: event.providerID, until: until)
            }
        }
    }

    private func clearExpiredFlash(providerID: String, until: Date, now: Date = Date()) {
        guard let flash = activeFlashes[providerID],
              flash.until == until,
              flash.until <= now
        else {
            return
        }
        activeFlashes.removeValue(forKey: providerID)
        flashTasks.removeValue(forKey: providerID)
    }

    private static var stateURL: URL {
        let directory = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("conductor", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("usage-quota-warning-state.json")
    }

    private static func loadStates() -> [StateKey: QuotaWarningState] {
        guard let data = try? Data(contentsOf: stateURL) else { return [:] }
        let decoder = JSONDecoder()
        guard let artifact = try? decoder.decode(PersistentState.self, from: data),
              artifact.version == 1
        else {
            try? FileManager.default.moveItem(
                at: stateURL,
                to: stateURL.appendingPathExtension("corrupt-\(UUID().uuidString)"))
            return [:]
        }

        return Dictionary(
            uniqueKeysWithValues: artifact.entries.map {
                (StateKey(providerID: $0.providerID, window: $0.window), $0.state)
            })
    }

    private static func save(_ states: [StateKey: QuotaWarningState]) {
        let artifact = PersistentState(
            entries: states
                .sorted {
                    if $0.key.providerID == $1.key.providerID {
                        return $0.key.window.rawValue < $1.key.window.rawValue
                    }
                    return $0.key.providerID < $1.key.providerID
                }
                .map {
                    PersistentState.Entry(
                        providerID: $0.key.providerID,
                        window: $0.key.window,
                        state: $0.value)
                })
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(artifact) else { return }
        try? data.write(to: stateURL, options: .atomic)
    }
}
