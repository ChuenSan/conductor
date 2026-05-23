import Foundation

enum RenderCounter {
    private static let queue = DispatchQueue(label: "app.conductor.render-counter")
    nonisolated(unsafe) private static var counts: [String: Int] = [:]

    static func increment(_ name: String) {
        let count = queue.sync {
            counts[name, default: 0] += 1
            return counts[name, default: 0]
        }
        ConductorDiagnostics.record(
            "render-counter",
            fields: [
                "name": name,
                "count": count
            ]
        )
    }

    static func value(_ name: String) -> Int {
        queue.sync {
            counts[name, default: 0]
        }
    }

    static func reset() {
        queue.sync {
            counts.removeAll(keepingCapacity: true)
        }
    }
}
