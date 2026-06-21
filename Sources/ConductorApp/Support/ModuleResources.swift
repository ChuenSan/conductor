import Foundation

private final class AppModuleResourceToken: NSObject {}

/// ConductorApp 资源 bundle（logo、本地化文案）。**不要用 SwiftPM 生成的
/// `Bundle.module`**：生成的访问器只认「可执行文件同目录」与构建机的 `.build`
/// 绝对路径，打包进 .app 后资源在 `Contents/Resources/`，在别人机器上两个路径
/// 都不存在 → `fatalError` 启动即崩（含 App Translocation 场景）。
/// 这里按真实布局解析，找不到也只回退主 bundle，绝不崩。
let appModuleResources: Bundle = {
    let name = "Conductor_ConductorApp.bundle"
    let tokenBundle = Bundle(for: AppModuleResourceToken.self)
    let candidates = [
        Bundle.main.resourceURL,   // Conductor.app/Contents/Resources/
        Bundle.main.bundleURL,     // 裸可执行（swift run / swift build 产物目录）
        Bundle.main.bundleURL.deletingLastPathComponent(),   // XCTest: *.xctest 的兄弟目录
        tokenBundle.resourceURL,
        tokenBundle.bundleURL,
        tokenBundle.bundleURL.deletingLastPathComponent(),
    ]
    for base in candidates {
        if let url = base?.appendingPathComponent(name), let bundle = Bundle(url: url) {
            return bundle
        }
    }
    return .main
}()
