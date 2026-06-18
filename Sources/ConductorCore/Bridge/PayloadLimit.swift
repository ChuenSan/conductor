public enum PayloadLimit {
    public static let maxBytes = 4 * 1024 * 1024
    private static let asciiZero = UInt8(ascii: "0")
    private static let asciiNine = UInt8(ascii: "9")

    public static func validateContentLength(_ raw: String?) -> Result<Int, PayloadLimitError> {
        guard let raw else { return .success(0) }
        guard !raw.isEmpty else { return .failure(.invalidContentLength(raw)) }

        var value = 0
        var overflowed = false
        for byte in raw.utf8 {
            guard byte >= asciiZero, byte <= asciiNine else {
                return .failure(.invalidContentLength(raw))
            }
            guard !overflowed else { continue }

            let multiplied = value.multipliedReportingOverflow(by: 10)
            if multiplied.overflow {
                overflowed = true
                continue
            }
            let added = multiplied.partialValue.addingReportingOverflow(Int(byte - asciiZero))
            if added.overflow {
                overflowed = true
                continue
            }
            value = added.partialValue
        }

        guard !overflowed else {
            return .failure(.tooLarge(Int.max, maxBytes))
        }
        guard value <= maxBytes else {
            return .failure(.tooLarge(value, maxBytes))
        }
        return .success(value)
    }

    public static func validateFrameLength(_ length: UInt64) -> Result<Void, PayloadLimitError> {
        guard length <= UInt64(maxBytes) else {
            return .failure(.tooLarge(Int(clamping: length), maxBytes))
        }
        return .success(())
    }
}

public enum PayloadLimitError: Error, Equatable {
    case invalidContentLength(String)
    case tooLarge(Int, Int)
}
