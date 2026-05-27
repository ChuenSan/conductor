import ConductorCore
import Foundation

enum ConductorUpdatePhase: Equatable, Sendable {
    case idle
    case checking
    case upToDate
    case available
    case downloading
    case downloaded
    case installing
    case failed(String)

    var isBusy: Bool {
        switch self {
        case .checking, .downloading, .installing:
            true
        case .idle, .upToDate, .available, .downloaded, .failed:
            false
        }
    }

    var statusTitle: String {
        switch self {
        case .idle:
            ConductorLocalization.text(zh: "尚未检查", en: "Not Checked")
        case .checking:
            ConductorLocalization.text(zh: "正在检查", en: "Checking")
        case .upToDate:
            ConductorLocalization.text(zh: "已是最新", en: "Up to Date")
        case .available:
            ConductorLocalization.text(zh: "发现更新", en: "Update Available")
        case .downloading:
            ConductorLocalization.text(zh: "正在下载", en: "Downloading")
        case .downloaded:
            ConductorLocalization.text(zh: "准备安装", en: "Ready to Install")
        case .installing:
            ConductorLocalization.text(zh: "正在替换", en: "Installing")
        case .failed:
            ConductorLocalization.text(zh: "需要处理", en: "Needs Attention")
        }
    }

    var systemImage: String {
        switch self {
        case .idle:
            "arrow.triangle.2.circlepath"
        case .checking:
            "dot.radiowaves.left.and.right"
        case .upToDate:
            "checkmark.seal"
        case .available:
            "arrow.down.circle"
        case .downloading:
            "icloud.and.arrow.down"
        case .downloaded:
            "shippingbox"
        case .installing:
            "arrow.clockwise.circle"
        case .failed:
            "exclamationmark.triangle"
        }
    }
}

struct ConductorUpdateState: Equatable, Sendable {
    var phase: ConductorUpdatePhase = .idle
    var currentVersion: ConductorAppVersion = .current()
    var availableVersion: ConductorAppVersion?
    var manifest: ConductorUpdateManifest?
    var selectedPackageKind: ConductorUpdatePackageKind?
    var selectedArtifact: ConductorUpdateArtifact?
    var downloadedPackageURL: URL?
    var lastCheckedAt: Date?

    var canCheck: Bool {
        !phase.isBusy
    }

    var canDownload: Bool {
        phase == .available && manifest != nil && selectedArtifact != nil
    }

    var canInstall: Bool {
        phase == .downloaded && downloadedPackageURL != nil && selectedPackageKind != nil
    }
}

struct ConductorDownloadedUpdate: Equatable, Sendable {
    var packageURL: URL
    var artifactURL: URL
    var kind: ConductorUpdatePackageKind
    var manifest: ConductorUpdateManifest
    var artifact: ConductorUpdateArtifact
}

struct ConductorPreparedUpdate: Equatable, Sendable {
    var scriptURL: URL
}
