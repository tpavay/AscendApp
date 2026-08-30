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

    func recordPaywallReached(placement: String, expectedUserID: String? = nil) {
        recordPaywallEvent(
            type: "paywall_reached",
            placement: placement,
            expectedUserID: expectedUserID
        )
    }

    func recordPaywallShown(placement: String, expectedUserID: String? = nil) {
        recordPaywallEvent(
            type: "paywall_shown",
            placement: placement,
            expectedUserID: expectedUserID
        )
    }

    func recordPaywallDismissed(
        placement: String,
        reason: String? = nil,
        expectedUserID: String? = nil
    ) {
        recordPaywallEvent(
            type: "paywall_dismissed",
            placement: placement,
            reason: reason,
            expectedUserID: expectedUserID
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

    func recordAppleHealthIntegration(state: AppleHealthConnectionState) {
        record(
            type: "apple_health_integration_changed",
            payload: [
                "status": state.lifecycleStatusRawValue
            ]
        )
    }

    /// Unlike the other lifecycle events, this one backs a settings control the
    /// user is watching, so it reports failure instead of swallowing it.
    func recordCommunicationPreferences(
        lifecycleEmails: (isEnabled: Bool, source: LifecycleEmailConsentSource)? = nil,
        productUpdatesEnabled: Bool? = nil,
        climbDropEmailsEnabled: Bool? = nil
    ) async throws {
        var payload: [String: Any] = [:]
        // The flag and where it was answered travel as one value: a decision
        // written without its source silently inherits the source of the last
        // one, and the server rejects the pair anyway.
        if let lifecycleEmails {
            payload["lifecycleEmailsEnabled"] = lifecycleEmails.isEnabled
            payload["lifecycleEmailsSource"] = lifecycleEmails.source.rawValue
        }
        if let productUpdatesEnabled {
            payload["productUpdatesEnabled"] = productUpdatesEnabled
        }
        if let climbDropEmailsEnabled {
            payload["climbDropEmailsEnabled"] = climbDropEmailsEnabled
        }
        guard !payload.isEmpty else { return }

        try await sendLifecycleEvent(
            type: "communication_preferences_updated",
            payload: payload
        )
    }

    private func recordPaywallEvent(
        type: String,
        placement: String,
        reason: String? = nil,
        expectedUserID: String?
    ) {
        var payload: [String: Any] = ["placement": placement]
        if let reason {
            payload["reason"] = reason
        }
        record(type: type, payload: payload, expectedUserID: expectedUserID)
    }

    /// Fire-and-forget recording for observational events, where a failed send
    /// is not worth interrupting the user over.
    private func record(
        type: String,
        payload: sending [String: Any],
        expectedUserID: String? = nil
    ) {
        Task {
            do {
                try await sendLifecycleEvent(
                    type: type,
                    payload: payload,
                    expectedUserID: expectedUserID
                )
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

    private func sendLifecycleEvent(
        type: String,
        payload: sending [String: Any],
        expectedUserID: String? = nil
    ) async throws {
        // Lifecycle events are per-user server state; the callable rejects
        // unauthenticated requests, so don't send them while signed out.
        try Self.validateIdentity(
            currentUserID: Auth.auth().currentUser?.uid,
            expectedUserID: expectedUserID
        )

        let eventData: [String: Any] = [
            "type": type,
            "payload": payload
        ]

        _ = try await functions
            .httpsCallable("recordLifecycleEvent")
            .call(eventData)
    }

    nonisolated static func validateIdentity(
        currentUserID: String?,
        expectedUserID: String?
    ) throws {
        guard let currentUserID else {
            throw LifecycleEventRecorderError.signedOut
        }
        if let expectedUserID, currentUserID != expectedUserID {
            throw LifecycleEventRecorderError.identityChanged
        }
    }

    /// Errors that are part of normal operation — a request cancelled by the
    /// system mid-flight, or auth racing sign-out — not defects worth alerting on.
    private nonisolated static func isExpectedTransportNoise(_ error: Error) -> Bool {
        if let recorderError = error as? LifecycleEventRecorderError {
            // Exhaustive on purpose: a new case must decide for itself whether
            // it is noise rather than inheriting silence.
            switch recorderError {
            case .signedOut, .identityChanged:
                return true
            }
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
