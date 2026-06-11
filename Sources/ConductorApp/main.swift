import AppKit
import ConductorCore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var coordinator: AppCoordinator!
    private var keyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        LegacyMigration.migrateIfNeeded()   // cmux → Conductor 改名后迁移旧用户数据
        // 原生控件外观跟随 app 主题（coordinator.attach 起持续同步；这里设初值避免启动闪深色）。
        NSApp.appearance = NSAppearance(named: AppStyle.theme.isDark ? .darkAqua : .aqua)
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        coordinator = AppCoordinator(rootCwd: home)

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1180, height: 760),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Conductor"
        WindowChromePolicy.applyMainWindowChrome(to: window)
        window.contentView = NSHostingView(rootView: RootView(coordinator: coordinator))
        coordinator.attach(to: window)
        window.center()
        window.setFrameAutosaveName("ConductorMainWindow")   // 记住上次窗口大小/位置
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        installKeyMonitor()
    }

    private func installKeyMonitor() {
        // 键位统一走命令注册表查表分发；键位由 config.yaml 可覆盖。
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak coordinator] event in
            guard let coordinator,
                  let chord = KeyChord(event: event),
                  coordinator.commandRegistry.dispatch(chord) else { return event }
            return nil   // 命中命令 → 吞掉事件
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator.captureAllScrollbackForRestart()   // 内容快照（下次启动回放）
        coordinator.save()
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
