import ConductorCore
import Combine
import Foundation

/// 当前生效的配置，供全局读取与观察。SwiftUI/coordinator 观察它变化。
/// 单一真相源：`GhosttyRuntime` 启动、`AppStyle` 主题派生都从这里取。
@MainActor
final class ConfigStore: ObservableObject {
    static let shared = ConfigStore()

    @Published private(set) var config: AppConfig

    private let loader = ConfigLoader()

    private init() {
        config = loader.load()
        if !persistResolvedCodexActiveAccountCorrectionIfNeeded() {
            UsageCredentials.apply(config)   // 启动即把应用内 provider 配置注入进程环境
        }
    }

    /// 重新从磁盘加载（手动触发；后续接文件监听做热更新）。
    func reload() {
        config = loader.load()
        if !persistResolvedCodexActiveAccountCorrectionIfNeeded() {
            UsageCredentials.apply(config)
        }
    }

    /// 用户显式重载配置：解析失败要抛给 UI，避免静默回退默认配置。
    func reloadFromDisk() throws {
        config = try loader.loadStrict()
        if !persistResolvedCodexActiveAccountCorrectionIfNeeded() {
            UsageCredentials.apply(config)
        }
    }

    /// 设置面板改配置：内存即时更新（@Published 驱动 UI）。
    func set(_ newConfig: AppConfig) {
        config = newConfig
        _ = persistResolvedCodexActiveAccountCorrectionIfNeeded(saveToDisk: false)
        UsageCredentials.apply(config)
    }

    /// 把当前配置落盘到 config.yaml。
    func persist() {
        loader.save(config)
    }

    @discardableResult
    func persistResolvedCodexActiveAccountCorrectionIfNeeded(saveToDisk: Bool = true) -> Bool {
        guard var codexConfig = config.usage.providers["codex"],
              let corrected = CodexActiveAccountResolver.correctedTokenAccountData(
                  configured: codexConfig.tokenAccounts,
                  discoveredAccounts: CodexManagedAccountDiscovery.tokenAccounts(
                      env: UsageCredentials.providerDiscoveryEnvironment())),
              // 幂等护栏：修正值与现存一致就别写——否则每次 reload 都"修正"+写盘，
              // 触发 ConfigWatcher → reloadConfig → reload → 又写，形成 ~0.4s 的热更新死循环
              // （CPU 飙高 + codex 详情被反复重渲，是 codex 渠道点开即崩的根因）。
              codexConfig.tokenAccounts != corrected
        else {
            return false
        }

        codexConfig.tokenAccounts = corrected
        var next = config
        next.usage.providers["codex"] = codexConfig
        config = next
        UsageCredentials.apply(config)
        if saveToDisk {
            loader.save(config)
        }
        return true
    }
}
