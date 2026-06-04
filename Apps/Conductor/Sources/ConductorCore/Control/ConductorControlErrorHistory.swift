import Foundation

public struct ConductorControlErrorRecord: Equatable, Sendable {
    public var timestamp: Date
    public var requestID: String
    public var method: String
    public var code: String
    public var message: String
    public var details: [String: ConductorControlJSON]

    public init(
        timestamp: Date,
        requestID: String,
        method: String,
        code: String,
        message: String,
        details: [String: ConductorControlJSON] = [:]
    ) {
        self.timestamp = timestamp
        self.requestID = requestID
        self.method = method
        self.code = code
        self.message = message
        self.details = details
    }
}

public struct ConductorControlErrorHistory: Equatable, Sendable {
    public private(set) var records: [ConductorControlErrorRecord] = []
    public var capacity: Int

    public init(capacity: Int = 20) {
        self.capacity = max(1, capacity)
    }

    public mutating func append(_ record: ConductorControlErrorRecord) {
        records.append(record)
        if records.count > capacity {
            records.removeFirst(records.count - capacity)
        }
    }

    public var latestFirst: [ConductorControlErrorRecord] {
        Array(records.reversed())
    }
}
