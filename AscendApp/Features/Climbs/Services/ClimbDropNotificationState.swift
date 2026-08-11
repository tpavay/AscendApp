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
    func disable() async -> UNAuthorizationStatus
    func openSystemNotificationSettings()
}

@MainActor
final class LiveClimbDropNotificationStateClient: ClimbDropNotificationStateClient {
    var isPreferenceEnabled: Bool {
        ClimbDropNotificationPreferenceStore.isEnabled
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await PushNotificationService.shared.authorizationStatus()
    }

    /// Requests permission from the onboarding opt-in screen. Unlike `enable`, a prior
    /// denial must never deep-link to system settings - leaving the app mid-onboarding
    /// strands the flow.
    func requestDuringOnboarding() async -> UNAuthorizationStatus {
        await PushNotificationService.shared.requestClimbDropNotifications(opensSettingsWhenDenied: false)
    }

    func enable() async -> UNAuthorizationStatus {
        await PushNotificationService.shared.requestClimbDropNotifications(opensSettingsWhenDenied: true)
    }

    func disable() async -> UNAuthorizationStatus {
        await PushNotificationService.shared.disableClimbDropNotifications()
    }

    func openSystemNotificationSettings() {
        PushNotificationService.shared.openSystemNotificationSettings()
    }
}

/// The app-wide answer to whether climb-drop notifications can reach this climber.
///
/// iOS authorization and the in-app climb-drop preference are separate inputs, but views must
/// never interpret them independently. This state owns that interpretation and publishes every
/// permission or preference transition to all mounted surfaces.
///
/// The two inputs never overwrite each other. The stored preference is what the climber asked
/// for; iOS authorization is only whether the system will currently deliver it. A denial
/// suppresses delivery and is reported as such, and leaves the preference exactly as chosen.
///
/// Reading iOS authorization costs a lifecycle callable, so surfaces never read it themselves and
/// never own a refresh trigger of their own: this state reads once when the first surface needs an
/// answer, once per foreground - the only way authorization changes behind the app's back - and
/// once per mutation, however many surfaces are mounted.
@MainActor
@Observable
final class ClimbDropNotificationState {
    static let shared = ClimbDropNotificationState(client: LiveClimbDropNotificationStateClient())

    private(set) var authorizationStatus: UNAuthorizationStatus?
    private(set) var isPreferenceEnabled: Bool
    private(set) var isUpdating = false

    @ObservationIgnored private let client: any ClimbDropNotificationStateClient
    @ObservationIgnored private var environmentChangeCancellables: Set<AnyCancellable> = []
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var mutationTask: Task<UNAuthorizationStatus, Never>?
    @ObservationIgnored private var mutationGeneration = 0
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

    /// True when the climber asked for climb drops but iOS will not deliver them, so a surface can
    /// say delivery is blocked rather than implying the preference is live. A preference the
    /// climber turned off is not blocked by anything.
    var isBlockedBySystemSettings: Bool {
        authorizationStatus == .denied && isPreferenceEnabled
    }

    init(
        client: any ClimbDropNotificationStateClient,
        observesEnvironmentChanges: Bool = true
    ) {
        self.client = client
        isPreferenceEnabled = client.isPreferenceEnabled

        guard observesEnvironmentChanges else { return }

        NotificationCenter.default
            .publisher(for: .climbDropNotificationPreferenceDidChange)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.synchronizePreferenceSnapshot()
                }
            }
            .store(in: &environmentChangeCancellables)

        NotificationCenter.default
            .publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    await self?.refresh()
                }
            }
            .store(in: &environmentChangeCancellables)
    }

    /// Resolves authorization the first time a surface needs it, and stays quiet on every later
    /// mount. What a surface reads afterwards is kept current by the foreground read and by the
    /// mutations, so remounting is not a reason to pay for another read.
    func refreshIfNeeded() async {
        guard authorizationStatus == nil else { return }
        await refresh()
    }

    func refresh() async {
        if let refreshTask {
            await refreshTask.value
            return
        }

        let task = Task { @MainActor in
            await self.readAuthorizationStatus()
        }
        refreshTask = task
        await task.value
        refreshTask = nil
    }

    @discardableResult
    func requestDuringOnboarding() async -> UNAuthorizationStatus {
        await performUpdate(.requestDuringOnboarding)
    }

    @discardableResult
    func enable() async -> UNAuthorizationStatus {
        await performUpdate(.enable)
    }

    @discardableResult
    func disable() async -> UNAuthorizationStatus {
        await performUpdate(.disable)
    }

    func openSystemNotificationSettings() {
        client.openSystemNotificationSettings()
    }

    /// Drops the deleted account's preference so the next climber's first render asks fresh.
    /// Deletion has already cleared the backing store; only this in-memory mirror survives it.
    /// iOS authorization is device state rather than account state, so it is left alone.
    func resetAfterAccountDeletion() {
        stateRevision += 1
        isPreferenceEnabled = client.isPreferenceEnabled
    }

    private func readAuthorizationStatus() async {
        guard isUpdating == false else { return }
        let revision = stateRevision
        let status = await client.authorizationStatus()
        guard revision == stateRevision else { return }
        apply(status: status)
    }

    /// Runs mutations one at a time, queueing rather than dropping. Onboarding branches its
    /// telemetry and its user property on what comes back, so a request that never happened must
    /// never return a status that reads like an answer.
    private func performUpdate(_ mutation: Mutation) async -> UNAuthorizationStatus {
        let precedingUpdate = mutationTask
        let task = Task { @MainActor in
            _ = await precedingUpdate?.value
            return await self.run(mutation)
        }

        mutationTask = task
        mutationGeneration += 1
        let generation = mutationGeneration
        isUpdating = true
        stateRevision += 1

        let status = await task.value

        if mutationGeneration == generation {
            mutationTask = nil
            isUpdating = false
            apply(status: status)
        }

        return status
    }

    private func run(_ mutation: Mutation) async -> UNAuthorizationStatus {
        switch mutation {
        case .requestDuringOnboarding:
            await client.requestDuringOnboarding()
        case .enable:
            await client.enable()
        case .disable:
            await client.disable()
        }
    }

    private func apply(status: UNAuthorizationStatus) {
        authorizationStatus = status
        isPreferenceEnabled = client.isPreferenceEnabled
    }

    private func synchronizePreferenceSnapshot() {
        isPreferenceEnabled = client.isPreferenceEnabled
    }

    private enum Mutation {
        case requestDuringOnboarding
        case enable
        case disable
    }
}
