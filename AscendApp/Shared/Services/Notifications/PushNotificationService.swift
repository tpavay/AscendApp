import Foundation
@preconcurrency import FirebaseAuth
@preconcurrency import FirebaseFunctions
@preconcurrency import FirebaseMessaging
import UIKit
import UserNotifications

@MainActor
final class PushNotificationService: NSObject, MessagingDelegate {
    static let shared = PushNotificationService()

    private let functions = Functions.functions(region: "us-central1")
    private var isConfigured = false
    private var lastRegisteredToken: String?
    private let deviceSyncQueue = PushDeviceSyncQueue()

    private override init() {
        super.init()
    }

    func configure() {
        guard !isConfigured else { return }
        isConfigured = true
        Messaging.messaging().delegate = self
    }

    nonisolated func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        Task { @MainActor in
            await PushNotificationService.shared.handleRegistrationTokenRefresh(fcmToken)
        }
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        LifecycleEventRecorder.shared.recordNotificationPermission(status: settings.authorizationStatus)
        return settings.authorizationStatus
    }

    @discardableResult
    func requestClimbDropNotifications(opensSettingsWhenDenied: Bool) async -> UNAuthorizationStatus {
        let request = ClimbDropNotificationEnableRequest(
            currentAuthorizationStatus: { await self.authorizationStatus() },
            presentSystemAuthorizationAlert: {
                let center = UNUserNotificationCenter.current()
                _ = (try? await center.requestAuthorization(options: [.alert, .badge, .sound])) ?? false
                return await self.authorizationStatus()
            },
            recordIntent: { ClimbDropNotificationPreferenceStore.isEnabled = $0 },
            openSystemNotificationSettings: { self.openSystemNotificationSettings() },
            synchronizeInBackground: { status in
                self.deviceSyncQueue.enqueue { [self] in
                    await synchronizePreferenceAndDevice(authorizationStatus: status)
                }
            }
        )

        return await request.run(opensSettingsWhenDenied: opensSettingsWhenDenied)
    }

    @discardableResult
    func disableClimbDropNotifications() async -> UNAuthorizationStatus {
        ClimbDropNotificationPreferenceStore.isEnabled = false
        let status = await authorizationStatus()
        await deviceSyncQueue.enqueue { [self] in
            await synchronizePreferenceAndDevice(authorizationStatus: status)
        }.value
        return status
    }

    func synchronizeAuthenticatedDeviceIfNeeded() async {
        guard Auth.auth().currentUser != nil else { return }

        // Launch fires this from several hooks at once (root task, APNS
        // callback, FCM token refresh), and every foreground fires it again -
        // which is also what carries a mutation's sync when the app was
        // suspended before it landed.
        //
        // The stored preference is what the climber asked for; the authorization status is
        // whether iOS will currently deliver it. Both travel to the backend as they stand -
        // a denial reports itself and never rewrites the answer it was refusing.
        await deviceSyncQueue.coalesce { [self] in
            let status = await authorizationStatus()
            await synchronizePreferenceAndDevice(authorizationStatus: status)
        }
    }

    func unregisterCurrentDevice() async {
        guard Auth.auth().currentUser != nil else { return }

        let token: String?
        if let lastRegisteredToken {
            token = lastRegisteredToken
        } else {
            token = await fetchFCMToken()
        }
        var payload: [String: Any] = [:]
        if let token {
            payload["fcmToken"] = token
        }

        do {
            try await callFunction("unregisterPushDevice", data: payload)
            lastRegisteredToken = nil
        } catch {
            TelemetryManager.shared.recordError(
                error,
                context: .network,
                code: "push_device_unregister_failed"
            )
        }
    }

    func openSystemNotificationSettings() {
        guard let url = URL(string: UIApplication.openNotificationSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func handleRegistrationTokenRefresh(_ token: String?) async {
        guard let token, !token.isEmpty else { return }
        lastRegisteredToken = token
        await synchronizeAuthenticatedDeviceIfNeeded()
    }

    private func synchronizePreferenceAndDevice(authorizationStatus: UNAuthorizationStatus) async {
        guard Auth.auth().currentUser != nil else { return }

        await updateBackendPreference()

        // A device that stops being allowed to deliver has to say so, or the
        // send audience keeps its last authorized answer and pushes into a
        // system that will drop them.
        if authorizationStatus.allowsRemoteUserVisibleNotifications {
            UIApplication.shared.registerForRemoteNotifications()
        }

        guard let token = await fetchFCMToken() else {
            return
        }

        await registerDevice(token: token, authorizationStatus: authorizationStatus)
    }

    private func updateBackendPreference() async {
        do {
            try await callFunction(
                "updatePushNotificationPreferences",
                data: [
                    "climbDropPushEnabled": ClimbDropNotificationPreferenceStore.isEnabled
                ]
            )
        } catch {
            TelemetryManager.shared.recordError(
                error,
                context: .network,
                code: "push_preference_sync_failed"
            )
        }
    }

    private func registerDevice(token: String, authorizationStatus: UNAuthorizationStatus) async {
        do {
            try await callFunction(
                "registerPushDevice",
                data: [
                    "fcmToken": token,
                    "platform": "ios",
                    "authorizationStatus": authorizationStatus.backendRawValue,
                    "climbDropPushEnabled": ClimbDropNotificationPreferenceStore.isEnabled,
                    "appVersion": Bundle.main.appVersionString,
                    "buildNumber": Bundle.main.buildNumberString,
                    "bundleId": Bundle.main.bundleIdentifier ?? "",
                    "locale": Locale.current.identifier,
                    "timeZone": TimeZone.current.identifier
                ]
            )
            lastRegisteredToken = token
        } catch {
            TelemetryManager.shared.recordError(
                error,
                context: .network,
                code: "push_device_register_failed"
            )
        }
    }

    private func fetchFCMToken() async -> String? {
        await withCheckedContinuation { continuation in
            Messaging.messaging().token { token, error in
                if let error, !Self.isMissingAPNSTokenError(error) {
                    Task { @MainActor in
                        TelemetryManager.shared.recordError(
                            error,
                            context: .network,
                            code: "push_fcm_token_fetch_failed"
                        )
                    }
                }

                continuation.resume(returning: token)
            }
        }
    }

    /// FCM error 505: token requested before APNS delivered a device token
    /// (always the case on Simulator, and briefly after
    /// `registerForRemoteNotifications()`). The APNS callback and the FCM
    /// token-refresh delegate both re-run the sync, so this is an expected
    /// transient state, not an error worth reporting.
    private nonisolated static func isMissingAPNSTokenError(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == "com.google.fcm" && nsError.code == 505
    }

    private func callFunction(_ name: String, data: sending [String: Any]) async throws {
        _ = try await functions.httpsCallable(name).call(data)
    }
}

extension UNAuthorizationStatus {
    var allowsRemoteUserVisibleNotifications: Bool {
        switch self {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied, .notDetermined:
            return false
        @unknown default:
            return false
        }
    }

    var backendRawValue: String {
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

private extension Bundle {
    var appVersionString: String {
        object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    var buildNumberString: String {
        object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
    }
}
