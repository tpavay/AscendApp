import SwiftUI
import Testing
import UIKit
@testable import AscendApp

/// Evidence for the post-auth gender question copy.
///
/// The question a climber reads has to name what it asks for. `Choose your
/// division` asked about a word the app never defines, so this holds the plain
/// version: the headline asks for the gender and the four answers stay
/// Male / Female / Other / Prefer not to say. The step is hosted in a real
/// window and its copy read off the accessibility tree (`RenderedScreen`).
///
/// The screen carries no subtitle on purpose. Gender drives no comparison group,
/// no filter, and no profile field - it reaches a climber only as the `M` / `F`
/// abbreviation in the leaderboard demographic row - so every public-context line
/// proposed for it so far described behavior that does not exist. The negative
/// assertions below are what keep one from coming back.
@MainActor
@Suite(.hostsAWindow)
struct PostAuthGenderQuestionCopySnapshotTests {
    private static let expectedHeadline = "What's your gender?"
    private static let expectedOptions = ["Male", "Female", "Other", "Prefer not to say"]

    @Test
    func theGenderStepAsksForGenderWithoutClaimingAPublicUse() async throws {
        let text = try await RenderedScreen.host(
            PostAuthOnboardingFlowView(
                stage: .gender,
                onBack: {},
                onContinue: {}
            )
            .frame(width: 390, height: 844)
            .environment(AuthenticationViewModel()),
            size: CGSize(width: 390, height: 844)
        ) { screen in
            let text = try await screen.copy { $0.contains("gender") }

            // Evidence lands before the expectations are judged, so a failing run
            // still leaves a reviewable picture of what the climber actually sees.
            try screen.photograph(named: "post-auth-gender-question")

            return text
        }

        #expect(
            text.contains(Self.expectedHeadline.lowercased()),
            "Headline should read \"\(Self.expectedHeadline)\". Rendered text: \(text)"
        )
        for option in Self.expectedOptions {
            #expect(
                text.contains(option.lowercased()),
                "Option \"\(option)\" should be on the screen. Rendered text: \(text)"
            )
        }

        // The jargon the rewrite exists to remove.
        #expect(
            !text.contains("division"),
            "The screen should not use undefined division jargon. Rendered text: \(text)"
        )
        #expect(
            !text.contains("your sex"),
            "The screen should stay consistent with the gender question. Rendered text: \(text)"
        )

        // A claim the answer does not earn. Gender is not a comparison group,
        // not a filter, and not a profile field, so a subtitle promising one
        // would describe a feature the app does not have.
        #expect(
            !text.contains("comparison"),
            "The screen should not claim gender drives a comparison. Rendered text: \(text)"
        )
    }

    /// The Edit Profile row and the onboarding step have to name the same thing.
    @Test
    func editProfileStillLabelsTheSameQuestionGender() {
        #expect(Self.expectedHeadline.localizedCaseInsensitiveContains("gender"))
        #expect(ProfileGender.allCases.count == Self.expectedOptions.count)
    }
}
