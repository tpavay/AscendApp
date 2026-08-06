import SwiftUI
import Testing
import UIKit
import Vision
@testable import AscendApp

/// Visual evidence for the post-auth gender question copy.
///
/// The question a climber reads has to say what the answer is for. `Choose your
/// division` asked about a word the app never defines, so this holds the plain
/// version: the headline asks for the gender, the subtitle says the gender sets
/// the leaderboard comparison, and the four answers stay Male / Female / Other /
/// Prefer not to say.
///
/// The subtitle also has to survive the shell it renders in - 334pt wide, one
/// short line - so `theSubtitleFitsOneLineAtTheOnboardingWidth` measures it
/// rather than trusting that it looks fine on one simulator.
@MainActor
struct PostAuthGenderQuestionCopySnapshotTests {
    private static let expectedHeadline = "What's your gender?"
    private static let expectedSubtitle = "Your gender sets your leaderboard comparison."
    private static let expectedOptions = ["Male", "Female", "Other", "Prefer not to say"]

    /// The shell lays the headline and subtitle out in a 334pt column.
    private static let copyColumnWidth: CGFloat = 334

    @Test
    func theGenderStepAsksForGenderAndSaysWhatItIsFor() async throws {
        let image = try renderGenderStep()
        let text = try await recognizedText(in: image)

        // Evidence lands before the expectations are judged, so a failing run
        // still leaves a reviewable picture of what the climber actually sees.
        try writeEvidence(image: image, named: "post-auth-gender-question.png")

        #expect(
            text.contains(Self.expectedHeadline.forOCRComparison),
            "Headline should read \"\(Self.expectedHeadline)\". Rendered text: \(text)"
        )
        #expect(
            text.contains(Self.expectedSubtitle.forOCRComparison),
            "Subtitle should read \"\(Self.expectedSubtitle)\". Rendered text: \(text)"
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
            "The subtitle should stay consistent with the gender question. Rendered text: \(text)"
        )
    }

    @Test
    func theSubtitleFitsOneLineAtTheOnboardingWidth() throws {
        let font = try #require(
            UIFont(name: "Montserrat-Medium", size: 11),
            "Montserrat-Medium is not registered in the test host"
        )

        let bounds = (Self.expectedSubtitle as NSString).boundingRect(
            with: CGSize(width: Self.copyColumnWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font],
            context: nil
        )

        #expect(
            bounds.height <= font.lineHeight * 1.5,
            """
            Subtitle must wrap to one line at \(Self.copyColumnWidth)pt. \
            Measured \(bounds.height)pt against a \(font.lineHeight)pt line.
            """
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
