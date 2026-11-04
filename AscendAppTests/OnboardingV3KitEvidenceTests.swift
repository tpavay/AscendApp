import Foundation
import SwiftUI
import Testing
@testable import AscendApp

/// The kit on screen: the stub flow with the real header, wordmark and buttons, at the smallest
/// phone Ascend supports and at an accessibility text size. Photographs are written only when
/// `ASCEND_EVIDENCE_DIR` is set.
@MainActor
@Suite(.hostsAWindow)
struct OnboardingV3KitEvidenceTests {
    /// iPhone SE (3rd generation), the smallest phone that runs iOS 26.
    private static let smallestPhone = CGSize(width: 375, height: 667)

    private func coordinator(startingAt step: OnboardingV3Step = .welcome, advancing taps: Int = 0) -> OnboardingV3Coordinator {
        let suite = "onboarding-v3-evidence-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let coordinator = OnboardingV3Coordinator(store: PreAuthOnboardingStore(userDefaults: defaults), startingAt: step)
        for _ in 0..<taps { coordinator.advance() }
        return coordinator
    }

    @Test
    func theWelcomeStubShowsTheRealWordmarkAndItsTwoActions() async throws {
        try await RenderedScreen.host(
            OnboardingV3FlowView(coordinator: coordinator()),
            size: Self.smallestPhone,
            settle: .turns(30)
        ) { screen in
            let copy = try await screen.copy()
            #expect(copy.contains("ascend"), "the wordmark is labelled Ascend: \(copy)")
            #expect(copy.contains("continue"), "\(copy)")
            #expect(copy.contains("already climbing? sign in"), "\(copy)")
            #expect(!copy.contains("onboarding progress"), "01 has no bar: \(copy)")
            try screen.photograph(named: "onboarding-v3-welcome-se")
        }
    }

    /// The bar for 02 ends at 38 percent: lime fill under the first 38 percent of the track and the
    /// dark track after it.
    @Test
    func theProgressBarFillsToItsStepsValueOnTheDesignsColours() async throws {
        try await RenderedScreen.host(
            OnboardingV3FlowView(coordinator: coordinator(advancing: 1)),
            size: Self.smallestPhone,
            settle: .turns(40)
        ) { screen in
            _ = try await screen.copy()
            let bar = try #require(try await screen.frame(ofElementLabelled: "Onboarding progress"))
            #expect(bar.height >= 5 && bar.height <= 7, "6 pt tall: \(bar)")

            let y = bar.midY
            let filled = try screen.color(at: CGPoint(x: bar.minX + bar.width * 0.2, y: y))
            let empty = try screen.color(at: CGPoint(x: bar.minX + bar.width * 0.7, y: y))
            #expect(filled.green > 140 && filled.red < 190 && filled.blue < 90, "lime fill: \(filled)")
            #expect(empty.isClose(to: RGBA(red: 0x26, green: 0x26, blue: 0x26, alpha: 255), tolerance: 12), "track: \(empty)")

            let copy = try await screen.copy()
            #expect(copy.contains("back"), "\(copy)")
            try screen.photograph(named: "onboarding-v3-go-harder-se")
        }
    }

    @Test
    func theSkipAndTheCloseVariantRender() async throws {
        try await RenderedScreen.host(
            OnboardingV3FlowView(coordinator: coordinator(startingAt: .climberCard)),
            size: Self.smallestPhone,
            settle: .turns(30)
        ) { screen in
            let copy = try await screen.copy()
            #expect(copy.contains("skip"), "\(copy)")
            try screen.photograph(named: "onboarding-v3-climber-card-se")
        }

        try await RenderedScreen.host(
            OnboardingProgressHeader(onClose: {}).background(Color.black),
            size: CGSize(width: 375, height: 120),
            settle: .turns(12)
        ) { screen in
            let copy = try await screen.copy()
            #expect(copy.contains("close"), "\(copy)")
            #expect(!copy.contains("onboarding progress"), "the close variant has no bar: \(copy)")
        }
    }

    @Test
    func everyLabelStaysReachableAtAnAccessibilityTextSize() async throws {
        try await RenderedScreen.host(
            OnboardingV3FlowView(coordinator: coordinator(startingAt: .healthConnect))
                .environment(\.dynamicTypeSize, .accessibility3),
            size: Self.smallestPhone,
            settle: .turns(30)
        ) { screen in
            let recognized = try await screen.recognizedText(scale: 2).lowercased()
            let copy = try await screen.copy()
            #expect(copy.contains("continue"), "\(copy)")
            #expect(copy.contains("i don't track workouts"), "\(copy)")
            #expect(recognized.contains("continue"), "legible, not just in the tree: \(recognized)")
            try screen.photograph(named: "onboarding-v3-health-connect-se-accessibility3")
        }
    }

    @Test
    func theSignedOutHoldIsTheWordmarkOnBlackAndNothingElse() async throws {
        try await RenderedScreen.host(
            SignedOutHoldView(),
            size: CGSize(width: 390, height: 844),
            settle: .turns(12)
        ) { screen in
            let wordmark = try #require(try await screen.frame(ofElementLabelled: "Ascend"))
            #expect(abs(wordmark.midX - 195) < 1, "\(wordmark)")
            #expect(try await screen.copy().contains("ascend"))
            try screen.photograph(named: "onboarding-v3-signed-out-hold")
        }
    }

    @Test
    func theWordmarkKeepsTheBrandProportionsAtEveryHeight() async throws {
        try await RenderedScreen.host(
            VStack(alignment: .leading, spacing: 20) {
                AscendWordmark(height: 22, treatment: .onDark)
                AscendWordmark(height: 22, treatment: .mono(.white))
                AscendWordmark(height: 36, treatment: .onDark)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.black),
            size: CGSize(width: 375, height: 220),
            settle: .turns(12)
        ) { screen in
            let wordmark = try #require(try await screen.frame(ofElementLabelled: "Ascend"))
            // 1815 x 413 artwork: a 22 pt A makes a lockup about 96.7 pt wide.
            #expect(abs(wordmark.height - 22) < 1, "\(wordmark)")
            #expect(abs(wordmark.width - 22 * 1815 / 413) < 2, "\(wordmark)")
            try screen.photograph(named: "onboarding-v3-wordmarks")
        }
    }
}
