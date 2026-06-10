import CmuxCore
import Foundation

/// 用量报告磁盘缓存：按 daysBack 各存一份，面板打开时先显示缓存（秒开），再后台重扫更新。
enum UsageReportStore {
    private static var dir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("cmux", isDirectory: true)
    }

    private static func cacheURL(daysBack: Int) -> URL {
        dir.appendingPathComponent("usage-\(daysBack)d.json")
    }

    static func load(daysBack: Int) -> UsageReport? {
        guard let data = try? Data(contentsOf: cacheURL(daysBack: daysBack)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(UsageReport.self, from: data)
    }

    static func save(_ report: UsageReport, daysBack: Int) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(report) else { return }
        try? data.write(to: cacheURL(daysBack: daysBack))
    }
}
