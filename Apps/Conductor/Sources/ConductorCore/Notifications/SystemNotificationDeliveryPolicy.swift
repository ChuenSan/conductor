import Foundation

public enum ConductorSystemNotificationAuthorizationState: String, Codable, Equatable, Sendable, CaseIterable {
    case unavailable
    case authorized
    case denied
    case notDetermined = "not-determined"
    case unknown

    public var diagnosticValue: String {
        rawValue
    }
}

public struct ConductorSystemNotificationTestResult: Codable, Equatable, Sendable {
    public enum Status: String, Codable, Equatable, Sendable {
        case delivered
        case permissionUnavailable = "permission_unavailable"
        case deliveryFailed = "delivery_failed"
    }

    public let status: Status
    public let authorizationState: ConductorSystemNotificationAuthorizationState
    public let launchSupportsSystemNotifications: Bool
    public let addedToNotificationCenter: Bool
    public let errorMessage: String?

    public init(
        status: Status,
        authorizationState: ConductorSystemNotificationAuthorizationState,
        launchSupportsSystemNotifications: Bool,
        addedToNotificationCenter: Bool,
        errorMessage: String?
    ) {
        self.status = status
        self.authorizationState = authorizationState
        self.launchSupportsSystemNotifications = launchSupportsSystemNotifications
        self.addedToNotificationCenter = addedToNotificationCenter
        self.errorMessage = errorMessage
    }
}

public enum ConductorSystemNotificationPermissionAction: Equatable, Sendable {
    case deliver
    case requestAuthorization
    case unavailable(ConductorSystemNotificationTestResult)
}

public enum ConductorSystemNotificationDeliveryPolicy {
    public static func action(
        authorizationState: ConductorSystemNotificationAuthorizationState,
        launchSupportsSystemNotifications: Bool,
        unavailableMessage: String
    ) -> ConductorSystemNotificationPermissionAction {
        guard launchSupportsSystemNotifications else {
            return .unavailable(ConductorSystemNotificationTestResult(
                status: .permissionUnavailable,
                authorizationState: .unavailable,
                launchSupportsSystemNotifications: false,
                addedToNotificationCenter: false,
                errorMessage: unavailableMessage
            ))
        }

        switch authorizationState {
        case .authorized:
            return .deliver
        case .notDetermined:
            return .requestAuthorization
        case .denied, .unavailable, .unknown:
            return .unavailable(ConductorSystemNotificationTestResult(
                status: .permissionUnavailable,
                authorizationState: authorizationState,
                launchSupportsSystemNotifications: true,
                addedToNotificationCenter: false,
                errorMessage: unavailableMessage
            ))
        }
    }

    public static func authorizationRequestResult(
        granted: Bool,
        errorMessage: String?,
        deniedMessage: String
    ) -> ConductorSystemNotificationTestResult? {
        guard !granted else { return nil }
        return ConductorSystemNotificationTestResult(
            status: .permissionUnavailable,
            authorizationState: errorMessage == nil ? .denied : .unknown,
            launchSupportsSystemNotifications: true,
            addedToNotificationCenter: false,
            errorMessage: errorMessage ?? deniedMessage
        )
    }

    public static func deliveryResult(
        authorizationState: ConductorSystemNotificationAuthorizationState,
        errorMessage: String?
    ) -> ConductorSystemNotificationTestResult {
        if let errorMessage, !errorMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return ConductorSystemNotificationTestResult(
                status: .deliveryFailed,
                authorizationState: authorizationState,
                launchSupportsSystemNotifications: true,
                addedToNotificationCenter: false,
                errorMessage: errorMessage
            )
        }

        return ConductorSystemNotificationTestResult(
            status: .delivered,
            authorizationState: authorizationState,
            launchSupportsSystemNotifications: true,
            addedToNotificationCenter: true,
            errorMessage: nil
        )
    }
}
