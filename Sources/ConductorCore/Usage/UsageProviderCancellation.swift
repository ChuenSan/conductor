import Foundation

public enum UsageProviderCancellation {
    public static func isCancelled(_ error: Error) -> Bool {
        if error is CancellationError { return true }

        if let urlError = error as? URLError {
            return urlError.code == .cancelled
        }

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain
            && nsError.code == NSURLErrorCancelled
        {
            return true
        }

        let message = error.localizedDescription
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return message == "cancelled"
            || message.contains("cancellationerror")
            || message.contains("cancelled")
    }

    public static func rethrowIfCancelled(_ error: Error) throws {
        if Self.isCancelled(error) {
            throw CancellationError()
        }
    }
}
