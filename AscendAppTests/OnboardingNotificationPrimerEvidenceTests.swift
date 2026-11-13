import Foundation
import SwiftUI
import Testing
@testable import AscendApp

/// Screen 12 on screen, at the smallest phone and at an accessibility text size. Photographs are
/// written only when `ASCEND_EVIDENCE_DIR` is set.
@MainActor
@Suite(.hostsAWindow)
struct OnboardingNotificationPrimerEvidenceTests {
    /// iPhone SE (3rd generation), the smallest phone that runs iOS 26.
    private static let smallestPhone = CGSize(width: 375, height: 667)

    private func flow(target: Int?) -> OnboardingV3FlowView {
        let suite = "notification-primer-evidence-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let coordinator = OnboardingV3Coordinator(
            store: PreAuthOnboardingStore(userDefaults: defaults),
            startingAt: .notificationPrimer
        )
        coordinator.update {
            $0.weeklyTargetDays = target
            $0.usualClimbMinutes = 20
        }
        return OnboardingV3FlowView(coordinator: coordinator)
    }

    @Test
    func theWholeScreenFitsTheSmallestPhone() async throws {
        try await RenderedScreen.host(flow(target: 3), size: Self.smallestPhone, settle: .turns(60)) { screen in
            let copy = try await screen.copy()
            #expect(copy.contains("we'll keep you on track."), "\(copy)")
            #expect(copy.contains("turn on"), "\(copy)")
            #expect(copy.contains("not now"), "\(copy)")
            #expect(copy.contains("one climb from your target"), "\(copy)")
            #expect(copy.contains("gear just dropped"), "\(copy)")
            #expect(copy.contains("new climb open"), "\(copy)")
            #expect(!copy.contains("that's it"), "\(copy)")
            #expect(copy.contains("onboarding progress"), "the bar shows on 12: \(copy)")

            let bar = try #require(try await screen.frame(ofElementLabelled: "Onboarding progress"))
            #expect(bar.minY >= 0 && bar.maxY <= Self.smallestPhone.height)
            let turnOn = try #require(try await screen.frame(ofElementLabelled: "Turn on"))
            #expect(turnOn.maxY <= Self.smallestPhone.height, "the buttons stay on the phone: \(turnOn)")

            // The copy sits above the buttons rather than under them, with no scrolling needed.
            let body = try #require(
                try await screen.frame(ofElementLabelled: NotificationPrimerContent.body(hasTarget: true))
            )
            #expect(body.maxY <= turnOn.minY, "the body \(body) clears the button \(turnOn)")
            let emailBox = try #require(
                try await screen.frame(ofElementLabelled: NotificationPrimerContent.emailOptInLabel)
            )
            #expect(body.maxY <= emailBox.minY, "the body \(body) clears the email box \(emailBox)")
            #expect(emailBox.maxY <= turnOn.minY, "the email box \(emailBox) sits above the button \(turnOn)")
            let lastCard = try #require(try await screen.frame(ofElementLabelled: "Example notification. New climb open, Today. Burj Khalifa just opened. Be the first to the top."))
            let headline = try #require(try await screen.frame(ofElementLabelled: "We'll keep you on track."))
            #expect(lastCard.maxY <= headline.minY, "the cards clear the headline")
            try screen.photograph(named: "onboarding-v3-notification-primer-se")
        }
    }

    @Test
    func withoutATargetTheScreenOffersOnlyTheOtherTwoExamples() async throws {
        try await RenderedScreen.host(flow(target: nil), size: Self.smallestPhone, settle: .turns(60)) { screen in
            let copy = try await screen.copy()
            #expect(!copy.contains("from your target"), "\(copy)")
            #expect(!copy.contains("weekly target"), "\(copy)")
            #expect(copy.contains("gear just dropped"), "\(copy)")
            #expect(copy.contains("new climb open"), "\(copy)")
            try screen.photograph(named: "onboarding-v3-notification-primer-no-target-se")
        }
    }

    @Test
    func theButtonsStayReachableAtAnAccessibilityTextSize() async throws {
        try await RenderedScreen.host(
            flow(target: 3).environment(\.dynamicTypeSize, .accessibility3),
            size: Self.smallestPhone,
            settle: .turns(60)
        ) { screen in
            let recognized = try await screen.recognizedText(scale: 2).lowercased()
            let copy = try await screen.copy()
            #expect(copy.contains("turn on"), "\(copy)")
            #expect(copy.contains("not now"), "\(copy)")
            #expect(recognized.contains("turn on"), "legible, not just in the tree: \(recognized)")
            try screen.photograph(named: "onboarding-v3-notification-primer-se-accessibility3")
        }
    }

    @Test
    func thePrimerRendersOnTheCurrentPhone() async throws {
        try await RenderedScreen.host(flow(target: 3), settle: .turns(60)) { screen in
            _ = try await screen.copy()
            try screen.photograph(named: "onboarding-v3-notification-primer-16pro")
        }
    }
}
