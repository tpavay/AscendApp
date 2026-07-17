import Foundation
@preconcurrency import FirebaseAuth
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

    /// Unlike the other lifecycle events, this one backs a settings control the
    /// user is watching, so it reports failure instead of swallowing it.
    func recordCommunicationPreferences(
        lifecycleEmailsEnabled: Bool? = nil,
        productUpdatesEnabled: Bool? = nil,
        climbDropEmailsEnabled: Bool? = nil
    ) async throws {
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

        try await record(
            type: "communication_preferences_updated",
            payload: payload
        )
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

    /// Fire-and-forget recording for observational events, where a failed send
    /// is not worth interrupting the user over.
    private func record(type: String, payload: sending [String: Any]) {
        Task {
            do {
                try await record(type: type, payload: payload)
            } catch {
                guard !Self.isExpectedTransportNoise(error) else { return }

                TelemetryManager.shared.recordError(
                    error,
                    context: .network,
                    code: "lifecycle_event_record_failed",
                    additionalInfo: ["type": type]
                )
            }
        }
    }

    private func record(
        type: String,
        payload: sending [String: Any]
    ) async throws {
        // Lifecycle events are per-user server state; the callable rejects
        // unauthenticated requests, so don't send them while signed out.
        guard Auth.auth().currentUser != nil else {
            throw LifecycleEventRecorderError.signedOut
        }

        let eventData: [String: Any] = [
            "type": type,
            "payload": payload
        ]

        _ = try await functions
            .httpsCallable("recordLifecycleEvent")
            .call(eventData)
    }

    /// Errors that are part of normal operation — a request cancelled by the
    /// system mid-flight, or auth racing sign-out — not defects worth alerting on.
    private nonisolated static func isExpectedTransportNoise(_ error: Error) -> Bool {
        if error is LifecycleEventRecorderError {
            return true
        }

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
            return true
        }
        if nsError.domain == FunctionsErrorDomain,
           nsError.code == FunctionsErrorCode.unauthenticated.rawValue {
            return true
        }
        return false
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
