import AppKit
import CodexBarCore
import SwiftUI

@MainActor
public final class CodexBarEmbeddedRuntime: NSObject {
    public static let shared = CodexBarEmbeddedRuntime()

    private let updaterController = DisabledUpdaterController(
        unavailableReason: "Updates are managed by Conductor in this embedded build.")
    private let confettiOverlayController = ScreenConfettiOverlayController()
    private let confettiLogger = CodexBarLog.logger(LogCategories.confetti)
    private var preferencesSelection: PreferencesSelection?
    private var settings: SettingsStore?
    private var store: UsageStore?
    private var account: AccountInfo?
    private var managedCodexAccountCoordinator: ManagedCodexAccountCoordinator?
    private var codexAccountPromotionCoordinator: CodexAccountPromotionCoordinator?
    private var statusController: StatusItemController?
    private var settingsWindow: NSWindow?
    private var tokenRecordsWindow: NSWindow?
    private var didBootstrap = false

    public private(set) var isRunning = false

    public override init() {
        super.init()
    }

    public func start() {
        guard !isRunning else { return }
        bootstrapIfNeeded()

        applyEmbeddedPrivacyDefaults()
        KeychainAccessGate.isDisabled = UserDefaults.standard.bool(forKey: "debugDisableKeychainAccess")
        KeychainPromptCoordinator.install()
        AppNotifications.shared.requestAuthorizationOnStartup()

        let preferencesSelection = PreferencesSelection()
        let settings = SettingsStore()
        let managedCodexAccountCoordinator = ManagedCodexAccountCoordinator()
        managedCodexAccountCoordinator.onManagedAccountsDidChange = {
            _ = settings.persistResolvedCodexActiveSourceCorrectionIfNeeded()
        }
        _ = settings.persistResolvedCodexActiveSourceCorrectionIfNeeded()

        let fetcher = UsageFetcher()
        let browserDetection = BrowserDetection(cacheTTL: BrowserDetection.defaultCacheTTL)
        let account = fetcher.loadAccountInfo()
        let store = UsageStore(fetcher: fetcher, browserDetection: browserDetection, settings: settings)
        let codexAccountPromotionCoordinator = CodexAccountPromotionCoordinator(
            settingsStore: settings,
            usageStore: store,
            managedAccountCoordinator: managedCodexAccountCoordinator)

        let statusController = StatusItemController(
            store: store,
            settings: settings,
            account: account,
            updater: updaterController,
            preferencesSelection: preferencesSelection,
            managedCodexAccountCoordinator: managedCodexAccountCoordinator,
            codexAccountPromotionCoordinator: codexAccountPromotionCoordinator)
        statusController.embeddedCloseHandler = { [weak self] in
            self?.stop()
        }

        self.preferencesSelection = preferencesSelection
        self.settings = settings
        self.store = store
        self.account = account
        self.managedCodexAccountCoordinator = managedCodexAccountCoordinator
        self.codexAccountPromotionCoordinator = codexAccountPromotionCoordinator
        self.statusController = statusController
        applyHostLanguageOverride()
        installObservers()
        migrateKeychainItems()
        isRunning = true
    }

    public func stop() {
        guard isRunning || statusController != nil else { return }
        settingsWindow?.close()
        settingsWindow = nil
        tokenRecordsWindow?.close()
        tokenRecordsWindow = nil
        confettiOverlayController.dismiss()
        statusController?.releaseEmbeddedStatusItems()
        statusController = nil
        TTYCommandRunner.terminateActiveProcessesForAppShutdown()
        removeObservers()
        preferencesSelection = nil
        settings = nil
        store = nil
        account = nil
        managedCodexAccountCoordinator = nil
        codexAccountPromotionCoordinator = nil
        isRunning = false
    }

    private func bootstrapIfNeeded() {
        guard !didBootstrap else { return }
        let env = ProcessInfo.processInfo.environment
        let storedLevel = CodexBarLog.parseLevel(UserDefaults.standard.string(forKey: "debugLogLevel")) ?? .verbose
        let level = CodexBarLog.parseLevel(env["CODEXBAR_LOG_LEVEL"]) ?? storedLevel
        CodexBarLog.bootstrapIfNeeded(.init(
            destination: .oslog(subsystem: "app.conductor.codexbar"),
            level: level,
            json: false))
        didBootstrap = true
    }

    private func applyEmbeddedPrivacyDefaults() {
        guard ProcessInfo.processInfo.environment["CONDUCTOR_USAGE_ENABLE_KEYCHAIN"] != "1" else { return }
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: "debugDisableKeychainAccess")
    }

    private func installObservers() {
        removeObservers()
        let center = NotificationCenter.default
        center.addObserver(
            self,
            selector: #selector(handleOpenSettingsNotification(_:)),
            name: .codexbarOpenSettings,
            object: nil,
        )
        center.addObserver(
            self,
            selector: #selector(handleWeeklyLimitResetNotification(_:)),
            name: .codexbarWeeklyLimitReset,
            object: nil,
        )
    }

    private func removeObservers() {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func handleOpenSettingsNotification(_ notification: Notification) {
        openSettings(from: notification)
    }

    private func migrateKeychainItems() {
        Task.detached(priority: .userInitiated) {
            KeychainMigration.migrateIfNeeded()
        }
    }

    private func openSettings(from notification: Notification) {
        guard let settings,
              let store,
              let preferencesSelection,
              let managedCodexAccountCoordinator,
              let codexAccountPromotionCoordinator else {
            return
        }

        if let rawTab = notification.userInfo?["tab"] as? String,
           let tab = PreferencesTab(rawValue: rawTab) {
            preferencesSelection.tab = tab
        }

        if settingsWindow == nil {
            let rootView = PreferencesView(
                settings: settings,
                store: store,
                updater: updaterController,
                selection: preferencesSelection,
                managedCodexAccountCoordinator: managedCodexAccountCoordinator,
                codexAccountPromotionCoordinator: codexAccountPromotionCoordinator,
                runProviderLoginFlow: { [weak self] provider in
                    await self?.statusController?.runLoginFlowFromSettings(provider: provider)
                })
            let hostingController = NSHostingController(rootView: rootView)
            let size = NSSize(
                width: preferencesSelection.tab.preferredWidth,
                height: preferencesSelection.tab.preferredHeight)
            let window = NSWindow(
                contentRect: NSRect(origin: .zero, size: size),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false)
            window.title = "\(CodexBarDisplayBrand.productName) Settings"
            window.contentViewController = hostingController
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }

        settingsWindow?.setContentSize(NSSize(
            width: preferencesSelection.tab.preferredWidth,
            height: preferencesSelection.tab.preferredHeight))
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func openTokenRecordsWindow(
        style: ConductorUsagePanelStyle = .fallback,
        languageIdentifier: String? = nil)
    {
        guard let settings, let store, let statusController else { return }
        if let languageIdentifier {
            ConductorUsageFeature.configureHostLanguageIdentifier(languageIdentifier)
        }
        applyHostLanguageOverride()
        settings.costUsageEnabled = true

        let rootView = ConductorTokenRecordsWindowView(
            settings: settings,
            store: store,
            statusController: statusController,
            style: style,
            languageIdentifier: languageIdentifier)
        let hostingController = NSHostingController(rootView: rootView)
        hostingController.view.wantsLayer = true
        hostingController.view.layer?.backgroundColor = NSColor.clear.cgColor

        if let tokenRecordsWindow {
            tokenRecordsWindow.contentViewController = hostingController
            configureTokenRecordsWindow(tokenRecordsWindow, style: style)
        } else {
            let window = NSPanel(
                contentRect: NSRect(origin: .zero, size: NSSize(width: 760, height: 640)),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false)
            window.title = conductorTokenRecordsText(
                "Token 记录",
                "Token Records",
                languageIdentifier: languageIdentifier)
            window.contentViewController = hostingController
            window.isReleasedWhenClosed = false
            window.minSize = NSSize(width: 680, height: 520)
            window.center()
            configureTokenRecordsWindow(window, style: style)
            tokenRecordsWindow = window
        }

        tokenRecordsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        refreshTokenRecords()
    }

    func closeTokenRecordsWindow() {
        tokenRecordsWindow?.close()
    }

    func refreshTokenRecords() {
        guard let settings, let store else { return }
        settings.costUsageEnabled = true
        Task { @MainActor in
            await store.refreshTokenUsageNow(force: true)
        }
    }

    func openTokenRecordSettings() {
        tokenRecordsWindow?.close()
        ConductorUsageFeature.openHostSettings()
    }

    func applyHostLanguageOverride() {
        guard ConductorUsageFeature.hasHostLanguageIdentifierOverride,
              let settings
        else {
            return
        }
        let language = ConductorUsageFeature.currentHostLanguageIdentifier ?? ""
        if settings.appLanguage != language {
            settings.appLanguage = language
        }
    }

    func conductorUsageSettingsContext() -> ConductorUsageSettingsContext? {
        guard let settings,
              let store,
              let managedCodexAccountCoordinator,
              let codexAccountPromotionCoordinator
        else {
            return nil
        }
        return ConductorUsageSettingsContext(
            settings: settings,
            store: store,
            managedCodexAccountCoordinator: managedCodexAccountCoordinator,
            codexAccountPromotionCoordinator: codexAccountPromotionCoordinator,
            runProviderLoginFlow: { [weak self] provider in
                await self?.statusController?.runLoginFlowFromSettings(provider: provider)
            })
    }

    private func configureTokenRecordsWindow(_ window: NSWindow, style: ConductorUsagePanelStyle) {
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.appearance = NSAppearance(named: style.usesDarkChrome ? .darkAqua : .aqua)
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        [
            NSWindow.ButtonType.closeButton,
            .miniaturizeButton,
            .zoomButton,
        ].forEach { buttonType in
            window.standardWindowButton(buttonType)?.isHidden = true
        }
        if let panel = window as? NSPanel {
            panel.isFloatingPanel = false
            panel.becomesKeyOnlyIfNeeded = false
            panel.hidesOnDeactivate = false
        }
    }

    @objc private func handleWeeklyLimitResetNotification(_ notification: Notification) {
        guard let event = notification.object as? WeeklyLimitResetEvent else { return }
        guard settings?.confettiOnWeeklyLimitResetsEnabled == true else { return }
        let origin = statusController?.celebrationOriginPoint(for: event.provider)
        confettiLogger.info(
            "Triggering embedded confetti",
            metadata: [
                "provider": event.provider.rawValue,
                "accountIdentifier": event.accountIdentifier,
                "originKnown": origin == nil ? "0" : "1",
            ])
        confettiOverlayController.play(originInScreen: origin)
    }
}

private extension StatusItemController {
    func releaseEmbeddedStatusItems() {
        blinkTask?.cancel()
        loginTask?.cancel()
        screenChangeVisibilityTask?.cancel()
        pendingScreenChangePreviousCount = nil
        animationDriver?.stop()
        animationDriver = nil
        animationPhase = 0
        blinkForceUntil = nil
        blinkStates.removeAll(keepingCapacity: false)
        blinkAmounts.removeAll(keepingCapacity: false)
        wiggleAmounts.removeAll(keepingCapacity: false)
        tiltAmounts.removeAll(keepingCapacity: false)

        for task in menuRefreshTasks.values {
            task.cancel()
        }
        menuRefreshTasks.removeAll(keepingCapacity: false)
        openMenus.removeAll(keepingCapacity: false)
        menuProviders.removeAll(keepingCapacity: false)
        menuVersions.removeAll(keepingCapacity: false)
        providerMenus.removeAll(keepingCapacity: false)
        mergedMenu = nil
        fallbackMenu = nil

        statusItem.menu = nil
        NSStatusBar.system.removeStatusItem(statusItem)

        for item in statusItems.values {
            item.menu = nil
            NSStatusBar.system.removeStatusItem(item)
        }
        statusItems.removeAll(keepingCapacity: false)
        lastAppliedProviderIconRenderSignatures.removeAll(keepingCapacity: false)
    }
}
