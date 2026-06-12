import AppKit
import Foundation

/// 基于 GitHub Releases 的版本更新：手动/自动检测 + 带进度下载对应芯片的 DMG。
@MainActor
final class UpdateManager: ObservableObject {
    static let shared = UpdateManager()
    static let repo = "zhengzizhe/conductor"
    static var releasesPageURL: URL { URL(string: "https://github.com/\(repo)/releases")! }

    struct Release: Equatable {
        let version: String      // tag 去掉可选的 v 前缀
        let notes: String
        let htmlURL: URL
        let assetName: String
        let assetURL: URL
        let assetSize: Int64
    }

    enum Phase: Equatable {
        case idle
        case checking
        case upToDate(Date)
        case available(Release)
        case downloading(Release)
        case downloaded(Release, localURL: URL)
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var downloadProgress: Double = 0
    @Published var autoCheckEnabled: Bool {
        didSet {
            UserDefaults.standard.set(autoCheckEnabled, forKey: "update.autoCheck")
            if autoCheckEnabled { scheduleAutoCheck() } else { autoCheckTimer?.invalidate() }
        }
    }

    let currentVersion: String

    /// tab 栏按钮的小圆点：有新版（含下载中/已下载）时亮。
    var updateAvailable: Bool {
        switch phase {
        case .available, .downloading, .downloaded: return true
        default: return false
        }
    }

    private var downloadTask: URLSessionDownloadTask?
    private var progressObservation: NSKeyValueObservation?
    private var autoCheckTimer: Timer?
    /// 自动检测间隔：6 小时。
    private static let autoCheckInterval: TimeInterval = 6 * 60 * 60

    private init() {
        currentVersion =
            Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
        autoCheckEnabled = UserDefaults.standard.object(forKey: "update.autoCheck") as? Bool ?? true
        if autoCheckEnabled {
            // 启动稍等几秒再查，别跟首屏抢网络/CPU。
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(3))
                await self?.check(manual: false)
            }
            scheduleAutoCheck()
        }
    }

    func check(manual: Bool) async {
        // 下载中/已下载不要被后台检查覆盖状态。
        switch phase {
        case .downloading, .downloaded: return
        case .checking: return
        default: break
        }
        phase = .checking
        do {
            var request = URLRequest(
                url: URL(string: "https://api.github.com/repos/\(Self.repo)/releases/latest")!)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            let payload = try JSONDecoder().decode(GitHubRelease.self, from: data)
            guard let release = Self.makeRelease(from: payload) else {
                throw URLError(.cannotParseResponse)
            }
            if Self.isNewer(release.version, than: currentVersion) {
                phase = .available(release)
            } else {
                phase = .upToDate(Date())
            }
        } catch {
            // 自动检查失败保持安静，手动检查才显示错误。
            if manual {
                phase = .failed(error.localizedDescription)
            } else if case .checking = phase {
                phase = .idle
            }
        }
    }

    func download(_ release: Release) {
        guard downloadTask == nil else { return }
        phase = .downloading(release)
        downloadProgress = 0
        let task = URLSession.shared.downloadTask(with: release.assetURL) { [weak self] temp, _, error in
            Task { @MainActor in
                guard let self else { return }
                self.downloadTask = nil
                self.progressObservation = nil
                if let error {
                    // 用户主动取消不算失败。
                    if (error as? URLError)?.code == .cancelled {
                        self.phase = .available(release)
                    } else {
                        self.phase = .failed(error.localizedDescription)
                    }
                    return
                }
                guard let temp else {
                    self.phase = .failed("download failed")
                    return
                }
                do {
                    let dest = Self.downloadDestination(for: release.assetName)
                    try? FileManager.default.removeItem(at: dest)
                    try FileManager.default.moveItem(at: temp, to: dest)
                    self.phase = .downloaded(release, localURL: dest)
                } catch {
                    self.phase = .failed(error.localizedDescription)
                }
            }
        }
        progressObservation = task.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
            Task { @MainActor in self?.downloadProgress = progress.fractionCompleted }
        }
        downloadTask = task
        task.resume()
    }

    func cancelDownload() {
        downloadTask?.cancel()
    }

    func openDownloaded() {
        guard case .downloaded(_, let localURL) = phase else { return }
        NSWorkspace.shared.open(localURL)
    }

    func revealDownloaded() {
        guard case .downloaded(_, let localURL) = phase else { return }
        NSWorkspace.shared.activateFileViewerSelecting([localURL])
    }

    private func scheduleAutoCheck() {
        autoCheckTimer?.invalidate()
        let timer = Timer(timeInterval: Self.autoCheckInterval, repeats: true) { _ in
            Task { @MainActor in await UpdateManager.shared.check(manual: false) }
        }
        RunLoop.main.add(timer, forMode: .common)
        autoCheckTimer = timer
    }

    private static func downloadDestination(for assetName: String) -> URL {
        let downloads =
            FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return downloads.appendingPathComponent(assetName)
    }

    // MARK: - GitHub payload

    private struct GitHubRelease: Decodable {
        struct Asset: Decodable {
            let name: String
            let browser_download_url: String
            let size: Int64
        }
        let tag_name: String
        let body: String?
        let html_url: String
        let assets: [Asset]
    }

    private static func makeRelease(from payload: GitHubRelease) -> Release? {
        guard let htmlURL = URL(string: payload.html_url) else { return nil }
        #if arch(arm64)
            let archSuffix = "arm64.dmg"
        #else
            let archSuffix = "x86_64.dmg"
        #endif
        // 优先匹配本机芯片的 DMG，没有就退而求其次拿任意 DMG。
        let asset =
            payload.assets.first { $0.name.hasSuffix(archSuffix) }
            ?? payload.assets.first { $0.name.hasSuffix(".dmg") }
        guard let asset, let assetURL = URL(string: asset.browser_download_url) else { return nil }
        var version = payload.tag_name
        if version.hasPrefix("v") { version.removeFirst() }
        return Release(
            version: version,
            notes: payload.body?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            htmlURL: htmlURL,
            assetName: asset.name,
            assetURL: assetURL,
            assetSize: asset.size)
    }

    /// 语义化版本比较：按 . 分段数字比较，段数不齐补 0。
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = candidate.split(separator: ".").map { Int($0.prefix(while: \.isNumber)) ?? 0 }
        let b = current.split(separator: ".").map { Int($0.prefix(while: \.isNumber)) ?? 0 }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
