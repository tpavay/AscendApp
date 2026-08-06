import SwiftUI
import Testing
import UIKit
import UserNotifications
@testable import AscendApp

/// Reviewer-facing photographs of the two surfaces that ask a climber to turn climb-drop
/// notifications on: Profile Achievements and the Climbs Collection.
///
/// `ClimbDropNotificationPromptHostingTests` proves the prompt's visibility with the accessibility
/// tree; these tests put the same hosted screens in front of a camera so the report shows what a
/// climber sees. The grant transition is photographed inside one mounted window - the screen is
/// never rebuilt between the before and after frames, which is exactly the "without a relaunch"
/// claim.
///
/// Images land in `ASCEND_EVIDENCE_DIR` when it is set and in the test host's temporary directory
/// otherwise; the path is logged either way. Nothing reads them back - these are evidence, not
/// golden-image assertions.
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

        try await withHostedSurface(surface, notificationState: state) { root in
            await settle(root)
            #expect(isPromptOnScreen(in: root))
            try await photograph(root, named: "\(surface.slug)-1-not-yet-asked")

            // The climber taps the CTA on the screen that is already up.
            try activateAccessibilityElement(labelled: "Turn on notifications", in: root)
            await settle(root)

            #expect(client.enableCount == 1)
            #expect(state.isEnabled)
            #expect(isPromptOnScreen(in: root) == false)
            try await photograph(root, named: "\(surface.slug)-2-after-granting")
        }
    }

    @Test(
        "An already enabled climber is photographed never seeing the prompt",
        .bug(id: 397),
        arguments: EvidencePromptSurface.allCases
    )
    func theEnabledFirstRenderIsPhotographed(surface: EvidencePromptSurface) async throws {
        // The captain's state: iOS permission allowed and the climb-drop preference on. The status
        // is deliberately left unresolved so the very first frame is the one under the camera.
        let client = EvidenceClimbDropNotificationStateClient(
            authorizationStatus: .authorized,
            isPreferenceEnabled: true
        )
        let state = ClimbDropNotificationState(client: client, observesEnvironmentChanges: false)

        try await withHostedSurface(surface, notificationState: state) { root in
            // Every frame from the first one on, not just the settled one: a prompt that flashes
            // and then corrects itself is the defect, not the fix.
            for _ in 0..<8 {
                #expect(isPromptOnScreen(in: root) == false)
                await Task.yield()
                root.setNeedsLayout()
                root.layoutIfNeeded()
            }

            // The screen did publish a tree over those passes, so the absence above is a reading
            // rather than an empty one.
            #expect(accessibilityElements(under: root).isEmpty == false)
            try await photograph(root, named: "\(surface.slug)-3-enabled-first-render")

            await state.refresh()
            await settle(root)

            #expect(state.isEnabled)
            #expect(isPromptOnScreen(in: root) == false)
            try await photograph(root, named: "\(surface.slug)-4-enabled-after-refresh")
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

        try await withHostedSurface(surface, notificationState: deniedState) { root in
            await settle(root)
            #expect(isPromptOnScreen(in: root))
            try await photograph(root, named: "\(surface.slug)-5-denied")
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

        try await withHostedSurface(surface, notificationState: preferenceOffState) { root in
            await settle(root)
            #expect(isPromptOnScreen(in: root))
            try await photograph(root, named: "\(surface.slug)-6-allowed-but-preference-off")
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

        try await withHostedSurface(surface, notificationState: state) { root in
            await settle(root)
            #expect(state.isBlockedBySystemSettings)
            #expect(isPromptOnScreen(in: root))
            try await photograph(root, named: "\(surface.slug)-7-blocked-before-leaving")

            client.simulateSystemSettingsGrant()
            NotificationCenter.default.post(
                name: UIApplication.willEnterForegroundNotification,
                object: nil
            )
            await settle(root)

            #expect(state.isEnabled)
            #expect(isPromptOnScreen(in: root) == false)
            try await photograph(root, named: "\(surface.slug)-8-after-returning-from-ios-settings")
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

        try await withHostedSettings(notificationState: allowedState) { root in
            try await photograph(root, named: "push-settings-1-allowed-and-on")
        }

        let blocked = EvidenceClimbDropNotificationStateClient(
            authorizationStatus: .denied,
            isPreferenceEnabled: true
        )
        let blockedState = ClimbDropNotificationState(client: blocked, observesEnvironmentChanges: false)
        await blockedState.refresh()

        try await withHostedSettings(notificationState: blockedState) { root in
            #expect(blockedState.isBlockedBySystemSettings)
            try await photograph(root, named: "push-settings-2-blocked-by-ios")
        }
    }

    // MARK: - Hosting

    private func withHostedSurface(
        _ surface: EvidencePromptSurface,
        notificationState: ClimbDropNotificationState,
        _ whileOnScreen: (UIView) async throws -> Void
    ) async throws {
        try await host(
            EvidencePromptSurfaceHarness(surface: surface, notificationState: notificationState),
            whileOnScreen
        )
    }

    private func withHostedSettings(
        notificationState: ClimbDropNotificationState,
        _ whileOnScreen: (UIView) async throws -> Void
    ) async throws {
        try await host(
            NavigationStack {
                NotificationSettingsView(notificationState: notificationState)
            },
            whileOnScreen
        )
    }

    private func host(
        _ view: some View,
        _ whileOnScreen: (UIView) async throws -> Void
    ) async throws {
        try await withAccessibilityAutomation {
            let size = CGSize(width: 402, height: 874)
            let controller = UIHostingController(rootView: view.frame(width: size.width, height: size.height))
            controller.overrideUserInterfaceStyle = .dark
            controller.view.frame = CGRect(origin: .zero, size: size)

            let window = UIWindow(frame: controller.view.frame)
            window.overrideUserInterfaceStyle = .dark
            window.rootViewController = controller
            window.makeKeyAndVisible()
            defer { window.isHidden = true }

            controller.view.setNeedsLayout()
            controller.view.layoutIfNeeded()

            try await whileOnScreen(controller.view)
        }
    }

    private func settle(_ view: UIView) async {
        for _ in 0..<8 {
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

    private func photograph(_ view: UIView, named name: String) async throws {
        // Fonts, strokes and the toggle knob need a few passes before the frame is final.
        for _ in 0..<8 {
            view.setNeedsLayout()
            view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(40))
        }

        let format = UIGraphicsImageRendererFormat.preferred()
        format.scale = 3
        let image = UIGraphicsImageRenderer(size: view.bounds.size, format: format).image { _ in
            view.drawHierarchy(in: view.bounds, afterScreenUpdates: true)
        }
        let png = try #require(image.pngData(), "UIImage produced no PNG data")

        let directory = ProcessInfo.processInfo.environment["ASCEND_EVIDENCE_DIR"]
            ?? NSTemporaryDirectory()
        let url = URL(filePath: directory).appending(path: "\(name).png")
        try png.write(to: url)

        #expect(png.count > 5_000)
        print("Rendered climb-drop notification evidence: \(url.path())")
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
                        achievements: .zero,
                        achievementRecords: [],
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
