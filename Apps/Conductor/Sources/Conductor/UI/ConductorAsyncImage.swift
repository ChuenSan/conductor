import AppKit
import SwiftUI

private func L(_ zh: String, _ en: String) -> String {
    ConductorLocalization.text(zh: zh, en: en)
}

private final class ConductorSharedImageCache: @unchecked Sendable {
    static let shared = ConductorSharedImageCache()

    private let cache = NSCache<NSString, NSImage>()

    func image(for key: String) -> NSImage? {
        cache.object(forKey: key as NSString)
    }

    func setImage(_ image: NSImage, for key: String) {
        cache.setObject(image, forKey: key as NSString)
    }
}

@MainActor
final class ConductorAsyncImageLoader: ObservableObject {
    @Published private(set) var image: NSImage?
    @Published private(set) var isLoading = false
    @Published private(set) var failureMessage: String?

    private var generation = 0
    private var currentURL: URL?
    private static let queue = DispatchQueue(label: "conductor.image-loader", qos: .userInitiated, attributes: .concurrent)

    func load(url: URL) {
        let standardized = url.standardizedFileURL
        if currentURL == standardized, image != nil || isLoading {
            return
        }

        currentURL = standardized
        image = nil
        failureMessage = nil
        isLoading = true
        generation &+= 1
        let generation = generation

        Self.queue.async {
            let key = Self.cacheKey(for: standardized)
            if let cached = ConductorSharedImageCache.shared.image(for: key) {
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.generation == generation else { return }
                    self.image = cached
                    self.isLoading = false
                }
                return
            }

            guard let loaded = NSImage(contentsOf: standardized) else {
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.generation == generation else { return }
                    self.isLoading = false
                    self.failureMessage = L("图片无法读取", "Image could not be loaded")
                }
                return
            }

            _ = loaded.representations
            ConductorSharedImageCache.shared.setImage(loaded, for: key)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == generation else { return }
                self.image = loaded
                self.isLoading = false
            }
        }
    }

    nonisolated private static func cacheKey(for url: URL) -> String {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let modified = values?.contentModificationDate?.timeIntervalSinceReferenceDate ?? 0
        let size = values?.fileSize ?? 0
        return "\(url.path)|\(modified)|\(size)"
    }
}

struct ConductorAsyncImage<Content: View, Placeholder: View>: View {
    let url: URL
    let content: (NSImage) -> Content
    let placeholder: (_ isLoading: Bool, _ failureMessage: String?) -> Placeholder

    @StateObject private var loader = ConductorAsyncImageLoader()

    init(
        url: URL,
        @ViewBuilder content: @escaping (NSImage) -> Content,
        @ViewBuilder placeholder: @escaping (_ isLoading: Bool, _ failureMessage: String?) -> Placeholder
    ) {
        self.url = url
        self.content = content
        self.placeholder = placeholder
    }

    var body: some View {
        Group {
            if let image = loader.image {
                content(image)
            } else {
                placeholder(loader.isLoading, loader.failureMessage)
            }
        }
        .task(id: url.standardizedFileURL) {
            loader.load(url: url)
        }
    }
}
