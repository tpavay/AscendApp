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

        async let enabling = state.enable()
        async let disabling = state.disable()
        let (enabled, disabled) = await (enabling, disabling)

        #expect(client.enableCount == 1)
        #expect(client.disableCount == 1)
        #expect(enabled == .authorized)
        #expect(disabled == .authorized)
        #expect(state.isPreferenceEnabled == false)
        #expect(state.isEnabled == false)
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
                    achievements: .zero,
                    achievementRecords: [],
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

    private var status: UNAuthorizationStatus

    init(
        authorizationStatus: UNAuthorizationStatus,
        isPreferenceEnabled: Bool
    ) {
        status = authorizationStatus
        self.isPreferenceEnabled = isPreferenceEnabled
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
        status = .authorized
        isPreferenceEnabled = true
        return status
    }

    func disable() async -> UNAuthorizationStatus {
        await Task.yield()
        disableCount += 1
        isPreferenceEnabled = false
        return status
    }

    func openSystemNotificationSettings() {}
}
