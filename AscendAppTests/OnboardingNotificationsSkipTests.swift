import Foundation
import SwiftUI
import Testing
import UIKit
import UserNotifications
@testable import AscendApp

/// Presses the real controls on the onboarding notifications step.
///
/// `OnboardingEmailOptInViewModelTests` covers `recordDecision()` directly; this
/// suite covers the wiring between the buttons and it, because the board's
/// settled Skip behaviour - ticking email and tapping Skip still saves the tick
/// - lives in the screen, not in the view model. The screen takes an
/// already-built `OnboardingEmailOptInViewModel` so the write is observable;
/// production keeps the default and is unchanged.
///
/// ENABLE NOTIFICATIONS is deliberately not pressed. That path calls
/// `UNUserNotificationCenter.requestAuthorization`, which raises the real iOS
/// prompt inside the test host, so a test cannot press it deterministically.
/// What is proved here instead is the half of the invariant that is provable in
/// process: the email answer is written by Skip alone, and Skip leaves the push
/// authorization status where it found it - it declines push rather than asking
/// for it. That the reverse direction holds (Enable never ticks the box) is
/// carried by `requestNotifications()` containing no write to `emailOptIn`, not
/// by an assertion here.
@Suite(.serialized, .hostsAWindow)
@MainActor
struct OnboardingNotificationsSkipTests {
    @Test
    func skipSavesATickedBoxAsAnOnboardingYes() async throws {
        let service = SkipRecordingEmailPreferencesService()
        let optIn = OnboardingEmailOptInViewModel(service: service)

        let statusBefore = await PushNotificationService.shared.authorizationStatus()

        try await hostNotificationsStep(emailOptIn: optIn) { screen in
            #expect(optIn.isSelected, "The box ships ticked")
            try screen.photograph(named: "onboarding-skip-box-ticked")
            try activateAccessibilityElement(labelled: "Skip", in: screen.root)
        }

        let decisions = await service.awaitDecisions()
        #expect(decisions == [StubEmailConsentDecision(isGranted: true, source: .onboarding)])
        report("box left ticked, Skip pressed", recorded: decisions)

        // Skip declines push; it must not be a second way to ask for it.
        let statusAfter = await PushNotificationService.shared.authorizationStatus()
        #expect(statusAfter == statusBefore)
    }

    @Test
    func skipSavesAnUntickedBoxAsAnExplicitNo() async throws {
        // An untick that Skip drops on the floor would leave the preference
        // absent, and absent is exactly the state this whole change exists to
        // stop Ascend reading as a yes.
        let service = SkipRecordingEmailPreferencesService()
        let optIn = OnboardingEmailOptInViewModel(service: service)

        try await hostNotificationsStep(emailOptIn: optIn) { screen in
            try activateAccessibilityElement(labelled: "Email me when climbs drop.", in: screen.root)
            #expect(optIn.isSelected == false)
            try screen.photograph(named: "onboarding-skip-box-unticked")
            try activateAccessibilityElement(labelled: "Skip", in: screen.root)
        }

        let decisions = await service.awaitDecisions()
        #expect(decisions == [StubEmailConsentDecision(isGranted: false, source: .onboarding)])
        report("box unticked by the climber, Skip pressed", recorded: decisions)
    }

    // MARK: - Hosting

    /// Puts the shipping step in a real window through `RenderedScreen` so its
    /// controls exist and can be pressed, then tears it down once
    /// `whileOnScreen` has finished with it. The photograph `whileOnScreen`
    /// takes shows the step exactly as it stands when Skip is about to be
    /// pressed - which way the box was pointing at the moment of the press -
    /// and is written only under `ASCEND_EVIDENCE_DIR`.
    private func hostNotificationsStep(
        emailOptIn: OnboardingEmailOptInViewModel,
        whileOnScreen: (HostedScreen) throws -> Void
    ) async throws {
        // Skip writes the device-local push preference. It is global state the
        // rest of the suite shares, so it goes back exactly as it was found.
        let pushPreference = ClimbDropNotificationPreferenceStore.isEnabled
        defer { ClimbDropNotificationPreferenceStore.isEnabled = pushPreference }

        let size = RenderedScreen.iPhone16ProSize
        try await RenderedScreen.host(
            PostAuthNotificationScreen(
                stage: .notifications,
                onBack: {},
                onContinue: {},
                emailOptIn: emailOptIn
            )
            .frame(width: size.width, height: size.height),
            size: size,
            settle: .turns(8)
        ) { screen in
            try whileOnScreen(screen)

            // The button handlers hop through their own tasks before the write
            // starts, so the screen stays up long enough for them to get there.
            try await screen.settle(.turns(8))
        }
    }

    /// Prints what the press actually persisted, so the recorded answer reads
    /// back in the run transcript next to the photograph of the screen it came
    /// from.
    private func report(_ situation: String, recorded decisions: [StubEmailConsentDecision]) {
        let written = decisions
            .map { "lifecycleEmailsEnabled=\($0.isGranted) source=\($0.source.rawValue)" }
            .joined(separator: ", ")
        print("Onboarding Skip - \(situation) -> wrote [\(written.isEmpty ? "nothing" : written)]")
    }
}

private actor SkipRecordingEmailPreferencesService: EmailPreferencesProviding {
    private var storedConsent: LifecycleEmailConsent = .undecided
    private var savedDecisions: [StubEmailConsentDecision] = []

    /// The screen records the decision on an unstructured task so onboarding is
    /// never held open on the network, so the test waits on the write rather
    /// than assuming it has already landed.
    func awaitDecisions() async -> [StubEmailConsentDecision] {
        for _ in 0..<100 where savedDecisions.isEmpty {
            try? await Task.sleep(for: .milliseconds(20))
        }

        return savedDecisions
    }

    func loadConsent() async throws -> LifecycleEmailConsent {
        storedConsent
    }

    func recordConsent(
        isGranted: Bool,
        source: LifecycleEmailConsentSource
    ) async throws {
        savedDecisions.append(
            StubEmailConsentDecision(isGranted: isGranted, source: source)
        )
        storedConsent = LifecycleEmailConsent(isGranted: isGranted)
    }
}
