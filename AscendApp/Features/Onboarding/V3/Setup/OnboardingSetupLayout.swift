import SwiftUI

/// The frame every "make it theirs" screen shares: the progress header on top, a body that
/// scrolls when the text size or a small phone needs it to, and the primary action pinned below
/// it so CONTINUE never scrolls out of reach.
struct OnboardingSetupLayout<Content: View, Footer: View>: View {
    @State private var hasMoreBelow = false

    let step: OnboardingV3Step
    var onSkip: (() -> Void)?
    /// The design's side margin: 24 on most screens, 20 on the ones that carry the most content.
    var horizontalPadding: CGFloat = 24
    /// Fades the body's bottom edge while there is more of it below the fold, so a form that
    /// has to scroll on a short phone reads as scrollable instead of as clipped.
    var fadesWhenScrollable = false
    /// Space above the body's first line; 22 by default, less on a short phone.
    var topPadding: CGFloat = 22
    @ViewBuilder let content: Content
    @ViewBuilder let footer: Footer

    var body: some View {
        VStack(spacing: 0) {
            OnboardingProgressHeader(step: step, onSkip: onSkip)
                .padding(.top, 9)

            ScrollView {
                content
                    .padding(.horizontal, horizontalPadding)
                    .padding(.top, topPadding)
                    .padding(.bottom, 20)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.containerSize.height < geometry.contentSize.height - 1
            } action: { _, isMoreBelow in
                hasMoreBelow = isMoreBelow
            }
            .overlay(alignment: .bottom) {
                if fadesWhenScrollable && hasMoreBelow {
                    LinearGradient(
                        stops: [
                            .init(color: OnboardingV3Palette.background.opacity(0), location: 0),
                            .init(color: OnboardingV3Palette.background.opacity(0.92), location: 0.8),
                            .init(color: OnboardingV3Palette.background, location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 72)
                    .allowsHitTesting(false)
                    .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.15), value: hasMoreBelow)

            footer
                .padding(.horizontal, horizontalPadding)
                .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
