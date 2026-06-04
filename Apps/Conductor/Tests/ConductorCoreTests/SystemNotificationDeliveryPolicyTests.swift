import ConductorCore
import Testing

@Test func systemNotificationPolicyDeliversWhenAuthorizedInAppBundle() {
    let action = ConductorSystemNotificationDeliveryPolicy.action(
        authorizationState: .authorized,
        launchSupportsSystemNotifications: true,
        unavailableMessage: "unavailable"
    )

    #expect(action == .deliver)
}

@Test func systemNotificationPolicyRequestsAuthorizationWhenNotDetermined() {
    let action = ConductorSystemNotificationDeliveryPolicy.action(
        authorizationState: .notDetermined,
        launchSupportsSystemNotifications: true,
        unavailableMessage: "unavailable"
    )

    #expect(action == .requestAuthorization)
}

@Test func systemNotificationPolicyExplainsUnsupportedLaunchBeforePermissionState() {
    let action = ConductorSystemNotificationDeliveryPolicy.action(
        authorizationState: .authorized,
        launchSupportsSystemNotifications: false,
        unavailableMessage: "debug launch cannot show banners"
    )

    guard case .unavailable(let result) = action else {
        Issue.record("Expected unsupported launch to return an unavailable result.")
        return
    }
    #expect(result.status == .permissionUnavailable)
    #expect(result.authorizationState == .unavailable)
    #expect(result.launchSupportsSystemNotifications == false)
    #expect(result.addedToNotificationCenter == false)
    #expect(result.errorMessage == "debug launch cannot show banners")
}

@Test(arguments: [
    ConductorSystemNotificationAuthorizationState.denied,
    .unavailable,
    .unknown
])
func systemNotificationPolicyExplainsUnavailablePermissionStates(
    state: ConductorSystemNotificationAuthorizationState
) {
    let action = ConductorSystemNotificationDeliveryPolicy.action(
        authorizationState: state,
        launchSupportsSystemNotifications: true,
        unavailableMessage: "permission blocked"
    )

    guard case .unavailable(let result) = action else {
        Issue.record("Expected unavailable result for \(state).")
        return
    }
    #expect(result.status == .permissionUnavailable)
    #expect(result.authorizationState == state)
    #expect(result.launchSupportsSystemNotifications == true)
    #expect(result.addedToNotificationCenter == false)
    #expect(result.errorMessage == "permission blocked")
}

@Test func systemNotificationPolicyTreatsDeniedAuthorizationRequestAsDenied() {
    let result = ConductorSystemNotificationDeliveryPolicy.authorizationRequestResult(
        granted: false,
        errorMessage: nil,
        deniedMessage: "user denied"
    )

    #expect(result?.status == .permissionUnavailable)
    #expect(result?.authorizationState == .denied)
    #expect(result?.launchSupportsSystemNotifications == true)
    #expect(result?.addedToNotificationCenter == false)
    #expect(result?.errorMessage == "user denied")
}

@Test func systemNotificationPolicyTreatsFailedAuthorizationRequestAsUnknown() {
    let result = ConductorSystemNotificationDeliveryPolicy.authorizationRequestResult(
        granted: false,
        errorMessage: "request failed",
        deniedMessage: "user denied"
    )

    #expect(result?.status == .permissionUnavailable)
    #expect(result?.authorizationState == .unknown)
    #expect(result?.launchSupportsSystemNotifications == true)
    #expect(result?.addedToNotificationCenter == false)
    #expect(result?.errorMessage == "request failed")
}

@Test func systemNotificationPolicyReturnsNoResultWhenAuthorizationRequestSucceeds() {
    let result = ConductorSystemNotificationDeliveryPolicy.authorizationRequestResult(
        granted: true,
        errorMessage: nil,
        deniedMessage: "user denied"
    )

    #expect(result == nil)
}

@Test func systemNotificationPolicyReportsDeliverySuccess() {
    let result = ConductorSystemNotificationDeliveryPolicy.deliveryResult(
        authorizationState: .authorized,
        errorMessage: nil
    )

    #expect(result.status == .delivered)
    #expect(result.authorizationState == .authorized)
    #expect(result.launchSupportsSystemNotifications == true)
    #expect(result.addedToNotificationCenter == true)
    #expect(result.errorMessage == nil)
}

@Test func systemNotificationPolicyReportsDeliveryFailure() {
    let result = ConductorSystemNotificationDeliveryPolicy.deliveryResult(
        authorizationState: .authorized,
        errorMessage: "Notification Center rejected request"
    )

    #expect(result.status == .deliveryFailed)
    #expect(result.authorizationState == .authorized)
    #expect(result.launchSupportsSystemNotifications == true)
    #expect(result.addedToNotificationCenter == false)
    #expect(result.errorMessage == "Notification Center rejected request")
}
