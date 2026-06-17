import AppKit
import ConductorCore
import Foundation

/// 一只可选的宠物：要么是程序化内置模版，要么是发现到的 Codex Pets 图集宠物。
/// 设置里的「模版列表」和桌宠渲染都基于它——内置 + 发现 统一成一份目录。
struct CompanionPet: Identifiable, Equatable {
    enum Kind: Equatable {
        case procedural(PetTemplate)
        case atlas(URL)           // 图集文件 URL（webp/png）
    }
    let id: String
    let name: String
    let kind: Kind
}

/// Codex Pets 宠物包的发现 + 图集加载。
///
/// 抄 openpets 的**格式与发现目录**（不打包它的美术，授权不清）：扫描 `~/.codex/pets/` 等标准目录，
/// 每个含 `pet.json` 的子目录解析成一只可渲染宠物。用户装了 openpets / 往目录丢一个 Codex 宠物包，
/// Conductor 自动认出并渲染——这正是 openpets「一只共享宠物」的本意，且零授权风险。
enum CodexPetCatalog {
    /// 标准发现目录（Codex / openpets 生态 + Conductor 自己的口 `~/.config/conductor/pets/`）。
    static func searchDirs() -> [URL] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        var dirs = [
            home.appendingPathComponent(".codex/pets", isDirectory: true),
            home.appendingPathComponent(".local/share/openpets/pets", isDirectory: true),
            home.appendingPathComponent(".config/openpets/pets", isDirectory: true),
            home.appendingPathComponent(".config/conductor/pets", isDirectory: true),
        ]
        if let appSup = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            dirs.append(appSup.appendingPathComponent("OpenPets/Pets", isDirectory: true))
        }
        return dirs
    }

    /// Conductor 自己的宠物投放目录（`~/.config/conductor/pets/`）——用户把 Codex 宠物包丢这里即可被认出。
    static var dropFolder: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/conductor/pets", isDirectory: true)
    }

    /// 确保投放目录存在（给用户一个明确的放置点）。
    static func ensureDropFolder() {
        try? FileManager.default.createDirectory(at: dropFolder, withIntermediateDirectories: true)
    }

    /// 扫描标准目录，返回有效宠物（按 id 去重，先见者胜）。
    static func discover() -> [CompanionPet] { discover(in: searchDirs()) }

    /// 扫描指定目录（可注入，便于测试）。
    static func discover(in dirs: [URL]) -> [CompanionPet] {
        let fm = FileManager.default
        var out: [CompanionPet] = []
        var seen = Set<String>()
        for dir in dirs {
            guard let subs = try? fm.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { continue }
            for sub in subs {
                // 直接尝试读 pet.json：是文件/无清单的目录会读失败 → 跳过（不依赖 isDirectory 属性）。
                guard let data = try? Data(contentsOf: sub.appendingPathComponent("pet.json")),
                      let manifest = try? JSONDecoder().decode(PetManifest.self, from: data),
                      manifest.isValid else { continue }
                let sheet = sub.appendingPathComponent(manifest.resolvedSpritesheet)
                guard fm.fileExists(atPath: sheet.path), seen.insert(manifest.id).inserted else { continue }
                // 名字走 L()：我们生成的宠物（喵喵→Kitty 等）可本地化，社区宠物名自然回退原文。
                out.append(CompanionPet(id: manifest.id, name: L(manifest.resolvedName), kind: .atlas(sheet)))
            }
        }
        return out
    }

    // MARK: 图集加载（CGImage 缓存）

    private static var cache: [URL: CGImage] = [:]

    /// 加载图集为 CGImage（webp/png 走 NSImage/ImageIO）；按 URL 缓存。
    static func sheet(at url: URL) -> CGImage? {
        if let hit = cache[url] { return hit }
        guard let img = NSImage(contentsOf: url) else { return nil }
        var rect = CGRect(origin: .zero, size: img.size)
        guard let cg = img.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return nil }
        cache[url] = cg
        return cg
    }

    /// 把图集切成 9 行帧，**剔除全透明的空格**（真 Codex 图集每行帧数不齐，循环到空格会整只闪没）。
    /// 一次切好缓存；渲染层只按行取帧、按时间索引，不再每帧裁剪。
    private static var sliceCache: [ObjectIdentifier: [[CGImage]]] = [:]
    static func animationFrames(of sheet: CGImage, cols: Int = 8, rows: Int = 9) -> [[CGImage]] {
        let key = ObjectIdentifier(sheet)
        if let hit = sliceCache[key] { return hit }
        let cw = max(1, sheet.width / cols), ch = max(1, sheet.height / rows)
        var grid: [[CGImage]] = []
        for r in 0..<rows {
            var frames: [CGImage] = []
            for c in 0..<cols {
                guard let cell = sheet.cropping(to: CGRect(x: c * cw, y: r * ch, width: cw, height: ch)),
                      !isBlank(cell) else { continue }
                frames.append(cell)
            }
            grid.append(frames)
        }
        sliceCache[key] = grid
        return grid
    }

    /// 缩到 8×8 看 alpha 是否全空（判定空帧）。
    private static func isBlank(_ img: CGImage) -> Bool {
        let w = 8, h = 8
        var px = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        for i in stride(from: 3, to: px.count, by: 4) where px[i] > 12 { return false }
        return true
    }
}

/// 全部可选宠物 = 程序化内置 + 发现到的 Codex 宠物。
enum CompanionPetCatalog {
    static func all() -> [CompanionPet] {
        let builtins = PetTemplateCatalog.builtins.map {
            CompanionPet(id: $0.id, name: L($0.nameKey), kind: .procedural($0))
        }
        return builtins + CodexPetCatalog.discover()
    }

    /// 按 id 解析；找不到回落第一个内置模版。
    static func pet(id: String) -> CompanionPet {
        all().first { $0.id == id }
            ?? CompanionPet(id: PetTemplateCatalog.default.id,
                            name: L(PetTemplateCatalog.default.nameKey),
                            kind: .procedural(PetTemplateCatalog.default))
    }
}
