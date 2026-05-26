import AppKit

extension StatusItemController {
    func usesPersistentMenuActionItem(for action: MenuDescriptor.MenuAction) -> Bool {
        #if CONDUCTOR_EMBEDDED
        switch action {
        case .settings, .about, .quit:
            false
        default:
            true
        }
        #else
        switch action {
        case .settings:
            true
        case .installUpdate, .refresh, .about, .quit:
            true
        default:
            false
        }
        #endif
    }

    func persistentMenuActionSystemImageName(for action: MenuDescriptor.MenuAction) -> String? {
        switch action {
        case .installUpdate:
            "arrow.down.circle"
        case .refresh:
            MenuDescriptor.MenuActionSystemImage.refresh.rawValue
        case .settings:
            MenuDescriptor.MenuActionSystemImage.settings.rawValue
        case .about:
            MenuDescriptor.MenuActionSystemImage.about.rawValue
        case .quit:
            MenuDescriptor.MenuActionSystemImage.quit.rawValue
        default:
            action.systemImageName
        }
    }

    func performPersistentMenuAction(_ action: MenuDescriptor.MenuAction, in menu: NSMenu?) {
        switch action {
        case .refresh:
            self.refreshNow()
        case .refreshAugmentSession:
            self.refreshAugmentSession()
        case .installUpdate:
            self.closeMenuForPersistentAction(menu)
            self.installUpdate()
        case .dashboard:
            self.closeMenuForPersistentAction(menu)
            self.openDashboard()
        case .statusPage:
            self.closeMenuForPersistentAction(menu)
            self.openStatusPage()
        case .changelog:
            self.closeMenuForPersistentAction(menu)
            self.openChangelog()
        case .addCodexAccount:
            self.closeMenuForPersistentAction(menu)
            self.addManagedCodexAccountFromMenu(NSMenuItem())
        case let .addProviderAccount(provider), let .switchAccount(provider):
            self.closeMenuForPersistentAction(menu)
            let item = NSMenuItem()
            item.representedObject = provider.rawValue
            self.runSwitchAccount(item)
        case let .requestCodexSystemPromotion(managedAccountID):
            self.closeMenuForPersistentAction(menu)
            let item = NSMenuItem()
            item.representedObject = managedAccountID.uuidString
            self.requestCodexSystemPromotionFromMenu(item)
        case let .openTerminal(command):
            self.closeMenuForPersistentAction(menu)
            let item = NSMenuItem()
            item.representedObject = command
            self.openTerminalCommand(item)
        case let .loginToProvider(url):
            self.closeMenuForPersistentAction(menu)
            let item = NSMenuItem()
            item.representedObject = url
            self.openLoginToProvider(item)
        case .settings:
            self.closeMenuForPersistentAction(menu)
            self.showSettingsGeneral()
        case .about:
            self.closeMenuForPersistentAction(menu)
            self.showSettingsAbout()
        case .quit:
            self.closeMenuForPersistentAction(menu)
            self.quit()
        case let .copyError(message):
            let item = NSMenuItem()
            item.representedObject = message
            self.copyError(item)
        }
    }

    private func closeMenuForPersistentAction(_ menu: NSMenu?) {
        guard let menu else { return }
        menu.cancelTrackingWithoutAnimation()
        self.forgetClosedMenu(menu)
    }
}
