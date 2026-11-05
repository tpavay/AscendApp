import SwiftUI

/// The shape 02 to 05 share: the progress header on top, art that takes whatever room is left, the
/// headline and message, and the primary action pinned to the bottom.
///
/// The middle scrolls only when it has to - at an accessibility text size the art shrinks to its
/// minimum and the text block grows past the screen - while the header and the button never move,
/// so Continue is always reachable.
struct SellScreenFrame<Art: View, Extras: View>: View {
    let step: OnboardingV3Step
    let headline: OnboardingHeadline
    let message: String
    /// The text block's entrance, in seconds after the screen appears (the design's per-screen delay).
    var textDelay: Double = 0.3
    /// The art's smallest height before the middle starts to scroll.
    var artMinimumHeight: CGFloat = 150
    let onContinue: () -> Void
    @ViewBuilder let art: () -> Art
    @ViewBuilder let extras: () -> Extras

    @Environment(\.onboardingV3Coordinator) private var coordinator

    var body: some View {
        VStack(spacing: 0) {
            OnboardingProgressHeader(step: step)
                .padding(.top, 9)

            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: 18) {
                        art()
                            .frame(maxWidth: .infinity, minHeight: artMinimumHeight, maxHeight: .infinity)

                        VStack(alignment: .leading, spacing: 10) {
                            headline

                            Text(message)
                                .onboardingSecondary()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)

                            extras()
                        }
                        .padding(.horizontal, 24)
                        .onboardingEntrance(delay: textDelay, duration: 0.5)
                    }
                    .frame(minHeight: proxy.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollIndicators(.hidden)
            }

            Button(SellScreenCopy.continueTitle, action: onContinue)
                .buttonStyle(.onboardingPrimary)
                .padding(.horizontal, 24)
                .padding(.top, 14)
                .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

extension SellScreenFrame where Extras == EmptyView {
    init(
        step: OnboardingV3Step,
        headline: OnboardingHeadline,
        message: String,
        textDelay: Double = 0.3,
        artMinimumHeight: CGFloat = 150,
        onContinue: @escaping () -> Void,
        @ViewBuilder art: @escaping () -> Art
    ) {
        self.init(
            step: step,
            headline: headline,
            message: message,
            textDelay: textDelay,
            artMinimumHeight: artMinimumHeight,
            onContinue: onContinue,
            art: art,
            extras: { EmptyView() }
        )
    }
}

/// A soft coloured glow behind a screen's art, the radial wash every selling screen opens with.
struct SellGlow: View {
    let color: Color
    var opacity: Double = 0.22

    var body: some View {
        RadialGradient(
            colors: [color.opacity(opacity), color.opacity(0)],
            center: .center,
            startRadius: 0,
            endRadius: 220
        )
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
