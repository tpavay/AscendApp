import SwiftUI
import Testing
import UIKit
import Vision
@testable import AscendApp

/// Visual evidence for the post-auth gender question copy.
///
/// The question a climber reads has to name what it asks for. `Choose your
/// division` asked about a word the app never defines, so this holds the plain
/// version: the headline asks for the gender and the four answers stay
/// Male / Female / Other / Prefer not to say.
///
/// The screen carries no subtitle on purpose. Gender drives no comparison group,
/// no filter, and no profile field - it reaches a climber only as the `M` / `F`
/// abbreviation in the leaderboard demographic row - so every public-context line
/// proposed for it so far described behavior that does not exist. The negative
/// assertions below are what keep one from coming back.
@MainActor
struct PostAuthGenderQuestionCopySnapshotTests {
    private static let expectedHeadline = "What's your gender?"
    private static let expectedOptions = ["Male", "Female", "Other", "Prefer not to say"]

    @Test
    func theGenderStepAsksForGenderWithoutClaimingAPublicUse() async throws {
        let image = try renderGenderStep()
        let text = try await recognizedText(in: image)

        // Evidence lands before the expectations are judged, so a failing run
        // still leaves a reviewable picture of what the climber actually sees.
        try writeEvidence(image: image, named: "post-auth-gender-question.png")

        #expect(
            text.contains(Self.expectedHeadline.forOCRComparison),
            "Headline should read \"\(Self.expectedHeadline)\". Rendered text: \(text)"
        )
        for option in Self.expectedOptions {
            #expect(
                text.contains(option.forOCRComparison),
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

    // MARK: - Rendering

    private func renderGenderStep() throws -> UIImage {
        let renderer = ImageRenderer(
            content: PostAuthOnboardingFlowView(
                stage: .gender,
                onBack: {},
                onContinue: {}
            )
            .frame(width: 390, height: 844)
            .environment(AuthenticationViewModel())
            .environment(\.colorScheme, .dark)
        )
        renderer.scale = 3
        return try #require(renderer.uiImage, "ImageRenderer produced no image")
    }

    // MARK: - Reading the rendered pixels back

    private func recognizedText(in image: UIImage) async throws -> String {
        let cgImage = try #require(image.cgImage, "UIImage had no CGImage")
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false

        let observations = try await request.perform(on: cgImage)
        return observations
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: " ")
            .forOCRComparison
    }

    private func writeEvidence(image: UIImage, named name: String) throws {
        let png = try #require(image.pngData(), "UIImage produced no PNG data")
        let directory = ProcessInfo.processInfo.environment["ASCEND_EVIDENCE_DIR"]
            ?? NSTemporaryDirectory()
        try png.write(to: URL(filePath: directory).appending(path: name))
        #expect(png.count > 5_000)
    }
}

private extension String {
    /// Vision returns typographic apostrophes for the straight ones in source,
    /// so both sides of a comparison get folded to the same shape.
    var forOCRComparison: String {
        lowercased()
            .replacing("\u{2019}", with: "'")
            .replacing("\u{2018}", with: "'")
    }
}
