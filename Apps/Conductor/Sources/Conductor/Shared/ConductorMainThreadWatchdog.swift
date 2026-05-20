import Foundation

final class ConductorMainThreadWatchdog: @unchecked Sendable {
    private let queue = DispatchQueue(label: "app.conductor.main-thread-watchdog", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var lastMainBeat = DispatchTime.now().uptimeNanoseconds
    private var lastReportedStallBucket: UInt64 = 0
    private let stallThresholdNanoseconds: UInt64 = 2_000_000_000

    func start() {
        guard timer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [weak self] in
            self?.tick()
        }
        self.timer = timer
        timer.resume()
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    private func tick() {
        let now = DispatchTime.now().uptimeNanoseconds
        let elapsed = now - lastMainBeat
        if elapsed > stallThresholdNanoseconds {
            let bucket = elapsed / 1_000_000_000
            if bucket != lastReportedStallBucket {
                lastReportedStallBucket = bucket
                ConductorLog.performance.warning("main-thread stall approx \(Double(elapsed) / 1_000_000_000, privacy: .public)s")
            }
        }

        DispatchQueue.main.async { [weak self] in
            let beat = DispatchTime.now().uptimeNanoseconds
            self?.queue.async { [weak self] in
                self?.lastMainBeat = beat
                self?.lastReportedStallBucket = 0
            }
        }
    }
}
