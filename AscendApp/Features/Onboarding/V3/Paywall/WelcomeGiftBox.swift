import SwiftUI

/// The lime gift box: a body, a lid, a black ribbon and a bow, drawn at the design's 180 by 190 size.
///
/// Closed, it shakes for a beat every two seconds. Opening sends the lid up and away and sinks the
/// body. Reduce Motion keeps it still and lets it fade.
struct WelcomeGiftBox: View {
    let isOpen: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let ribbon = Color(hex: "0A0A0A")

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            bodyShape
            lid
            bow
        }
        .frame(width: 180, height: 190, alignment: .bottomLeading)
        .modifier(GiftShake(isActive: !isOpen && !reduceMotion))
    }

    private var bodyShape: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: "C6F07A"), Color(hex: "6FA820")], startPoint: .topLeading, endPoint: .bottomTrailing))
            Rectangle().fill(ribbon).frame(width: 26)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .frame(width: 150, height: 108)
        .shadow(color: .black.opacity(0.6), radius: 24, y: 24)
        .offset(x: 15)
        .offset(y: isOpen ? (reduceMotion ? 0 : 80) : 0)
        .scaleEffect(isOpen && !reduceMotion ? 0.85 : 1, anchor: .bottom)
        .opacity(isOpen ? 0 : 1)
        .animation(reduceMotion ? .easeOut(duration: 0.3) : .easeIn(duration: 0.5).delay(0.35), value: isOpen)
    }

    private var lid: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: "DDF8A6"), Color(hex: "86BF30")], startPoint: .topLeading, endPoint: .bottomTrailing))
            Rectangle().fill(ribbon).frame(width: 26)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .frame(width: 170, height: 38)
        .offset(x: 5, y: -104)
        .offset(x: isOpen && !reduceMotion ? 70 : 0, y: isOpen && !reduceMotion ? -300 : 0)
        .rotationEffect(.degrees(isOpen && !reduceMotion ? 45 : 0))
        .opacity(isOpen ? 0 : 1)
        .animation(reduceMotion ? .easeOut(duration: 0.3) : .timingCurve(0.3, 0.6, 0.3, 1, duration: 0.7), value: isOpen)
    }

    private var bow: some View {
        ZStack {
            loop(rotation: -18, tailLeading: true).offset(x: -23)
            loop(rotation: 18, tailLeading: false).offset(x: 23)
        }
        .frame(width: 92, height: 32)
        .offset(x: 44, y: -136)
        .opacity(isOpen ? 0 : 1)
        .animation(.easeOut(duration: 0.3), value: isOpen)
    }

    private func loop(rotation: Double, tailLeading: Bool) -> some View {
        UnevenRoundedRectangle(
            topLeadingRadius: 24,
            bottomLeadingRadius: tailLeading ? 6 : 24,
            bottomTrailingRadius: tailLeading ? 24 : 6,
            topTrailingRadius: 24,
            style: .continuous
        )
        .strokeBorder(ribbon, lineWidth: 8)
        .frame(width: 46, height: 32)
        .rotationEffect(.degrees(rotation))
    }
}

/// A short shake on a two second cycle, pivoting on the bottom edge: still for 70 percent of it.
private struct GiftShake: ViewModifier {
    let isActive: Bool

    func body(content: Content) -> some View {
        if isActive {
            content.keyframeAnimator(initialValue: 0.0, repeating: true) { view, angle in
                view.rotationEffect(.degrees(angle), anchor: .bottom)
            } keyframes: { _ in
                KeyframeTrack {
                    LinearKeyframe(0, duration: 1.4)
                    LinearKeyframe(-6, duration: 0.08)
                    LinearKeyframe(6, duration: 0.08)
                    LinearKeyframe(-5, duration: 0.08)
                    LinearKeyframe(4, duration: 0.08)
                    LinearKeyframe(-2, duration: 0.08)
                    LinearKeyframe(0, duration: 0.2)
                }
            }
        } else {
            content
        }
    }
}
