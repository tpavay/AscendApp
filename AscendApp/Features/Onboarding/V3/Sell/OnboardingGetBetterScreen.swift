import SwiftUI

/// 03 See yourself get better: four record cards drop in from above, each with a heavy tap, over a
/// soft gold wash. The two all-time bests wear laurel medals and the runners-up a 2.
struct OnboardingGetBetterScreen: View {
    let coordinator: OnboardingV3Coordinator

    @OnboardingReduceMotion private var reduceMotion

    private static let tilts: [Double] = [-1.5, 1, -0.5, 1.2]

    var body: some View {
        SellScreenFrame(
            step: .getBetter,
            headline: OnboardingHeadline(
                SellScreenCopy.GetBetter.headlineLead,
                accentLines: SellScreenCopy.GetBetter.headlineAccent,
                accent: .gold
            ),
            message: SellScreenCopy.GetBetter.body,
            textDelay: 1.1,
            artMinimumHeight: 260,
            onContinue: coordinator.advance
        ) {
            cards
        }
        .background(alignment: .top) {
            SellGlow(color: Color(hex: "E8C34A"), opacity: 0.16)
                .frame(height: 420)
                .padding(.top, 90)
                .allowsHitTesting(false)
        }
        .task {
            for index in SellRecordCard.examples.indices {
                try? await Task.sleep(for: .seconds(index == 0 ? 0.15 : 0.22))
                guard !Task.isCancelled else { return }
                HapticsManager.shared.trigger(.heavyImpact)
            }
        }
        .trackOnce(screen: .onboardingGetBetter)
    }

    private var cards: some View {
        VStack(spacing: 12) {
            ForEach(Array(SellRecordCard.examples.enumerated()), id: \.element.id) { index, card in
                SellRecordCardView(card: card)
                    .rotationEffect(.degrees(SellMotion.cardTilt(Self.tilts[index], reduceMotion: reduceMotion)))
                    .modifier(SellCardDrop(index: index))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

/// The card's entrance: it falls 60 pt, overshoots by 4 and settles, 0.15 s after the screen
/// appears and 0.22 s after the card above it. Reduce Motion fades it in without the fall.
private struct SellCardDrop: ViewModifier {
    let index: Int

    @OnboardingReduceMotion private var reduceMotion
    @State private var trigger = false

    private var delay: Double { 0.15 + 0.22 * Double(index) }

    func body(content: Content) -> some View {
        if reduceMotion {
            content
                .opacity(trigger ? 1 : 0)
                .onAppear { withAnimation(.easeOut(duration: 0.3).delay(delay)) { trigger = true } }
        } else {
            content
                .keyframeAnimator(initialValue: Frame.start, trigger: trigger) { view, frame in
                    view.offset(y: frame.offset).opacity(frame.opacity)
                } keyframes: { _ in
                    KeyframeTrack(\.opacity) {
                        LinearKeyframe(0, duration: max(delay, 0.001))
                        LinearKeyframe(1, duration: 0.2)
                    }
                    KeyframeTrack(\.offset) {
                        LinearKeyframe(-60, duration: max(delay, 0.001))
                        CubicKeyframe(4, duration: 0.35)
                        CubicKeyframe(0, duration: 0.15)
                    }
                }
                .onAppear { trigger = true }
        }
    }

    struct Frame {
        static let start = Frame(offset: -60, opacity: 0)

        var offset: Double
        var opacity: Double
    }
}
