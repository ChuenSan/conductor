import AppKit
import ConductorCore

@MainActor
enum CopilotLoginFlow {
    struct AccountResult {
        let label: String
        let token: String
        let externalIdentifier: String?
        let matchedAccountID: UUID?
    }

    static func run(
        enterpriseHost: String?,
        existingAccounts: [UsageProviderTokenAccount]) async -> AccountResult?
    {
        let flow = CopilotDeviceFlow(enterpriseHost: enterpriseHost)
        do {
            let code = try await flow.requestDeviceCode()
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(code.userCode, forType: .string)

            let alert = NSAlert()
            alert.messageText = L("GitHub Copilot 登录")
            alert.informativeText = L("已复制代码 %@。在浏览器打开 %@ 完成授权。", code.userCode, code.verificationUri)
            alert.addButton(withTitle: L("打开浏览器"))
            alert.addButton(withTitle: L("取消"))
            guard alert.runModal() != .alertSecondButtonReturn else { return nil }

            if let url = URL(string: code.verificationURLToOpen) {
                NSWorkspace.shared.open(url)
            }

            let waitingAlert = NSAlert()
            waitingAlert.messageText = L("等待 GitHub 授权")
            waitingAlert.informativeText = L("请在浏览器完成授权。完成后 Conductor 会自动保存账号。")
            waitingAlert.addButton(withTitle: L("取消"))
            let parentWindow = resolveWaitingParentWindow()
            let hostWindow = parentWindow ?? makeWaitingHostWindow()
            let shouldCloseHostWindow = parentWindow == nil

            let tokenTask = Task.detached(priority: .userInitiated) {
                try await flow.pollForToken(deviceCode: code.deviceCode, interval: code.interval)
            }
            let waitTask = Task { @MainActor in
                let response = await presentWaitingAlert(waitingAlert, parentWindow: hostWindow)
                if response == .alertFirstButtonReturn {
                    tokenTask.cancel()
                }
                return response
            }

            let tokenResult: Result<String, Error>
            do {
                tokenResult = .success(try await tokenTask.value)
            } catch {
                tokenResult = .failure(error)
            }

            dismissWaitingAlert(waitingAlert, parentWindow: hostWindow, closeHost: shouldCloseHostWindow)
            if await waitTask.value == .alertFirstButtonReturn {
                return nil
            }

            switch tokenResult {
            case let .success(token):
                return await accountResult(
                    token: token,
                    enterpriseHost: enterpriseHost,
                    existingAccounts: existingAccounts)
            case let .failure(error):
                guard !(error is CancellationError) else { return nil }
                showError(title: L("登录失败"), message: error.localizedDescription)
                return nil
            }
        } catch {
            showError(title: L("登录失败"), message: error.localizedDescription)
            return nil
        }
    }

    private static func accountResult(
        token: String,
        enterpriseHost: String?,
        existingAccounts: [UsageProviderTokenAccount]) async -> AccountResult?
    {
        let identity: CopilotUsageFetcher.GitHubUserIdentity?
        let label: String
        do {
            let resolvedIdentity = try await CopilotUsageFetcher.fetchGitHubIdentity(token: token)
            identity = resolvedIdentity
            let planSuffix: String
            do {
                let usage = try await CopilotUsageFetcher.fetchTokenUsage(
                    token: token,
                    enterpriseHost: enterpriseHost)
                planSuffix = usage.planName.map { " (\($0))" } ?? ""
            } catch {
                planSuffix = ""
            }
            label = "\(resolvedIdentity.login)\(planSuffix)"
        } catch {
            guard existingAccounts.isEmpty else {
                showError(
                    title: L("无法识别 GitHub 账号"),
                    message: L("GitHub 登录成功，但无法确认对应账号。请重试。"))
                return nil
            }
            identity = nil
            label = L("账号 1")
        }

        let matched = await matchExistingAccount(
            existingAccounts: existingAccounts,
            identity: identity,
            label: label)
        return AccountResult(
            label: label,
            token: token,
            externalIdentifier: identity.map(externalIdentifier),
            matchedAccountID: matched?.id)
    }

    private static func matchExistingAccount(
        existingAccounts: [UsageProviderTokenAccount],
        identity: CopilotUsageFetcher.GitHubUserIdentity?,
        label: String,
        legacyIdentityResolver: @escaping @Sendable (UsageProviderTokenAccount) async
            -> CopilotUsageFetcher.GitHubUserIdentity? = { account in
                try? await CopilotUsageFetcher.fetchGitHubIdentity(token: account.token)
            }) async -> UsageProviderTokenAccount?
    {
        guard let identity, !existingAccounts.isEmpty else { return nil }
        let stableIdentifier = externalIdentifier(for: identity)
        let login = normalizedGitHubLogin(identity.login)

        if let byID = existingAccounts.first(where: {
            normalizedExternalIdentifier($0.externalIdentifier) == stableIdentifier
        }) {
            return byID
        }
        if let byLegacyLogin = existingAccounts.first(where: {
            normalizedGitHubLogin($0.externalIdentifier) == login
        }) {
            return byLegacyLogin
        }

        let legacyAccounts = existingAccounts.filter { $0.externalIdentifier == nil }
        for account in legacyAccounts {
            guard let resolved = await legacyIdentityResolver(account) else { continue }
            if resolved.id == identity.id || normalizedGitHubLogin(resolved.login) == login {
                return account
            }
        }

        let usernamePrefix = displayLabelPrefix(label)
        return legacyAccounts.first { displayLabelPrefix($0.label) == usernamePrefix }
    }

    private static func externalIdentifier(for identity: CopilotUsageFetcher.GitHubUserIdentity) -> String {
        "github:user:\(identity.id)"
    }

    private static func normalizedExternalIdentifier(_ identifier: String?) -> String? {
        let trimmed = identifier?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed.lowercased()
    }

    private static func normalizedGitHubLogin(_ login: String?) -> String? {
        let trimmed = login?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty, !trimmed.lowercased().hasPrefix("github:user:") else { return nil }
        return trimmed.lowercased()
    }

    private static func displayLabelPrefix(_ label: String) -> String {
        (label.components(separatedBy: " (").first ?? label)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private static func presentWaitingAlert(
        _ alert: NSAlert,
        parentWindow: NSWindow) async -> NSApplication.ModalResponse
    {
        await withCheckedContinuation { continuation in
            alert.beginSheetModal(for: parentWindow) { response in
                continuation.resume(returning: response)
            }
        }
    }

    private static func dismissWaitingAlert(_ alert: NSAlert, parentWindow: NSWindow, closeHost: Bool) {
        let alertWindow = alert.window
        if alertWindow.sheetParent != nil {
            parentWindow.endSheet(alertWindow)
        } else {
            alertWindow.orderOut(nil)
        }
        guard closeHost else { return }
        parentWindow.orderOut(nil)
        parentWindow.close()
    }

    private static func resolveWaitingParentWindow() -> NSWindow? {
        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            return window
        }
        if let window = NSApp.windows.first(where: { $0.isVisible && !$0.ignoresMouseEvents }) {
            return window
        }
        return NSApp.windows.first
    }

    private static func makeWaitingHostWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 1),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false)
        window.isReleasedWhenClosed = false
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.center()
        window.makeKeyAndOrderFront(nil)
        return window
    }

    private static func showError(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }
}
