import SwiftUI
import Testing
import UIKit
@testable import AscendApp

/// Evidence that the email ask is on the onboarding notifications step,
/// pre-ticked, and that adding it did not push the CTA or the Skip link off the
/// screen it shares.
///
/// The ask is a checkbox on a step that already exists rather than a step of its
/// own, and it is a separate answer from push: tapping ENABLE NOTIFICATIONS must
/// not tick it, and Skip must not clear it. Those two are held by
/// `OnboardingEmailOptInViewModelTests`; this holds that a climber can see the
/// box and read what it says before they answer either question. The step is
/// hosted at phone size through `RenderedScreen` and its copy read off the
/// accessibility tree, which only lists what is inside the window - so a control
/// pushed off the bottom is missing from it exactly as it would be from the
/// screen.
@MainActor
@Suite(.hostsAWindow)
struct OnboardingEmailOptInSnapshotTests {
    @Test
    func theNotificationsStepAsksAboutEmailWithoutLosingItsButtons() async throws {
        try await RenderedScreen.host(
            PostAuthOnboardingFlowView(
                stage: .notifications,
                onBack: {},
                onContinue: {}
            )
            .environment(AuthenticationViewModel()),
            size: CGSize(width: 390, height: 844)
        ) { screen in
            let text = try await screen.copy { $0.contains("email me when climbs drop") }

            #expect(text.contains("email me when climbs drop"))
            #expect(text.contains("never miss an"))
            #expect(text.contains("enable notifications"))
            #expect(text.contains("skip"))

            try screen.photograph(named: "onboarding-email-opt-in")
        }
    }
}
