import SwiftUI
import Testing
import UIKit
import UserNotifications
@testable import AscendApp

/// Reviewer-facing evidence for the two surfaces that ask a climber to turn climb-drop
/// notifications on: Profile Achievements and the Climbs Collection.
///
/// `ClimbDropNotificationPromptHostingTests` proves the prompt's visibility with the accessibility
/// tree; these tests host the same screens through `RenderedScreen` and drive the live transitions
/// on them. The grant transition happens inside one mounted window - the screen is never rebuilt
/// between the before and after frames, which is exactly the "without a relaunch" claim.
///
/// Photographs are written to `ASCEND_EVIDENCE_DIR` when it is set and not taken otherwise. Nothing
/// reads them back - these are evidence, not golden-image assertions.
@MainActor
@Suite(.serialized, .hostsAWindow)
struct ClimbDropNotificationPromptEvidenceTests {
    @Test(
        "The prompt is photographed disappearing the moment permission is granted",
        .bug(id: 397),
        arguments: EvidencePromptSurface.allCases
    )
    func theGrantTransitionIsPhotographedInOneMountedWindow(
        surface: EvidencePromptSurface
    ) async throws {
        let client = EvidenceClimbDropNotificationStateClient(
            authorizationStatus: .notDetermined,
            isPreferenceEnabled: false
        )
        let state = ClimbDropNotificationState(client: client, observesEnvironmentChanges: false)
        await state.refresh()

        try await withHostedSurface(surface, notificationState: state) { screen in
            #expect(isPromptOnScreen(in: screen.root))
            try screen.photograph(named: "\(surface.slug)-1-not-yet-asked")

            // The climber taps the CTA on the screen that is already up.
            try activateAccessibilityElement(labelled: "Turn on notifications", in: screen.root)
            try await screen.settle()

            #expect(client.enableCount == 1)
            #expect(state.isEnabled)
            #expect(isPromptOnScreen(in: screen.root) == false)
            try screen.photograph(named: "\(surface.slug)-2-after-granting")
        }
    }

    @Test(
        "An already enabled climber is photographed never seeing the prompt",
        .bug(id: 397),
        arguments: EvidencePromptSurface.allCases
    )
    func theEnabledFirstRenderIsPhotographed(surface: EvidencePromptSurface) async throws {
        // The captain's state: iOS permission allowed and the climb-drop preference on. The status
        // is deliberately left unresolved so the very first frame is the one under scrutiny.
        let client = EvidenceClimbDropNotificationStateClient(
            authorizationStatus: .authorized,
            isPreferenceEnabled: true
        )
        let state = ClimbDropNotificationState(client: client, observesEnvironmentChanges: false)

        // No settle before the first read: the frames under test are the first ones the screen
        // draws, and a settled screen would have already corrected a flash.
        try await withHostedSurface(surface, notificationState: state, settle: .turns(0)) { screen in
            // Every frame from the first one on, not just the settled one: a prompt that flashes
            // and then corrects itself is the defect, not the fix.
            for _ in 0..<8 {
                #expect(isPromptOnScreen(in: screen.root) == false)
                await Task.yield()
                screen.root.setNeedsLayout()
                screen.root.layoutIfNeeded()
            }

            // The screen did publish a tree over those passes, so the absence above is a reading
            // rather than an empty one.
            #expect(accessibilityElements(under: screen.root).isEmpty == false)
            try await screen.settle()
            try screen.photograph(named: "\(surface.slug)-3-enabled-first-render")

            await state.refresh()
            try await screen.settle()

            #expect(state.isEnabled)
            #expect(isPromptOnScreen(in: screen.root) == false)
            try screen.photograph(named: "\(surface.slug)-4-enabled-after-refresh")
        }
    }

    @Test(
        "A genuinely switched-off climber is photographed still being asked",
        .bug(id: 397),
        arguments: EvidencePromptSurface.allCases
    )
    func thePromptSurvivesForDisabledClimbers(surface: EvidencePromptSurface) async throws {
        let denied = EvidenceClimbDropNotificationStateClient(
            authorizationStatus: .denied,
            isPreferenceEnabled: false
        )
        let deniedState = ClimbDropNotificationState(client: denied, observesEnvironmentChanges: false)
        await deniedState.refresh()

        try await withHostedSurface(surface, notificationState: deniedState) { screen in
            #expect(isPromptOnScreen(in: screen.root))
            try screen.photograph(named: "\(surface.slug)-5-denied")
        }

        // Allowed in iOS, but the climb-drop preference itself is off: still a real ask.
        let preferenceOff = EvidenceClimbDropNotificationStateClient(
            authorizationStatus: .authorized,
            isPreferenceEnabled: false
        )
        let preferenceOffState = ClimbDropNotificationState(
            client: preferenceOff,
            observesEnvironmentChanges: false
        )
        await preferenceOffState.refresh()

        try await withHostedSurface(surface, notificationState: preferenceOffState) { screen in
            #expect(isPromptOnScreen(in: screen.root))
            try screen.photograph(named: "\(surface.slug)-6-allowed-but-preference-off")
        }
    }

    @Test(
        "Allowing in iOS Settings and coming back clears the prompt on the screen already up",
        .bug(id: 397),
        arguments: EvidencePromptSurface.allCases
    )
    func returningFromSystemSettingsRefreshesTheMountedSurface(
        surface: EvidencePromptSurface
    ) async throws {
        // The climber tapped the CTA under a standing denial, was handed to iOS Settings, and
        // allowed notifications there. Nothing in the app ran while they were gone, so coming back
        // is the only thing that can correct the screen.
        let client = EvidenceClimbDropNotificationStateClient(
            authorizationStatus: .denied,
            isPreferenceEnabled: true
        )
        let state = ClimbDropNotificationState(client: client)
        await state.refresh()

        try await withHostedSurface(surface, notificationState: state) { screen in
            #expect(state.isBlockedBySystemSettings)
            #expect(isPromptOnScreen(in: screen.root))
            try screen.photograph(named: "\(surface.slug)-7-blocked-before-leaving")

            client.simulateSystemSettingsGrant()
            NotificationCenter.default.post(
                name: UIApplication.willEnterForegroundNotification,
                object: nil
            )
            try await screen.settle()

            #expect(state.isEnabled)
            #expect(isPromptOnScreen(in: screen.root) == false)
            try screen.photograph(named: "\(surface.slug)-8-after-returning-from-ios-settings")
        }
    }

    @Test("The Push settings screen is photographed in the states it reports", .bug(id: 397))
    func theSettingsScreenIsPhotographed() async throws {
        let allowed = EvidenceClimbDropNotificationStateClient(
            authorizationStatus: .authorized,
            isPreferenceEnabled: true
        )
        let allowedState = ClimbDropNotificationState(client: allowed, observesEnvironmentChanges: false)
        await allowedState.refresh()

        try await withHostedSettings(notificationState: allowedState) { screen in
            let text = try await screen.copy { $0.contains("new climb drops") }
            #expect(allowedState.isEnabled)
            // The row reports a deliverable preference, not a blocked one.
            #expect(!text.contains("notifications are off in ios"))
            try screen.photograph(named: "push-settings-1-allowed-and-on")
        }

        let blocked = EvidenceClimbDropNotificationStateClient(
            authorizationStatus: .denied,
            isPreferenceEnabled: true
        )
        let blockedState = ClimbDropNotificationState(client: blocked, observesEnvironmentChanges: false)
        await blockedState.refresh()

        try await withHostedSettings(notificationState: blockedState) { screen in
            #expect(blockedState.isBlockedBySystemSettings)
            let text = try await screen.copy { $0.contains("notifications are off in ios") }
            #expect(text.contains("notifications are off in ios"))
            try screen.photograph(named: "push-settings-2-blocked-by-ios")
        }
    }

    // MARK: - Hosting

    private func withHostedSurface(
        _ surface: EvidencePromptSurface,
        notificationState: ClimbDropNotificationState,
        settle: RenderedScreen.Settle = .turns(12),
        _ whileOnScreen: @MainActor (HostedScreen) async throws -> Void
    ) async throws {
        try await RenderedScreen.host(
            EvidencePromptSurfaceHarness(surface: surface, notificationState: notificationState)
                .frame(width: RenderedScreen.iPhone16ProSize.width, height: RenderedScreen.iPhone16ProSize.height),
            settle: settle,
            whileOnScreen
        )
    }

    private func withHostedSettings(
        notificationState: ClimbDropNotificationState,
        _ whileOnScreen: @MainActor (HostedScreen) async throws -> Void
    ) async throws {
        try await RenderedScreen.host(
            NavigationStack {
                NotificationSettingsView(notificationState: notificationState)
            }
            .frame(width: RenderedScreen.iPhone16ProSize.width, height: RenderedScreen.iPhone16ProSize.height),
            whileOnScreen
        )
    }

    private func isPromptOnScreen(in root: UIView) -> Bool {
        accessibilityElements(under: root).contains {
            $0.accessibilityLabel == "Turn on notifications"
        }
    }
}

/// The two shipping surfaces a climber meets the prompt on, photographed with content rather than
/// bare, so the CTA is seen in the layout it actually lives in.
enum EvidencePromptSurface: String, CaseIterable, CustomStringConvertible {
    case profileAchievements
    case climbsCollection

    var slug: String {
        switch self {
        case .profileAchievements:
            "profile-achievements"
        case .climbsCollection:
            "climbs-collection"
        }
    }

    var description: String {
        switch self {
        case .profileAchievements:
            "Profile Achievements"
        case .climbsCollection:
            "Climbs Collection"
        }
    }
}

private struct EvidencePromptSurfaceHarness: View {
    let surface: EvidencePromptSurface
    let notificationState: ClimbDropNotificationState

    var body: some View {
        Group {
            switch surface {
            case .profileAchievements:
                ScrollView {
                    PrestigeSection(
                        held: [],
                        open: [
                            openFirstAscent(id: "eiffel", name: "Eiffel Tower", location: "Paris, France"),
                            openFirstAscent(id: "burj", name: "Burj Khalifa", location: "Dubai, UAE"),
                            openFirstAscent(id: "cn", name: "CN Tower", location: "Toronto, Canada")
                        ],
                        achievements: .empty,
                        mode: .own,
                        notificationState: notificationState
                    )
                    .padding(20)
                }
            case .climbsCollection:
                ClimbsCollectionView(
                    collection: ProfileCollectionSummary(
                        collectedCount: 3,
                        catalogCount: 12,
                        previewCards: [],
                        launchedCards: [],
                        comingSoonClimbs: []
                    ),
                    mode: .own,
                    notificationState: notificationState
                )
            }
        }
        .background(ProfileVisualStyle.background)
    }

    private func openFirstAscent(
        id: String,
        name: String,
        location: String
    ) -> ProfileFirstAscentSummary {
        ProfileFirstAscentSummary(
            climbId: id,
            climbName: name,
            locationText: location,
            tier: .gold,
            targetSteps: 1_665,
            kind: .open
        )
    }
}

/// Scripts one climber's notification environment: what iOS reports, what the stored climb-drop
/// preference says, and what one enable request turns them into.
@MainActor
private final class EvidenceClimbDropNotificationStateClient: ClimbDropNotificationStateClient {
    var isPreferenceEnabled: Bool
    private(set) var enableCount = 0

    private var status: UNAuthorizationStatus

    init(authorizationStatus: UNAuthorizationStatus, isPreferenceEnabled: Bool) {
        status = authorizationStatus
        self.isPreferenceEnabled = isPreferenceEnabled
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await Task.yield()
        return status
    }

    /// What the climber did while the app was backgrounded and nothing here was running.
    func simulateSystemSettingsGrant() {
        status = .authorized
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
        isPreferenceEnabled = false
        return status
    }

    func openSystemNotificationSettings() {}
}
