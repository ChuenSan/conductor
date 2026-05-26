import AppKit
import Combine
import CodexBar
import ConductorCore
import QuartzCore
import SwiftUI

private func L(_ zh: String, _ en: String) -> String {
    ConductorLocalization.text(zh: zh, en: en)
}

private let conductorUncaughtExceptionHandler: @convention(c) (NSException) -> Void = { exception in
    ConductorDiagnostics.recordSync(
        "uncaught-nsexception",
        fields: [
            "name": exception.name.rawValue,
            "reasonLength": exception.reason?.count ?? 0
        ]
    )
}

@main
struct ConductorApp {
    @MainActor
    private static var retainedDelegate: ConductorAppDelegate?

    @MainActor
    static func main() {
        if ConductorHookCLI.runIfNeeded(arguments: CommandLine.arguments) {
            return
        }

        let app = NSApplication.shared
        let delegate = ConductorAppDelegate()
        retainedDelegate = delegate
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }
}

@MainActor
final class ConductorWindow: NSWindow {
    var routeAppShortcut: ((NSEvent) -> Bool)?

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown,
           event.clickCount == 2,
           isChromeBorderDoubleClick(event) {
            toggleFullScreen(nil)
            return
        }
        super.sendEvent(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if performTextEditingKeyEquivalent(with: event) {
            return true
        }

        if let terminalHost = Self.owningTerminalHost(for: firstResponder) {
            if routeAppShortcut?(event) == true {
                return true
            }
            if let mainMenu = NSApp.mainMenu, mainMenu.performKeyEquivalent(with: event) {
                return true
            }
            if terminalHost.performKeyEquivalent(with: event) {
                return true
            }
            return false
        }

        if routeAppShortcut?(event) == true {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    private func performTextEditingKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown,
              let responder = firstResponder,
              Self.owningTerminalHost(for: responder) == nil else {
            return false
        }
        let flags = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting([.numericPad, .function, .capsLock])
        guard flags == .command || flags == [.command, .shift],
              let character = event.charactersIgnoringModifiers?.lowercased() else {
            return false
        }

        switch (character, flags.contains(.shift)) {
        case ("a", false):
            return performTextCommand(#selector(NSResponder.selectAll(_:)), responder: responder)
        case ("c", false):
            return performTextCommand(#selector(NSText.copy(_:)), responder: responder)
        case ("x", false):
            return performTextCommand(#selector(NSText.cut(_:)), responder: responder)
        case ("v", false):
            return performTextCommand(#selector(NSText.paste(_:)), responder: responder)
        case ("z", false):
            return performUndoCommand(redo: false, responder: responder)
        case ("z", true):
            return performUndoCommand(redo: true, responder: responder)
        default:
            return false
        }
    }

    private func performTextCommand(_ action: Selector, responder: NSResponder) -> Bool {
        if responder.tryToPerform(action, with: self) {
            return true
        }

        if let textView = responder as? NSTextView,
           textView.responds(to: action) {
            textView.perform(action, with: self)
            return true
        }

        if let control = responder as? NSControl,
           let editor = control.currentEditor() as? NSTextView,
           editor.responds(to: action) {
            editor.perform(action, with: self)
            return true
        }

        return NSApp.sendAction(action, to: nil, from: self)
    }

    private func performUndoCommand(redo: Bool, responder: NSResponder) -> Bool {
        if let undoManager = (responder as? NSView)?.undoManager ?? undoManager {
            if redo, undoManager.canRedo {
                undoManager.redo()
                return true
            }
            if !redo, undoManager.canUndo {
                undoManager.undo()
                return true
            }
        }
        let action = NSSelectorFromString(redo ? "redo:" : "undo:")
        return responder.tryToPerform(action, with: self) || NSApp.sendAction(action, to: nil, from: self)
    }

    private func isChromeBorderDoubleClick(_ event: NSEvent) -> Bool {
        guard event.window === self else { return false }
        let location = event.locationInWindow
        let size = frame.size
        let borderHitWidth: CGFloat = 6
        return location.x <= borderHitWidth ||
            location.x >= size.width - borderHitWidth ||
            location.y <= borderHitWidth ||
            location.y >= size.height - borderHitWidth
    }

    private static func owningTerminalHost(for responder: NSResponder?) -> TerminalHostView? {
        if let host = responder as? TerminalHostView {
            return host
        }
        guard let view = responder as? NSView else { return nil }
        var current: NSView? = view
        while let candidate = current {
            if let host = candidate as? TerminalHostView {
                return host
            }
            current = candidate.superview
        }
        return nil
    }

    func hideSystemTrafficLights() {
        [
            NSWindow.ButtonType.closeButton,
            .miniaturizeButton,
            .zoomButton
        ].forEach { buttonType in
            standardWindowButton(buttonType)?.isHidden = true
        }
    }
}

final class ConductorHostingView<Content: View>: NSHostingView<Content> {
    override var safeAreaInsets: NSEdgeInsets {
        NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}

@MainActor
final class NotificationWindowDelegate: NSObject, NSWindowDelegate {
    private let onClose: () -> Void

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}

@MainActor
final class ConductorAppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation, NSWindowDelegate {
    private var window: ConductorWindow?
    private var notificationWindow: NSPanel?
    private var notificationWindowDelegate: NotificationWindowDelegate?
    private var codexBarRuntime: CodexBarEmbeddedRuntime?
    private var agentHookObserver: NSObjectProtocol?
    private var shellKeyMonitor: Any?
    private var cancellables = Set<AnyCancellable>()
    private let model = ConductorWindowModel()
    private let mainThreadWatchdog = ConductorMainThreadWatchdog()
    private var stressOriginalWorkspace: WorkspaceState?
    private var stressOriginalTheme: TerminalTheme?
    private var resizeStressOriginalWorkspace: WorkspaceState?
    private var resizeStressOriginalTheme: TerminalTheme?
    private var didStart = false
    private var isTerminating = false
    private let notificationWindowMotionDuration: TimeInterval = 0.18
    private let notificationWindowMotionDistance: CGFloat = 18

    func applicationDidFinishLaunching(_ notification: Notification) {
        startApplication()
    }

    func startApplication() {
        guard !didStart else { return }
        didStart = true
        NSSetUncaughtExceptionHandler(conductorUncaughtExceptionHandler)
        ConductorDiagnostics.record(
            "app-start",
            fields: [
                "diagnostics": ConductorDiagnostics.logURL.path,
                "pid": ProcessInfo.processInfo.processIdentifier
            ]
        )
        let window = ConductorWindow(
            contentRect: NSRect(x: 120, y: 120, width: 1320, height: 860),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Conductor"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isOpaque = false
        window.delegate = self
        window.backgroundColor = .clear
        window.collectionBehavior = [.fullScreenPrimary, .managed]
        applyAppearance(for: model.theme, to: window)
        window.hideSystemTrafficLights()
        window.routeAppShortcut = { [weak self] event in
            self?.routeAppShortcut(event) ?? false
        }
        model.onNotificationPanelVisibilityChange = { [weak self] visible in
            self?.setNotificationWindowVisible(visible)
        }
        installShellKeyMonitor()
        installAgentHookObserver()
        mainThreadWatchdog.start()
        GhosttyAppRuntime.shared.actionDelegate = model
        prepareStressWorkspaceIfRequested()
        prepareResizeStressWorkspaceIfRequested()
        let contentContainer = NSView()
        contentContainer.wantsLayer = true
        contentContainer.layer?.backgroundColor = NSColor.clear.cgColor
        let hostingView = ConductorHostingView(rootView: ConductorRootView(model: model))
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(hostingView)
        window.contentView = contentContainer
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor)
        ])
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
        startCodexBarIfEnabled()
        installAppearanceBinding()
        installMainMenu()
        runShortcutAutomationIfRequested()
        runSmokeAutomationIfRequested()
        runFocusAutomationIfRequested()
        runLayoutAutomationIfRequested()
        runLifecycleAutomationIfRequested()
        runWorkspaceAutomationIfRequested()
        runShellPanelAutomationIfRequested()
        runNotificationAutomationIfRequested()
        runStressAutomationIfRequested()
        runResizeStressAutomationIfRequested()
        ConductorLog.app.info("Conductor window launched")
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        ConductorDiagnostics.record("app-active")
        GhosttyAppRuntime.shared.setAppFocus(true)
    }

    func applicationDidResignActive(_ notification: Notification) {
        ConductorDiagnostics.record("app-inactive")
        GhosttyAppRuntime.shared.setAppFocus(false)
    }

    func applicationWillTerminate(_ notification: Notification) {
        isTerminating = true
        ConductorDiagnostics.recordSync("app-will-terminate")
        ConductorLog.app.info("Conductor will terminate")
        Self.appendStressTrace("applicationWillTerminate", to: ProcessInfo.processInfo.environment["CONDUCTOR_STRESS_TRACE_OUTPUT"])
        model.flushPersistence()
        codexBarRuntime?.stop()
        notificationWindow?.close()
        if let agentHookObserver {
            DistributedNotificationCenter.default().removeObserver(agentHookObserver)
        }
        if let shellKeyMonitor {
            NSEvent.removeMonitor(shellKeyMonitor)
        }
        mainThreadWatchdog.stop()
        model.closeAllSurfaces()
        GhosttyAppRuntime.shared.actionDelegate = nil
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        Self.appendStressTrace("applicationShouldTerminateAfterLastWindowClosed", to: ProcessInfo.processInfo.environment["CONDUCTOR_STRESS_TRACE_OUTPUT"])
        ConductorDiagnostics.record("last-window-closed")
        ConductorLog.app.warning("Last window closed; keeping Conductor process alive")
        return false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            ConductorDiagnostics.record("app-reopen-no-visible-windows")
            ConductorLog.app.info("Reopening Conductor main window after no visible windows")
            didStart = false
            startApplication()
            return true
        }
        return false
    }

    func windowWillClose(_ notification: Notification) {
        guard notification.object as? NSWindow === window else { return }
        ConductorDiagnostics.record("main-window-will-close", fields: ["terminating": isTerminating])
        ConductorLog.app.warning("Main window will close")
        if !isTerminating {
            model.closeAllSurfaces()
        }
        window = nil
        didStart = false
    }

    private func installMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu(title: "Conductor")
        appMenu.addItem(menuItem(L("设置...", "Settings..."), command: .toggleSettings, #selector(settingsPanelCommand)))
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(NSMenuItem(title: L("退出 Conductor", "Quit Conductor"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let fileMenuItem = NSMenuItem()
        fileMenuItem.title = L("文件", "File")
        let fileMenu = NSMenu(title: L("文件", "File"))
        fileMenu.addItem(menuItem(L("新建工作区", "New Workspace"), command: .newWorkspace, #selector(newWorkspaceCommand)))
        fileMenu.addItem(menuItem(L("新开终端", "New Terminal"), command: .newTerminal, #selector(newTerminalCommand)))
        fileMenu.addItem(menuItem(L("新建网页标签", "New Web Tab"), command: .newWebTab, #selector(newWebTabCommand)))
        fileMenu.addItem(NSMenuItem.separator())
        fileMenu.addItem(menuItem(L("关闭标签", "Close Tab"), command: .closeSelectedTab, #selector(closeTabCommand)))
        fileMenu.addItem(menuItem(L("关闭分屏", "Close Pane"), command: .closeFocusedPane, #selector(closePaneCommand)))
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        let layoutMenuItem = NSMenuItem()
        layoutMenuItem.title = L("布局", "Layout")
        let layoutMenu = NSMenu(title: L("布局", "Layout"))
        layoutMenu.addItem(menuItem(L("向右分屏", "Split Right"), command: .splitRight, #selector(splitRightCommand)))
        layoutMenu.addItem(menuItem(L("向下分屏", "Split Down"), command: .splitDown, #selector(splitDownCommand)))
        layoutMenu.addItem(NSMenuItem.separator())
        layoutMenu.addItem(menuItem(L("下一个标签", "Next Tab"), command: .selectNextTab, #selector(selectNextTabCommand)))
        layoutMenu.addItem(menuItem(L("上一个标签", "Previous Tab"), command: .selectPreviousTab, #selector(selectPreviousTabCommand)))
        layoutMenu.addItem(menuItem(L("下一个分屏", "Next Pane"), command: .focusNextPane, #selector(focusNextPaneCommand)))
        layoutMenu.addItem(menuItem(L("上一个分屏", "Previous Pane"), command: .focusPreviousPane, #selector(focusPreviousPaneCommand)))
        layoutMenu.addItem(NSMenuItem.separator())
        layoutMenu.addItem(menuItem(L("均分分屏", "Equalize Splits"), command: .equalizeSplits, #selector(equalizeSplitsCommand)))
        layoutMenu.addItem(menuItem(L("切换分屏放大", "Toggle Pane Zoom"), command: .toggleZoom, #selector(toggleZoomCommand)))
        layoutMenu.addItem(NSMenuItem.separator())
        layoutMenu.addItem(menuItem(L("标签左移", "Move Tab Left"), command: .moveTabLeft, #selector(moveTabLeftCommand)))
        layoutMenu.addItem(menuItem(L("标签右移", "Move Tab Right"), command: .moveTabRight, #selector(moveTabRightCommand)))
        layoutMenu.addItem(menuItem(L("移动标签到下一个分屏", "Move Tab to Next Pane"), command: .moveTabToNextPane, #selector(moveTabToNextPaneCommand)))
        layoutMenu.addItem(menuItem(L("移动标签到右侧新分屏", "Move Tab to New Right Split"), command: .moveTabToNewRightSplit, #selector(moveTabToNewRightSplitCommand)))
        layoutMenuItem.submenu = layoutMenu
        mainMenu.addItem(layoutMenuItem)

        let viewMenuItem = NSMenuItem()
        viewMenuItem.title = L("视图", "View")
        let viewMenu = NSMenu(title: L("视图", "View"))
        viewMenu.addItem(menuItem(L("工作区总览", "Workspace Overview"), command: .toggleWorkspaceOverview, #selector(workspaceOverviewCommand)))
        viewMenu.addItem(menuItem(L("命令面板", "Command Palette"), command: .toggleCommandPalette, #selector(commandPaletteCommand)))
        viewMenu.addItem(menuItem(L("通知", "Notifications"), command: .toggleNotifications, #selector(notificationCenterCommand)))
        viewMenu.addItem(menuItem(L("跳转到最新未读", "Jump to Latest Unread"), command: .jumpToLatestUnread, #selector(jumpToLatestUnreadCommand)))
        viewMenu.addItem(NSMenuItem.separator())
        viewMenu.addItem(menuItem(L("聚焦网页地址", "Focus Web Address"), command: .focusWebAddress, #selector(focusWebAddressCommand)))
        viewMenu.addItem(menuItem(L("重新载入网页", "Reload Web Page"), command: .reloadSelectedWebTab, #selector(reloadSelectedWebTabCommand)))
        viewMenu.addItem(menuItem(L("在浏览器中打开网页", "Open Web Page in Browser"), command: .openSelectedWebTabExternally, #selector(openSelectedWebTabExternallyCommand)))
        viewMenu.addItem(menuItem(L("复制网页 URL", "Copy Web URL"), command: .copySelectedWebTabURL, #selector(copySelectedWebTabURLCommand)))
        viewMenu.addItem(menuItem(L("复制网页引用", "Copy Web Reference"), command: .copySelectedWebTabReference, #selector(copySelectedWebTabReferenceCommand)))
        viewMenu.addItem(NSMenuItem.separator())
        viewMenu.addItem(menuItem(L("打开当前目录", "Open Current Directory"), command: .openFocusedDirectory, #selector(openCurrentDirectoryCommand)))
        viewMenu.addItem(menuItem(L("复制当前目录路径", "Copy Current Directory Path"), command: .copyFocusedDirectory, #selector(copyCurrentDirectoryCommand)))
        viewMenu.addItem(NSMenuItem.separator())
        viewMenu.addItem(menuItem(L("上下文搜索", "Context Search"), command: .showTerminalSearch, #selector(contextSearchCommand)))
        viewMenu.addItem(menuItem(L("查找下一个", "Find Next"), command: .findNext, #selector(findNextCommand)))
        viewMenu.addItem(menuItem(L("查找上一个", "Find Previous"), command: .findPrevious, #selector(findPreviousCommand)))
        viewMenu.addItem(NSMenuItem.separator())
        viewMenu.addItem(menuItem(L("切换全屏", "Toggle Full Screen"), command: .toggleFullScreen, #selector(toggleFullScreenCommand)))
        viewMenu.addItem(menuItem(L("重置工作区", "Reset Workspace"), command: .resetWorkspace, #selector(resetWorkspaceCommand)))
        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)

        NSApp.mainMenu = mainMenu
    }

    private func menuItem(
        _ title: String,
        command: ConductorShellCommand,
        _ action: Selector
    ) -> NSMenuItem {
        let shortcut = model.appearance.keyboardShortcuts.shortcut(for: command)
        let item = NSMenuItem(title: title, action: action, keyEquivalent: shortcut?.menuKeyEquivalent ?? "")
        item.target = self
        item.keyEquivalentModifierMask = shortcut?.menuModifierFlags ?? []
        return item
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let command = command(for: menuItem.action) else {
            return true
        }
        if model.settingsPanelVisible, !command.allowsWhenSettingsPanelVisible {
            return false
        }
        return model.canPerformCommand(command)
    }

    private func command(for action: Selector?) -> ConductorShellCommand? {
        switch action {
        case #selector(newWorkspaceCommand):
            .newWorkspace
        case #selector(newTerminalCommand):
            .newTerminal
        case #selector(newWebTabCommand):
            .newWebTab
        case #selector(closeTabCommand):
            .closeSelectedTab
        case #selector(closePaneCommand):
            .closeFocusedPane
        case #selector(splitRightCommand):
            .splitRight
        case #selector(splitDownCommand):
            .splitDown
        case #selector(equalizeSplitsCommand):
            .equalizeSplits
        case #selector(toggleZoomCommand):
            .toggleZoom
        case #selector(moveTabLeftCommand):
            .moveTabLeft
        case #selector(moveTabRightCommand):
            .moveTabRight
        case #selector(moveTabToNextPaneCommand):
            .moveTabToNextPane
        case #selector(moveTabToNewRightSplitCommand):
            .moveTabToNewRightSplit
        case #selector(commandPaletteCommand):
            .toggleCommandPalette
        case #selector(workspaceOverviewCommand):
            .toggleWorkspaceOverview
        case #selector(settingsPanelCommand):
            .toggleSettings
        case #selector(notificationCenterCommand):
            .toggleNotifications
        case #selector(jumpToLatestUnreadCommand):
            .jumpToLatestUnread
        case #selector(openCurrentDirectoryCommand):
            .openFocusedDirectory
        case #selector(copyCurrentDirectoryCommand):
            .copyFocusedDirectory
        case #selector(focusWebAddressCommand):
            .focusWebAddress
        case #selector(reloadSelectedWebTabCommand):
            .reloadSelectedWebTab
        case #selector(openSelectedWebTabExternallyCommand):
            .openSelectedWebTabExternally
        case #selector(copySelectedWebTabURLCommand):
            .copySelectedWebTabURL
        case #selector(copySelectedWebTabReferenceCommand):
            .copySelectedWebTabReference
        case #selector(contextSearchCommand):
            .showTerminalSearch
        case #selector(findNextCommand):
            .findNext
        case #selector(findPreviousCommand):
            .findPrevious
        case #selector(toggleFullScreenCommand):
            .toggleFullScreen
        case #selector(resetWorkspaceCommand):
            .resetWorkspace
        case #selector(selectNextTabCommand):
            .selectNextTab
        case #selector(selectPreviousTabCommand):
            .selectPreviousTab
        case #selector(focusNextPaneCommand):
            .focusNextPane
        case #selector(focusPreviousPaneCommand):
            .focusPreviousPane
        default:
            nil
        }
    }

    private func startCodexBarIfEnabled() {
        guard ProcessInfo.processInfo.environment["CONDUCTOR_DISABLE_CODEXBAR"] != "1",
              !Self.isAutomationRun else {
            return
        }
        ConductorUsageFeature.configureOpenSettings { [weak self] in
            guard let self else { return }
            self.model.showSettingsPanel(section: .usage)
            self.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
        let runtime = CodexBarEmbeddedRuntime.shared
        runtime.start()
        codexBarRuntime = runtime
    }

    private static var isAutomationRun: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["CONDUCTOR_SMOKE_AUTORUN"] == "1" ||
            environment["CONDUCTOR_SHORTCUT_AUTORUN"] == "1" ||
            environment["CONDUCTOR_FOCUS_AUTORUN"] == "1" ||
            environment["CONDUCTOR_LAYOUT_AUTORUN"] == "1" ||
            environment["CONDUCTOR_LIFECYCLE_AUTORUN"] == "1" ||
            environment["CONDUCTOR_SHELL_PANEL_AUTORUN"] == "1" ||
            environment["CONDUCTOR_NOTIFICATION_AUTORUN"] == "1" ||
            environment["CONDUCTOR_STRESS_AUTORUN"] == "1" ||
            environment["CONDUCTOR_RESIZE_STRESS_AUTORUN"] == "1" ||
            environment["CONDUCTOR_WORKSPACE_AUTORUN"] == "1"
    }

    private func routeAppShortcut(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command) else {
            return false
        }
        if let command = model.appearance.keyboardShortcuts.command(matching: event) {
            if model.settingsPanelVisible, !command.allowsWhenSettingsPanelVisible {
                return true
            }
            guard model.canPerformCommand(command) else { return false }
            scheduleCommand(command)
            return true
        }

        if model.settingsPanelVisible,
           event.charactersIgnoringModifiers?.lowercased() != "q" {
            return true
        }
        return false
    }

    private func scheduleCommand(_ command: @escaping @MainActor () -> Void) {
        Task { @MainActor in
            command()
        }
    }

    private func scheduleCommand(_ command: ConductorShellCommand) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.model.performCommand(command, window: self.window)
        }
    }

    private func installShellKeyMonitor() {
        guard shellKeyMonitor == nil else { return }
        shellKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.consumeShellEscape(event) ? nil : event
        }
    }

    private func consumeShellEscape(_ event: NSEvent) -> Bool {
        guard event.keyCode == 53 else { return false }
        let flags = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting([.numericPad, .function, .capsLock])
        guard flags.isEmpty else { return false }
        return model.dismissVisibleShellPanel()
    }

    @objc private func newWorkspaceCommand() {
        scheduleCommand(.newWorkspace)
    }

    @objc private func newTerminalCommand() {
        scheduleCommand(.newTerminal)
    }

    @objc private func newWebTabCommand() {
        scheduleCommand(.newWebTab)
    }

    @objc private func closeTabCommand() {
        scheduleCommand(.closeSelectedTab)
    }

    @objc private func closePaneCommand() {
        scheduleCommand(.closeFocusedPane)
    }

    @objc private func splitRightCommand() {
        scheduleCommand(.splitRight)
    }

    @objc private func splitDownCommand() {
        scheduleCommand(.splitDown)
    }

    @objc private func equalizeSplitsCommand() {
        scheduleCommand(.equalizeSplits)
    }

    @objc private func toggleZoomCommand() {
        scheduleCommand(.toggleZoom)
    }

    @objc private func moveTabLeftCommand() {
        scheduleCommand(.moveTabLeft)
    }

    @objc private func moveTabRightCommand() {
        scheduleCommand(.moveTabRight)
    }

    @objc private func moveTabToNextPaneCommand() {
        scheduleCommand(.moveTabToNextPane)
    }

    @objc private func moveTabToNewRightSplitCommand() {
        scheduleCommand(.moveTabToNewRightSplit)
    }

    @objc private func commandPaletteCommand() {
        scheduleCommand(.toggleCommandPalette)
    }

    @objc private func workspaceOverviewCommand() {
        scheduleCommand(.toggleWorkspaceOverview)
    }

    @objc private func settingsPanelCommand() {
        scheduleCommand(.toggleSettings)
    }

    @objc private func notificationCenterCommand() {
        scheduleCommand(.toggleNotifications)
    }

    @objc private func jumpToLatestUnreadCommand() {
        scheduleCommand(.jumpToLatestUnread)
    }

    @objc private func openCurrentDirectoryCommand() {
        scheduleCommand(.openFocusedDirectory)
    }

    @objc private func copyCurrentDirectoryCommand() {
        scheduleCommand(.copyFocusedDirectory)
    }

    @objc private func focusWebAddressCommand() {
        scheduleCommand(.focusWebAddress)
    }

    @objc private func reloadSelectedWebTabCommand() {
        scheduleCommand(.reloadSelectedWebTab)
    }

    @objc private func openSelectedWebTabExternallyCommand() {
        scheduleCommand(.openSelectedWebTabExternally)
    }

    @objc private func copySelectedWebTabURLCommand() {
        scheduleCommand(.copySelectedWebTabURL)
    }

    @objc private func copySelectedWebTabReferenceCommand() {
        scheduleCommand(.copySelectedWebTabReference)
    }

    @objc private func contextSearchCommand() {
        scheduleCommand(.showTerminalSearch)
    }

    @objc private func findNextCommand() {
        scheduleCommand(.findNext)
    }

    @objc private func findPreviousCommand() {
        scheduleCommand(.findPrevious)
    }

    @objc private func toggleFullScreenCommand() {
        scheduleCommand(.toggleFullScreen)
    }

    @objc private func resetWorkspaceCommand() {
        scheduleCommand(.resetWorkspace)
    }

    private func setNotificationWindowVisible(_ visible: Bool) {
        if visible {
            showNotificationWindow()
        } else {
            hideNotificationWindow()
        }
    }

    private func installAppearanceBinding() {
        model.$theme
            .removeDuplicates()
            .sink { [weak self] theme in
                guard let self else { return }
                if let window {
                    applyAppearance(for: theme, to: window)
                }
                if let notificationWindow {
                    applyAppearance(for: theme, to: notificationWindow)
                }
            }
            .store(in: &cancellables)

        model.$appearance
            .map(\.keyboardShortcuts)
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.installMainMenu()
            }
            .store(in: &cancellables)
    }

    private func applyAppearance(for theme: TerminalTheme, to window: NSWindow) {
        let appearanceName: NSAppearance.Name = theme.chromeColorScheme == .dark ? .darkAqua : .aqua
        let appearance = NSAppearance(named: appearanceName)
        window.appearance = appearance
        window.contentView?.appearance = appearance
    }

    private func hideNotificationWindow() {
        guard let notificationWindow else {
            restoreMainWindowFocus()
            return
        }
        guard notificationWindow.isVisible else {
            notificationWindow.orderOut(nil)
            restoreMainWindowFocus()
            return
        }

        let startFrame = notificationWindow.frame
        let endFrame = startFrame.offsetBy(dx: notificationWindowMotionDistance * 0.72, dy: 0)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = notificationWindowMotionDuration
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)
            notificationWindow.animator().alphaValue = 0
            notificationWindow.animator().setFrame(endFrame, display: true)
        } completionHandler: { [weak self, weak notificationWindow] in
            Task { @MainActor in
                guard let self, let notificationWindow else { return }
                guard !self.model.notificationPanelVisible else {
                    notificationWindow.alphaValue = 1
                    notificationWindow.setFrame(startFrame, display: false)
                    notificationWindow.orderFrontRegardless()
                    return
                }
                notificationWindow.orderOut(nil)
                notificationWindow.alphaValue = 1
                notificationWindow.setFrame(startFrame, display: false)
                self.restoreMainWindowFocus()
            }
        }
    }

    private func restoreMainWindowFocus() {
        guard let window else { return }
        if NSApp.isActive {
            window.makeKeyAndOrderFront(nil)
        } else {
            window.orderFront(nil)
        }
    }

    private func showNotificationWindow() {
        if let notificationWindow {
            animateNotificationWindowIn(notificationWindow)
            return
        }

        let panel = NSPanel(
            contentRect: notificationWindowFrame(),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "通知"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        applyAppearance(for: model.theme, to: panel)
        [
            NSWindow.ButtonType.closeButton,
            .miniaturizeButton,
            .zoomButton
        ].forEach { buttonType in
            panel.standardWindowButton(buttonType)?.isHidden = true
        }
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.minSize = NSSize(
            width: ConductorTokens.Space.notificationPanelMinWidth,
            height: ConductorTokens.Space.notificationPanelMinHeight
        )

        let delegate = NotificationWindowDelegate { [weak self] in
            self?.model.hideNotificationPanel()
        }
        panel.delegate = delegate
        notificationWindowDelegate = delegate

        let contentContainer = NSView()
        contentContainer.wantsLayer = true
        contentContainer.layer?.backgroundColor = NSColor.clear.cgColor
        let hostingView = ConductorHostingView(
            rootView: NotificationPanelRootView(model: model)
                .frame(
                    minWidth: ConductorTokens.Space.notificationPanelMinWidth,
                    minHeight: ConductorTokens.Space.notificationPanelMinHeight
                )
        )
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(hostingView)
        panel.contentView = contentContainer
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor)
        ])

        notificationWindow = panel
        animateNotificationWindowIn(panel)
    }

    private func animateNotificationWindowIn(_ panel: NSPanel) {
        let targetFrame = panel.frame
        if panel.isVisible {
            panel.alphaValue = 1
            panel.orderFrontRegardless()
            return
        }
        panel.alphaValue = 0
        panel.setFrame(targetFrame.offsetBy(dx: notificationWindowMotionDistance, dy: 0), display: false)
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = notificationWindowMotionDuration
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)
            panel.animator().alphaValue = 1
            panel.animator().setFrame(targetFrame, display: true)
        }
    }

    private func installAgentHookObserver() {
        guard agentHookObserver == nil else { return }
        agentHookObserver = DistributedNotificationCenter.default().addObserver(
            forName: ConductorAgentHookBridge.notificationName,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let userInfo = notification.userInfo?.reduce(into: [String: String]()) { result, item in
                guard let key = item.key as? String, let value = item.value as? String else { return }
                result[key] = value
            }
            Task { @MainActor [weak self] in
                self?.model.receiveAgentHookNotification(userInfo)
            }
        }
    }

    private func notificationWindowFrame() -> NSRect {
        let size = NSSize(
            width: ConductorTokens.Space.notificationPanelWidth,
            height: ConductorTokens.Space.notificationPanelHeight
        )
        guard let window else {
            return NSRect(x: 180, y: 180, width: size.width, height: size.height)
        }
        let frame = window.frame
        return NSRect(
            x: frame.maxX - size.width - 24,
            y: max(frame.minY + 40, frame.maxY - size.height - 72),
            width: size.width,
            height: size.height
        )
    }

    @objc private func selectNextTabCommand() {
        scheduleCommand(.selectNextTab)
    }

    @objc private func selectPreviousTabCommand() {
        scheduleCommand(.selectPreviousTab)
    }

    @objc private func focusNextPaneCommand() {
        scheduleCommand(.focusNextPane)
    }

    @objc private func focusPreviousPaneCommand() {
        scheduleCommand(.focusPreviousPane)
    }

    private func runShortcutAutomationIfRequested() {
        guard ProcessInfo.processInfo.environment["CONDUCTOR_SHORTCUT_AUTORUN"] == "1" else { return }
        let outputPath = ProcessInfo.processInfo.environment["CONDUCTOR_SHORTCUT_OUTPUT"] ?? "/tmp/conductor-shortcut-ok.txt"
        let originalWorkspace = model.workspace
        let originalTheme = model.theme

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self, let window = self.window else { return }
            window.makeKeyAndOrderFront(nil)
            if let tab = self.model.workspace.focusedPane?.selectedTab {
                let surface = self.model.surface(for: tab)
                surface.attachIfPossible()
                _ = window.makeFirstResponder(surface.hostView)
            }

            let shortcuts: [(String, String, NSEvent.ModifierFlags, UInt16)] = [
                ("n", "n", [.command], 45),
                ("t", "t", [.command], 17),
                ("T", "t", [.command, .shift], 17),
                ("d", "d", [.command], 2),
                ("D", "d", [.command, .shift], 2),
                ("n", "n", [.command, .option], 45),
                ("j", "j", [.command, .option], 38),
                ("z", "z", [.command, .option], 6),
                ("]", "]", [.command], 30),
                ("[", "[", [.command], 33),
                ("}", "]", [.command, .shift], 30),
                ("{", "[", [.command, .shift], 33),
                ("", "", [.command, .option], 124),
                ("", "", [.command, .shift], 124),
                ("w", "w", [.command], 13)
            ]

            self.performShortcutAutomationStep(
                shortcuts,
                index: 0,
                outputPath: outputPath,
                originalWorkspace: originalWorkspace,
                originalTheme: originalTheme
            )
        }
    }

    private func performShortcutAutomationStep(
        _ shortcuts: [(String, String, NSEvent.ModifierFlags, UInt16)],
        index: Int,
        outputPath: String,
        originalWorkspace: WorkspaceState,
        originalTheme: TerminalTheme
    ) {
        guard index < shortcuts.count else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [model] in
                let summary = [
                    "status=ok",
                    "shortcut=perform-key-equivalent",
                    "panes=\(model.workspace.panes.count)",
                    "terminals=\(model.workspace.panes.values.reduce(0) { $0 + $1.tabs.count })",
                    "zoomed=\(model.workspace.isZoomed)"
                ].joined(separator: "\n")

                do {
                    try summary.write(toFile: outputPath, atomically: true, encoding: .utf8)
                } catch {
                    ConductorLog.app.error("Shortcut output write failed: \(error.localizedDescription)")
                }

                model.closeAllSurfaces()
                model.workspace = originalWorkspace
                model.theme = originalTheme
                model.flushPersistence()
                NSApp.terminate(nil)
            }
            return
        }

        let shortcut = shortcuts[index]
        if let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: shortcut.2,
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window?.windowNumber ?? 0,
            context: nil,
            characters: shortcut.0,
            charactersIgnoringModifiers: shortcut.1,
            isARepeat: false,
            keyCode: shortcut.3
        ) {
            _ = window?.performKeyEquivalent(with: event)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.performShortcutAutomationStep(
                shortcuts,
                index: index + 1,
                outputPath: outputPath,
                originalWorkspace: originalWorkspace,
                originalTheme: originalTheme
            )
        }
    }

    private func runSmokeAutomationIfRequested() {
        guard ProcessInfo.processInfo.environment["CONDUCTOR_SMOKE_AUTORUN"] == "1" else { return }
        let outputPath = ProcessInfo.processInfo.environment["CONDUCTOR_SMOKE_OUTPUT"] ?? "/tmp/conductor-smoke-ok.txt"
        let originalWorkspace = model.workspace
        let originalTheme = model.theme
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [model] in
            model.newTerminal()
            model.selectPreviousTab()
            model.selectNextTab()
            model.splitRight()
            model.focusPreviousPane()
            model.moveSelectedTabToNextPane()
            model.moveSelectedTabLeft()
            model.moveSelectedTabToNewSplit(.down)
            model.equalizeSplits()
            model.toggleZoom()
            model.toggleZoom()
            model.focusPreviousPane()
            model.focusNextPane()
            model.closeSelectedTab()

            let summary = [
                "status=ok",
                "panes=\(model.workspace.panes.count)",
                "terminals=\(model.workspace.panes.values.reduce(0) { $0 + $1.tabs.count })",
                "zoomed=\(model.workspace.isZoomed)"
            ].joined(separator: "\n")

            do {
                try summary.write(toFile: outputPath, atomically: true, encoding: .utf8)
            } catch {
                ConductorLog.app.error("Smoke output write failed: \(error.localizedDescription)")
            }
            model.closeAllSurfaces()
            model.workspace = originalWorkspace
            model.theme = originalTheme
            model.flushPersistence()
            NSApp.terminate(nil)
        }
    }

    private func runWorkspaceAutomationIfRequested() {
        guard ProcessInfo.processInfo.environment["CONDUCTOR_WORKSPACE_AUTORUN"] == "1" else { return }
        let outputPath = ProcessInfo.processInfo.environment["CONDUCTOR_WORKSPACE_OUTPUT"] ?? "/tmp/conductor-workspace-ok.txt"
        let originalWorkspace = model.workspace
        let originalTheme = model.theme

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [model] in
            let startingWorkspaceID = model.workspace.id
            let regressionFileURL = URL(fileURLWithPath: "/tmp/conductor-workspace-switch-regression.txt")
            try? "workspace switch regression".write(to: regressionFileURL, atomically: true, encoding: .utf8)
            model.openFileInWorkspace(regressionFileURL)
            let fileTabSelectedBeforeWorkspaceSwitch = model.selectedWorkspaceFileTab != nil
            let sameWorkspaceActivationReturnedTerminalStage = model.activateWorkspace(startingWorkspaceID, source: .tabStrip) &&
                model.workspace.id == startingWorkspaceID &&
                model.selectedWorkspaceFileTab == nil &&
                model.workspace.focusedPane?.selectedTab != nil
            model.openFileInWorkspace(regressionFileURL)
            model.newWorkspace()
            let createdWorkspaceID = model.workspace.id
            let newWorkspaceOpenedTerminalStage = model.selectedWorkspaceFileTab == nil &&
                model.workspace.focusedPane?.selectedTab != nil
            model.openFileInWorkspace(regressionFileURL)
            let crossWorkspaceActivationSucceeded = model.activateWorkspace(startingWorkspaceID, source: .sidebar)
            let workspaceSwitchRestoredTerminalStage = model.workspace.id == startingWorkspaceID &&
                model.selectedWorkspaceFileTab == nil &&
                model.workspace.focusedPane?.selectedTab != nil
            model.closeWorkspace(createdWorkspaceID)

            model.closeAllSurfaces()
            model.workspace = WorkspaceState(title: "Automation")
            model.commandPaletteVisible = false

            model.newTerminal()
            model.selectPreviousTab()
            model.selectNextTab()
            model.moveSelectedTabLeft()
            model.moveSelectedTabRight()
            model.splitRight()
            model.focusPreviousPane()
            model.moveSelectedTabToNextPane()
            model.closeSelectedTab()
            model.closePane(model.workspace.focusedPaneID)
            model.splitDown()
            model.equalizeSplits()
            model.toggleZoom()
            model.toggleZoom()

            let workspaceValid = self.workspaceIsValid(model.workspace)
            let navigationRestoredTerminalStage = fileTabSelectedBeforeWorkspaceSwitch &&
                sameWorkspaceActivationReturnedTerminalStage &&
                crossWorkspaceActivationSucceeded &&
                newWorkspaceOpenedTerminalStage &&
                workspaceSwitchRestoredTerminalStage
            let summary = [
                "status=\(workspaceValid && navigationRestoredTerminalStage ? "ok" : "invalid")",
                "workspace=operations",
                "workspaceNavigationRestoresTerminal=\(navigationRestoredTerminalStage)",
                "sameWorkspaceActivationReturnsTerminal=\(sameWorkspaceActivationReturnedTerminalStage)",
                "crossWorkspaceActivationSucceeded=\(crossWorkspaceActivationSucceeded)",
                "panes=\(model.workspace.panes.count)",
                "terminals=\(model.workspace.panes.values.reduce(0) { $0 + $1.tabs.count })",
                "zoomed=\(model.workspace.isZoomed)"
            ].joined(separator: "\n")

            do {
                try summary.write(toFile: outputPath, atomically: true, encoding: .utf8)
            } catch {
                ConductorLog.app.error("Workspace automation output write failed: \(error.localizedDescription)")
            }
            model.closeAllSurfaces()
            model.workspace = originalWorkspace
            model.theme = originalTheme
            model.flushPersistence()
            NSApp.terminate(nil)
        }
    }

    private func runFocusAutomationIfRequested() {
        guard ProcessInfo.processInfo.environment["CONDUCTOR_FOCUS_AUTORUN"] == "1" else { return }
        let outputPath = ProcessInfo.processInfo.environment["CONDUCTOR_FOCUS_OUTPUT"] ?? "/tmp/conductor-focus-ok.txt"
        let originalWorkspace = model.workspace
        let originalTheme = model.theme

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self else { return }
            self.model.closeAllSurfaces()
            self.model.workspace = WorkspaceState(title: "Focus Automation")
            self.model.commandPaletteVisible = false

            self.model.newTerminal()
            self.model.selectPreviousTab()
            self.model.selectNextTab()
            self.model.splitRight()
            self.model.focusPreviousPane()
            self.model.moveSelectedTabToNextPane()
            self.model.focusNextPane()
            self.model.selectPreviousTab()

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                guard let self else { return }
                let firstLeafFocus = self.focusTerminalHostForLeaf(at: 0)
                let secondLeafFocus = self.focusTerminalHostForLeaf(at: 1)
                let focused = self.focusedTerminalIsFirstResponder()
                let summary = [
                    "status=\(focused && firstLeafFocus && secondLeafFocus && self.workspaceIsValid(self.model.workspace) ? "ok" : "invalid")",
                    "focus=first-responder",
                    "mouse-focus=workspace",
                    "panes=\(self.model.workspace.panes.count)",
                    "terminals=\(self.model.workspace.panes.values.reduce(0) { $0 + $1.tabs.count })",
                    "zoomed=\(self.model.workspace.isZoomed)"
                ].joined(separator: "\n")

                do {
                    try summary.write(toFile: outputPath, atomically: true, encoding: .utf8)
                } catch {
                    ConductorLog.app.error("Focus automation output write failed: \(error.localizedDescription)")
                }
                self.model.closeAllSurfaces()
                self.model.workspace = originalWorkspace
                self.model.theme = originalTheme
                self.model.flushPersistence()
                NSApp.terminate(nil)
            }
        }
    }

    private func runLayoutAutomationIfRequested() {
        guard ProcessInfo.processInfo.environment["CONDUCTOR_LAYOUT_AUTORUN"] == "1" else { return }
        let outputPath = ProcessInfo.processInfo.environment["CONDUCTOR_LAYOUT_OUTPUT"] ?? "/tmp/conductor-layout-ok.txt"
        let originalWorkspace = model.workspace
        let originalTheme = model.theme

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self else { return }
            self.model.closeAllSurfaces()
            self.model.workspace = WorkspaceState(title: "Layout Automation")
            self.model.commandPaletteVisible = false

            self.model.splitRight()
            self.model.splitDown()
            self.model.setSplitFraction(path: [], fraction: 0.995)
            self.model.setSplitFraction(path: [.second], fraction: 0.005)
            let clamped = self.splitFractions(in: self.model.workspace.root) == [SplitNode.maximumFraction, SplitNode.minimumFraction]
            self.model.equalizeSplits()
            let equalized = self.splitFractions(in: self.model.workspace.root).allSatisfy { abs($0 - 0.5) < 0.0001 }
            self.model.resizeFocusedSplit(direction: .right, amount: 12)
            self.model.resizeFocusedSplit(direction: .left, amount: 12)

            let summary = [
                "status=\(clamped && equalized && self.workspaceIsValid(self.model.workspace) ? "ok" : "invalid")",
                "layout=resize",
                "clamped=\(clamped)",
                "equalized=\(equalized)",
                "panes=\(self.model.workspace.panes.count)",
                "terminals=\(self.model.workspace.panes.values.reduce(0) { $0 + $1.tabs.count })",
                "zoomed=\(self.model.workspace.isZoomed)"
            ].joined(separator: "\n")

            do {
                try summary.write(toFile: outputPath, atomically: true, encoding: .utf8)
            } catch {
                ConductorLog.app.error("Layout automation output write failed: \(error.localizedDescription)")
            }
            self.model.closeAllSurfaces()
            self.model.workspace = originalWorkspace
            self.model.theme = originalTheme
            self.model.flushPersistence()
            NSApp.terminate(nil)
        }
    }

    private func runLifecycleAutomationIfRequested() {
        guard ProcessInfo.processInfo.environment["CONDUCTOR_LIFECYCLE_AUTORUN"] == "1" else { return }
        let outputPath = ProcessInfo.processInfo.environment["CONDUCTOR_LIFECYCLE_OUTPUT"] ?? "/tmp/conductor-lifecycle-ok.txt"
        let originalWorkspace = model.workspace
        let originalTheme = model.theme

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self else { return }
            self.model.closeAllSurfaces()
            self.model.workspace = WorkspaceState(title: "Lifecycle Automation")
            self.model.commandPaletteVisible = false

            let paneID = self.model.workspace.focusedPaneID
            guard let first = self.model.workspace.focusedPane?.selectedTabID else {
                self.writeLifecycleSummary(outputPath: outputPath, status: "invalid")
                return
            }

            _ = self.model.surface(for: self.model.workspace.focusedPane!.selectedTab!)
            _ = self.model.ghosttyRuntimeDidReceiveNotification(terminalID: first, title: "seed", body: "metadata")

            self.model.newTerminal()
            guard let second = self.model.workspace.focusedPane?.selectedTabID,
                  let secondTab = self.model.workspace.focusedPane?.selectedTab else {
                self.writeLifecycleSummary(outputPath: outputPath, status: "invalid")
                return
            }
            _ = self.model.surface(for: secondTab)

            self.model.newTerminal()
            guard let third = self.model.workspace.focusedPane?.selectedTabID,
                  let thirdTab = self.model.workspace.focusedPane?.selectedTab else {
                self.writeLifecycleSummary(outputPath: outputPath, status: "invalid")
                return
            }
            _ = self.model.surface(for: thirdTab)

            let createdThreeSurfaces = self.model.runtimeSurfaceCount == 3
            self.model.selectTab(first, in: paneID)
            self.model.closeTab(second, in: paneID)
            let inactiveClosed = !self.model.runtimeHasSurface(for: second) && self.model.runtimeSurfaceCount == 2
            let closedCallbackRejected = !self.model.ghosttyRuntimeDidRequestClose(terminalID: second)

            self.model.selectTab(third, in: paneID)
            self.model.closeSelectedTab()
            let selectedClosed = !self.model.runtimeHasSurface(for: third) && self.model.runtimeSurfaceCount == 1

            self.model.closeSelectedTab()
            let replacedLastTab = !self.model.runtimeHasSurface(for: first) && self.model.runtimeSurfaceCount == 0 && self.model.workspace.focusedPane?.tabs.count == 1
            guard let replacementTab = self.model.workspace.focusedPane?.selectedTab else {
                self.writeLifecycleSummary(outputPath: outputPath, status: "invalid")
                return
            }
            _ = self.model.surface(for: replacementTab)

            self.model.splitRight()
            guard let splitTab = self.model.workspace.focusedPane?.selectedTab else {
                self.writeLifecycleSummary(outputPath: outputPath, status: "invalid")
                return
            }
            _ = self.model.surface(for: splitTab)
            let splitSurfaceCreated = self.model.runtimeSurfaceCount == 2
            let closedPaneID = self.model.workspace.focusedPaneID
            let closedPaneTerminalID = splitTab.id
            self.model.closePane(closedPaneID)
            let paneClosed = !self.model.runtimeHasSurface(for: closedPaneTerminalID) && self.model.runtimeSurfaceCount == 1
            let paneCloseCallbackRejected = !self.model.ghosttyRuntimeDidRequestClose(terminalID: closedPaneTerminalID)

            self.model.closeAllSurfaces()
            let allClosed = self.model.runtimeSurfaceCount == 0 && self.model.runtimeMetadataCount == 0
            let ok = createdThreeSurfaces &&
                inactiveClosed &&
                closedCallbackRejected &&
                selectedClosed &&
                replacedLastTab &&
                splitSurfaceCreated &&
                paneClosed &&
                paneCloseCallbackRejected &&
                allClosed &&
                self.workspaceIsValid(self.model.workspace)

            let summary = [
                "status=\(ok ? "ok" : "invalid")",
                "lifecycle=close",
                "surfaces=\(self.model.runtimeSurfaceCount)",
                "metadata=\(self.model.runtimeMetadataCount)",
                "panes=\(self.model.workspace.panes.count)",
                "terminals=\(self.model.workspace.panes.values.reduce(0) { $0 + $1.tabs.count })",
                "zoomed=\(self.model.workspace.isZoomed)"
            ].joined(separator: "\n")

            do {
                try summary.write(toFile: outputPath, atomically: true, encoding: .utf8)
            } catch {
                ConductorLog.app.error("Lifecycle automation output write failed: \(error.localizedDescription)")
            }
            self.model.workspace = originalWorkspace
            self.model.theme = originalTheme
            self.model.flushPersistence()
            NSApp.terminate(nil)
        }
    }

    private func runShellPanelAutomationIfRequested() {
        guard ProcessInfo.processInfo.environment["CONDUCTOR_SHELL_PANEL_AUTORUN"] == "1" else { return }
        let outputPath = ProcessInfo.processInfo.environment["CONDUCTOR_SHELL_PANEL_OUTPUT"] ?? "/tmp/conductor-shell-panel-ok.txt"
        let originalWorkspace = model.workspace
        let originalTheme = model.theme

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [model] in
            let dismissesEmpty = model.dismissVisibleShellPanel()

            model.toggleSettingsPanel()
            let settingsOpenedAlone = model.settingsPanelVisible &&
                !model.commandPaletteVisible &&
                !model.workspaceOverviewVisible
            let settingsDismissed = model.dismissVisibleShellPanel() &&
                !model.settingsPanelVisible

            model.toggleCommandPalette()
            let commandOpenedAlone = model.commandPaletteVisible &&
                !model.settingsPanelVisible &&
                !model.workspaceOverviewVisible
            let commandDismissed = model.dismissVisibleShellPanel() &&
                !model.commandPaletteVisible

            model.toggleWorkspaceOverview()
            let overviewOpenedAlone = model.workspaceOverviewVisible &&
                !model.commandPaletteVisible &&
                !model.settingsPanelVisible
            let overviewDismissed = model.dismissVisibleShellPanel() &&
                !model.workspaceOverviewVisible

            let status = !dismissesEmpty &&
                settingsOpenedAlone &&
                settingsDismissed &&
                commandOpenedAlone &&
                commandDismissed &&
                overviewOpenedAlone &&
                overviewDismissed

            let summary = [
                "status=\(status ? "ok" : "invalid")",
                "shell-panels=dismiss",
                "empty=\(!dismissesEmpty)",
                "settings=\(settingsOpenedAlone && settingsDismissed)",
                "command=\(commandOpenedAlone && commandDismissed)",
                "overview=\(overviewOpenedAlone && overviewDismissed)"
            ].joined(separator: "\n")

            do {
                try summary.write(toFile: outputPath, atomically: true, encoding: .utf8)
            } catch {
                ConductorLog.app.error("Shell panel automation output write failed: \(error.localizedDescription)")
            }
            model.workspace = originalWorkspace
            model.theme = originalTheme
            model.flushPersistence()
            NSApp.terminate(nil)
        }
    }

    private func runNotificationAutomationIfRequested() {
        guard ProcessInfo.processInfo.environment["CONDUCTOR_NOTIFICATION_AUTORUN"] == "1" else { return }
        let outputPath = ProcessInfo.processInfo.environment["CONDUCTOR_NOTIFICATION_OUTPUT"] ?? "/tmp/conductor-notification-ok.txt"
        let originalWorkspace = model.workspace
        let originalTheme = model.theme

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [model] in
            model.closeAllSurfaces()
            model.workspace = WorkspaceState(title: "Notification Automation")
            model.commandPaletteVisible = false
            model.settingsPanelVisible = false
            model.workspaceOverviewVisible = false
            model.notificationPanelVisible = true

            model.toggleNotificationPanel()
            let toggleClosed = !model.notificationPanelVisible
            model.commandPaletteVisible = true
            model.toggleNotificationPanel()
            let toggleOpenedAlone = model.notificationPanelVisible &&
                !model.commandPaletteVisible &&
                !model.settingsPanelVisible &&
                !model.workspaceOverviewVisible

            let focusedBefore = model.workspace.focusedPane?.selectedTabID
            model.notifyFocusedTerminalForTesting()
            let notification = model.notifications.snapshot.latestUnread
            let opened = notification.map { model.openNotification($0.id) } ?? false
            let focusedAfter = model.workspace.focusedPane?.selectedTabID
            let unreadCleared = focusedBefore.map { model.notifications.snapshot.unreadCount(for: $0) == 0 } ?? false
            let panelClosed = !model.notificationPanelVisible
            let targetFocused = focusedAfter == focusedBefore
            let status = toggleClosed && toggleOpenedAlone && opened && panelClosed && unreadCleared && targetFocused

            let summary = [
                "status=\(status ? "ok" : "invalid")",
                "notification=open",
                "toggleClosed=\(toggleClosed)",
                "toggleOpenedAlone=\(toggleOpenedAlone)",
                "opened=\(opened)",
                "panelClosed=\(panelClosed)",
                "unreadCleared=\(unreadCleared)",
                "targetFocused=\(targetFocused)"
            ].joined(separator: "\n")

            do {
                try summary.write(toFile: outputPath, atomically: true, encoding: .utf8)
            } catch {
                ConductorLog.app.error("Notification automation output write failed: \(error.localizedDescription)")
            }
            model.closeAllSurfaces()
            model.workspace = originalWorkspace
            model.theme = originalTheme
            model.flushPersistence()
            NSApp.terminate(nil)
        }
    }

    private func runStressAutomationIfRequested() {
        guard ProcessInfo.processInfo.environment["CONDUCTOR_STRESS_AUTORUN"] == "1" else { return }
        let outputPath = ProcessInfo.processInfo.environment["CONDUCTOR_STRESS_OUTPUT"] ?? "/tmp/conductor-stress-ok.txt"
        let requestedCharacters = Self.positiveEnvironmentInt("CONDUCTOR_STRESS_CHARACTERS")
        let completionDelay = TimeInterval(Self.positiveEnvironmentInt("CONDUCTOR_STRESS_WAIT_SECONDS") ?? 1)
        let multiTerminalStress = ProcessInfo.processInfo.environment["CONDUCTOR_STRESS_MULTI_TERMINAL"] == "1"
        let markerRoot = ProcessInfo.processInfo.environment["CONDUCTOR_STRESS_MARKER_DIR"] ??
            "/tmp/conductor-stress-\(UUID().uuidString)"
        let tracePath = ProcessInfo.processInfo.environment["CONDUCTOR_STRESS_TRACE_OUTPUT"]
        let originalWorkspace = stressOriginalWorkspace ?? model.workspace
        let originalTheme = stressOriginalTheme ?? model.theme
        Self.appendStressTrace("scheduled characters=\(requestedCharacters ?? 0) multi=\(multiTerminalStress)", to: tracePath)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [model] in
            Self.appendStressTrace("begin", to: tracePath)
            model.commandPaletteVisible = false
            if self.stressOriginalWorkspace == nil {
                model.workspace = self.makeStressWorkspace(
                    requestedCharacters: requestedCharacters,
                    multiTerminalStress: multiTerminalStress
                )
            }
            Self.appendStressTrace(
                "workspace panes=\(model.workspace.panes.count) terminals=\(model.workspace.panes.values.reduce(0) { $0 + $1.tabs.count })",
                to: tracePath
            )

            let markerURL = URL(fileURLWithPath: markerRoot, isDirectory: true)
            try? FileManager.default.removeItem(at: markerURL)
            try? FileManager.default.createDirectory(at: markerURL, withIntermediateDirectories: true)
            var markerPaths: [String] = []
            let targetTabs: [TerminalTabState]
            if requestedCharacters == nil {
                targetTabs = model.workspace.panes.values.flatMap(\.tabs)
            } else {
                targetTabs = model.workspace.root.leaves.compactMap { paneID in
                    model.workspace.panes[paneID]?.selectedTab
                }
            }
            Self.appendStressTrace("targets=\(targetTabs.count)", to: tracePath)
            for tab in targetTabs {
                let command: String
                if let requestedCharacters {
                    let markerPath = markerURL.appendingPathComponent("\(tab.id.description).done").path
                    markerPaths.append(markerPath)
                    command = Self.stressCommand(characterCount: requestedCharacters, completionMarkerPath: markerPath)
                } else {
                    command = Self.defaultStressCommand()
                }
                model.surface(for: tab).sendText(command)
            }
            Self.appendStressTrace("sent markers=\(markerPaths.count)", to: tracePath)

            @MainActor
            func finish(status: String) {
                let terminalCount = model.workspace.panes.values.reduce(0) { $0 + $1.tabs.count }
                let completedCount = markerPaths.filter { FileManager.default.fileExists(atPath: $0) }.count
                Self.appendStressTrace("finish status=\(status) completed=\(completedCount)", to: tracePath)
                let summary = [
                    "status=\(status)",
                    "stress=long-output",
                    "characters=\(requestedCharacters ?? 0)",
                    "characters_per_terminal=\(requestedCharacters ?? 0)",
                    "total_characters=\((requestedCharacters ?? 0) * terminalCount)",
                    "completed_terminals=\(completedCount)",
                    "panes=\(model.workspace.panes.count)",
                    "terminals=\(terminalCount)",
                    "zoomed=\(model.workspace.isZoomed)"
                ].joined(separator: "\n")

                do {
                    try summary.write(toFile: outputPath, atomically: true, encoding: .utf8)
                } catch {
                    ConductorLog.app.error("Stress output write failed: \(error.localizedDescription)")
                }
                model.closeAllSurfaces()
                model.workspace = originalWorkspace
                model.theme = originalTheme
                model.flushPersistence()
                NSApp.terminate(nil)
            }

            let deadline = Date().addingTimeInterval(completionDelay)
            @MainActor
            func pollCompletion() {
                let completedCount = markerPaths.filter { FileManager.default.fileExists(atPath: $0) }.count
                let completed = completedCount == markerPaths.count
                if completed {
                    finish(status: "ok")
                    return
                }
                if Date() >= deadline {
                    finish(status: "timeout")
                    return
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    pollCompletion()
                }
            }
            if requestedCharacters == nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + completionDelay) {
                    finish(status: "ok")
                }
            } else {
                pollCompletion()
            }
        }
    }

    private static func appendStressTrace(_ line: String, to tracePath: String?) {
        guard let tracePath else { return }
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let text = "\(timestamp) \(line)\n"
        guard let data = text.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: tracePath),
           let handle = try? FileHandle(forWritingTo: URL(fileURLWithPath: tracePath)) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: URL(fileURLWithPath: tracePath), options: [.atomic])
        }
    }

    private static func positiveEnvironmentInt(_ key: String) -> Int? {
        guard let rawValue = ProcessInfo.processInfo.environment[key],
              let value = Int(rawValue),
              value > 0 else {
            return nil
        }
        return value
    }

    private static func defaultStressCommand() -> String {
        "for i in {1..2000}; do echo conductor-stress-$i; done\n"
    }

    private static func stressCommand(characterCount: Int, completionMarkerPath: String) -> String {
        let escapedMarkerPath = completionMarkerPath.replacingOccurrences(of: "'", with: "'\"'\"'")
        return """
        python3 - <<'PY'
        import pathlib
        import sys

        remaining = \(characterCount)
        chunk = "x" * 8192
        while remaining > 0:
            size = min(remaining, len(chunk))
            sys.stdout.write(chunk[:size])
            remaining -= size
        sys.stdout.flush()
        pathlib.Path('\(escapedMarkerPath)').write_text('ok', encoding='utf-8')
        PY

        """
    }

    private func prepareStressWorkspaceIfRequested() {
        guard ProcessInfo.processInfo.environment["CONDUCTOR_STRESS_AUTORUN"] == "1" else { return }
        guard stressOriginalWorkspace == nil else { return }
        stressOriginalWorkspace = model.workspace
        stressOriginalTheme = model.theme
        model.commandPaletteVisible = false
        model.workspace = makeStressWorkspace(
            requestedCharacters: Self.positiveEnvironmentInt("CONDUCTOR_STRESS_CHARACTERS"),
            multiTerminalStress: ProcessInfo.processInfo.environment["CONDUCTOR_STRESS_MULTI_TERMINAL"] == "1"
        )
    }

    private func makeStressWorkspace(
        requestedCharacters: Int?,
        multiTerminalStress: Bool
    ) -> WorkspaceState {
        var stressWorkspace = WorkspaceState(title: "Stress Automation")
        if requestedCharacters == nil {
            stressWorkspace.newTerminal(title: "zsh 2")
            stressWorkspace.splitWorkspaceEdge(.right, title: "zsh 3")
            stressWorkspace.splitWorkspaceEdge(.down, title: "zsh 4")
            stressWorkspace.equalizeSplits()
        } else if multiTerminalStress {
            stressWorkspace.splitWorkspaceEdge(.right, title: "zsh 2")
            stressWorkspace.splitWorkspaceEdge(.down, title: "zsh 3")
            stressWorkspace.splitWorkspaceEdge(.right, title: "zsh 4")
            stressWorkspace.equalizeSplits()
        }
        return stressWorkspace
    }

    private func runResizeStressAutomationIfRequested() {
        guard ProcessInfo.processInfo.environment["CONDUCTOR_RESIZE_STRESS_AUTORUN"] == "1" else { return }
        let outputPath = ProcessInfo.processInfo.environment["CONDUCTOR_RESIZE_STRESS_OUTPUT"] ?? "/tmp/conductor-resize-stress-ok.txt"
        let originalWorkspace = resizeStressOriginalWorkspace ?? model.workspace
        let originalTheme = resizeStressOriginalTheme ?? model.theme

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self else { return }
            self.model.commandPaletteVisible = false

            let command = "for i in {1..4000}; do echo conductor-resize-stress-$i; done\n"
            for pane in self.model.workspace.panes.values {
                for tab in pane.tabs {
                    self.model.surface(for: tab).sendText(command)
                }
            }

            self.performResizeStressStep(
                index: 0,
                outputPath: outputPath,
                originalWorkspace: originalWorkspace,
                originalTheme: originalTheme
            )
        }
    }

    private func prepareResizeStressWorkspaceIfRequested() {
        guard ProcessInfo.processInfo.environment["CONDUCTOR_RESIZE_STRESS_AUTORUN"] == "1" else { return }
        guard resizeStressOriginalWorkspace == nil else { return }
        resizeStressOriginalWorkspace = model.workspace
        resizeStressOriginalTheme = model.theme
        model.commandPaletteVisible = false

        var stressWorkspace = WorkspaceState(title: "Resize Stress Automation")
        stressWorkspace.newTerminal(title: "zsh 2")
        stressWorkspace.splitWorkspaceEdge(.right, title: "zsh 3")
        stressWorkspace.splitWorkspaceEdge(.down, title: "zsh 4")
        stressWorkspace.equalizeSplits()
        model.workspace = stressWorkspace
    }

    private func performResizeStressStep(
        index: Int,
        outputPath: String,
        originalWorkspace: WorkspaceState,
        originalTheme: TerminalTheme
    ) {
        let directions: [ResizeSplitDirection] = [.right, .down, .left, .up]
        if index < 32 {
            model.resizeFocusedSplit(direction: directions[index % directions.count], amount: 7)
            if index % 3 == 0 {
                model.focusNextPane()
            }
            if index % 8 == 7 {
                model.equalizeSplits()
            }
            window?.contentView?.layoutSubtreeIfNeeded()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.075) { [weak self] in
                self?.performResizeStressStep(
                    index: index + 1,
                    outputPath: outputPath,
                    originalWorkspace: originalWorkspace,
                    originalTheme: originalTheme
                )
            }
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self else { return }
            let ok = self.workspaceIsValid(self.model.workspace) &&
                self.model.workspace.panes.count == 3 &&
                self.model.workspace.panes.values.reduce(0) { $0 + $1.tabs.count } == 4 &&
                self.model.runtimeSurfaceCount == 4 &&
                !self.model.workspace.isZoomed
            let summary = [
                "status=\(ok ? "ok" : "invalid")",
                "stress=resize-while-output",
                "resized=true",
                "panes=\(self.model.workspace.panes.count)",
                "terminals=\(self.model.workspace.panes.values.reduce(0) { $0 + $1.tabs.count })",
                "surfaces=\(self.model.runtimeSurfaceCount)",
                "zoomed=\(self.model.workspace.isZoomed)"
            ].joined(separator: "\n")

            do {
                try summary.write(toFile: outputPath, atomically: true, encoding: .utf8)
            } catch {
                ConductorLog.app.error("Resize stress output write failed: \(error.localizedDescription)")
            }
            self.model.closeAllSurfaces()
            self.model.workspace = originalWorkspace
            self.model.theme = originalTheme
            self.model.flushPersistence()
            NSApp.terminate(nil)
        }
    }

    private func writeLifecycleSummary(outputPath: String, status: String) {
        let summary = [
            "status=\(status)",
            "lifecycle=close",
            "surfaces=\(model.runtimeSurfaceCount)",
            "metadata=\(model.runtimeMetadataCount)",
            "panes=\(model.workspace.panes.count)",
            "terminals=\(model.workspace.panes.values.reduce(0) { $0 + $1.tabs.count })",
            "zoomed=\(model.workspace.isZoomed)"
        ].joined(separator: "\n")
        try? summary.write(toFile: outputPath, atomically: true, encoding: .utf8)
        NSApp.terminate(nil)
    }

    private func workspaceIsValid(_ workspace: WorkspaceState) -> Bool {
        let leaves = workspace.root.leaves
        guard !leaves.isEmpty,
              Set(leaves).count == leaves.count,
              Set(leaves) == Set(workspace.panes.keys),
              workspace.panes[workspace.focusedPaneID] != nil else {
            return false
        }
        for paneID in leaves {
            guard let pane = workspace.panes[paneID],
                  !pane.tabs.isEmpty,
                  pane.tabs.contains(where: { $0.id == pane.selectedTabID }),
                  Set(pane.tabs.map(\.id)).count == pane.tabs.count else {
                return false
            }
        }
        if let zoomedPaneID = workspace.zoomedPaneID,
           workspace.panes[zoomedPaneID] == nil {
            return false
        }
        return true
    }

    private func splitFractions(in node: SplitNode) -> [Double] {
        switch node {
        case .leaf:
            []
        case let .split(_, first, second, fraction):
            [fraction] + splitFractions(in: first) + splitFractions(in: second)
        }
    }

    private func focusedTerminalIsFirstResponder() -> Bool {
        guard let window,
              let tab = model.workspace.focusedPane?.selectedTab else {
            return false
        }
        let surface = model.surface(for: tab)
        surface.attachIfPossible()
        return window.firstResponder === surface.hostView
    }

    private func focusTerminalHostForLeaf(at index: Int) -> Bool {
        guard let window else { return false }
        let leaves = model.workspace.root.leaves
        guard leaves.indices.contains(index),
              let pane = model.workspace.panes[leaves[index]],
              let tab = pane.selectedTab else {
            return false
        }
        let surface = model.surface(for: tab)
        surface.attachIfPossible()
        _ = window.makeFirstResponder(surface.hostView)
        return model.workspace.focusedPaneID == pane.id &&
            model.workspace.focusedPane?.selectedTabID == tab.id &&
            window.firstResponder === surface.hostView
    }
}
