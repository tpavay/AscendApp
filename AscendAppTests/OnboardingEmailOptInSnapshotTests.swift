import SwiftUI
import Testing
import UIKit
import Vision
@testable import AscendApp

/// Visual evidence that the email ask is on the onboarding notifications step,
/// pre-ticked, and that adding it did not push the CTA or the Skip link off the
/// screen it shares.
///
/// The ask is a checkbox on a step that already exists rather than a step of its
/// own, and it is a separate answer from push: tapping ENABLE NOTIFICATIONS must
/// not tick it, and Skip must not clear it. Those two are held by
/// `OnboardingEmailOptInViewModelTests`; this holds that a climber can see the
/// box and read what it says before they answer either question.
@MainActor
struct OnboardingEmailOptInSnapshotTests {
    @Test
    func theNotificationsStepAsksAboutEmailWithoutLosingItsButtons() async throws {
        let image = try renderNotificationsStep()
        let text = try await recognizedText(in: image)

        #expect(text.contains("email me when climbs drop"))
        #expect(text.contains("never miss an"))
        #expect(text.contains("enable notifications"))
        #expect(text.contains("skip"))

        try writeEvidence(image: image, named: "onboarding-email-opt-in.png")
    }

    // MARK: - Rendering

    private func renderNotificationsStep() throws -> UIImage {
        let renderer = ImageRenderer(
            content: PostAuthOnboardingFlowView(
                stage: .notifications,
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
            .lowercased()
    }

    private func writeEvidence(image: UIImage, named name: String) throws {
        let png = try #require(image.pngData(), "UIImage produced no PNG data")
        let directory = ProcessInfo.processInfo.environment["ASCEND_EVIDENCE_DIR"]
            ?? NSTemporaryDirectory()
        try png.write(to: URL(filePath: directory).appending(path: name))
        #expect(png.count > 5_000)
    }
}
