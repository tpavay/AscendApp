import Foundation
@preconcurrency import FirebaseFunctions
import UserNotifications

@MainActor
final class LifecycleEventRecorder {
    static let shared = LifecycleEventRecorder()

    private let functions = Functions.functions(region: "us-central1")

    private init() {}

    func recordRatingPromptAnswered(response: String) {
        record(
            type: "rating_prompt_answered",
            payload: ["response": response]
        )
    }

    func recordAppStoreReviewRequested(reason: String) {
        record(
            type: "app_store_review_requested",
            payload: ["reason": reason]
        )
    }

    func recordOnboardingStageReached(
        stage: String,
        completedStages: [String]
    ) {
        record(
            type: "onboarding_stage_reached",
            payload: [
                "stage": stage,
                "completedStages": completedStages
            ]
        )
    }

    func recordOnboardingCompleted(
        currentStage: String,
        completedStages: [String]
    ) {
        record(
            type: "onboarding_completed",
            payload: [
                "currentStage": currentStage,
                "completedStages": completedStages
            ]
        )
    }

    func recordPaywallReached(placement: String) {
        recordPaywallEvent(type: "paywall_reached", placement: placement)
    }

    func recordPaywallShown(placement: String) {
        recordPaywallEvent(type: "paywall_shown", placement: placement)
    }

    func recordPaywallDismissed(placement: String, reason: String? = nil) {
        recordPaywallEvent(
            type: "paywall_dismissed",
            placement: placement,
            reason: reason
        )
    }

    func recordNotificationPermission(status: UNAuthorizationStatus) {
        record(
            type: "notification_permission_observed",
            payload: ["status": status.lifecycleStatusRawValue]
        )
    }

    func recordNotificationPermission(status: String) {
        record(
            type: "notification_permission_observed",
            payload: ["status": status]
        )
    }

    func recordAppleHealthIntegration(
        state: AppleHealthConnectionState,
        autoImportEnabled: Bool
    ) {
        record(
            type: "apple_health_integration_changed",
            payload: [
                "status": state.lifecycleStatusRawValue,
                "autoImportEnabled": autoImportEnabled
            ]
        )
    }

    func recordCommunicationPreferences(
        lifecycleEmailsEnabled: Bool? = nil,
        productUpdatesEnabled: Bool? = nil,
        climbDropEmailsEnabled: Bool? = nil
    ) {
        var payload: [String: Any] = [:]
        if let lifecycleEmailsEnabled {
            payload["lifecycleEmailsEnabled"] = lifecycleEmailsEnabled
        }
        if let productUpdatesEnabled {
            payload["productUpdatesEnabled"] = productUpdatesEnabled
        }
        if let climbDropEmailsEnabled {
            payload["climbDropEmailsEnabled"] = climbDropEmailsEnabled
        }
        guard !payload.isEmpty else { return }

        record(type: "communication_preferences_updated", payload: payload)
    }

    private func recordPaywallEvent(
        type: String,
        placement: String,
        reason: String? = nil
    ) {
        var payload: [String: Any] = ["placement": placement]
        if let reason {
            payload["reason"] = reason
        }
        record(type: type, payload: payload)
    }

    private func record(type: String, payload: sending [String: Any]) {
        let eventData: [String: Any] = [
            "type": type,
            "payload": payload
        ]

        functions.httpsCallable("recordLifecycleEvent").call(eventData) { _, error in
            if let error {
                TelemetryManager.shared.recordError(
                    error,
                    context: .network,
                    code: "lifecycle_event_record_failed",
                    additionalInfo: ["type": type]
                )
            }
        }
    }
}

private extension UNAuthorizationStatus {
    var lifecycleStatusRawValue: String {
        switch self {
        case .notDetermined:
            return "not_determined"
        case .denied:
            return "denied"
        case .authorized:
            return "authorized"
        case .provisional:
            return "provisional"
        case .ephemeral:
            return "ephemeral"
        @unknown default:
            return "unknown"
        }
    }
}

private extension AppleHealthConnectionState {
    var lifecycleStatusRawValue: String {
        switch self {
        case .unavailable:
            return "unavailable"
        case .neverConnected:
            return "never_connected"
        case .connected:
            return "connected"
        case .revoked:
            return "revoked"
        }
    }
}
