import Foundation
import SwiftUI
import Testing
import UIKit
@testable import AscendApp

/// Screen 15 on the simulator, at the smallest phone and at an accessibility text size. Photographs
/// are written only when `ASCEND_EVIDENCE_DIR` is set.
@MainActor
@Suite(.hostsAWindow)
struct OnboardingAuthEvidenceTests {
    private static let smallestPhone = CGSize(width: 375, height: 667)

    private func coordinator(from origin: OnboardingV3Step) -> OnboardingV3Coordinator {
        let suite = "onboarding-auth-evidence-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let coordinator = OnboardingV3Coordinator(store: PreAuthOnboardingStore(userDefaults: defaults), startingAt: origin)
        coordinator.go(to: .auth)
        return coordinator
    }

    private func screen(from origin: OnboardingV3Step) -> some View {
        OnboardingAuthScreen(coordinator: coordinator(from: origin))
            .environment(AuthenticationViewModel())
            .background(Color.black)
            .environment(\.colorScheme, .dark)
    }

    @Test
    func theClaimYourSpotScreenShowsTheExampleBoardAndYourEmptyRow() async throws {
        try await RenderedScreen.host(screen(from: .paywall), size: Self.smallestPhone, settle: .turns(40)) { hosted in
            let copy = try await hosted.copy()
            #expect(copy.contains("claim your"), "\(copy)")
            #expect(copy.contains("maya d."), "\(copy)")
            #expect(copy.contains("noah r."), "\(copy)")
            #expect(copy.contains("ava m."), "\(copy)")
            #expect(copy.contains("38,891"), "\(copy)")
            #expect(copy.contains("you, not ranked yet"), "\(copy)")
            #expect(copy.contains("continue with apple"), "\(copy)")
            #expect(copy.contains("continue with google"), "\(copy)")
            #expect(copy.contains("ascend"), "the wordmark: \(copy)")
            #expect(!copy.contains("your name here"), "no name prompt: \(copy)")
            try hosted.photograph(named: "onboarding-v3-auth-claim-se")
        }
    }

    @Test
    func nothingOnTheScreenTakesTypedInput() async throws {
        try await RenderedScreen.host(screen(from: .paywall), size: Self.smallestPhone, settle: .turns(40)) { hosted in
            _ = try await hosted.copy()
            func inputs(in view: UIView) -> Int {
                let own = (view is UITextField || view is UITextView || view is UISearchBar) ? 1 : 0
                return own + view.subviews.reduce(0) { $0 + inputs(in: $1) }
            }
            #expect(inputs(in: hosted.window) == 0)
        }
    }

    @Test
    func returningModeFromTheFirstScreenShowsNoBoard() async throws {
        try await RenderedScreen.host(screen(from: .welcome), size: Self.smallestPhone, settle: .turns(40)) { hosted in
            let copy = try await hosted.copy()
            #expect(copy.contains("welcome back"), "\(copy)")
            #expect(copy.contains("keep climbing"), "\(copy)")
            #expect(!copy.contains("maya d."), "no board: \(copy)")
            #expect(!copy.contains("not ranked yet"), "no climber row: \(copy)")
            #expect(copy.contains("back"), "a way back: \(copy)")
            #expect(copy.contains("continue with apple"), "\(copy)")
            try hosted.photograph(named: "onboarding-v3-auth-returning-se")
        }
    }

    @Test
    func everyControlStaysReachableAtAnAccessibilityTextSize() async throws {
        try await RenderedScreen.host(
            screen(from: .paywall).environment(\.dynamicTypeSize, .accessibility3),
            size: Self.smallestPhone,
            settle: .turns(40)
        ) { hosted in
            let copy = try await hosted.copy()
            #expect(copy.contains("continue with apple"), "\(copy)")
            #expect(copy.contains("continue with google"), "\(copy)")
            #expect(copy.contains("maya d."), "\(copy)")
            let recognized = try await hosted.recognizedText(scale: 2).lowercased()
            #expect(recognized.contains("claim"), "legible, not just in the tree: \(recognized)")
            try hosted.photograph(named: "onboarding-v3-auth-claim-se-accessibility3")
        }
    }
}
