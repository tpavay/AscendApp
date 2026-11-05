import SwiftUI

/// Type and motion helpers the paywall (13) and the gift (14) share, so the two screens read as one
/// piece and neither restates a font name.
enum PaywallFontWeight: String {
    case medium = "Montserrat-Medium"
    case semiBold = "Montserrat-SemiBold"
    case bold = "Montserrat-Bold"
    case extraBold = "Montserrat-ExtraBold"
    case black = "Montserrat-Black"
}

private struct PaywallTextStyle: ViewModifier {
    let weight: PaywallFontWeight
    let tracking: CGFloat
    let textStyle: Font.TextStyle
    @ScaledMetric private var size: CGFloat

    init(weight: PaywallFontWeight, size: CGFloat, tracking: CGFloat, relativeTo textStyle: Font.TextStyle) {
        self.weight = weight
        self.tracking = tracking
        self.textStyle = textStyle
        _size = ScaledMetric(wrappedValue: size, relativeTo: textStyle)
    }

    func body(content: Content) -> some View {
        content
            .font(.custom(weight.rawValue, fixedSize: size))
            .tracking(size * tracking)
    }
}

extension View {
    /// A Montserrat run that scales with the climber's text size. `tracking` is in em.
    func paywallText(
        _ weight: PaywallFontWeight,
        size: CGFloat,
        tracking: CGFloat = 0,
        relativeTo textStyle: Font.TextStyle = .body
    ) -> some View {
        modifier(PaywallTextStyle(weight: weight, size: size, tracking: tracking, relativeTo: textStyle))
    }
}

/// The light that crosses the primary button every 3.4 seconds: a 1.87 second pass and a rest.
/// Reduce Motion draws nothing.
struct PaywallSheen: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            EmptyView()
        } else {
            GeometryReader { proxy in
                KeyframeAnimator(initialValue: 0.0, repeating: true) { progress in
                    LinearGradient(
                        colors: [.white.opacity(0), .white.opacity(0.55), .white.opacity(0)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: 70)
                    .offset(x: -70 + progress * (proxy.size.width + 140))
                } keyframes: { _ in
                    LinearKeyframe(1.0, duration: 1.87)
                    LinearKeyframe(1.0, duration: 1.53)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

extension View {
    /// Lays the sheen over a 16 pt rounded primary button.
    func paywallSheen() -> some View {
        overlay { PaywallSheen() }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
