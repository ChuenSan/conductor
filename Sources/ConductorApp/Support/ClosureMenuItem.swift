import AppKit

/// 绑闭包的 NSMenuItem——AppKit 菜单项原生只支持 target/action，这里包一层闭包，方便构造右键菜单。
/// 可选 `systemImage`（SF Symbol）让菜单项带图标，更接近系统原生右键菜单的质感。
final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, systemImage: String? = nil, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
        if let systemImage {
            image = NSImage(systemSymbolName: systemImage, accessibilityDescription: nil)
        }
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError() }

    @objc private func fire() { handler() }
}
