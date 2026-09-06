import SwiftUI
import Testing
import UIKit
@testable import AscendApp

/// Evidence for the Guideline 4 fix: post-auth onboarding never asks for a name.
///
/// The rejection was a screen, so the proof is the screens. This hosts the real
/// `PostAuthOnboardingFlowView` at every stage a climber can reach after signing in and reads each
/// screen's copy back off its accessibility tree (`RenderedScreen`), asserting that none of them
/// carries the copy the rejected build showed - "What's your name", a First name field, a Last
/// name field. The reviewable filmstrip of every stage is written when `ASCEND_EVIDENCE_DIR` is set.
///
/// Rendered rather than asserted on the enum alone on purpose: `PostAuthOnboardingStage` no longer
/// has a `displayName` case, but what App Review saw was a screen, and a screen is what this shows
/// is gone.
@MainActor
@Suite(.hostsAWindow)
struct PostAuthOnboardingNoNameStepEvidenceTests {
    /// The copy the rejected 1.0 build put in front of every Sign in with Apple climber.
    private static let rejectedNameCopy = [
        "what's your name",
        "first name",
        "last name",
        "name climbers see on leaderboards"
    ]

    private static let screenSize = CGSize(width: 390, height: 844)

    @Test
    func noScreenAClimberReachesAfterSigningInAsksForAName() async throws {
        let stages = PostAuthOnboardingStage.allCases
        #expect(!stages.isEmpty)

        for stage in stages {
            let text = try await screenCopy(stage: stage)
            for phrase in Self.rejectedNameCopy {
                #expect(
                    !text.contains(phrase),
                    "\(stage.rawValue) asks for a name (\"\(phrase)\"). On-screen text: \(text)"
                )
            }
        }

        if RenderedScreen.isPhotographing {
            try RenderedScreen.photograph(
                Filmstrip(stages: stages),
                named: "post-auth-onboarding-every-screen",
                scale: 2
            )
            try RenderedScreen.photograph(
                Self.screen(stage: .first),
                named: "post-auth-onboarding-first-screen-after-sign-in",
                scale: 2
            )
        }
    }

    /// The first thing a climber sees after the authorization sheet closes.
    @Test
    func onboardingOpensOnTheStairStepperQuestionRatherThanANameForm() async throws {
        let text = try await screenCopy(stage: .first)

        #expect(PostAuthOnboardingStage.first == .stairStepperBaseline)
        #expect(
            text.contains("stair"),
            "The opening screen should be the stair stepper question. On-screen text: \(text)"
        )
        for phrase in Self.rejectedNameCopy {
            #expect(!text.contains(phrase), "The opening screen asks for a name. On-screen text: \(text)")
        }
    }

    // MARK: - Reading the hosted screen back

    private func screenCopy(stage: PostAuthOnboardingStage) async throws -> String {
        try await RenderedScreen.host(Self.screen(stage: stage), size: Self.screenSize) { screen in
            try await screen.copy().forOCRComparison
        }
    }

    private static func screen(stage: PostAuthOnboardingStage) -> some View {
        PostAuthOnboardingFlowView(
            stage: stage,
            onBack: {},
            onContinue: {}
        )
        .frame(width: screenSize.width, height: screenSize.height)
        .environment(AuthenticationViewModel(observesFirebaseAuth: false))
        .environment(\.colorScheme, .dark)
    }
}

/// Every stage side by side at half size, for the reviewer.
private struct Filmstrip: View {
    let stages: [PostAuthOnboardingStage]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("EVERY POST-AUTH ONBOARDING SCREEN, IN ORDER")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(Color.ascendAccent)
                Text("No name step. Nothing after Sign in with Apple asks the climber for a name.")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
            }

            HStack(alignment: .top, spacing: 16) {
                ForEach(stages, id: \.self) { stage in
                    VStack(spacing: 8) {
                        Text("\(stage.progressIndex + 1). \(stage.rawValue)")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.85))
                        PostAuthOnboardingFlowView(stage: stage, onBack: {}, onContinue: {})
                            .frame(width: 390, height: 844)
                            .environment(AuthenticationViewModel(observesFirebaseAuth: false))
                            .environment(\.colorScheme, .dark)
                            .scaleEffect(0.5)
                            .frame(width: 195, height: 422)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(.white.opacity(0.18), lineWidth: 1)
                            )
                    }
                }
            }
        }
        .padding(28)
        .background(Color.black)
    }
}

private extension String {
    var forOCRComparison: String {
        lowercased()
            .replacing("\u{2019}", with: "'")
            .replacing("\u{2018}", with: "'")
    }
}
