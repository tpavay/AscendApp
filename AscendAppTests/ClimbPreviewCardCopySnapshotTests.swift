import SwiftUI
import Testing
import UIKit
@testable import AscendApp

/// Visual evidence for the copy shown on the climb preview card that appears when a
/// landmark is tapped on the globe (`ClimbBrowseView.previewCardArea` ->
/// `ClimbPreviewCardView`).
///
/// The card used to stack "Finish in one live attempt" directly under the First Ascent
/// stake line, so the two lines read as one confusing sentence. This test hosts the
/// real `ClimbPreviewCardView` for every state the globe can show, then reads the
/// card's on-screen copy back off the accessibility tree (`RenderedScreen`) to assert no
/// attempt copy survives on the card while the identifying copy (name, location, steps,
/// estimate) still does.
@MainActor
@Suite(.hostsAWindow)
struct ClimbPreviewCardCopySnapshotTests {
    @Test
    func previewCardRendersNoAttemptCopy() async throws {
        let availableText = try await RenderedScreen.host(
            cardContent(summary: ClimbPreviewSummary(climb: .preview, isCompleted: false))
        ) { screen in
            let text = try await screen.copy { $0.contains("steps") }
            try screen.photograph(named: "climb-preview-card-available")
            return text
        }
        let completedText = try await cardCopy(
            summary: ClimbPreviewSummary(climb: .preview, isCompleted: true)
        )
        let comingSoonText = try await cardCopy(
            summary: ClimbPreviewSummary(climb: .previewComingSoon, isCompleted: false)
        )

        // The card still identifies the landmark and its effort.
        #expect(availableText.contains("empire state"))
        #expect(availableText.contains("new york"))
        #expect(availableText.contains("steps"))

        // No attempt copy on any preview card state.
        #expect(!availableText.contains("attempt"))
        #expect(!completedText.contains("attempt"))
        #expect(!comingSoonText.contains("attempt"))

        // The reviewer-facing sheet is laid out only when a photograph is being kept.
        if RenderedScreen.isPhotographing {
            try RenderedScreen.photograph(PreviewCardProof(), named: "climb-preview-card-copy")
        }
    }

    // MARK: - Reading the hosted card back

    /// The card's on-screen copy in `summary`'s state, lowercased, off the accessibility tree.
    private func cardCopy(summary: ClimbPreviewSummary) async throws -> String {
        try await RenderedScreen.host(cardContent(summary: summary)) { screen in
            try await screen.copy()
        }
    }

    private func cardContent(summary: ClimbPreviewSummary) -> some View {
        ClimbPreviewCardView(summary: summary, onSelect: {}, onClose: {})
            .frame(width: 361)
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color.black)
            .environment(\.colorScheme, .dark)
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
