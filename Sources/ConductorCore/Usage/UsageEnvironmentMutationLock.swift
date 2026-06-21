import Dispatch

public final class UsageEnvironmentMutationLock: @unchecked Sendable {
    public static let shared = UsageEnvironmentMutationLock()

    private let semaphore = DispatchSemaphore(value: 1)

    private init() {}

    public func withLock<T>(_ body: () throws -> T) rethrows -> T {
        semaphore.wait()
        defer { semaphore.signal() }
        return try body()
    }

    public func withAsyncLock<T>(_ body: () async throws -> T) async rethrows -> T {
        await wait()
        defer { semaphore.signal() }
        return try await body()
    }

    private func wait() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                self.semaphore.wait()
                continuation.resume()
            }
        }
    }
}
