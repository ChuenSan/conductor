import Foundation
import os
import os.signpost

enum ConductorLog {
    private static let subsystem = "app.conductor"
    static let terminal = Logger(subsystem: subsystem, category: "terminal")
    static let app = Logger(subsystem: subsystem, category: "app")
    static let performance = Logger(subsystem: subsystem, category: "performance")
    static let diagnostics = Logger(subsystem: subsystem, category: "diagnostics")
}

enum ConductorSignpost {
    private static let log = OSLog(subsystem: "app.conductor", category: .pointsOfInterest)

    @discardableResult
    static func begin(_ name: StaticString) -> OSSignpostID {
        let id = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: name, signpostID: id)
        return id
    }

    static func end(_ name: StaticString, _ id: OSSignpostID) {
        os_signpost(.end, log: log, name: name, signpostID: id)
    }
}
