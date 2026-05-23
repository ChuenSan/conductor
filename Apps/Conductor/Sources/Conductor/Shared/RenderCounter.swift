import Foundation

enum RenderCounter {
    private static let queue = DispatchQueue(label: "app.conductor.render-counter")
    nonisolated(unsafe) private static var counts: [String: Int] = [:]

    static func increment(_ name: String) {
        queue.sync {
            counts[name, default: 0] += 1
        }
    }

    static func recordSnapshot(_ name: String) {
        ConductorDiagnostics.record(
            "render-counter",
            fields: [
                "name": name,
                "count": value(name)
            ]
        )
    }

    static func recordAll() {
        let snapshot = queue.sync {
            counts
        }
        for name in snapshot.keys.sorted() {
            ConductorDiagnostics.record(
                "render-counter",
                fields: [
                    "name": name,
                    "count": snapshot[name, default: 0]
                ]
            )
        }
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
