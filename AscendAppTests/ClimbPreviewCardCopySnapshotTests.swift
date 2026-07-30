import SwiftUI
import Testing
import UIKit
import Vision
@testable import AscendApp

/// Visual evidence for the copy shown on the climb preview card that appears when a
/// landmark is tapped on the globe (`ClimbBrowseView.previewCardArea` ->
/// `ClimbPreviewCardView`).
///
/// The card used to stack "Finish in one live attempt" directly under the First Ascent
/// stake line, so the two lines read as one confusing sentence. This test renders the
/// real `ClimbPreviewCardView` for every state the globe can show, then reads the
/// rendered pixels back with Vision text recognition to assert no attempt copy survives
/// on the card while the identifying copy (name, location, steps, estimate) still does.
@MainActor
struct ClimbPreviewCardCopySnapshotTests {
    @Test
    func previewCardRendersNoAttemptCopy() async throws {
        let availableImage = try renderCard(
            summary: ClimbPreviewSummary(climb: .preview, isCompleted: false)
        )
        let completedImage = try renderCard(
            summary: ClimbPreviewSummary(climb: .preview, isCompleted: true)
        )
        let comingSoonImage = try renderCard(
            summary: ClimbPreviewSummary(climb: .previewComingSoon, isCompleted: false)
        )

        let availableText = try await recognizedText(in: availableImage)
        let completedText = try await recognizedText(in: completedImage)
        let comingSoonText = try await recognizedText(in: comingSoonImage)

        // The card still identifies the landmark and its effort.
        #expect(availableText.contains("empire state"))
        #expect(availableText.contains("new york"))
        #expect(availableText.contains("steps"))

        // No attempt copy on any preview card state.
        #expect(!availableText.contains("attempt"))
        #expect(!completedText.contains("attempt"))
        #expect(!comingSoonText.contains("attempt"))

        try writeEvidence(
            image: try renderProofSheet(),
            named: "climb-preview-card-copy.png"
        )
        try writeEvidence(image: availableImage, named: "climb-preview-card-available.png")
    }

    // MARK: - Rendering

    private func renderCard(summary: ClimbPreviewSummary) throws -> UIImage {
        let renderer = ImageRenderer(
            content: ClimbPreviewCardView(summary: summary, onSelect: {}, onClose: {})
                .frame(width: 361)
                .padding(16)
                .background(Color.black)
                .environment(\.colorScheme, .dark)
        )
        renderer.scale = 3
        return try #require(renderer.uiImage, "ImageRenderer produced no image")
    }

    private func renderProofSheet() throws -> UIImage {
        let renderer = ImageRenderer(content: PreviewCardProof())
        renderer.scale = 3
        return try #require(renderer.uiImage, "ImageRenderer produced no proof sheet")
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

/// Reviewer-facing proof sheet: the stacked read a captain sees on the globe, plus every
/// preview card state. The stake line copy comes from the real `TodayClimbStakeLine`
/// case that sits above the card, so the pairing shown here is the shipped pairing.
private struct PreviewCardProof: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            Text("Globe · climb preview card")
                .font(.montserratBold(size: 20))
                .foregroundStyle(.white)

            section("Available climb · stacked under the First Ascent stake line") {
                VStack(alignment: .leading, spacing: 10) {
                    stakeLine
                    ClimbPreviewCardView(
                        summary: ClimbPreviewSummary(climb: .preview, isCompleted: false),
                        onSelect: {},
                        onClose: {}
                    )
                }
            }

            section("Completed climb") {
                ClimbPreviewCardView(
                    summary: ClimbPreviewSummary(climb: .preview, isCompleted: true),
                    onSelect: {},
                    onClose: {}
                )
            }

            section("Coming soon climb") {
                ClimbPreviewCardView(
                    summary: ClimbPreviewSummary(climb: .previewComingSoon, isCompleted: false),
                    onSelect: {},
                    onClose: {}
                )
            }
        }
        .padding(28)
        .frame(width: 460)
        .background(Color.black)
        .environment(\.colorScheme, .dark)
    }

    private var stakeLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: TodayClimbStakeLine.openFirstAscent.systemImageName)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.accent)
                .frame(width: 16, alignment: .leading)

            Text(TodayClimbStakeLine.openFirstAscent.text)
                .font(.montserratMedium(size: 13))
                .foregroundStyle(.white.opacity(0.86))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func section(
        _ caption: String,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(caption)
                .font(.montserratSemiBold(size: 11))
                .foregroundStyle(Color.ascendAccent.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)

            content()
        }
    }
}
