import AppKit
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

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if let terminalHost = Self.owningTerminalHost(for: firstResponder) {
            if terminalHost.performKeyEquivalent(with: event) {
                return true
            }
            if let mainMenu = NSApp.mainMenu, mainMenu.performKeyEquivalent(with: event) {
                return true
            }
            return routeAppShortcut?(event) == true
        }

        if super.performKeyEquivalent(with: event) {
            return true
        }
        return routeAppShortcut?(event) == true
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
        window.hideSystemTrafficLights()
        window.routeAppShortcut = { [weak self] event in
            self?.routeAppShortcut(event) ?? false
        }
        model.onNotificationPanelVisibilityChange = { [weak self] visible in
            self?.setNotificationWindowVisible(visible)
        }
        installAgentHookObserver()
        GhosttyAppRuntime.shared.actionDelegate = model
        let contentContainer = NSView()
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
        installMainMenu()
        runShortcutAutomationIfRequested()
        runSmokeAutomationIfRequested()
        runFocusAutomationIfRequested()
        runLayoutAutomationIfRequested()
        runLifecycleAutomationIfRequested()
        runWorkspaceAutomationIfRequested()
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
        model.flushPersistence()
        notificationWindow?.close()
        if let agentHookObserver {
            DistributedNotificationCenter.default().removeObserver(agentHookObserver)
        }
        model.closeAllSurfaces()
        GhosttyAppRuntime.shared.actionDelegate = nil
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    private func installMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu(title: "Conductor")
        appMenu.addItem(NSMenuItem(title: "Quit Conductor", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let fileMenuItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(menuItem("New Terminal", "t", [], #selector(newTerminalCommand)))
        fileMenu.addItem(menuItem("New Tab", "t", [.shift], #selector(newTabCommand)))
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
        layoutMenu.addItem(menuItem("Toggle Pane Zoom", "z", [], #selector(toggleZoomCommand)))
        layoutMenu.addItem(NSMenuItem.separator())
        layoutMenu.addItem(menuItem("Move Tab Left", ",", [.shift], #selector(moveTabLeftCommand)))
        layoutMenu.addItem(menuItem("Move Tab Right", ".", [.shift], #selector(moveTabRightCommand)))
        layoutMenu.addItem(menuItem("Move Tab to Next Pane", "m", [.option], #selector(moveTabToNextPaneCommand)))
        layoutMenu.addItem(menuItem("Move Tab to New Right Split", "m", [.option, .shift], #selector(moveTabToNewRightSplitCommand)))
        layoutMenuItem.submenu = layoutMenu
        mainMenu.addItem(layoutMenuItem)

        let viewMenuItem = NSMenuItem()
        let viewMenu = NSMenu(title: "View")
        viewMenu.addItem(menuItem("Command Palette", "k", [], #selector(commandPaletteCommand)))
        viewMenu.addItem(menuItem("Notifications", "", [], #selector(notificationCenterCommand)))
        viewMenu.addItem(menuItem("Reset Workspace", "", [], #selector(resetWorkspaceCommand)))
        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)

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
            model.canCloseFocusedPane
        case #selector(splitRightCommand), #selector(splitDownCommand):
            model.canSplit
        case #selector(equalizeSplitsCommand), #selector(toggleZoomCommand):
            model.workspace.root.leaves.count > 1
        case #selector(moveTabLeftCommand):
            model.canMoveSelectedTabLeft
        case #selector(moveTabRightCommand):
            model.canMoveSelectedTabRight
        case #selector(moveTabToNextPaneCommand):
            model.canMoveSelectedTabToNextPane
        case #selector(moveTabToNewRightSplitCommand):
            model.canMoveSelectedTabToNewSplit
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
        case ("t", true):
            scheduleCommand { [model] in
                if let paneID = model.workspace.focusedPane?.id {
                    model.newTab(in: paneID)
                }
            }
            return true
        case ("t", _):
            scheduleCommand { [model] in model.newTerminal() }
            return true
        case ("k", _):
            scheduleCommand { [model] in model.toggleCommandPalette() }
            return true
        case ("w", true):
            guard model.canCloseFocusedPane else { return true }
            scheduleCommand { [model] in model.closePane(model.workspace.focusedPaneID) }
            return true
        case ("w", _):
            scheduleCommand { [model] in model.closeSelectedTab() }
            return true
        case ("d", false):
            guard model.canSplit else { return true }
            scheduleCommand { [model] in model.splitRight() }
            return true
        case ("d", true):
            guard model.canSplit else { return true }
            scheduleCommand { [model] in model.splitDown() }
            return true
        case ("]", true):
            scheduleCommand { [model] in model.focusNextPane() }
            return true
        case ("[", true):
            scheduleCommand { [model] in model.focusPreviousPane() }
            return true
        case ("]", false):
            scheduleCommand { [model] in model.selectNextTab() }
            return true
        case ("[", false):
            scheduleCommand { [model] in model.selectPreviousTab() }
            return true
        case (",", true):
            guard model.canMoveSelectedTabLeft else { return true }
            scheduleCommand { [model] in model.moveSelectedTabLeft() }
            return true
        case (".", true):
            guard model.canMoveSelectedTabRight else { return true }
            scheduleCommand { [model] in model.moveSelectedTabRight() }
            return true
        case ("m", false) where flags.contains(.option):
            guard model.canMoveSelectedTabToNextPane else { return true }
            scheduleCommand { [model] in model.moveSelectedTabToNextPane() }
            return true
        case ("m", true) where flags.contains(.option):
            guard model.canMoveSelectedTabToNewSplit else { return true }
            scheduleCommand { [model] in model.moveSelectedTabToNewSplit(.right) }
            return true
        case ("=", true):
            guard model.workspace.root.leaves.count > 1 else { return true }
            scheduleCommand { [model] in model.equalizeSplits() }
            return true
        case ("z", _):
            guard model.workspace.root.leaves.count > 1 else { return true }
            scheduleCommand { [model] in model.toggleZoom() }
            return true
        case ("}", _):
            scheduleCommand { [model] in model.focusNextPane() }
            return true
        case ("{", _):
            scheduleCommand { [model] in model.focusPreviousPane() }
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
                scheduleCommand { [model] in model.focusPane(direction: .left) }
            case .right:
                scheduleCommand { [model] in model.focusPane(direction: .right) }
            case .up:
                scheduleCommand { [model] in model.focusPane(direction: .up) }
            case .down:
                scheduleCommand { [model] in model.focusPane(direction: .down) }
            }
            return true
        }

        if flags.contains(.shift) {
            switch direction {
            case .left:
                scheduleCommand { [model] in model.resizeFocusedSplit(direction: .left) }
            case .right:
                scheduleCommand { [model] in model.resizeFocusedSplit(direction: .right) }
            case .up:
                scheduleCommand { [model] in model.resizeFocusedSplit(direction: .up) }
            case .down:
                scheduleCommand { [model] in model.resizeFocusedSplit(direction: .down) }
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

    @objc private func newTerminalCommand() {
        scheduleCommand { [model] in model.newTerminal() }
    }

    @objc private func newTabCommand() {
        scheduleCommand { [model] in
            guard let paneID = model.workspace.focusedPane?.id else { return }
            model.newTab(in: paneID)
        }
    }

    @objc private func closeTabCommand() {
        scheduleCommand { [model] in model.closeSelectedTab() }
    }

    @objc private func closePaneCommand() {
        guard model.canCloseFocusedPane else { return }
        scheduleCommand { [model] in model.closePane(model.workspace.focusedPaneID) }
    }

    @objc private func splitRightCommand() {
        guard model.canSplit else { return }
        scheduleCommand { [model] in model.splitRight() }
    }

    @objc private func splitDownCommand() {
        guard model.canSplit else { return }
        scheduleCommand { [model] in model.splitDown() }
    }

    @objc private func equalizeSplitsCommand() {
        guard model.workspace.root.leaves.count > 1 else { return }
        scheduleCommand { [model] in model.equalizeSplits() }
    }

    @objc private func toggleZoomCommand() {
        guard model.workspace.root.leaves.count > 1 else { return }
        scheduleCommand { [model] in model.toggleZoom() }
    }

    @objc private func moveTabLeftCommand() {
        guard model.canMoveSelectedTabLeft else { return }
        scheduleCommand { [model] in model.moveSelectedTabLeft() }
    }

    @objc private func moveTabRightCommand() {
        guard model.canMoveSelectedTabRight else { return }
        scheduleCommand { [model] in model.moveSelectedTabRight() }
    }

    @objc private func moveTabToNextPaneCommand() {
        guard model.canMoveSelectedTabToNextPane else { return }
        scheduleCommand { [model] in model.moveSelectedTabToNextPane() }
    }

    @objc private func moveTabToNewRightSplitCommand() {
        guard model.canMoveSelectedTabToNewSplit else { return }
        scheduleCommand { [model] in model.moveSelectedTabToNewSplit(.right) }
    }

    @objc private func commandPaletteCommand() {
        scheduleCommand { [model] in model.toggleCommandPalette() }
    }

    @objc private func notificationCenterCommand() {
        scheduleCommand { [model] in model.toggleNotificationPanel() }
    }

    @objc private func resetWorkspaceCommand() {
        scheduleCommand { [model] in model.resetWorkspace() }
    }

    private func setNotificationWindowVisible(_ visible: Bool) {
        if visible {
            showNotificationWindow()
        } else {
            notificationWindow?.orderOut(nil)
        }
    }

    private func showNotificationWindow() {
        if let notificationWindow {
            notificationWindow.makeKeyAndOrderFront(nil)
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
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = false
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
            rootView: NotificationPanelView(model: model)
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
        panel.makeKeyAndOrderFront(nil)
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
            y: max(frame.minY + 40, frame.maxY - size.height - 54),
            width: size.width,
            height: size.height
        )
    }

    @objc private func selectNextTabCommand() {
        scheduleCommand { [model] in model.selectNextTab() }
    }

    @objc private func selectPreviousTabCommand() {
        scheduleCommand { [model] in model.selectPreviousTab() }
    }

    @objc private func focusNextPaneCommand() {
        scheduleCommand { [model] in model.focusNextPane() }
    }

    @objc private func focusPreviousPaneCommand() {
        scheduleCommand { [model] in model.focusPreviousPane() }
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
                ("t", "t", [.command], 17),
                ("T", "t", [.command, .shift], 17),
                ("d", "d", [.command], 2),
                ("D", "d", [.command, .shift], 2),
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

    private func runStressAutomationIfRequested() {
        guard ProcessInfo.processInfo.environment["CONDUCTOR_STRESS_AUTORUN"] == "1" else { return }
        let outputPath = ProcessInfo.processInfo.environment["CONDUCTOR_STRESS_OUTPUT"] ?? "/tmp/conductor-stress-ok.txt"
        let originalWorkspace = model.workspace
        let originalTheme = model.theme
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [model] in
            model.closeAllSurfaces()
            model.workspace = WorkspaceState(title: "Stress Automation")
            model.commandPaletteVisible = false

            model.newTerminal()
            model.splitRight()
            model.splitDown()
            model.equalizeSplits()

            let command = "for i in {1..2000}; do echo conductor-stress-$i; done\n"
            for pane in model.workspace.panes.values {
                guard let tab = pane.selectedTab else { continue }
                model.surface(for: tab).sendText(command)
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                let summary = [
                    "status=ok",
                    "stress=long-output",
                    "panes=\(model.workspace.panes.count)",
                    "terminals=\(model.workspace.panes.values.reduce(0) { $0 + $1.tabs.count })",
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
        }
    }

    private func runResizeStressAutomationIfRequested() {
        guard ProcessInfo.processInfo.environment["CONDUCTOR_RESIZE_STRESS_AUTORUN"] == "1" else { return }
        let outputPath = ProcessInfo.processInfo.environment["CONDUCTOR_RESIZE_STRESS_OUTPUT"] ?? "/tmp/conductor-resize-stress-ok.txt"
        let originalWorkspace = model.workspace
        let originalTheme = model.theme

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self else { return }
            self.model.closeAllSurfaces()
            self.model.workspace = WorkspaceState(title: "Resize Stress Automation")
            self.model.commandPaletteVisible = false

            self.model.newTerminal()
            self.model.splitRight()
            self.model.splitDown()
            self.model.equalizeSplits()
            self.model.closeAllSurfaces()

            let command = "for i in {1..4000}; do echo conductor-resize-stress-$i; done\n"
            for pane in self.model.workspace.panes.values {
                guard let tab = pane.selectedTab else { continue }
                self.model.surface(for: tab).sendText(command)
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
