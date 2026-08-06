import Combine
import Observation
import UIKit
import UserNotifications

@MainActor
protocol ClimbDropNotificationStateClient: AnyObject {
    var isPreferenceEnabled: Bool { get }

    func authorizationStatus() async -> UNAuthorizationStatus
    func requestDuringOnboarding() async -> UNAuthorizationStatus
    func enable() async -> UNAuthorizationStatus
    func disable() async
    func openSystemNotificationSettings()
}

@MainActor
final class LiveClimbDropNotificationStateClient: ClimbDropNotificationStateClient {
    var isPreferenceEnabled: Bool {
        ClimbDropNotificationPreferenceStore.isEnabled
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await ClimbDropNotificationPermissionController.authorizationStatus()
    }

    func requestDuringOnboarding() async -> UNAuthorizationStatus {
        await ClimbDropNotificationPermissionController.requestDuringOnboarding()
    }

    func enable() async -> UNAuthorizationStatus {
        await ClimbDropNotificationPermissionController.enable()
    }

    func disable() async {
        await ClimbDropNotificationPermissionController.disable()
    }

    func openSystemNotificationSettings() {
        ClimbDropNotificationPermissionController.openSystemNotificationSettings()
    }
}

/// The app-wide answer to whether climb-drop notifications can reach this climber.
///
/// iOS authorization and the in-app climb-drop preference are separate inputs, but views must
/// never interpret them independently. This state owns that interpretation and publishes every
/// permission or preference transition to all mounted surfaces.
@MainActor
@Observable
final class ClimbDropNotificationState {
    static let shared = ClimbDropNotificationState(client: LiveClimbDropNotificationStateClient())

    private(set) var authorizationStatus: UNAuthorizationStatus?
    private(set) var isPreferenceEnabled: Bool
    private(set) var isUpdating = false

    @ObservationIgnored private let client: any ClimbDropNotificationStateClient
    @ObservationIgnored private var preferenceChangeCancellable: AnyCancellable?
    @ObservationIgnored private var stateRevision = 0

    var isEnabled: Bool {
        guard let authorizationStatus else { return false }
        return authorizationStatus.allowsRemoteUserVisibleNotifications && isPreferenceEnabled
    }

    /// Suppress the CTA while an enabled stored preference is being verified so an already opted-in
    /// climber never sees a false prompt flash on first render.
    var shouldPromptForEnablement: Bool {
        guard authorizationStatus != nil else { return isPreferenceEnabled == false }
        return isEnabled == false
    }

    init(
        client: any ClimbDropNotificationStateClient,
        observesPreferenceChanges: Bool = true
    ) {
        self.client = client
        isPreferenceEnabled = client.isPreferenceEnabled

        guard observesPreferenceChanges else { return }
        preferenceChangeCancellable = NotificationCenter.default
            .publisher(for: .climbDropNotificationPreferenceDidChange)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.synchronizePreferenceSnapshot()
                }
            }
    }

    func refresh() async {
        guard isUpdating == false else { return }
        let revision = stateRevision
        let status = await client.authorizationStatus()
        guard revision == stateRevision else { return }
        apply(status: status)
    }

    @discardableResult
    func requestDuringOnboarding() async -> UNAuthorizationStatus {
        await performUpdate { client in
            await client.requestDuringOnboarding()
        }
    }

    @discardableResult
    func enable() async -> UNAuthorizationStatus {
        await performUpdate { client in
            await client.enable()
        }
    }

    func disable() async {
        guard isUpdating == false else { return }
        isUpdating = true
        stateRevision += 1
        defer { isUpdating = false }

        await client.disable()
        isPreferenceEnabled = client.isPreferenceEnabled
        authorizationStatus = await client.authorizationStatus()
    }

    func openSystemNotificationSettings() {
        client.openSystemNotificationSettings()
    }

    private func performUpdate(
        _ operation: (any ClimbDropNotificationStateClient) async -> UNAuthorizationStatus
    ) async -> UNAuthorizationStatus {
        guard isUpdating == false else {
            return authorizationStatus ?? .notDetermined
        }

        isUpdating = true
        stateRevision += 1
        defer { isUpdating = false }

        let status = await operation(client)
        apply(status: status)
        return status
    }

    private func apply(status: UNAuthorizationStatus) {
        authorizationStatus = status
        isPreferenceEnabled = client.isPreferenceEnabled
    }

    private func synchronizePreferenceSnapshot() {
        isPreferenceEnabled = client.isPreferenceEnabled
    }
}
