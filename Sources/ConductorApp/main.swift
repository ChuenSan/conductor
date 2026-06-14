import AppKit
import ConductorCore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var window: NSWindow!
    var coordinator: AppCoordinator!
    private var keyMonitor: Any?
    /// 关窗时已确认过中断思考，applicationShouldTerminate 不再问第二遍。
    private var closeConfirmed = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        LegacyMigration.migrateIfNeeded()   // cmux → Conductor 改名后迁移旧用户数据
        AppLanguage.bootstrap()   // 把持久化的语言选择应用到运行时查表（App + ConductorCore）
        // 原生控件外观跟随 app 主题（coordinator.attach 起持续同步；这里设初值避免启动闪深色）。
        NSApp.appearance = NSAppearance(named: AppStyle.theme.isDark ? .darkAqua : .aqua)
        installMainMenu()
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
        window.delegate = self   // 误关保护：windowShouldClose 守门
        coordinator.attach(to: window)
        window.center()
        window.setFrameAutosaveName("ConductorMainWindow")   // 记住上次窗口大小/位置
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        installKeyMonitor()
    }

    private func installMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: L("退出 Conductor"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: L("编辑"))
        editMenu.addItem(NSMenuItem(title: L("撤销"), action: Selector(("undo:")), keyEquivalent: "z"))
        let redo = NSMenuItem(title: L("重做"), action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(redo)
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: L("剪切"), action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: L("复制"), action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: L("粘贴"), action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: L("全选"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        NSApp.mainMenu = mainMenu
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

    /// 误关保护：红绿灯关窗时有 agent 正在思考 → 先确认（窗口没了 app 也就退出了）。
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        closeConfirmed = coordinator.shouldTerminateApp()
        return closeConfirmed
    }

    /// 误关保护：⌘Q / 菜单退出时同款确认；关窗路径已确认过则直接放行。
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        (closeConfirmed || coordinator.shouldTerminateApp()) ? .terminateNow : .terminateCancel
    }

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
