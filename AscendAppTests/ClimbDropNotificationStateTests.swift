import SwiftUI
import Testing
import UIKit
import UserNotifications
@testable import AscendApp

@MainActor
struct ClimbDropNotificationStateTests {
    @Test("Enabled notifications suppress prompts on the first render", .bug(id: 397))
    func enabledSuppressesPromptBeforeAndAfterAuthorizationRefresh() async {
        let client = StubClimbDropNotificationStateClient(
            authorizationStatus: .authorized,
            isPreferenceEnabled: true
        )
        let state = ClimbDropNotificationState(client: client, observesEnvironmentChanges: false)

        #expect(state.shouldPromptForEnablement == false)

        await state.refresh()

        #expect(state.isEnabled)
        #expect(state.shouldPromptForEnablement == false)
    }

    @Test("Denied notifications keep prompts visible", .bug(id: 397))
    func deniedShowsPrompt() async {
        let client = StubClimbDropNotificationStateClient(
            authorizationStatus: .denied,
            isPreferenceEnabled: false
        )
        let state = ClimbDropNotificationState(client: client, observesEnvironmentChanges: false)

        await state.refresh()

        #expect(state.isEnabled == false)
        #expect(state.shouldPromptForEnablement)
    }

    @Test("Notifications that have not been requested keep prompts visible", .bug(id: 397))
    func notDeterminedShowsPrompt() async {
        let client = StubClimbDropNotificationStateClient(
            authorizationStatus: .notDetermined,
            isPreferenceEnabled: false
        )
        let state = ClimbDropNotificationState(client: client, observesEnvironmentChanges: false)

        await state.refresh()

        #expect(state.isEnabled == false)
        #expect(state.shouldPromptForEnablement)
    }

    @Test("An off climb-drop preference keeps prompts visible even with iOS permission", .bug(id: 397))
    func disabledPreferenceShowsPrompt() async {
        let client = StubClimbDropNotificationStateClient(
            authorizationStatus: .authorized,
            isPreferenceEnabled: false
        )
        let state = ClimbDropNotificationState(client: client, observesEnvironmentChanges: false)

        await state.refresh()

        #expect(state.isEnabled == false)
        #expect(state.shouldPromptForEnablement)
    }

    @Test("Granting permission updates shared state without a relaunch", .bug(id: 397))
    func notDeterminedTransitionsToEnabled() async {
        let client = StubClimbDropNotificationStateClient(
            authorizationStatus: .notDetermined,
            isPreferenceEnabled: false
        )
        let state = ClimbDropNotificationState(client: client, observesEnvironmentChanges: false)
        await state.refresh()
        #expect(state.shouldPromptForEnablement)

        let result = await state.enable()

        #expect(result == .authorized)
        #expect(state.authorizationStatus == .authorized)
        #expect(state.isPreferenceEnabled)
        #expect(state.isEnabled)
        #expect(state.shouldPromptForEnablement == false)
    }

    @Test("A denied iOS permission leaves the stored preference exactly as the climber set it")
    func deniedPreservesTheStoredPreference() async {
        let client = StubClimbDropNotificationStateClient(
            authorizationStatus: .denied,
            isPreferenceEnabled: true
        )
        let state = ClimbDropNotificationState(client: client, observesEnvironmentChanges: false)

        await state.refresh()

        #expect(client.disableCount == 0)
        #expect(state.isPreferenceEnabled)
        #expect(state.isEnabled == false)
        #expect(state.isBlockedBySystemSettings)
        #expect(state.shouldPromptForEnablement)
    }

    @Test("Surfaces asking at once share one authorization read")
    func concurrentRefreshesCoalesceIntoOneRead() async {
        let client = StubClimbDropNotificationStateClient(
            authorizationStatus: .authorized,
            isPreferenceEnabled: true
        )
        let state = ClimbDropNotificationState(client: client, observesEnvironmentChanges: false)

        async let first: Void = state.refresh()
        async let second: Void = state.refresh()
        _ = await (first, second)

        #expect(client.authorizationReadCount == 1)
        #expect(state.authorizationStatus == .authorized)
    }

    @Test("A resolved status is not re-read when another surface mounts")
    func refreshIfNeededOnlyReadsUntilTheStatusIsKnown() async {
        let client = StubClimbDropNotificationStateClient(
            authorizationStatus: .authorized,
            isPreferenceEnabled: true
        )
        let state = ClimbDropNotificationState(client: client, observesEnvironmentChanges: false)

        await state.refreshIfNeeded()
        await state.refreshIfNeeded()
        await state.refreshIfNeeded()

        #expect(client.authorizationReadCount == 1)
    }

    @Test("A mutation requested during another is performed, not dropped")
    func concurrentMutationsAreQueuedRatherThanSwallowed() async {
        let client = StubClimbDropNotificationStateClient(
            authorizationStatus: .notDetermined,
            isPreferenceEnabled: false
        )
        let state = ClimbDropNotificationState(client: client, observesEnvironmentChanges: false)

        let enabling = Task { await state.enable() }
        await Task.yield()
        let disabled = await state.disable()
        let enabled = await enabling.value

        #expect(client.enableCount == 1)
        #expect(client.disableCount == 1)
        #expect(enabled == .authorized)
        #expect(disabled == .authorized)
        #expect(state.isPreferenceEnabled == false)
        #expect(state.isEnabled == false)
    }

    @Test("A standing denial does not answer the climber's fresh yes")
    func enableUnderAStandingDenialRecordsTheIntentAndRoutesOut() async {
        let client = StubClimbDropNotificationStateClient(
            authorizationStatus: .denied,
            isPreferenceEnabled: false,
            enableOutcome: .denied,
            enableRecordsPreference: true,
            enableOpensSettings: true
        )
        let state = ClimbDropNotificationState(client: client, observesEnvironmentChanges: false)
        await state.refresh()

        let result = await state.enable()

        #expect(result == .denied)
        #expect(state.isPreferenceEnabled)
        #expect(state.isEnabled == false)
        #expect(state.isBlockedBySystemSettings)
        #expect(state.shouldPromptForEnablement)
        #expect(client.openSettingsCount == 1)
    }

    @Test("Granting in iOS Settings after that yes needs no second tap")
    func permissionGrantedAfterTheRoutedYesNeedsNoSecondTap() async {
        let client = StubClimbDropNotificationStateClient(
            authorizationStatus: .denied,
            isPreferenceEnabled: false,
            enableOutcome: .denied,
            enableRecordsPreference: true,
            enableOpensSettings: true
        )
        let state = ClimbDropNotificationState(client: client, observesEnvironmentChanges: false)
        await state.enable()
        #expect(state.shouldPromptForEnablement)

        client.status = .authorized
        await state.refresh()

        #expect(state.isEnabled)
        #expect(state.isBlockedBySystemSettings == false)
        #expect(state.shouldPromptForEnablement == false)
        #expect(client.enableCount == 1)
    }

    @Test("Declining the first-time iOS alert leaves the preference off")
    func decliningTheFirstAlertRecordsNoAndKeepsThePrompt() async {
        let client = StubClimbDropNotificationStateClient(
            authorizationStatus: .notDetermined,
            isPreferenceEnabled: false,
            enableOutcome: .denied,
            enableRecordsPreference: false
        )
        let state = ClimbDropNotificationState(client: client, observesEnvironmentChanges: false)
        await state.refresh()

        let result = await state.enable()

        #expect(result == .denied)
        #expect(state.isPreferenceEnabled == false)
        #expect(state.isBlockedBySystemSettings == false)
        #expect(state.shouldPromptForEnablement)
        #expect(client.openSettingsCount == 0)
    }

    @Test("A preference the climber turned off is not reported as blocked")
    func deniedWithThePreferenceOffIsNotBlocked() async {
        let client = StubClimbDropNotificationStateClient(
            authorizationStatus: .denied,
            isPreferenceEnabled: false
        )
        let state = ClimbDropNotificationState(client: client, observesEnvironmentChanges: false)

        await state.refresh()

        #expect(state.isBlockedBySystemSettings == false)
        #expect(state.shouldPromptForEnablement)
    }

    @Test("Account deletion drops the deleted climber's preference")
    func resetAfterAccountDeletionClearsThePreferenceSnapshot() async {
        let client = StubClimbDropNotificationStateClient(
            authorizationStatus: .authorized,
            isPreferenceEnabled: true
        )
        let state = ClimbDropNotificationState(client: client, observesEnvironmentChanges: false)
        await state.refresh()
        #expect(state.shouldPromptForEnablement == false)

        // Deletion clears the persistent domain the preference lives in.
        client.isPreferenceEnabled = false
        state.resetAfterAccountDeletion()

        #expect(state.isPreferenceEnabled == false)
        #expect(state.isEnabled == false)
        #expect(state.shouldPromptForEnablement)
    }
}

/// Presses on the two surfaces a climber actually sees the prompt on, one hosted screen at a time,
/// because what each has to prove is that its own CTA follows the shared state.
@MainActor
@Suite(.hostsAWindow)
struct ClimbDropNotificationPromptHostingTests {
    @Test(
        "A prompt disappears live after permission is granted",
        .bug(id: 397),
        arguments: NotificationPromptSurface.allCases
    )
    func promptFollowsTheSharedStateTransition(surface: NotificationPromptSurface) async throws {
        let client = StubClimbDropNotificationStateClient(
            authorizationStatus: .notDetermined,
            isPreferenceEnabled: false
        )
        let state = ClimbDropNotificationState(client: client, observesEnvironmentChanges: false)
        await state.refresh()

        try await withHostedPromptSurface(surface, notificationState: state) { root in
            #expect(isPromptOnScreen(in: root))

            await state.enable()
            await renderNextUpdate(in: root)

            #expect(isPromptOnScreen(in: root) == false)
        }
    }

    @Test(
        "A prompt stays hidden on an enabled first render",
        .bug(id: 397),
        arguments: NotificationPromptSurface.allCases
    )
    func promptIsHiddenOnEnabledFirstRender(surface: NotificationPromptSurface) async throws {
        let client = StubClimbDropNotificationStateClient(
            authorizationStatus: .authorized,
            isPreferenceEnabled: true
        )
        let state = ClimbDropNotificationState(client: client, observesEnvironmentChanges: false)

        try await withHostedPromptSurface(surface, notificationState: state) { root in
            #expect(isPromptOnScreen(in: root) == false)
        }
    }

    @Test(
        "A prompt remains visible when permission is denied",
        .bug(id: 397),
        arguments: NotificationPromptSurface.allCases
    )
    func promptRemainsVisibleWhenDenied(surface: NotificationPromptSurface) async throws {
        let client = StubClimbDropNotificationStateClient(
            authorizationStatus: .denied,
            isPreferenceEnabled: false
        )
        let state = ClimbDropNotificationState(client: client, observesEnvironmentChanges: false)
        await state.refresh()

        try await withHostedPromptSurface(surface, notificationState: state) { root in
            #expect(isPromptOnScreen(in: root))
        }
    }

    private func withHostedPromptSurface(
        _ surface: NotificationPromptSurface,
        notificationState: ClimbDropNotificationState,
        _ whileOnScreen: (UIView) async throws -> Void
    ) async throws {
        try await withAccessibilityAutomation {
            let size = CGSize(width: 402, height: 874)
            let controller = UIHostingController(
                rootView: NotificationPromptSurfaceHarness(
                    surface: surface,
                    notificationState: notificationState
                )
            )
            controller.view.frame = CGRect(origin: .zero, size: size)

            let window = UIWindow(frame: controller.view.frame)
            window.overrideUserInterfaceStyle = .dark
            window.rootViewController = controller
            window.makeKeyAndVisible()
            defer { window.isHidden = true }

            await renderNextUpdate(in: controller.view)
            try await whileOnScreen(controller.view)
        }
    }

    private func renderNextUpdate(in view: UIView) async {
        for _ in 0..<4 {
            await Task.yield()
            view.setNeedsLayout()
            view.layoutIfNeeded()
        }
    }

    private func isPromptOnScreen(in root: UIView) -> Bool {
        accessibilityElements(under: root).contains {
            $0.accessibilityLabel == "Turn on notifications"
        }
    }
}

/// The two shipping surfaces that ask a climber to turn notifications on.
enum NotificationPromptSurface: String, CaseIterable, CustomStringConvertible {
    case profileAchievements
    case climbsCollection

    var description: String {
        switch self {
        case .profileAchievements:
            "Profile Achievements"
        case .climbsCollection:
            "Climbs Collection"
        }
    }
}

/// What the Push screen's climb-drop row says and offers while iOS is refusing delivery.
@MainActor
@Suite(.hostsAWindow)
struct NotificationSettingsDeliveryStatusTests {
    @Test("A blocked preference states its status and can still be turned off here")
    func blockedDeliveryIsStatedAndStaysSwitchableOff() async throws {
        let client = StubClimbDropNotificationStateClient(
            authorizationStatus: .denied,
            isPreferenceEnabled: true
        )
        let state = ClimbDropNotificationState(client: client, observesEnvironmentChanges: false)
        await state.refresh()

        try await withHostedNotificationSettings(notificationState: state) { root in
            let elements = accessibilityElements(under: root)
            #expect(elements.contains { label(of: $0).contains("On, but iOS is blocking delivery") })
            // The row is the switch, not the route: turning this off is the climber's alone.
            #expect(elements.contains { label(of: $0) == "New climb drops" })
            #expect(elements.contains { $0.accessibilityHint == routingHint } == false)

            await state.disable()
            await renderNextUpdate(in: root)

            #expect(state.isPreferenceEnabled == false)
            #expect(client.disableCount == 1)
            #expect(client.openSettingsCount == 0)

            let afterTurningOff = accessibilityElements(under: root)
            #expect(afterTurningOff.contains { label(of: $0).contains("blocking delivery") } == false)
            #expect(afterTurningOff.contains { $0.accessibilityHint == routingHint })
        }
    }

    @Test("A preference the climber turned off says what turning it on needs")
    func aDisabledPreferenceExplainsTheRouteWithoutClaimingToBeBlocked() async throws {
        let client = StubClimbDropNotificationStateClient(
            authorizationStatus: .denied,
            isPreferenceEnabled: false,
            enableOutcome: .denied,
            enableRecordsPreference: true,
            enableOpensSettings: true
        )
        let state = ClimbDropNotificationState(client: client, observesEnvironmentChanges: false)
        await state.refresh()

        try await withHostedNotificationSettings(notificationState: state) { root in
            let elements = accessibilityElements(under: root)
            #expect(elements.contains { label(of: $0).contains("blocking delivery") } == false)
            #expect(elements.contains { label(of: $0).contains("Off. Allow notifications in iOS first.") })

            try activateAccessibilityElement(in: root) {
                $0.accessibilityHint == routingHint
            }
            await renderUpdates(in: root) { state.isPreferenceEnabled }

            #expect(state.isPreferenceEnabled)
            #expect(client.enableCount == 1)
            #expect(client.openSettingsCount == 1)
        }
    }

    @Test("An allowed permission leaves the row on its own description and switch")
    func anAllowedPermissionKeepsTheSwitch() async throws {
        let client = StubClimbDropNotificationStateClient(
            authorizationStatus: .authorized,
            isPreferenceEnabled: true
        )
        let state = ClimbDropNotificationState(client: client, observesEnvironmentChanges: false)
        await state.refresh()

        try await withHostedNotificationSettings(notificationState: state) { root in
            let elements = accessibilityElements(under: root)

            #expect(elements.contains { label(of: $0).contains("blocking delivery") } == false)
            #expect(elements.contains { $0.accessibilityHint == routingHint } == false)
            #expect(elements.contains { label(of: $0) == "New climb drops" })
        }
    }

    private var routingHint: String {
        "Turns these on and opens iOS Settings"
    }

    private func label(of element: NSObject) -> String {
        element.accessibilityLabel ?? ""
    }

    private func renderNextUpdate(in view: UIView) async {
        for _ in 0..<4 {
            await Task.yield()
            view.setNeedsLayout()
            view.layoutIfNeeded()
        }
    }

    /// Renders until the tap's outcome has landed, for the one wait that follows a row the view
    /// answers with a detached task rather than an awaited call. That chain - the button's task,
    /// the state's queued mutation, the client's own suspension, the apply that follows it - takes
    /// four scheduling hops with no slack, and every main-actor job a concurrently running test
    /// enqueues consumes one of them. Counting hops is a race a loaded machine loses; waiting on
    /// the outcome costs a busy machine latency instead of a red build.
    private func renderUpdates(
        in view: UIView,
        iterations: Int = 200,
        until isSettled: () -> Bool
    ) async {
        for _ in 0..<iterations {
            await Task.yield()
            view.setNeedsLayout()
            view.layoutIfNeeded()

            if isSettled() {
                return
            }

            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    private func withHostedNotificationSettings(
        notificationState: ClimbDropNotificationState,
        _ whileOnScreen: (UIView) async throws -> Void
    ) async throws {
        try await withAccessibilityAutomation {
            let size = CGSize(width: 402, height: 874)
            let controller = UIHostingController(
                rootView: NavigationStack {
                    NotificationSettingsView(notificationState: notificationState)
                }
            )
            controller.view.frame = CGRect(origin: .zero, size: size)

            let window = UIWindow(frame: controller.view.frame)
            window.overrideUserInterfaceStyle = .dark
            window.rootViewController = controller
            window.makeKeyAndVisible()
            defer { window.isHidden = true }

            for _ in 0..<4 {
                await Task.yield()
                controller.view.setNeedsLayout()
                controller.view.layoutIfNeeded()
            }

            try await whileOnScreen(controller.view)
        }
    }
}

private struct NotificationPromptSurfaceHarness: View {
    let surface: NotificationPromptSurface
    let notificationState: ClimbDropNotificationState

    var body: some View {
        Group {
            switch surface {
            case .profileAchievements:
                PrestigeSection(
                    held: [],
                    open: [],
                    achievements: .empty,
                    mode: .own,
                    notificationState: notificationState
                )
            case .climbsCollection:
                ClimbsCollectionView(
                    collection: ProfileCollectionSummary(
                        collectedCount: 0,
                        catalogCount: 0,
                        previewCards: [],
                        launchedCards: [],
                        comingSoonClimbs: []
                    ),
                    mode: .own,
                    notificationState: notificationState
                )
            }
        }
        .frame(width: 402, height: 874)
        .background(ProfileVisualStyle.background)
    }
}

@MainActor
private final class StubClimbDropNotificationStateClient: ClimbDropNotificationStateClient {
    var isPreferenceEnabled: Bool
    private(set) var authorizationReadCount = 0
    private(set) var enableCount = 0
    private(set) var disableCount = 0
    private(set) var openSettingsCount = 0

    var status: UNAuthorizationStatus

    /// What one enable request does, scripted per scenario rather than re-derived: the status iOS
    /// ends up reporting, the answer the request writes down (`nil` leaves the stored one alone),
    /// and whether it hands the climber to iOS Settings. `ClimbDropNotificationEnableRequestTests`
    /// is what proves the shipping request produces these combinations.
    private let enableOutcome: UNAuthorizationStatus
    private let enableRecordsPreference: Bool?
    private let enableOpensSettings: Bool

    init(
        authorizationStatus: UNAuthorizationStatus,
        isPreferenceEnabled: Bool,
        enableOutcome: UNAuthorizationStatus = .authorized,
        enableRecordsPreference: Bool? = true,
        enableOpensSettings: Bool = false
    ) {
        status = authorizationStatus
        self.isPreferenceEnabled = isPreferenceEnabled
        self.enableOutcome = enableOutcome
        self.enableRecordsPreference = enableRecordsPreference
        self.enableOpensSettings = enableOpensSettings
    }

    /// The real read is a callable round trip, so it suspends here too - a stub that answers
    /// without ever suspending would let a caller through before an overlapping one has started,
    /// and coalescing is exactly what those tests are asking about.
    func authorizationStatus() async -> UNAuthorizationStatus {
        await Task.yield()
        authorizationReadCount += 1
        return status
    }

    func requestDuringOnboarding() async -> UNAuthorizationStatus {
        await enable()
    }

    func enable() async -> UNAuthorizationStatus {
        await Task.yield()
        enableCount += 1
        status = enableOutcome

        if let enableRecordsPreference {
            isPreferenceEnabled = enableRecordsPreference
        }

        if enableOpensSettings {
            openSystemNotificationSettings()
        }

        return status
    }

    func disable() async -> UNAuthorizationStatus {
        await Task.yield()
        disableCount += 1
        isPreferenceEnabled = false
        return status
    }

    func openSystemNotificationSettings() {
        openSettingsCount += 1
    }
}
