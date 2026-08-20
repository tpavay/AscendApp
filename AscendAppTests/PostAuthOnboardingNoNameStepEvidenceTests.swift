import SwiftUI
import Testing
import UIKit
import Vision
@testable import AscendApp

/// Visual evidence for the Guideline 4 fix: post-auth onboarding never asks for a name.
///
/// The rejection was a screen, so the proof has to be pictures of screens. This renders the real
/// `PostAuthOnboardingFlowView` at every stage a climber can reach after signing in, writes the
/// strip out as one reviewable image, and reads the pixels back with Vision to assert that none of
/// them carries the copy the rejected build showed - "What's your name", a First name field, a Last
/// name field.
///
/// Rendered rather than asserted on the enum alone on purpose: `PostAuthOnboardingStage` no longer
/// has a `displayName` case, but what App Review saw was a screen, and a screen is what this shows
/// is gone.
@MainActor
struct PostAuthOnboardingNoNameStepEvidenceTests {
    /// The copy the rejected 1.0 build put in front of every Sign in with Apple climber.
    private static let rejectedNameCopy = [
        "what's your name",
        "first name",
        "last name",
        "name climbers see on leaderboards"
    ]

    @Test
    func noScreenAClimberReachesAfterSigningInAsksForAName() async throws {
        let stages = PostAuthOnboardingStage.allCases
        var rendered: [(stage: PostAuthOnboardingStage, image: UIImage)] = []

        for stage in stages {
            rendered.append((stage, try render(stage: stage)))
        }

        let filmstrip = try #require(
            ImageRenderer(content: Filmstrip(screens: rendered)).uiImage,
            "ImageRenderer produced no filmstrip"
        )
        try writeEvidence(image: filmstrip, named: "post-auth-onboarding-every-screen.png")
        try writeEvidence(
            image: try #require(rendered.first?.image),
            named: "post-auth-onboarding-first-screen-after-sign-in.png"
        )

        for entry in rendered {
            let text = try await recognizedText(in: entry.image)
            for phrase in Self.rejectedNameCopy {
                #expect(
                    !text.contains(phrase),
                    "\(entry.stage.rawValue) asks for a name (\"\(phrase)\"). Rendered text: \(text)"
                )
            }
        }
    }

    /// The first thing a climber sees after the authorization sheet closes.
    @Test
    func onboardingOpensOnTheStairStepperQuestionRatherThanANameForm() async throws {
        let image = try render(stage: .first)
        let text = try await recognizedText(in: image)

        #expect(PostAuthOnboardingStage.first == .stairStepperBaseline)
        #expect(
            text.contains("stair"),
            "The opening screen should be the stair stepper question. Rendered text: \(text)"
        )
        for phrase in Self.rejectedNameCopy {
            #expect(!text.contains(phrase), "The opening screen asks for a name. Rendered text: \(text)")
        }
    }

    // MARK: - Rendering

    private func render(stage: PostAuthOnboardingStage) throws -> UIImage {
        let renderer = ImageRenderer(
            content: PostAuthOnboardingFlowView(
                stage: stage,
                onBack: {},
                onContinue: {}
            )
            .frame(width: 390, height: 844)
            .environment(AuthenticationViewModel(observesFirebaseAuth: false))
            .environment(\.colorScheme, .dark)
        )
        renderer.scale = 2
        return try #require(renderer.uiImage, "ImageRenderer produced no image for \(stage.rawValue)")
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

private struct Filmstrip: View {
    let screens: [(stage: PostAuthOnboardingStage, image: UIImage)]

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
                ForEach(screens, id: \.stage) { entry in
                    VStack(spacing: 8) {
                        Text("\(entry.stage.progressIndex + 1). \(entry.stage.rawValue)")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.85))
                        Image(uiImage: entry.image)
                            .resizable()
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
