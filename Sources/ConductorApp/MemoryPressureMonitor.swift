import ConductorCore
import Darwin
import Dispatch
import Foundation

@MainActor
struct MemoryPressureCacheTrimSummary: Equatable {
    var openAIWebViews = 0
    var cliToolLogos = 0
    var petSpriteSheets = 0
    var petFrameSets = 0
    var sessionPreviewEntries = 0
    var sessionUsageEntries = 0
    var webDebugLines = 0

    var total: Int {
        openAIWebViews +
            cliToolLogos +
            petSpriteSheets +
            petFrameSets +
            sessionPreviewEntries +
            sessionUsageEntries +
            webDebugLines
    }

    var metadata: [String: String] {
        [
            "openAIWebViews": "\(openAIWebViews)",
            "cliToolLogos": "\(cliToolLogos)",
            "petSpriteSheets": "\(petSpriteSheets)",
            "petFrameSets": "\(petFrameSets)",
            "sessionPreviewEntries": "\(sessionPreviewEntries)",
            "sessionUsageEntries": "\(sessionUsageEntries)",
            "webDebugLines": "\(webDebugLines)",
            "total": "\(total)",
        ]
    }

    var logDescription: String {
        metadata
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: ", ")
    }

    mutating func merge(_ other: MemoryPressureCacheTrimSummary) {
        openAIWebViews += other.openAIWebViews
        cliToolLogos += other.cliToolLogos
        petSpriteSheets += other.petSpriteSheets
        petFrameSets += other.petFrameSets
        sessionPreviewEntries += other.sessionPreviewEntries
        sessionUsageEntries += other.sessionUsageEntries
        webDebugLines += other.webDebugLines
    }
}

@MainActor
final class MemoryPressureMonitor {
    typealias CacheTrimHandler = @MainActor () -> MemoryPressureCacheTrimSummary

    private let releaseFreeMallocPages: @Sendable () -> Void
    private let trimAppCaches: CacheTrimHandler
    private var source: DispatchSourceMemoryPressure?

    init(
        trimAppCaches: @escaping CacheTrimHandler = { MemoryPressureCacheTrimSummary() },
        releaseFreeMallocPages: @escaping @Sendable () -> Void = {
            MemoryPressureRelief.releaseFreeMallocPages()
        })
    {
        self.trimAppCaches = trimAppCaches
        self.releaseFreeMallocPages = releaseFreeMallocPages
    }

    func start() {
        guard source == nil else { return }

        let source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical],
            queue: .global(qos: .utility))
        source.setEventHandler { [weak self, weak source] in
            let event = source?.data ?? []
            let isWarning = event.contains(.warning)
            let isCritical = event.contains(.critical)
            Task { @MainActor [weak self] in
                self?.handleMemoryPressure(isWarning: isWarning, isCritical: isCritical)
            }
        }
        self.source = source
        source.resume()
    }

    func stop() {
        source?.cancel()
        source = nil
    }

    deinit {
        source?.cancel()
    }

    #if DEBUG
    func handleMemoryPressureForTesting(isWarning: Bool, isCritical: Bool) -> MemoryPressureCacheTrimSummary {
        handleMemoryPressure(isWarning: isWarning, isCritical: isCritical)
    }
    #endif

    @discardableResult
    private func handleMemoryPressure(isWarning: Bool, isCritical: Bool) -> MemoryPressureCacheTrimSummary {
        let level: String
        if isCritical {
            level = "critical"
        } else if isWarning {
            level = "warning"
        } else {
            level = "normal"
        }
        let evictedWebViews = OpenAIWebViewCacheMemoryPressureRelief.evictIdleDashboardWebViews()
        var trimSummary = MemoryPressureCacheTrimSummary(openAIWebViews: evictedWebViews)
        trimSummary.merge(trimAppCaches())
        NSLog("[conductor] memory pressure: \(level), trimmed rebuildable caches: \(trimSummary.logDescription)")

        let releaseFreeMallocPages = releaseFreeMallocPages
        Task.detached(priority: .utility) {
            releaseFreeMallocPages()
        }
        return trimSummary
    }
}

@MainActor
final class MemoryPressureReliefScheduler {
    static let shared = MemoryPressureReliefScheduler()

    private let releaseFreeMallocPages: @Sendable () -> Void
    private var task: Task<Void, Never>?

    init(releaseFreeMallocPages: @escaping @Sendable () -> Void = {
        MemoryPressureRelief.releaseFreeMallocPages()
    }) {
        self.releaseFreeMallocPages = releaseFreeMallocPages
    }

    func schedule() {
        guard task == nil else { return }

        let releaseFreeMallocPages = releaseFreeMallocPages
        task = Task.detached(priority: .utility) { [weak self] in
            for delay in [Duration.seconds(2), .seconds(8), .seconds(20)] {
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled else { return }
                releaseFreeMallocPages()
            }
            await MainActor.run { [weak self] in
                self?.task = nil
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}

private enum MemoryPressureRelief {
    static func releaseFreeMallocPages() {
        _ = malloc_zone_pressure_relief(nil, 0)
    }
}
