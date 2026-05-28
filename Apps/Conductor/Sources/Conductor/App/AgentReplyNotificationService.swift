import AppKit
import ConductorCore
import Foundation
@preconcurrency import UserNotifications

private func L(_ zh: String, _ en: String) -> String {
    ConductorLocalization.text(zh: zh, en: en)
}

struct AgentReplyNotificationPreferences: Codable, Equatable {
    var enabled: Bool
    var onlyWhenUnattended: Bool
    var includeSummary: Bool
    var playSound: Bool

    init(
        enabled: Bool = true,
        onlyWhenUnattended: Bool = false,
        includeSummary: Bool = true,
        playSound: Bool = true
    ) {
        self.enabled = enabled
        self.onlyWhenUnattended = onlyWhenUnattended
        self.includeSummary = includeSummary
        self.playSound = playSound
    }
}

struct AgentReplyNotificationRequest: Equatable {
    let terminalID: TerminalID
    let agentTitle: String
    let body: String
    let isUnattended: Bool
}

@MainActor
final class AgentReplyNotificationService: NSObject, UNUserNotificationCenterDelegate {
    var activateTerminal: ((TerminalID) -> Void)?

    private lazy var center: UNUserNotificationCenter? = {
        guard Bundle.main.bundleURL.pathExtension == "app" else { return nil }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        return center
    }()
    private var lastDeliveredAtByTerminalID: [TerminalID: Date] = [:]
    private let minimumDeliveryInterval: TimeInterval = 3

    func requestAuthorization(completion: (@MainActor @Sendable (Bool) -> Void)? = nil) {
        guard let center = center else {
            ConductorLog.app.info("Agent reply notification skipped outside app bundle")
            ConductorDiagnostics.record("agent-notification-authorization", fields: ["status": "outside-app-bundle"])
            completion?(false)
            return
        }
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                ConductorDiagnostics.record("agent-notification-authorization", fields: ["status": "authorized"])
                Task { @MainActor in completion?(true) }
            case .denied:
                ConductorLog.app.info("Agent reply notification authorization denied")
                ConductorDiagnostics.record("agent-notification-authorization", fields: ["status": "denied"])
                Task { @MainActor in completion?(false) }
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    ConductorLog.app.info("Agent reply notification authorization requested granted=\(granted, privacy: .public)")
                    ConductorDiagnostics.record("agent-notification-authorization", fields: ["status": granted ? "granted" : "not-granted"])
                    Task { @MainActor in completion?(granted) }
                }
            @unknown default:
                ConductorLog.app.info("Agent reply notification authorization unknown status")
                ConductorDiagnostics.record("agent-notification-authorization", fields: ["status": "unknown"])
                Task { @MainActor in completion?(false) }
            }
        }
    }

    func deliver(_ request: AgentReplyNotificationRequest, preferences: AgentReplyNotificationPreferences) {
        guard preferences.enabled else {
            ConductorLog.app.info("Agent reply notification skipped because preference is disabled")
            ConductorDiagnostics.record("agent-notification-skipped", fields: ["reason": "disabled", "terminal": request.terminalID.description])
            return
        }
        guard !preferences.onlyWhenUnattended || request.isUnattended else {
            ConductorLog.app.info("Agent reply notification skipped because terminal is attended")
            ConductorDiagnostics.record("agent-notification-skipped", fields: ["reason": "attended", "terminal": request.terminalID.description])
            return
        }

        let now = Date()
        if let lastDeliveredAt = lastDeliveredAtByTerminalID[request.terminalID],
           now.timeIntervalSince(lastDeliveredAt) < minimumDeliveryInterval {
            ConductorLog.app.info("Agent reply notification skipped by debounce")
            ConductorDiagnostics.record("agent-notification-skipped", fields: ["reason": "debounce", "terminal": request.terminalID.description])
            return
        }
        lastDeliveredAtByTerminalID[request.terminalID] = now

        let content = UNMutableNotificationContent()
        content.title = L("\(request.agentTitle) 已回复", "\(request.agentTitle) replied")
        content.body = notificationBody(for: request, includeSummary: preferences.includeSummary)
        content.sound = preferences.playSound ? .default : nil
        content.userInfo = [
            "kind": "agent-reply",
            "terminalID": request.terminalID.description
        ]

        let notificationID = "agent-reply-\(request.terminalID.description)-\(UUID().uuidString)"
        let notificationRequest = UNNotificationRequest(
            identifier: notificationID,
            content: content,
            trigger: nil
        )

        requestAuthorization { [center] granted in
            guard granted, let center else {
                ConductorLog.app.info("Agent reply notification skipped because notification permission is unavailable")
                ConductorDiagnostics.record("agent-notification-skipped", fields: ["reason": "permission", "terminal": request.terminalID.description])
                NSApp.requestUserAttention(.informationalRequest)
                return
            }
            center.add(notificationRequest) { error in
                if let error {
                    ConductorLog.app.warning("Agent reply notification failed: \(error.localizedDescription, privacy: .public)")
                    ConductorDiagnostics.record("agent-notification-failed", fields: ["error": error.localizedDescription, "terminal": request.terminalID.description])
                } else {
                    ConductorLog.app.info("Agent reply notification delivered terminal=\(request.terminalID.description, privacy: .public)")
                    ConductorDiagnostics.record("agent-notification-delivered", fields: ["terminal": request.terminalID.description])
                }
            }
        }
    }

    private func notificationBody(
        for request: AgentReplyNotificationRequest,
        includeSummary: Bool
    ) -> String {
        let fallback = L("终端任务已完成，等待下一步。", "The terminal task is complete and waiting for the next step.")
        guard includeSummary else { return fallback }
        let trimmed = request.body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return fallback }
        return String(trimmed.prefix(240))
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let terminalIDString = userInfo["terminalID"] as? String
        completionHandler()
        Task { @MainActor [weak self] in
            guard let self,
                  let terminalIDString,
                  let uuid = UUID(uuidString: terminalIDString) else {
                return
            }
            self.activateTerminal?(TerminalID(uuid))
        }
    }
}
