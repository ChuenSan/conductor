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
    let attentionEventID: UUID
    let terminalID: TerminalID
    let agentTitle: String
    let body: String
    let isUnattended: Bool
}

struct TerminalAttentionNotificationRequest: Equatable {
    let attentionEventID: UUID
    let terminalID: TerminalID
    let kind: ConductorAttentionEvent.Kind
    let title: String
    let body: String
    let isUnattended: Bool
}

typealias AgentReplyNotificationAuthorizationState = ConductorSystemNotificationAuthorizationState

enum AgentReplyNotificationDeliveryIssue: Equatable {
    case permissionUnavailable
    case deliveryFailed(String)
}

typealias AgentReplyNotificationTestResult = ConductorSystemNotificationTestResult

@MainActor
final class AgentReplyNotificationService: NSObject, UNUserNotificationCenterDelegate {
    var activateNotificationTarget: ((UUID?, TerminalID?) -> Void)?
    var deliveryIssueHandler: ((AgentReplyNotificationDeliveryIssue) -> Void)?

    private lazy var center: UNUserNotificationCenter? = {
        guard Bundle.main.bundleURL.pathExtension == "app" else { return nil }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        return center
    }()
    private var lastDeliveredAtByTerminalID: [TerminalID: Date] = [:]
    private var lastDeliveredAtByTerminalAttentionKey: [String: Date] = [:]
    private let minimumDeliveryInterval: TimeInterval = 3

    func checkAuthorizationStatus(completion: @MainActor @Sendable @escaping (AgentReplyNotificationAuthorizationState) -> Void) {
        guard let center else {
            ConductorDiagnostics.record("agent-notification-authorization", fields: ["status": "outside-app-bundle"])
            completion(.unavailable)
            return
        }
        center.getNotificationSettings { settings in
            let state: AgentReplyNotificationAuthorizationState
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                state = .authorized
            case .denied:
                state = .denied
            case .notDetermined:
                state = .notDetermined
            @unknown default:
                state = .unknown
            }
            ConductorDiagnostics.record("agent-notification-authorization-check", fields: ["status": state.diagnosticValue])
            Task { @MainActor in completion(state) }
        }
    }

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

    func sendTestNotification(
        title: String,
        body: String,
        playSound: Bool,
        completion: @MainActor @Sendable @escaping (AgentReplyNotificationTestResult) -> Void
    ) {
        guard let center else {
            ConductorDiagnostics.record("notification-test-skipped", fields: ["reason": "outside-app-bundle"])
            if case .unavailable(let result) = Self.notificationPermissionAction(
                state: .unavailable,
                launchSupportsSystemNotifications: false
            ) {
                completion(result)
            }
            return
        }

        center.getNotificationSettings { [weak self, center] settings in
            Task { @MainActor in
                guard let self else { return }
                let state = Self.authorizationState(from: settings.authorizationStatus)
                switch Self.notificationPermissionAction(
                    state: state,
                    launchSupportsSystemNotifications: true
                ) {
                case .deliver:
                    self.addTestNotification(
                        center: center,
                        title: title,
                        body: body,
                        playSound: playSound,
                        authorizationState: state,
                        completion: completion
                    )
                case .requestAuthorization:
                    Task { @MainActor [weak self, center] in
                        guard let self else { return }
                        do {
                            let granted = try await center.requestAuthorization(options: [.alert, .sound])
                            if granted {
                                ConductorDiagnostics.record("notification-test-authorization", fields: ["status": "granted"])
                                self.addTestNotification(
                                    center: center,
                                    title: title,
                                    body: body,
                                    playSound: playSound,
                                    authorizationState: .authorized,
                                    completion: completion
                                )
                                return
                            }
                            ConductorDiagnostics.record("notification-test-skipped", fields: ["reason": "permission", "status": "not-granted"])
                            completion(Self.authorizationRequestResult(granted: false, errorMessage: nil))
                        } catch {
                            ConductorDiagnostics.record("notification-test-skipped", fields: ["reason": "permission", "status": "request-failed"])
                            completion(Self.authorizationRequestResult(granted: false, errorMessage: error.localizedDescription))
                        }
                    }
                case .unavailable(let result):
                    ConductorDiagnostics.record("notification-test-skipped", fields: ["reason": "permission", "status": state.diagnosticValue])
                    completion(result)
                }
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
            "attentionEventID": request.attentionEventID.uuidString,
            "terminalID": request.terminalID.description
        ]

        let notificationID = "agent-reply-\(request.terminalID.description)-\(UUID().uuidString)"
        let notificationRequest = UNNotificationRequest(
            identifier: notificationID,
            content: content,
            trigger: nil
        )

        requestAuthorization { [weak self, center] granted in
            guard let self else { return }
            guard granted, let center else {
                ConductorLog.app.info("Agent reply notification skipped because notification permission is unavailable")
                ConductorDiagnostics.record("agent-notification-skipped", fields: ["reason": "permission", "terminal": request.terminalID.description])
                self.deliveryIssueHandler?(.permissionUnavailable)
                NSApp.requestUserAttention(.informationalRequest)
                return
            }
            center.add(notificationRequest) { [weak self] error in
                if let error {
                    ConductorLog.app.warning("Agent reply notification failed: \(error.localizedDescription, privacy: .public)")
                    ConductorDiagnostics.record("agent-notification-failed", fields: ["error": error.localizedDescription, "terminal": request.terminalID.description])
                    Task { @MainActor in
                        self?.deliveryIssueHandler?(.deliveryFailed(error.localizedDescription))
                    }
                } else {
                    ConductorLog.app.info("Agent reply notification delivered terminal=\(request.terminalID.description, privacy: .public)")
                    ConductorDiagnostics.record("agent-notification-delivered", fields: ["terminal": request.terminalID.description])
                }
            }
        }
    }

    func deliverTerminalAttention(
        _ request: TerminalAttentionNotificationRequest,
        preferences: AgentReplyNotificationPreferences
    ) {
        guard preferences.enabled else {
            ConductorLog.app.info("Terminal attention notification skipped because preference is disabled")
            ConductorDiagnostics.record(
                "terminal-attention-notification-skipped",
                fields: ["reason": "disabled", "terminal": request.terminalID.description, "kind": request.kind.rawValue]
            )
            return
        }
        guard !preferences.onlyWhenUnattended || request.isUnattended else {
            ConductorLog.app.info("Terminal attention notification skipped because terminal is attended")
            ConductorDiagnostics.record(
                "terminal-attention-notification-skipped",
                fields: ["reason": "attended", "terminal": request.terminalID.description, "kind": request.kind.rawValue]
            )
            return
        }

        let now = Date()
        let deliveryKey = "\(request.kind.rawValue)-\(request.terminalID.description)"
        if let lastDeliveredAt = lastDeliveredAtByTerminalAttentionKey[deliveryKey],
           now.timeIntervalSince(lastDeliveredAt) < minimumDeliveryInterval {
            ConductorLog.app.info("Terminal attention notification skipped by debounce")
            ConductorDiagnostics.record(
                "terminal-attention-notification-skipped",
                fields: ["reason": "debounce", "terminal": request.terminalID.description, "kind": request.kind.rawValue]
            )
            return
        }
        lastDeliveredAtByTerminalAttentionKey[deliveryKey] = now

        let content = UNMutableNotificationContent()
        content.title = request.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? L("终端提醒", "Terminal Alert")
            : request.title
        content.body = terminalAttentionBody(for: request, includeSummary: preferences.includeSummary)
        content.sound = preferences.playSound ? .default : nil
        content.userInfo = [
            "kind": request.kind.rawValue,
            "attentionEventID": request.attentionEventID.uuidString,
            "terminalID": request.terminalID.description
        ]

        let notificationID = "terminal-attention-\(request.kind.rawValue)-\(request.terminalID.description)-\(UUID().uuidString)"
        let notificationRequest = UNNotificationRequest(
            identifier: notificationID,
            content: content,
            trigger: nil
        )

        requestAuthorization { [weak self, center] granted in
            guard let self else { return }
            guard granted, let center else {
                ConductorLog.app.info("Terminal attention notification skipped because notification permission is unavailable")
                ConductorDiagnostics.record(
                    "terminal-attention-notification-skipped",
                    fields: ["reason": "permission", "terminal": request.terminalID.description, "kind": request.kind.rawValue]
                )
                self.deliveryIssueHandler?(.permissionUnavailable)
                NSApp.requestUserAttention(.informationalRequest)
                return
            }
            center.add(notificationRequest) { [weak self] error in
                if let error {
                    ConductorLog.app.warning("Terminal attention notification failed: \(error.localizedDescription, privacy: .public)")
                    ConductorDiagnostics.record(
                        "terminal-attention-notification-failed",
                        fields: ["error": error.localizedDescription, "terminal": request.terminalID.description, "kind": request.kind.rawValue]
                    )
                    Task { @MainActor in
                        self?.deliveryIssueHandler?(.deliveryFailed(error.localizedDescription))
                    }
                } else {
                    ConductorLog.app.info(
                        "Terminal attention notification delivered kind=\(request.kind.rawValue, privacy: .public) terminal=\(request.terminalID.description, privacy: .public)"
                    )
                    ConductorDiagnostics.record(
                        "terminal-attention-notification-delivered",
                        fields: ["terminal": request.terminalID.description, "kind": request.kind.rawValue]
                    )
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

    private func terminalAttentionBody(
        for request: TerminalAttentionNotificationRequest,
        includeSummary: Bool
    ) -> String {
        let fallback: String
        switch request.kind {
        case .commandFinished:
            fallback = L("后台终端命令已完成。", "A background terminal command finished.")
        case .terminalBell:
            fallback = L("终端发送了一条提醒。", "The terminal sent an alert.")
        default:
            fallback = L("终端需要你的注意。", "The terminal needs your attention.")
        }
        guard includeSummary else { return fallback }
        let trimmed = request.body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return fallback }
        return String(trimmed.prefix(240))
    }

    private func addTestNotification(
        center: UNUserNotificationCenter,
        title: String,
        body: String,
        playSound: Bool,
        authorizationState: AgentReplyNotificationAuthorizationState,
        completion: @MainActor @Sendable @escaping (AgentReplyNotificationTestResult) -> Void
    ) {
        let content = UNMutableNotificationContent()
        content.title = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? L("Conductor 测试通知", "Conductor Test Notification")
            : title
        content.body = body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? L("如果你看到这条横幅，系统通知投递正常。", "If you see this banner, system notification delivery is working.")
            : body
        content.sound = playSound ? .default : nil
        content.userInfo = ["kind": "notification-test"]
        let request = UNNotificationRequest(
            identifier: "notification-test-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        center.add(request) { error in
            if let error {
                ConductorDiagnostics.record("notification-test-failed", fields: ["error": error.localizedDescription])
                Task { @MainActor in
                    completion(ConductorSystemNotificationDeliveryPolicy.deliveryResult(
                        authorizationState: authorizationState,
                        errorMessage: error.localizedDescription
                    ))
                }
            } else {
                ConductorDiagnostics.record("notification-test-delivered", fields: ["status": authorizationState.diagnosticValue])
                Task { @MainActor in
                    completion(ConductorSystemNotificationDeliveryPolicy.deliveryResult(
                        authorizationState: authorizationState,
                        errorMessage: nil
                    ))
                }
            }
        }
    }

    private static func authorizationState(
        from status: UNAuthorizationStatus
    ) -> AgentReplyNotificationAuthorizationState {
        switch status {
        case .authorized, .provisional, .ephemeral:
            .authorized
        case .denied:
            .denied
        case .notDetermined:
            .notDetermined
        @unknown default:
            .unknown
        }
    }

    private static func permissionUnavailableMessage(
        for state: AgentReplyNotificationAuthorizationState
    ) -> String {
        switch state {
        case .denied:
            L("macOS 已拒绝通知权限，请在系统设置里允许 Conductor。", "macOS denied notification permission. Enable Conductor in System Settings.")
        case .unavailable:
            L("当前启动方式无法使用系统通知，请从 Conductor.app 启动。", "System notifications are unavailable in this launch mode. Start from Conductor.app.")
        case .unknown:
            L("暂时无法确认系统通知权限。", "Could not confirm system notification permission.")
        case .notDetermined:
            L("尚未请求系统通知权限。", "System notification permission has not been requested.")
        case .authorized:
            ""
        }
    }

    private static func notificationPermissionAction(
        state: AgentReplyNotificationAuthorizationState,
        launchSupportsSystemNotifications: Bool
    ) -> ConductorSystemNotificationPermissionAction {
        ConductorSystemNotificationDeliveryPolicy.action(
            authorizationState: state,
            launchSupportsSystemNotifications: launchSupportsSystemNotifications,
            unavailableMessage: permissionUnavailableMessage(for: state)
        )
    }

    private static func authorizationRequestResult(
        granted: Bool,
        errorMessage: String?
    ) -> AgentReplyNotificationTestResult {
        ConductorSystemNotificationDeliveryPolicy.authorizationRequestResult(
            granted: granted,
            errorMessage: errorMessage,
            deniedMessage: L(
                "macOS 没有授予通知权限。",
                "macOS did not grant notification permission."
            )
        ) ?? ConductorSystemNotificationDeliveryPolicy.deliveryResult(
            authorizationState: .authorized,
            errorMessage: nil
        )
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
        let attentionEventIDString = userInfo["attentionEventID"] as? String
        let terminalIDString = userInfo["terminalID"] as? String
        let attentionEventID = attentionEventIDString.flatMap(UUID.init(uuidString:))
        let terminalID = terminalIDString
            .flatMap { UUID(uuidString: $0) }
            .map(TerminalID.init)
        completionHandler()
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            ConductorDiagnostics.record(
                "agent-notification-response",
                fields: [
                    "attentionEvent": attentionEventID?.uuidString ?? "none",
                    "terminal": terminalID?.description ?? "none"
                ]
            )
            self.activateNotificationTarget?(attentionEventID, terminalID)
        }
    }
}
