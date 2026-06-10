import Foundation

/// CLI 检测结果的磁盘缓存（含检测时间戳）。面板打开时直接读缓存，避免每次都跑昂贵的 shell 探测；
/// 只有用户点「重新检测」或缓存缺失时才真正检测。
struct CLIDetectionCache: Codable {
    var detectedAt: Date
    var tools: [CLIToolStatus]
}

enum CLIDetectionStore {
    private static var fileURL: URL {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("cmux", isDirectory: true)
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        return appSupport.appendingPathComponent("cli-detection.json")
    }

    static func load() -> CLIDetectionCache? {
        guard let data = try? Data(contentsOf: fileURL),
              let cache = try? JSONDecoder.cmux.decode(CLIDetectionCache.self, from: data)
        else { return nil }
        // 工具目录变化（新增/移除 CLI）时让旧缓存失效，强制重新检测。
        let cachedIDs = Set(cache.tools.map(\.id))
        let catalogIDs = Set(AgentCatalog.all.map(\.id))
        guard cachedIDs == catalogIDs else { return nil }
        return cache
    }

    @discardableResult
    static func save(_ tools: [CLIToolStatus], detectedAt: Date = Date()) -> CLIDetectionCache {
        let cache = CLIDetectionCache(detectedAt: detectedAt, tools: tools)
        if let data = try? JSONEncoder.cmux.encode(cache) {
            try? data.write(to: fileURL, options: .atomic)
        }
        return cache
    }
}

private extension JSONDecoder {
    static let cmux: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

private extension JSONEncoder {
    static let cmux: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
}
