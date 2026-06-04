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

private enum ConductorStartupTrustRepair {
    static func clearCurrentAppQuarantineInBackground() {
        guard let appURL = currentApplicationBundleURL() else { return }

        Task.detached(priority: .utility) {
            guard hasQuarantineAttribute(at: appURL) else { return }

            do {
                try runXattr(arguments: ["-dr", "com.apple.quarantine", appURL.path])
                ConductorLog.app.info("Cleared quarantine attribute for current app bundle")
            } catch {
                ConductorLog.app.warning("Unable to clear app quarantine attribute: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private static func currentApplicationBundleURL() -> URL? {
        var candidate = Bundle.main.bundleURL.standardizedFileURL
        while !candidate.path.isEmpty, candidate.path != "/" {
            if candidate.pathExtension == "app" {
                return candidate
            }
            candidate.deleteLastPathComponent()
        }
        return nil
    }

    private static func hasQuarantineAttribute(at url: URL) -> Bool {
        (try? runXattr(arguments: ["-p", "com.apple.quarantine", url.path])) == true
    }

    @discardableResult
    private static func runXattr(arguments: [String]) throws -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        process.arguments = arguments
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(
                domain: "ConductorStartupTrustRepair",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: "xattr exited with status \(process.terminationStatus)"]
            )
        }
        return process.terminationStatus == 0
    }
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

        if Self.isTextEditingResponder(firstResponder) {
            return super.performKeyEquivalent(with: event)
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
              Self.owningTerminalHost(for: responder) == nil,
              Self.isTextEditingResponder(responder) else {
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

    private static func isTextEditingResponder(_ responder: NSResponder?) -> Bool {
        guard let responder else { return false }
        if let textView = responder as? NSTextView {
            return textView.isFieldEditor || textView.isEditable
        }
        if let control = responder as? NSControl,
           control.currentEditor() != nil {
            return true
        }
        return false
    }

    private func isChromeBorderDoubleClick(_ event: NSEvent) -> Bool {
        guard event.window === self else { return false }
        let location = event.locationInWindow
        let size = frame.size
        let borderHitWidth: CGFloat = 6
        let topChromeHitHeight: CGFloat = 42
        if location.x <= borderHitWidth ||
            location.x >= size.width - borderHitWidth ||
            location.y <= borderHitWidth {
            return true
        }
        guard location.y >= size.height - topChromeHitHeight else {
            return false
        }
        return isEmptyTopChromeDoubleClick(event)
    }

    private func isEmptyTopChromeDoubleClick(_ event: NSEvent) -> Bool {
        guard let contentView else { return false }
        let point = contentView.convert(event.locationInWindow, from: nil)
        guard let hitView = contentView.hitTest(point) else { return true }
        return !Self.isInteractiveChromeView(hitView)
    }

    private static func isInteractiveChromeView(_ view: NSView) -> Bool {
        var current: NSView? = view
        while let candidate = current {
            if candidate is NSControl ||
                candidate is NSTextView {
                return true
            }

            let className = NSStringFromClass(type(of: candidate))
            if candidate.accessibilityIdentifier() == "ConductorWorkspaceTabInteractiveRegion" ||
                className.contains("NativeWorkspaceTopTabView") ||
                className.contains("NativeTerminalTab") ||
                className.contains("WorkspaceTab") ||
                className.contains("TerminalTab") ||
                className.contains("Button") ||
                className.contains("Menu") {
                return true
            }
            current = candidate.superview
        }
        return false
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
final class ConductorAppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation, NSWindowDelegate {
    private var window: ConductorWindow?
    private var codexBarRuntime: CodexBarEmbeddedRuntime?
    private var controlServer: ConductorControlServer?
    private var agentHookObserver: NSObjectProtocol?
    private var agentHookDrainTimer: Timer?
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

    func applicationDidFinishLaunching(_ notification: Notification) {
        startApplication()
    }

    func startApplication() {
        guard !didStart else { return }
        didStart = true
        ConductorStartupTrustRepair.clearCurrentAppQuarantineInBackground()
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
        window.minSize = NSSize(width: 1080, height: 720)
        window.tabbingMode = .disallowed
        _ = window.setFrameAutosaveName("Conductor.MainWindow")
        window.isOpaque = false
        window.delegate = self
        window.backgroundColor = .clear
        window.collectionBehavior = [.fullScreenPrimary, .managed]
        applyAppearance(for: model.theme, to: window)
        window.hideSystemTrafficLights()
        window.routeAppShortcut = { [weak self] event in
            self?.routeAppShortcut(event) ?? false
        }
        installShellKeyMonitor()
        installAgentHookObserver()
        startControlServer()
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
        model.installAgentReplyNotificationActivationHandler { [weak self] attentionEventID, terminalID in
            self?.activateTargetFromAgentReplyNotification(
                attentionEventID: attentionEventID,
                terminalID: terminalID
            )
        }
        model.installAgentReplyNotificationHooks(bridgePath: Bundle.main.executablePath)
        startCodexBarIfEnabled()
        installAppearanceBinding()
        installMainMenu()
        model.startUpdateChecksIfNeeded()
        runShortcutAutomationIfRequested()
        runShortcutProfileAutomationIfRequested()
        runMenuAutomationIfRequested()
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
        model.setApplicationActive(true)
        GhosttyAppRuntime.shared.setAppFocus(true)
    }

    func applicationDidResignActive(_ notification: Notification) {
        ConductorDiagnostics.record("app-inactive")
        model.setApplicationActive(false)
        GhosttyAppRuntime.shared.setAppFocus(false)
    }

    func applicationWillTerminate(_ notification: Notification) {
        isTerminating = true
        ConductorDiagnostics.recordSync("app-will-terminate")
        ConductorLog.app.info("Conductor will terminate")
        Self.appendStressTrace("applicationWillTerminate", to: ProcessInfo.processInfo.environment["CONDUCTOR_STRESS_TRACE_OUTPUT"])
        model.flushPersistence()
        controlServer?.stop()
        controlServer = nil
        codexBarRuntime?.stop()
        if let agentHookObserver {
            DistributedNotificationCenter.default().removeObserver(agentHookObserver)
        }
        agentHookDrainTimer?.invalidate()
        agentHookDrainTimer = nil
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
        let updateItem = NSMenuItem(
            title: L("检查更新...", "Check for Updates..."),
            action: #selector(checkForUpdatesCommand),
            keyEquivalent: ""
        )
        updateItem.target = self
        appMenu.addItem(updateItem)
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
        fileMenu.addItem(menuItem(L("重命名当前工作区", "Rename Current Workspace"), command: .renameCurrentWorkspace, #selector(renameCurrentWorkspaceCommand)))
        fileMenu.addItem(menuItem(L("复制工作区", "Duplicate Workspace"), command: .duplicateWorkspace, #selector(duplicateWorkspaceCommand)))
        fileMenu.addItem(menuItem(L("关闭其他工作区", "Close Other Workspaces"), command: .closeOtherWorkspaces, #selector(closeOtherWorkspacesCommand)))
        fileMenu.addItem(menuItem(L("关闭右侧工作区", "Close Workspaces to the Right"), command: .closeWorkspacesToRight, #selector(closeWorkspacesToRightCommand)))
        fileMenu.addItem(menuItem(L("关闭当前工作区", "Close Current Workspace"), command: .closeCurrentWorkspace, #selector(closeCurrentWorkspaceCommand)))
        fileMenu.addItem(NSMenuItem.separator())
        fileMenu.addItem(menuItem(L("打开工作区根目录", "Open Workspace Root"), command: .openCurrentWorkspaceRoot, #selector(openCurrentWorkspaceRootCommand)))
        fileMenu.addItem(menuItem(L("打开本地服务", "Open Local Service"), command: .openCurrentWorkspaceFirstService, #selector(openCurrentWorkspaceFirstServiceCommand)))
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
        viewMenu.addItem(menuItem(L("工作区面板", "Workspaces"), command: .toggleWorkspaceOverview, #selector(workspaceOverviewCommand)))
        viewMenu.addItem(menuItem(L("命令面板", "Command Palette"), command: .toggleCommandPalette, #selector(commandPaletteCommand)))
        viewMenu.addItem(menuItem(L("聚焦网页地址", "Focus Web Address"), command: .focusWebAddress, #selector(focusWebAddressCommand)))
        viewMenu.addItem(menuItem(L("网页后退", "Web Back"), command: .goBackSelectedWebTab, #selector(goBackSelectedWebTabCommand)))
        viewMenu.addItem(menuItem(L("网页前进", "Web Forward"), command: .goForwardSelectedWebTab, #selector(goForwardSelectedWebTabCommand)))
        viewMenu.addItem(menuItem(L("重新载入网页", "Reload Web Page"), command: .reloadSelectedWebTab, #selector(reloadSelectedWebTabCommand)))
        viewMenu.addItem(menuItem(L("在浏览器中打开网页", "Open Web Page in Browser"), command: .openSelectedWebTabExternally, #selector(openSelectedWebTabExternallyCommand)))
        viewMenu.addItem(menuItem(L("复制网页 URL", "Copy Web URL"), command: .copySelectedWebTabURL, #selector(copySelectedWebTabURLCommand)))
        viewMenu.addItem(menuItem(L("复制网页引用", "Copy Web Reference"), command: .copySelectedWebTabReference, #selector(copySelectedWebTabReferenceCommand)))
        viewMenu.addItem(NSMenuItem.separator())
        viewMenu.addItem(menuItem(L("系统应用打开当前文件", "Open Current File in System App"), command: .openSelectedFileExternally, #selector(openSelectedFileExternallyCommand)))
        viewMenu.addItem(menuItem(L("在 Finder 中显示当前文件", "Reveal Current File in Finder"), command: .revealSelectedFileInFinder, #selector(revealSelectedFileInFinderCommand)))
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
        case #selector(renameCurrentWorkspaceCommand):
            .renameCurrentWorkspace
        case #selector(duplicateWorkspaceCommand):
            .duplicateWorkspace
        case #selector(closeOtherWorkspacesCommand):
            .closeOtherWorkspaces
        case #selector(closeWorkspacesToRightCommand):
            .closeWorkspacesToRight
        case #selector(closeCurrentWorkspaceCommand):
            .closeCurrentWorkspace
        case #selector(openCurrentWorkspaceRootCommand):
            .openCurrentWorkspaceRoot
        case #selector(openCurrentWorkspaceFirstServiceCommand):
            .openCurrentWorkspaceFirstService
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
        case #selector(openCurrentDirectoryCommand):
            .openFocusedDirectory
        case #selector(copyCurrentDirectoryCommand):
            .copyFocusedDirectory
        case #selector(focusWebAddressCommand):
            .focusWebAddress
        case #selector(goBackSelectedWebTabCommand):
            .goBackSelectedWebTab
        case #selector(goForwardSelectedWebTabCommand):
            .goForwardSelectedWebTab
        case #selector(reloadSelectedWebTabCommand):
            .reloadSelectedWebTab
        case #selector(openSelectedWebTabExternallyCommand):
            .openSelectedWebTabExternally
        case #selector(copySelectedWebTabURLCommand):
            .copySelectedWebTabURL
        case #selector(copySelectedWebTabReferenceCommand):
            .copySelectedWebTabReference
        case #selector(openSelectedFileExternallyCommand):
            .openSelectedFileExternally
        case #selector(revealSelectedFileInFinderCommand):
            .revealSelectedFileInFinder
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

    private func startControlServer() {
        let router = ConductorControlRouter(model: model)
        let server = ConductorControlServer(router: router)
        server.start()
        controlServer = server
    }

    private static var isAutomationRun: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["CONDUCTOR_SMOKE_AUTORUN"] == "1" ||
            environment["CONDUCTOR_SHORTCUT_AUTORUN"] == "1" ||
            environment["CONDUCTOR_SHORTCUT_PROFILE_AUTORUN"] == "1" ||
            environment["CONDUCTOR_MENU_AUTORUN"] == "1" ||
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
            if !shortcutCommandCanPassVisibleShellPanel(command) {
                return true
            }
            guard model.canPerformCommand(command) else { return false }
            scheduleCommand(command)
            return true
        }

        if shortcutBlockingShellPanelVisible,
           event.charactersIgnoringModifiers?.lowercased() != "q" {
            return true
        }
        return false
    }

    private var shortcutBlockingShellPanelVisible: Bool {
        model.commandPaletteVisible ||
            model.settingsPanelVisible ||
            model.workspaceOverviewVisible ||
            model.terminalSearchVisible
    }

    private func shortcutCommandCanPassVisibleShellPanel(_ command: ConductorShellCommand) -> Bool {
        if model.commandPaletteVisible {
            return command == .toggleCommandPalette
        }
        if model.settingsPanelVisible {
            return command.allowsWhenSettingsPanelVisible
        }
        if model.workspaceOverviewVisible {
            return command == .toggleWorkspaceOverview
        }
        if model.terminalSearchVisible {
            switch command {
            case .showTerminalSearch, .findNext, .findPrevious:
                return true
            default:
                return false
            }
        }
        return true
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

    @objc private func renameCurrentWorkspaceCommand() {
        scheduleCommand(.renameCurrentWorkspace)
    }

    @objc private func duplicateWorkspaceCommand() {
        scheduleCommand(.duplicateWorkspace)
    }

    @objc private func closeOtherWorkspacesCommand() {
        scheduleCommand(.closeOtherWorkspaces)
    }

    @objc private func closeWorkspacesToRightCommand() {
        scheduleCommand(.closeWorkspacesToRight)
    }

    @objc private func closeCurrentWorkspaceCommand() {
        scheduleCommand(.closeCurrentWorkspace)
    }

    @objc private func openCurrentWorkspaceRootCommand() {
        scheduleCommand(.openCurrentWorkspaceRoot)
    }

    @objc private func openCurrentWorkspaceFirstServiceCommand() {
        scheduleCommand(.openCurrentWorkspaceFirstService)
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

    @objc private func checkForUpdatesCommand() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.model.showUpdatesAndCheck()
            self.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
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

    @objc private func goBackSelectedWebTabCommand() {
        scheduleCommand(.goBackSelectedWebTab)
    }

    @objc private func goForwardSelectedWebTabCommand() {
        scheduleCommand(.goForwardSelectedWebTab)
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

    @objc private func openSelectedFileExternallyCommand() {
        scheduleCommand(.openSelectedFileExternally)
    }

    @objc private func revealSelectedFileInFinderCommand() {
        scheduleCommand(.revealSelectedFileInFinder)
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

    private func installAppearanceBinding() {
        model.$theme
            .removeDuplicates()
            .sink { [weak self] theme in
                guard let self else { return }
                if let window {
                    applyAppearance(for: theme, to: window)
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

    private func installAgentHookObserver() {
        guard agentHookObserver == nil else { return }
        agentHookObserver = DistributedNotificationCenter.default().addObserver(
            forName: ConductorAgentHookBridge.eventName,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let userInfo = notification.userInfo?.reduce(into: [String: String]()) { result, item in
                guard let key = item.key as? String, let value = item.value as? String else { return }
                result[key] = value
            }
            Task { @MainActor [weak self] in
                let drainedCount = self?.drainPendingAgentHookEvents() ?? 0
                if drainedCount == 0 {
                    self?.model.receiveAgentHookNotification(userInfo)
                }
            }
        }
        agentHookDrainTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.drainPendingAgentHookEvents()
            }
        }
        drainPendingAgentHookEvents()
    }

    @discardableResult
    private func drainPendingAgentHookEvents() -> Int {
        let events = ConductorAgentHookBridge.drainPendingEvents()
        for userInfo in events {
            model.receiveAgentHookNotification(userInfo)
        }
        return events.count
    }

    private func activateTargetFromAgentReplyNotification(attentionEventID: UUID?, terminalID: TerminalID?) {
        if window == nil {
            didStart = false
            startApplication()
        }
        guard let window else { return }
        window.deminiaturize(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        _ = model.focusAttentionNotificationResponse(
            attentionEventID: attentionEventID,
            terminalID: terminalID
        )
        if let tab = model.workspace.focusedPane?.selectedTab {
            let surface = model.surface(for: tab)
            surface.attachIfPossible()
            _ = window.makeFirstResponder(surface.hostView)
        }
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

    private func runShortcutProfileAutomationIfRequested() {
        guard ProcessInfo.processInfo.environment["CONDUCTOR_SHORTCUT_PROFILE_AUTORUN"] == "1" else { return }
        let outputPath = ProcessInfo.processInfo.environment["CONDUCTOR_SHORTCUT_PROFILE_OUTPUT"] ?? "/tmp/conductor-shortcut-profile-ok.txt"
        let originalAppearance = model.appearance

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self else { return }
            let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
                .appendingPathComponent("conductor-shortcut-profile-\(UUID().uuidString)", isDirectory: true)
            let importURL = tempDirectory.appendingPathComponent("import.json")
            let exportURL = tempDirectory.appendingPathComponent("export.json")
            var status = "invalid"
            var imported = 0
            var unknown = 0
            var rejected = 0
            var conflicts = 0
            var exported = 0

            do {
                try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
                let profile = KeyboardShortcutProfile(
                    exportedAt: Date(timeIntervalSince1970: 0),
                    entries: [
                        .init(command: ConductorShellCommand.newTerminal.rawValue, shortcut: KeyboardShortcutDefinition(key: "t", modifiers: [.command, .option])),
                        .init(command: ConductorShellCommand.splitRight.rawValue, shortcut: KeyboardShortcutDefinition(key: "d", modifiers: [.command, .option])),
                        .init(command: "removedCommand", shortcut: KeyboardShortcutDefinition(key: "u", modifiers: [.command, .option])),
                        .init(command: ConductorShellCommand.toggleSettings.rawValue, shortcut: KeyboardShortcutDefinition(key: "q", modifiers: [.command])),
                        .init(command: ConductorShellCommand.newWorkspace.rawValue, shortcut: KeyboardShortcutDefinition(key: "t", modifiers: [.command, .option]))
                    ]
                )
                try KeyboardShortcutProfileCodec.encode(profile).write(to: importURL, options: [.atomic])

                let result = try self.model.importKeyboardShortcutProfile(from: importURL)
                imported = result.importedCount
                unknown = result.ignoredUnknownCommandCount
                rejected = result.rejectedShortcutCount
                conflicts = result.replacedConflictCount
                exported = try self.model.exportKeyboardShortcutProfile(to: exportURL)
                let exportedProfile = try KeyboardShortcutProfileCodec.decode(Data(contentsOf: exportURL))

                let newWorkspaceShortcut = self.model.appearance.keyboardShortcuts.customShortcuts[ConductorShellCommand.newWorkspace.rawValue]?.displayTitle
                let newTerminalIsDefault = !self.model.appearance.keyboardShortcuts.hasCustomShortcut(for: .newTerminal)
                let splitShortcut = self.model.appearance.keyboardShortcuts.customShortcuts[ConductorShellCommand.splitRight.rawValue]?.displayTitle
                if imported == 3 &&
                    unknown == 1 &&
                    rejected == 1 &&
                    conflicts == 1 &&
                    exported == 2 &&
                    exportedProfile.entries.count == 2 &&
                    newWorkspaceShortcut == "Cmd-Opt-T" &&
                    newTerminalIsDefault &&
                    splitShortcut == "Cmd-Opt-D" {
                    status = "ok"
                }
            } catch {
                ConductorLog.app.error("Shortcut profile automation failed: \(error.localizedDescription)")
            }

            let summary = [
                "status=\(status)",
                "shortcut-profile=import-export",
                "imported=\(imported)",
                "unknown=\(unknown)",
                "rejected=\(rejected)",
                "conflicts=\(conflicts)",
                "exported=\(exported)"
            ].joined(separator: "\n")

            do {
                try summary.write(toFile: outputPath, atomically: true, encoding: .utf8)
            } catch {
                ConductorLog.app.error("Shortcut profile automation output write failed: \(error.localizedDescription)")
            }
            self.model.appearance = originalAppearance
            self.model.flushPersistence()
            NSApp.terminate(nil)
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self else { return }
                let model = self.model
                let terminalCount = model.workspace.panes.values.reduce(0) { $0 + $1.tabs.count }
                let workspaceValid = self.workspaceIsValid(model.workspace)
                let expectedShape = model.workspace.panes.count == 3 &&
                    terminalCount == 3 &&
                    model.workspace.isZoomed
                let summary = [
                    "status=\(workspaceValid && expectedShape ? "ok" : "invalid")",
                    "shortcut=perform-key-equivalent",
                    "workspaceValid=\(workspaceValid)",
                    "expectedShape=\(expectedShape)",
                    "panes=\(model.workspace.panes.count)",
                    "terminals=\(terminalCount)",
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

    private func runMenuAutomationIfRequested() {
        guard ProcessInfo.processInfo.environment["CONDUCTOR_MENU_AUTORUN"] == "1" else { return }
        let outputPath = ProcessInfo.processInfo.environment["CONDUCTOR_MENU_OUTPUT"] ?? "/tmp/conductor-menu-ok.txt"
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            let checks: [(String, Selector, ConductorShellCommand)] = [
                ("web-back", #selector(self.goBackSelectedWebTabCommand), .goBackSelectedWebTab),
                ("web-forward", #selector(self.goForwardSelectedWebTabCommand), .goForwardSelectedWebTab),
                ("file-open-external", #selector(self.openSelectedFileExternallyCommand), .openSelectedFileExternally),
                ("file-reveal-finder", #selector(self.revealSelectedFileInFinderCommand), .revealSelectedFileInFinder),
                ("duplicate-workspace", #selector(self.duplicateWorkspaceCommand), .duplicateWorkspace),
                ("close-other-workspaces", #selector(self.closeOtherWorkspacesCommand), .closeOtherWorkspaces),
                ("close-workspaces-to-right", #selector(self.closeWorkspacesToRightCommand), .closeWorkspacesToRight),
                ("close-current-workspace", #selector(self.closeCurrentWorkspaceCommand), .closeCurrentWorkspace),
                ("workspace-open-root", #selector(self.openCurrentWorkspaceRootCommand), .openCurrentWorkspaceRoot),
                ("workspace-open-service", #selector(self.openCurrentWorkspaceFirstServiceCommand), .openCurrentWorkspaceFirstService),
                ("rename-workspace", #selector(self.renameCurrentWorkspaceCommand), .renameCurrentWorkspace)
            ]
            let menuItems = NSApp.mainMenu?.items.flatMap { item -> [NSMenuItem] in
                guard let submenu = item.submenu else { return [] }
                return submenu.items
            } ?? []
            let failures = checks.compactMap { id, selector, expectedCommand -> String? in
                guard self.command(for: selector) == expectedCommand else {
                    return "\(id):mapping"
                }
                guard menuItems.contains(where: { $0.action == selector }) else {
                    return "\(id):missing-menu-item"
                }
                return nil
            }
            let text: String
            if failures.isEmpty {
                text = [
                    "status=ok",
                    "menu=canonical-actions",
                    "checked=\(checks.count)"
                ].joined(separator: "\n") + "\n"
            } else {
                text = [
                    "status=failed",
                    "menu=canonical-actions",
                    "failures=\(failures.joined(separator: ","))"
                ].joined(separator: "\n") + "\n"
            }
            try? text.write(toFile: outputPath, atomically: true, encoding: .utf8)
            NSApp.terminate(nil)
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

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.runShellPanelAutomation(
                    outputPath: outputPath,
                    originalWorkspace: originalWorkspace,
                    originalTheme: originalTheme
                )
            }
        }
    }

    private func runShellPanelAutomation(
        outputPath: String,
        originalWorkspace: WorkspaceState,
        originalTheme: TerminalTheme
    ) async {
        let model = self.model
        let dismissesEmpty = model.dismissVisibleShellPanel()

        model.toggleSettingsPanel()
        let settingsOpenedAlone = model.settingsPanelVisible &&
            !model.commandPaletteVisible &&
            !model.workspaceOverviewVisible
        let settingsShortcutsBlocked = await shortcutContainmentProbe(events: Self.allShortcutContainmentEvents) {
            model.settingsPanelVisible &&
                !model.commandPaletteVisible &&
                !model.workspaceOverviewVisible
        }
        let settingsDismissed = model.dismissVisibleShellPanel() &&
            !model.settingsPanelVisible

        model.toggleCommandPalette()
        let commandOpenedAlone = model.commandPaletteVisible &&
            !model.settingsPanelVisible &&
            !model.workspaceOverviewVisible
        let commandShortcutsBlocked = await shortcutContainmentProbe(events: Self.shortcutContainmentEvents(excluding: "k")) {
            model.commandPaletteVisible &&
                !model.settingsPanelVisible &&
                !model.workspaceOverviewVisible
        }
        let commandDismissed = model.dismissVisibleShellPanel() &&
            !model.commandPaletteVisible

        model.toggleWorkspaceOverview()
        let overviewOpenedAlone = model.workspaceOverviewVisible &&
            !model.commandPaletteVisible &&
            !model.settingsPanelVisible
        let overviewShortcutsBlocked = await shortcutContainmentProbe(events: Self.shortcutContainmentEvents(excluding: "o")) {
            model.workspaceOverviewVisible &&
                !model.commandPaletteVisible &&
                !model.settingsPanelVisible
        }
        let overviewDismissed = model.dismissVisibleShellPanel() &&
            !model.workspaceOverviewVisible

        model.showTerminalSearch()
        let terminalSearchOpenedAlone = model.terminalSearchVisible &&
            !model.commandPaletteVisible &&
            !model.settingsPanelVisible &&
            !model.workspaceOverviewVisible
        let terminalSearchShortcutsBlocked = await shortcutContainmentProbe(events: Self.shortcutContainmentEvents(excluding: "f")) {
            model.terminalSearchVisible &&
                !model.commandPaletteVisible &&
                !model.settingsPanelVisible &&
                !model.workspaceOverviewVisible
        }
        let terminalSearchDismissed = model.dismissVisibleShellPanel() &&
            !model.terminalSearchVisible

        let shortcutsBlocked = settingsShortcutsBlocked &&
            commandShortcutsBlocked &&
            overviewShortcutsBlocked &&
            terminalSearchShortcutsBlocked
        let status = !dismissesEmpty &&
            settingsOpenedAlone &&
            settingsDismissed &&
            shortcutsBlocked &&
            commandOpenedAlone &&
            commandDismissed &&
            overviewOpenedAlone &&
            overviewDismissed &&
            terminalSearchOpenedAlone &&
            terminalSearchDismissed

        let summary = [
            "status=\(status ? "ok" : "invalid")",
            "shell-panels=dismiss",
            "empty=\(!dismissesEmpty)",
            "settings=\(settingsOpenedAlone && settingsDismissed)",
            "shortcut-blocked=\(shortcutsBlocked)",
            "command=\(commandOpenedAlone && commandDismissed)",
            "overview=\(overviewOpenedAlone && overviewDismissed)",
            "terminal-search=\(terminalSearchOpenedAlone && terminalSearchDismissed)"
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

    private func shortcutContainmentProbe(
        events: [(characters: String, ignoring: String, modifiers: NSEvent.ModifierFlags, keyCode: UInt16)],
        panelStillVisible: @escaping @MainActor () -> Bool
    ) async -> Bool {
        let baseline = Self.shortcutContainmentSnapshot(model: model)
        dispatchShortcutContainmentEvents(events)
        try? await Task.sleep(nanoseconds: 250_000_000)
        return panelStillVisible() &&
            Self.shortcutContainmentSnapshot(model: model) == baseline
    }

    private static var allShortcutContainmentEvents: [(characters: String, ignoring: String, modifiers: NSEvent.ModifierFlags, keyCode: UInt16)] {
        [
            ("t", "t", [.command], 17),
            ("w", "w", [.command], 13),
            ("d", "d", [.command], 2),
            ("n", "n", [.command], 45),
            ("k", "k", [.command], 40),
            ("o", "o", [.command], 31),
            ("f", "f", [.command], 3)
        ]
    }

    private static func shortcutContainmentEvents(
        excluding ignoredCharacter: String
    ) -> [(characters: String, ignoring: String, modifiers: NSEvent.ModifierFlags, keyCode: UInt16)] {
        allShortcutContainmentEvents.filter { $0.ignoring != ignoredCharacter }
    }

    private func dispatchShortcutContainmentEvents(
        _ shortcutEvents: [(characters: String, ignoring: String, modifiers: NSEvent.ModifierFlags, keyCode: UInt16)]
    ) {
        for shortcut in shortcutEvents {
            if let event = NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: shortcut.modifiers,
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window?.windowNumber ?? 0,
                context: nil,
                characters: shortcut.characters,
                charactersIgnoringModifiers: shortcut.ignoring,
                isARepeat: false,
                keyCode: shortcut.keyCode
            ) {
                _ = window?.performKeyEquivalent(with: event)
            }
        }
    }

    private static func shortcutContainmentSnapshot(model: ConductorWindowModel) -> String {
        [
            "workspaces=\(model.workspaces.count)",
            "workspace=\(model.workspace.id.rawValue.uuidString)",
            "panes=\(model.workspace.panes.count)",
            "terminals=\(model.workspace.panes.values.reduce(0) { $0 + $1.tabs.count })",
            "webTabs=\(model.workspaceWebTabs.count)",
            "fileTabs=\(model.workspaceFileTabs.count)",
            "zoomed=\(model.workspace.isZoomed)"
        ].joined(separator: "|")
    }

    private func runNotificationAutomationIfRequested() {
        guard ProcessInfo.processInfo.environment["CONDUCTOR_NOTIFICATION_AUTORUN"] == "1" else { return }
        let outputPath = ProcessInfo.processInfo.environment["CONDUCTOR_NOTIFICATION_OUTPUT"] ?? "/tmp/conductor-notification-ok.txt"
        let originalWorkspace = model.workspace
        let originalTheme = model.theme

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self else { return }
            let model = self.model
            model.refreshAttentionEvents()
            model.commandPaletteVisible = false
            model.workspaceOverviewVisible = false
            model.settingsPanelVisible = false
            model.closeTransientPanels()

            guard let targetTerminalID = model.workspace.focusedPane?.selectedTabID else {
                self.writeNotificationAutomationSummary(
                    outputPath: outputPath,
                    status: false,
                    eventStored: false,
                    nativeDeliveryAttempted: false,
                    unreadCleared: false,
                    targetFocused: false,
                    originalWorkspace: originalWorkspace,
                    originalTheme: originalTheme
                )
                return
            }

            let event = model.controlCreateAttentionEvent(
                title: "Automation notification",
                body: "Notification focus should return to the target terminal.",
                kind: .commandFinished,
                severity: .info,
                workspaceID: model.workspace.id,
                terminalID: targetTerminalID,
                source: "autorun",
                details: ["scenario": "notification-focus"]
            )
            let createdUnread = model.controlAttentionEvents(includeRead: false).contains { $0.id == event.id }

            let focusedEvent = model.controlFocusAttentionEvent(id: event.id)
            let unreadCleared = focusedEvent?.isUnread == false &&
                !model.controlAttentionEvents(includeRead: false).contains { $0.id == event.id }
            let targetFocused = model.focusedTerminalID == targetTerminalID &&
                model.selectedWorkspaceTerminalTabID == targetTerminalID

            self.writeNotificationAutomationSummary(
                outputPath: outputPath,
                status: createdUnread && unreadCleared && targetFocused,
                eventStored: createdUnread,
                nativeDeliveryAttempted: true,
                unreadCleared: unreadCleared,
                targetFocused: targetFocused,
                originalWorkspace: originalWorkspace,
                originalTheme: originalTheme
            )
        }
    }

    private func writeNotificationAutomationSummary(
        outputPath: String,
        status: Bool,
        eventStored: Bool,
        nativeDeliveryAttempted: Bool,
        unreadCleared: Bool,
        targetFocused: Bool,
        originalWorkspace: WorkspaceState,
        originalTheme: TerminalTheme
    ) {
        let summary = [
            "status=\(status ? "ok" : "invalid")",
            "notification=native",
            "eventStored=\(eventStored)",
            "nativeDeliveryAttempted=\(nativeDeliveryAttempted)",
            "unreadCleared=\(unreadCleared)",
            "targetFocused=\(targetFocused)"
        ].joined(separator: "\n")

        do {
            try summary.write(toFile: outputPath, atomically: true, encoding: .utf8)
        } catch {
            ConductorLog.app.error("Notification output write failed: \(error.localizedDescription)")
        }

        model.closeTransientPanels()
        model.controlClearAttentionEvent()
        model.closeAllSurfaces()
        model.workspace = originalWorkspace
        model.theme = originalTheme
        model.flushPersistence()
        NSApp.terminate(nil)
    }

    private func runStressAutomationIfRequested() {
        guard ProcessInfo.processInfo.environment["CONDUCTOR_STRESS_AUTORUN"] == "1" else { return }
        let outputPath = ProcessInfo.processInfo.environment["CONDUCTOR_STRESS_OUTPUT"] ?? "/tmp/conductor-stress-ok.txt"
        let requestedCharacters = Self.positiveEnvironmentInt("CONDUCTOR_STRESS_CHARACTERS") ?? 65_536
        let completionDelay = TimeInterval(Self.positiveEnvironmentInt("CONDUCTOR_STRESS_WAIT_SECONDS") ?? 10)
        let multiTerminalStress = ProcessInfo.processInfo.environment["CONDUCTOR_STRESS_MULTI_TERMINAL"] == "1"
        let markerRoot = ProcessInfo.processInfo.environment["CONDUCTOR_STRESS_MARKER_DIR"] ??
            "/tmp/conductor-stress-\(UUID().uuidString)"
        let tracePath = ProcessInfo.processInfo.environment["CONDUCTOR_STRESS_TRACE_OUTPUT"]
        let originalWorkspace = stressOriginalWorkspace ?? model.workspace
        let originalTheme = stressOriginalTheme ?? model.theme
        Self.appendStressTrace("scheduled characters=\(requestedCharacters) multi=\(multiTerminalStress)", to: tracePath)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self else { return }
            let model = self.model
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
            self.window?.contentView?.layoutSubtreeIfNeeded()
            let targetTabs: [(Int, TerminalTabState)] = model.workspace.root.leaves.enumerated().compactMap { index, paneID in
                guard let tab = model.workspace.panes[paneID]?.selectedTab else { return nil }
                return (index, tab)
            }
            Self.appendStressTrace("targets=\(targetTabs.count)", to: tracePath)
            var targetSurfaces: [(leafIndex: Int, markerPath: String, command: String, surface: TerminalSurface)] = []
            for (leafIndex, tab) in targetTabs {
                let markerPath = markerURL.appendingPathComponent("\(tab.id.description).done").path
                markerPaths.append(markerPath)
                let command = Self.stressCommand(characterCount: requestedCharacters, completionMarkerPath: markerPath)
                let focused = self.focusTerminalHostForLeaf(at: leafIndex)
                let surface = model.surface(for: tab)
                surface.attachIfPossible()
                Self.appendStressTrace(
                    "send leaf=\(leafIndex) focused=\(focused) ready=\(surface.isReadyForInput) marker=\(markerPath)",
                    to: tracePath
                )
                targetSurfaces.append((leafIndex, markerPath, command, surface))
            }

            @MainActor
            func finish(status: String) {
                let terminalCount = model.workspace.panes.values.reduce(0) { $0 + $1.tabs.count }
                let completedCount = markerPaths.filter { FileManager.default.fileExists(atPath: $0) }.count
                Self.appendStressTrace("finish status=\(status) completed=\(completedCount)", to: tracePath)
                if status != "ok" {
                    for target in targetSurfaces {
                        let visible = target.surface.visibleText() ?? "<nil>"
                        let compact = visible
                            .replacingOccurrences(of: "\n", with: "\\n")
                            .replacingOccurrences(of: "\r", with: "\\r")
                        Self.appendStressTrace(
                            "visible leaf=\(target.leafIndex) text=\(String(compact.prefix(220)))",
                            to: tracePath
                        )
                    }
                }
                let summary = [
                    "status=\(status)",
                    "stress=long-output",
                    "characters=\(requestedCharacters)",
                    "characters_per_terminal=\(requestedCharacters)",
                    "target_terminals=\(markerPaths.count)",
                    "total_characters=\(requestedCharacters * markerPaths.count)",
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
                let completed = !markerPaths.isEmpty && completedCount == markerPaths.count
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

            @MainActor
            func sendWhenReady(startedAt: Date) {
                let readyCount = targetSurfaces.filter { target in
                    target.surface.isReadyForInput &&
                        !(target.surface.visibleText()?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
                }.count
                let timedOut = Date().timeIntervalSince(startedAt) >= 5
                guard readyCount == targetSurfaces.count || timedOut else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        sendWhenReady(startedAt: startedAt)
                    }
                    return
                }
                Self.appendStressTrace(
                    "input-ready ready=\(readyCount)/\(targetSurfaces.count) timedOut=\(timedOut)",
                    to: tracePath
                )
                for target in targetSurfaces {
                    Self.appendStressTrace("send-command leaf=\(target.leafIndex) marker=\(target.markerPath)", to: tracePath)
                    target.surface.sendText(target.command)
                    self.sendReturnKey(to: target.surface)
                }
                Self.appendStressTrace("sent markers=\(markerPaths.count)", to: tracePath)
                pollCompletion()
            }

            sendWhenReady(startedAt: Date())
        }
    }

    private func sendReturnKey(to surface: TerminalSurface) {
        guard let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window?.windowNumber ?? 0,
            context: nil,
            characters: "\r",
            charactersIgnoringModifiers: "\r",
            isARepeat: false,
            keyCode: 36
        ) else {
            return
        }
        surface.hostView.keyDown(with: event)
        if let release = NSEvent.keyEvent(
            with: .keyUp,
            location: .zero,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window?.windowNumber ?? 0,
            context: nil,
            characters: "\r",
            charactersIgnoringModifiers: "\r",
            isARepeat: false,
            keyCode: 36
        ) {
            surface.hostView.keyUp(with: release)
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

    private static func stressCommand(characterCount: Int, completionMarkerPath: String) -> String {
        let escapedMarkerPath = completionMarkerPath
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "$", with: "\\$")
            .replacingOccurrences(of: "`", with: "\\`")
        return "python3 -c \"import pathlib,sys; n=\(characterCount); sys.stdout.write('x'*n); sys.stdout.flush(); pathlib.Path(\\\"\(escapedMarkerPath)\\\").write_text('ok', encoding='utf-8')\""
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
