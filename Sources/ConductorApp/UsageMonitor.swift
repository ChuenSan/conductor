import ConductorCore
import Foundation

/// 周期性拉取 Codex 用量，供状态栏常驻显示。面板各自即时拉取，这里只负责后台节奏。
@MainActor
final class UsageMonitor: ObservableObject {
    @Published private(set) var codex: CodexUsageSnapshot?
    @Published private(set) var codexError: String?
    @Published private(set) var isRefreshing = false

    private var timer: Timer?
    private var started = false

    /// 默认 5 分钟刷新一次（额度变化不频繁，避免无谓请求）。
    func start(interval: TimeInterval = 300) {
        guard !started else { return }
        started = true
        refresh()
        let t = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        t.tolerance = 30
        timer = t
    }

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        Task {
            do {
                let snap = try await CodexUsageFetcher.fetch()
                self.codex = snap
                self.codexError = nil
            } catch {
                self.codexError = error.localizedDescription
            }
            self.isRefreshing = false
        }
    }

    deinit {
        timer?.invalidate()
    }
}
