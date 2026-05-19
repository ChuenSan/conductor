import AppKit
import Combine
import ConductorCore
import SwiftUI

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

        if super.performKeyEquivalent(with: event) {
            return true
        }
        return routeAppShortcut?(event) == true
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
        guard flags == .command,
              event.charactersIgnoringModifiers?.lowercased() == "a" else {
            return false
        }

        if let textView = responder as? NSTextView {
            textView.selectAll(nil)
            return true
        }
        if let control = responder as? NSControl,
           let editor = control.currentEditor() as? NSTextView {
            editor.selectAll(nil)
            return true
        }
        return NSApp.sendAction(#selector(NSResponder.selectAll(_:)), to: nil, from: self)
    }

    private func isChromeBorderDoubleClick(_ event: NSEvent) -> Bool {
        guard event.window === self else { return false }
        let location = event.locationInWindow
        let size = frame.size
        let borderHitWidth: CGFloat = 18
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
final class ConductorAppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private var window: ConductorWindow?
    private var notificationWindow: NSPanel?
    private var notificationWindowDelegate: NotificationWindowDelegate?
    private var agentHookObserver: NSObjectProtocol?
    private var shellKeyMonitor: Any?
    private var cancellables = Set<AnyCancellable>()
    private let model = ConductorWindowModel()
    private var didStart = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        startApplication()
    }

    func startApplication() {
        guard !didStart else { return }
        didStart = true
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
        GhosttyAppRuntime.shared.actionDelegate = model
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
        installAppearanceBinding()
        installMainMenu()
        runShortcutAutomationIfRequested()
        runSmokeAutomationIfRequested()
        runFocusAutomationIfRequested()
        runLayoutAutomationIfRequested()
        runLifecycleAutomationIfRequested()
        runWorkspaceAutomationIfRequested()
        runShellPanelAutomationIfRequested()
        runStressAutomationIfRequested()
        runResizeStressAutomationIfRequested()
        ConductorLog.app.info("Conductor window launched")
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        GhosttyAppRuntime.shared.setAppFocus(true)
    }

    func applicationDidResignActive(_ notification: Notification) {
        GhosttyAppRuntime.shared.setAppFocus(false)
    }

    func applicationWillTerminate(_ notification: Notification) {
        Self.appendStressTrace("applicationWillTerminate", to: ProcessInfo.processInfo.environment["CONDUCTOR_STRESS_TRACE_OUTPUT"])
        model.flushPersistence()
        notificationWindow?.close()
        if let agentHookObserver {
            DistributedNotificationCenter.default().removeObserver(agentHookObserver)
        }
        if let shellKeyMonitor {
            NSEvent.removeMonitor(shellKeyMonitor)
        }
        model.closeAllSurfaces()
        GhosttyAppRuntime.shared.actionDelegate = nil
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        Self.appendStressTrace("applicationShouldTerminateAfterLastWindowClosed", to: ProcessInfo.processInfo.environment["CONDUCTOR_STRESS_TRACE_OUTPUT"])
        return true
    }

    private func installMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu(title: "Conductor")
        appMenu.addItem(menuItem("Settings...", ",", [], #selector(settingsPanelCommand)))
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(NSMenuItem(title: "Quit Conductor", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let fileMenuItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(menuItem("New Workspace", "n", [], #selector(newWorkspaceCommand)))
        fileMenu.addItem(menuItem("New Terminal", "t", [], #selector(newTerminalCommand)))
        fileMenu.addItem(NSMenuItem.separator())
        fileMenu.addItem(menuItem("Close Tab", "w", [], #selector(closeTabCommand)))
        fileMenu.addItem(menuItem("Close Pane", "w", [.shift], #selector(closePaneCommand)))
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        let layoutMenuItem = NSMenuItem()
        let layoutMenu = NSMenu(title: "Layout")
        layoutMenu.addItem(menuItem("Split Right", "d", [], #selector(splitRightCommand)))
        layoutMenu.addItem(menuItem("Split Down", "d", [.shift], #selector(splitDownCommand)))
        layoutMenu.addItem(NSMenuItem.separator())
        layoutMenu.addItem(menuItem("Next Tab", "]", [], #selector(selectNextTabCommand)))
        layoutMenu.addItem(menuItem("Previous Tab", "[", [], #selector(selectPreviousTabCommand)))
        layoutMenu.addItem(menuItem("Next Pane", "]", [.shift], #selector(focusNextPaneCommand)))
        layoutMenu.addItem(menuItem("Previous Pane", "[", [.shift], #selector(focusPreviousPaneCommand)))
        layoutMenu.addItem(NSMenuItem.separator())
        layoutMenu.addItem(menuItem("Equalize Splits", "=", [.shift], #selector(equalizeSplitsCommand)))
        layoutMenu.addItem(menuItem("Toggle Pane Zoom", "z", [.option], #selector(toggleZoomCommand)))
        layoutMenu.addItem(NSMenuItem.separator())
        layoutMenu.addItem(menuItem("Move Tab Left", ",", [.shift], #selector(moveTabLeftCommand)))
        layoutMenu.addItem(menuItem("Move Tab Right", ".", [.shift], #selector(moveTabRightCommand)))
        layoutMenu.addItem(menuItem("Move Tab to Next Pane", "m", [.option], #selector(moveTabToNextPaneCommand)))
        layoutMenu.addItem(menuItem("Move Tab to New Right Split", "m", [.option, .shift], #selector(moveTabToNewRightSplitCommand)))
        layoutMenuItem.submenu = layoutMenu
        mainMenu.addItem(layoutMenuItem)

        let viewMenuItem = NSMenuItem()
        let viewMenu = NSMenu(title: "View")
        viewMenu.addItem(menuItem("Workspace Overview", "o", [], #selector(workspaceOverviewCommand)))
        viewMenu.addItem(menuItem("Command Palette", "k", [], #selector(commandPaletteCommand)))
        viewMenu.addItem(menuItem("Notifications", "n", [.option], #selector(notificationCenterCommand)))
        viewMenu.addItem(menuItem("Jump to Latest Unread", "j", [.option], #selector(jumpToLatestUnreadCommand)))
        viewMenu.addItem(NSMenuItem.separator())
        viewMenu.addItem(menuItem("Toggle Full Screen", "f", [.control], #selector(toggleFullScreenCommand)))
        viewMenu.addItem(menuItem("Reset Workspace", "", [], #selector(resetWorkspaceCommand)))
        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)

        let findMenuItem = NSMenuItem()
        let findMenu = NSMenu(title: "Find")
        findMenu.addItem(menuItem("Find in Terminal", "f", [], #selector(findInTerminalCommand)))
        findMenu.addItem(menuItem("Find Next", "g", [], #selector(findNextCommand)))
        findMenu.addItem(menuItem("Find Previous", "g", [.shift], #selector(findPreviousCommand)))
        findMenuItem.submenu = findMenu
        mainMenu.addItem(findMenuItem)

        NSApp.mainMenu = mainMenu
    }

    private func menuItem(
        _ title: String,
        _ key: String,
        _ modifiers: NSEvent.ModifierFlags,
        _ action: Selector
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        item.keyEquivalentModifierMask = NSEvent.ModifierFlags.command.union(modifiers)
        return item
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(closePaneCommand):
            model.canPerformCommand(.closeFocusedPane)
        case #selector(splitRightCommand), #selector(splitDownCommand):
            model.canPerformCommand(menuItem.action == #selector(splitRightCommand) ? .splitRight : .splitDown)
        case #selector(equalizeSplitsCommand), #selector(toggleZoomCommand):
            model.canPerformCommand(menuItem.action == #selector(equalizeSplitsCommand) ? .equalizeSplits : .toggleZoom)
        case #selector(moveTabLeftCommand):
            model.canPerformCommand(.moveTabLeft)
        case #selector(moveTabRightCommand):
            model.canPerformCommand(.moveTabRight)
        case #selector(moveTabToNextPaneCommand):
            model.canPerformCommand(.moveTabToNextPane)
        case #selector(moveTabToNewRightSplitCommand):
            model.canPerformCommand(.moveTabToNewRightSplit)
        case #selector(jumpToLatestUnreadCommand):
            model.canPerformCommand(.jumpToLatestUnread)
        case #selector(findNextCommand), #selector(findPreviousCommand):
            model.canPerformCommand(menuItem.action == #selector(findNextCommand) ? .findNext : .findPrevious)
        default:
            true
        }
    }

    private func routeAppShortcut(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command) else {
            return false
        }
        if handleArrowCommand(event, flags: flags) {
            return true
        }
        guard let characters = event.charactersIgnoringModifiers?.lowercased() else {
            return false
        }

        switch (characters, flags.contains(.shift)) {
        case ("f", _) where flags.contains(.control):
            scheduleCommand(.toggleFullScreen)
            return true
        case ("n", _) where flags.contains(.option):
            scheduleCommand(.toggleNotifications)
            return true
        case ("n", _):
            scheduleCommand(.newWorkspace)
            return true
        case ("j", _) where flags.contains(.option):
            scheduleCommand(.jumpToLatestUnread)
            return true
        case ("t", _):
            scheduleCommand(.newTerminal)
            return true
        case ("k", _):
            scheduleCommand(.toggleCommandPalette)
            return true
        case ("o", _):
            scheduleCommand(.toggleWorkspaceOverview)
            return true
        case ("f", _):
            scheduleCommand(.showTerminalSearch)
            return true
        case ("g", true):
            guard model.canPerformCommand(.findPrevious) else { return false }
            scheduleCommand(.findPrevious)
            return true
        case ("g", false):
            guard model.canPerformCommand(.findNext) else { return false }
            scheduleCommand(.findNext)
            return true
        case ("w", true):
            scheduleCommand(.closeFocusedPane)
            return true
        case ("w", _):
            scheduleCommand(.closeSelectedTab)
            return true
        case ("d", false):
            scheduleCommand(.splitRight)
            return true
        case ("d", true):
            scheduleCommand(.splitDown)
            return true
        case ("h", true):
            scheduleCommand(.flashFocusedPane)
            return true
        case ("]", true):
            scheduleCommand(.focusNextPane)
            return true
        case ("[", true):
            scheduleCommand(.focusPreviousPane)
            return true
        case ("]", false):
            scheduleCommand(.selectNextTab)
            return true
        case ("[", false):
            scheduleCommand(.selectPreviousTab)
            return true
        case (",", true):
            scheduleCommand(.moveTabLeft)
            return true
        case (".", true):
            scheduleCommand(.moveTabRight)
            return true
        case ("m", false) where flags.contains(.option):
            scheduleCommand(.moveTabToNextPane)
            return true
        case ("m", true) where flags.contains(.option):
            scheduleCommand(.moveTabToNewRightSplit)
            return true
        case ("=", true):
            scheduleCommand(.equalizeSplits)
            return true
        case ("z", _) where flags.contains(.option):
            scheduleCommand(.toggleZoom)
            return true
        case ("}", _):
            scheduleCommand(.focusNextPane)
            return true
        case ("{", _):
            scheduleCommand(.focusPreviousPane)
            return true
        default:
            return false
        }
    }

    private func handleArrowCommand(_ event: NSEvent, flags: NSEvent.ModifierFlags) -> Bool {
        guard flags.contains(.command), let direction = event.arrowDirection else { return false }

        if flags.contains(.option) {
            switch direction {
            case .left:
                scheduleCommand(.focusPaneLeft)
            case .right:
                scheduleCommand(.focusPaneRight)
            case .up:
                scheduleCommand(.focusPaneUp)
            case .down:
                scheduleCommand(.focusPaneDown)
            }
            return true
        }

        if flags.contains(.shift) {
            switch direction {
            case .left:
                scheduleCommand(.resizePaneLeft)
            case .right:
                scheduleCommand(.resizePaneRight)
            case .up:
                scheduleCommand(.resizePaneUp)
            case .down:
                scheduleCommand(.resizePaneDown)
            }
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

    @objc private func toggleFullScreenCommand() {
        scheduleCommand(.toggleFullScreen)
    }

    @objc private func resetWorkspaceCommand() {
        scheduleCommand(.resetWorkspace)
    }

    @objc private func findInTerminalCommand() {
        scheduleCommand(.showTerminalSearch)
    }

    @objc private func findNextCommand() {
        scheduleCommand(.findNext)
    }

    @objc private func findPreviousCommand() {
        scheduleCommand(.findPrevious)
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
    }

    private func applyAppearance(for theme: TerminalTheme, to window: NSWindow) {
        let appearanceName: NSAppearance.Name = theme.chromeColorScheme == .dark ? .darkAqua : .aqua
        let appearance = NSAppearance(named: appearanceName)
        window.appearance = appearance
        window.contentView?.appearance = appearance
    }

    private func hideNotificationWindow() {
        notificationWindow?.orderOut(nil)
        restoreMainWindowFocus()
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
            notificationWindow.orderFrontRegardless()
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
        panel.orderFrontRegardless()
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
                window.makeFirstResponder(surface.hostView)
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

            let summary = [
                "status=\(self.workspaceIsValid(model.workspace) ? "ok" : "invalid")",
                "workspace=operations",
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
            self.model.setSplitFraction(path: [], fraction: 0.96)
            self.model.setSplitFraction(path: [.second], fraction: 0.04)
            let clamped = self.splitFractions(in: self.model.workspace.root) == [0.85, 0.15]
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

    private func runStressAutomationIfRequested() {
        guard ProcessInfo.processInfo.environment["CONDUCTOR_STRESS_AUTORUN"] == "1" else { return }
        let outputPath = ProcessInfo.processInfo.environment["CONDUCTOR_STRESS_OUTPUT"] ?? "/tmp/conductor-stress-ok.txt"
        let requestedCharacters = Self.positiveEnvironmentInt("CONDUCTOR_STRESS_CHARACTERS")
        let completionDelay = TimeInterval(Self.positiveEnvironmentInt("CONDUCTOR_STRESS_WAIT_SECONDS") ?? 3)
        let multiTerminalStress = ProcessInfo.processInfo.environment["CONDUCTOR_STRESS_MULTI_TERMINAL"] == "1"
        let markerRoot = ProcessInfo.processInfo.environment["CONDUCTOR_STRESS_MARKER_DIR"] ??
            "/tmp/conductor-stress-\(UUID().uuidString)"
        let tracePath = ProcessInfo.processInfo.environment["CONDUCTOR_STRESS_TRACE_OUTPUT"]
        let originalWorkspace = model.workspace
        let originalTheme = model.theme
        Self.appendStressTrace("scheduled characters=\(requestedCharacters ?? 0) multi=\(multiTerminalStress)", to: tracePath)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [model] in
            Self.appendStressTrace("begin", to: tracePath)
            model.closeAllSurfaces()
            model.commandPaletteVisible = false

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
            model.workspace = stressWorkspace
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

    private func runResizeStressAutomationIfRequested() {
        guard ProcessInfo.processInfo.environment["CONDUCTOR_RESIZE_STRESS_AUTORUN"] == "1" else { return }
        let outputPath = ProcessInfo.processInfo.environment["CONDUCTOR_RESIZE_STRESS_OUTPUT"] ?? "/tmp/conductor-resize-stress-ok.txt"
        let originalWorkspace = model.workspace
        let originalTheme = model.theme

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self else { return }
            self.model.closeAllSurfaces()
            self.model.commandPaletteVisible = false

            var stressWorkspace = WorkspaceState(title: "Resize Stress Automation")
            stressWorkspace.newTerminal(title: "zsh 2")
            stressWorkspace.splitWorkspaceEdge(.right, title: "zsh 3")
            stressWorkspace.splitWorkspaceEdge(.down, title: "zsh 4")
            stressWorkspace.equalizeSplits()
            self.model.workspace = stressWorkspace
            self.model.closeAllSurfaces()

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
        window.makeFirstResponder(surface.hostView)
        return model.workspace.focusedPaneID == pane.id &&
            model.workspace.focusedPane?.selectedTabID == tab.id &&
            window.firstResponder === surface.hostView
    }
}

private enum ArrowDirection {
    case left
    case right
    case up
    case down
}

private extension NSEvent {
    var arrowDirection: ArrowDirection? {
        switch keyCode {
        case 123:
            .left
        case 124:
            .right
        case 125:
            .down
        case 126:
            .up
        default:
            nil
        }
    }
}
