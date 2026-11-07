import SwiftUI

/// The frame every "make it theirs" screen shares: the progress header on top, a body that
/// scrolls when the text size or a small phone needs it to, and the primary action pinned below
/// it so CONTINUE never scrolls out of reach.
struct OnboardingSetupLayout<Content: View, Footer: View>: View {
    let step: OnboardingV3Step
    var onSkip: (() -> Void)?
    /// The design's side margin: 24 on most screens, 20 on the ones that carry the most content.
    var horizontalPadding: CGFloat = 24
    @ViewBuilder let content: Content
    @ViewBuilder let footer: Footer

    var body: some View {
        VStack(spacing: 0) {
            OnboardingProgressHeader(step: step, onSkip: onSkip)
                .padding(.top, 9)

            ScrollView {
                content
                    .padding(.horizontal, horizontalPadding)
                    .padding(.top, 22)
                    .padding(.bottom, 20)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)

            footer
                .padding(.horizontal, horizontalPadding)
                .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
