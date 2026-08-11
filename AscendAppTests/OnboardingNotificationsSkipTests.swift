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

        try await hostNotificationsStep(emailOptIn: optIn) { root in
            #expect(optIn.isSelected, "The box ships ticked")
            try photograph(root, named: "onboarding-skip-box-ticked.png")
            try activateElement(labelled: "Skip", in: root)
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

        try await hostNotificationsStep(emailOptIn: optIn) { root in
            try activateElement(labelled: "Email me when climbs drop.", in: root)
            #expect(optIn.isSelected == false)
            try photograph(root, named: "onboarding-skip-box-unticked.png")
            try activateElement(labelled: "Skip", in: root)
        }

        let decisions = await service.awaitDecisions()
        #expect(decisions == [StubEmailConsentDecision(isGranted: false, source: .onboarding)])
        report("box unticked by the climber, Skip pressed", recorded: decisions)
    }

    // MARK: - Hosting

    /// Puts the shipping step in a real window so its controls exist and can be
    /// pressed, then tears it down once `whileOnScreen` has finished with it.
    private func hostNotificationsStep(
        emailOptIn: OnboardingEmailOptInViewModel,
        whileOnScreen: (UIView) throws -> Void
    ) async throws {
        // Skip writes the device-local push preference. It is global state the
        // rest of the suite shares, so it goes back exactly as it was found.
        let pushPreference = ClimbDropNotificationPreferenceStore.isEnabled
        defer { ClimbDropNotificationPreferenceStore.isEnabled = pushPreference }

        try await withAccessibilityAutomation {
            let size = CGSize(width: 402, height: 874)
            let controller = UIHostingController(
                rootView: PostAuthNotificationScreen(
                    stage: .notifications,
                    onBack: {},
                    onContinue: {},
                    emailOptIn: emailOptIn
                )
                .frame(width: size.width, height: size.height)
            )
            controller.view.frame = CGRect(origin: .zero, size: size)

            let window = UIWindow(frame: controller.view.frame)
            window.overrideUserInterfaceStyle = .dark
            window.rootViewController = controller
            window.makeKeyAndVisible()
            defer { window.isHidden = true }

            for _ in 0..<8 {
                controller.view.setNeedsLayout()
                controller.view.layoutIfNeeded()
                try await Task.sleep(for: .milliseconds(50))
            }

            try whileOnScreen(controller.view)

            // The button handlers hop through their own tasks before the write
            // starts, so the screen stays up long enough for them to get there.
            for _ in 0..<8 {
                try await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    /// Photographs the step exactly as it stands when Skip is about to be
    /// pressed, so which way the box was pointing at the moment of the press is
    /// visible rather than only asserted. Images land in `ASCEND_EVIDENCE_DIR`
    /// when it is set and in the test host's temporary directory otherwise.
    /// Nothing reads them back - these are evidence, not golden images.
    private func photograph(_ view: UIView, named name: String) throws {
        let format = UIGraphicsImageRendererFormat.preferred()
        format.scale = 3
        let image = UIGraphicsImageRenderer(size: view.bounds.size, format: format).image { _ in
            view.drawHierarchy(in: view.bounds, afterScreenUpdates: true)
        }
        let png = try #require(image.pngData(), "UIImage produced no PNG data")

        let directory = ProcessInfo.processInfo.environment["ASCEND_EVIDENCE_DIR"]
            ?? NSTemporaryDirectory()
        let url = URL(filePath: directory).appending(path: name)
        try png.write(to: url)

        #expect(png.count > 5_000)
        print("Rendered onboarding Skip evidence: \(url.path())")
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

    private func activateElement(labelled label: String, in root: UIView) throws {
        try activateAccessibilityElement(labelled: label, in: root)
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
